//    Copyright (c) 2015-2017 Nikishin Alexander https://twitter.com/wisdors
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy of
//    this software and associated documentation files (the "Software"), to deal in
//    the Software without restriction, including without limitation the rights to
//    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//    the Software, and to permit persons to whom the Software is furnished to do so,
//    subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation

open class OBDConnection: OBDConnectionProtocol {
    
    // MARK: - Connection properties -
    open let configuration: OBDConnectionConfiguration
    open let completionQueue: DispatchQueue
    
    // MARK: - State handling & data received callback -
    /// The completion queue is used to dispatch this block.
    public var onStateChanged: OBDConnectionStateCallback? = nil
    public private(set) var state: OBDConnectionState {
        get {
            pthread_rwlock_rdlock(&stateLock)
            let state = _stateAtomicStorage
            pthread_rwlock_unlock(&stateLock)
            return state
        }
        set {
            pthread_rwlock_wrlock(&stateLock)
            _stateAtomicStorage = newValue
            pthread_rwlock_unlock(&stateLock)
        }
    }
    private var _stateAtomicStorage: OBDConnectionState = .closed {
        didSet { stateValueChanged(from: oldValue, to: _stateAtomicStorage) }
    }
    private var stateLock: pthread_rwlock_t
    
    // MARK: - Streams -
    private var streamsDelegate: OBDStreamDelegate
    private var streamQueue = DispatchQueue(label: "OBDConnectionQueue", qos: .utility, attributes: .concurrent)
    private var input: InputStream?
    private var output: OutputStream?
    private var streamLock: pthread_rwlock_t
    
    // MARK: - Request handling -
    private var requestResponse: String = ""
    private var requestTimeoutTimer: DispatchSourceTimer?
    private var requestCompletion: OBDResultCallback?
    private var requestLock: pthread_rwlock_t
    
    // MARK: - Init -
    public init(configuration: OBDConnectionConfiguration = OBDConnectionConfiguration.defaultELMAdapterConfiguration(),
                completionQueue: DispatchQueue = DispatchQueue.main) {
        
        self.configuration = configuration
        self.completionQueue = completionQueue
        self.streamsDelegate = OBDStreamDelegate()
        self.stateLock = pthread_rwlock_t()
        self.streamLock = pthread_rwlock_t()
        self.requestLock = pthread_rwlock_t()
        pthread_rwlock_init(&self.stateLock, nil)
        pthread_rwlock_init(&self.streamLock, nil)
        pthread_rwlock_init(&self.requestLock, nil)
        self.streamsDelegate.onStreamEvent = { [weak self] (stream, event) in
            self?.handleEvent(code: event, inStream: stream)
        }
    }
    
    deinit {

        flushConnection()
        pthread_rwlock_destroy(&stateLock)
        pthread_rwlock_destroy(&streamLock)
        pthread_rwlock_destroy(&requestLock)
    }
    
    private func stateValueChanged(from oldState: OBDConnectionState, to newState: OBDConnectionState) {
        guard newState != oldState else { return }
        
        completionQueue.async(flags: .barrier, execute: { [weak self] in
            self?.onStateChanged?(newState)
        })
    }
    
    // MARK: - Open -
    open func open() {
        let currentState = state
        guard currentState == .closed || currentState == .error(.unknown) else {
            assertionFailure("Trying to open connection while it already is opened")
            return
        }
        
        state = .connecting
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
                                           configuration.host as CFString,
                                           configuration.port,
                                           &readStream,
                                           &writeStream)
        guard let inputStream: InputStream = readStream?.takeRetainedValue(),
            let outputStream: OutputStream = writeStream?.takeRetainedValue() else {
            state = .error(.unknown)
            return
        }
        pthread_rwlock_wrlock(&streamLock)
        input = inputStream
        output = outputStream
        inputStream.delegate = self.streamsDelegate
        outputStream.delegate = self.streamsDelegate
        CFReadStreamSetDispatchQueue(input, streamQueue)
        CFWriteStreamSetDispatchQueue(output, streamQueue)
        inputStream.open()
        outputStream.open()
        pthread_rwlock_wrlock(&streamLock)
    }

    // MARK: - Close -
    open func close() {
        guard state != .closed else { return }
        
        flushConnection()
        state = .closed
    }
    
    private func flushConnection() {
        
        pthread_rwlock_wrlock(&requestLock)
        invalidateRequestTimeoutTimer()
        requestCompletion = nil
        requestResponse = ""
        pthread_rwlock_unlock(&requestLock)
        pthread_rwlock_wrlock(&streamLock)
        if let input = input {
            
            CFReadStreamSetDispatchQueue(input, nil)
            input.delegate = nil
            input.close()
        }
        if let output = output {
            
            CFWriteStreamSetDispatchQueue(output, nil)
            output.delegate = nil
            output.close()
        }
        input = nil
        output = nil
        pthread_rwlock_wrlock(&streamLock)
    }
    
    // MARK: - Data transmitting -
    
    /// Send data request. Completion handler will be executed in 3 cases.
    /// 1) An error is occured in connection
    /// 2) Connection receive termination character ">" means response received
    /// 3) The request timeout is reached, all response data received until timeout will be sent with completion
    ///
    /// - Parameters:
    ///   - data: Data to send
    ///   - completion: Result completion
    open func send(data: Data, completion: OBDResultCallback?) {
        guard data.count > 0 else {

            completionQueue.async { completion?(.failure(.sendingInvalidData)) }
            return
        }
        guard let output = output, state == .open else {

            completionQueue.async { completion?(.failure(.sendingIsNotAvailable)) }
            return
        }
        streamQueue.async { [weak self] in
            guard let `self` = self else { return }

            self.state = .transmitting
            pthread_rwlock_wrlock(&self.requestLock)
            defer { pthread_rwlock_unlock(&self.requestLock) }
            self.requestResponse = ""
            guard data.withUnsafeBytes({ output.write($0, maxLength: data.count) }) == data.count else {

                self.state = .open
                self.finishTransmission(result: .failure(.sendingDidFail))
                return
            }
            self.requestCompletion = completion
            self.startRequestTimeoutTimer()
        }
    }

    // MARK: - Stream event handling -
    open func handleEvent(code: Stream.Event, inStream stream: Stream) {
        guard stream == input || stream == output else { return }
        
        switch code {
            
            case Stream.Event.openCompleted: checkOpenCompleted()
            case Stream.Event.errorOccurred: handleErrorState(inStream: stream)
            case Stream.Event.hasBytesAvailable: handleBytesAvailable(inStream: stream)
            case Stream.Event.hasSpaceAvailable: return
            case Stream.Event.endEncountered: handle(connectionError: .connectionDidEnd)
            default: return
        }
    }
    
    private func checkOpenCompleted() {
        guard state != .open else { return }
        guard let input = input, let output = output else { return }
        guard (input.streamStatus == .open || input.streamStatus == .reading) &&
            output.streamStatus == .open else { return }
        
        state = .open
    }
    
    private func handleBytesAvailable(inStream stream: Stream) {
        guard let input = input, stream == input else { return }
        
        var buffer = [UInt8](repeating: 0, count: 512)
        while input.hasBytesAvailable {
            
            let len = input.read(&buffer, maxLength: buffer.count)
            handleReceived(data: Data(buffer[0..<len]))
        }
    }
    
    private func handleReceived(data: Data) {
        
        pthread_rwlock_wrlock(&self.requestLock)
        defer { pthread_rwlock_unlock(&self.requestLock) }
        guard let response = String(bytes: data, encoding: String.Encoding.ascii) else {
            finishTransmission(result: .failure(.responseIsInvaid)); return
        }

        requestResponse = requestResponse + response
        if requestResponse.hasSuffix(">") {
            finishTransmission(result: .success(requestResponse))
        }
    }
    
    private func finishTransmission(result: OBDResult<String>) {
        
        invalidateRequestTimeoutTimer()
        let completion = requestCompletion
        requestCompletion = nil
        requestResponse = ""
        state = .open
        completionQueue.async {
            completion?(result)
        }
    }
    
    private func handleErrorState(inStream stream: Stream) {
        
        let error: OBDConnectionError
        if let streamError = stream.streamError {
            error = .streamError(streamError)
        } else {
            error = .unknown
        }
        handle(connectionError: error)
    }
    
    private func handle(connectionError: OBDConnectionError) {
        
        flushConnection()
        state = .error(connectionError)
    }
    
    // MARK: - Timeout handling -
    private func startRequestTimeoutTimer() {
        
        invalidateRequestTimeoutTimer()
        let timer = DispatchSource.makeTimerSource(queue: streamQueue)
        timer.scheduleOneshot(deadline: .now() + configuration.requestTimeout)
        timer.setEventHandler { [weak self] in
            self?.finishTransmission(result: .failure(.requestTimeout))
        }
        timer.resume()
        requestTimeoutTimer = timer
    }
    
    private func invalidateRequestTimeoutTimer() {
        
        requestTimeoutTimer?.cancel()
        requestTimeoutTimer = nil
    }
}
