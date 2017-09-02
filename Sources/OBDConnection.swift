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
    open var onStateChanged: OBDConnectionStateCallback? = nil
    open private(set) var state: OBDConnectionState = .closed {
        didSet { stateValueChanged(oldValue: oldValue) }
    }
    
    // MARK: - Streams -
    private var streamsDelegate: OBDStreamDelegate
    private var streamQueue = DispatchQueue(label: "OBDConnectionQueue", qos: .utility, attributes: .concurrent)
    private var input: InputStream?
    private var output: OutputStream?
    
    // MARK: - Request handling -
    private var requestResponse: String = ""
    private var requestTimeoutTimer: Timer?
    private var requestCompletion: OBDResultCallback?
    
    // MARK: - Init -
    public init(configuration: OBDConnectionConfiguration = OBDConnectionConfiguration.defaultELMAdapterConfiguration(),
                completionQueue: DispatchQueue = DispatchQueue.main) {
        
        self.configuration = configuration
        self.completionQueue = completionQueue
        self.streamsDelegate = OBDStreamDelegate()
        self.streamsDelegate.onStreamEvent = { [weak self] (stream, event) in
            self?.handleEvent(code: event, inStream: stream)
        }
    }
    
    deinit {
        flushConnection()
    }
    
    private func stateValueChanged(oldValue: OBDConnectionState) {
        guard state != oldValue else { return }
        
        let newState = state
        completionQueue.async(flags: .barrier, execute: { [weak self] in
            self?.onStateChanged?(newState)
        })
    }
    
    // MARK: - Open -
    open func open() {
        guard state == .closed || state == .error(.unknown) else {
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
        
        input = readStream?.takeRetainedValue()
        output = writeStream?.takeRetainedValue()
        streamQueue.async { [weak self] in
            
            self?.configureAndOpen(stream: self?.input)
            self?.configureAndOpen(stream: self?.output)
            RunLoop.current.run()
        }
        streamQueue.async { [weak self] in
            self?.startTimeoutTimer()
        }
    }
    
    private func configureAndOpen(stream: Stream?) {
        
        stream?.delegate = streamsDelegate
        stream?.schedule(in: RunLoop.current, forMode: .defaultRunLoopMode)
        stream?.open()
    }
    
    // MARK: - Close -
    open func close() {
        guard state != .closed else { return }
        
        flushConnection()
        state = .closed
    }
    
    private func close(withError error: OBDConnectionError) {
        
        flushConnection()
        state = .error(error)
    }
    
    private func flushConnection() {
        
        flushTimeoutTimer()
        output?.close()
        output?.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
        output = nil
        input?.close()
        input?.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
        input = nil
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
            
            self?.state = .transmitting
            self?.requestResponse = ""
            guard data.withUnsafeBytes({ output.write($0, maxLength: data.count) }) == data.count else {
                
                self?.state = .open
                self?.completionQueue.async { completion?(.failure(.sendingDidFail)) }
                return
            }
            self?.requestCompletion = completion
            self?.startTimeoutTimer()
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
            case Stream.Event.endEncountered: close(withError: .connectionDidEnd)
            default: return
        }
    }
    
    private func checkOpenCompleted() {
        guard state != .open else { return }
        guard (input?.streamStatus == .open || input?.streamStatus == .reading) &&
            output?.streamStatus == .open else { return }
        
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
        guard let response = String(bytes: data, encoding: String.Encoding.ascii) else {
            finishTransmission(result: .failure(.responseIsInvaid)); return
        }
        
        requestResponse = requestResponse + response
        if requestResponse.hasSuffix(">") {
            finishTransmission(result: .success(requestResponse))
        }
    }
    
    private func finishTransmission(result: OBDResult<String>) {
        
        flushTimeoutTimer()
        state = .open
        let completion = requestCompletion
        requestCompletion = nil
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
        close(withError: error)
    }
    
    // MARK: Timeout handling -
    private func startTimeoutTimer() {
        let timer = Timer.scheduledTimer(
            timeInterval: configuration.requestTimeout,
            target: self,
            selector: #selector(timeoutReached),
            userInfo: nil,
            repeats: false
        )
        requestTimeoutTimer = timer
        RunLoop.current.add(timer, forMode: .commonModes)
    }
    
    @objc private func timeoutReached(timer: Timer) {
        finishTransmission(result: .failure(.requestTimeout))
    }
    
    private func flushTimeoutTimer() {
        
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
    }
}
