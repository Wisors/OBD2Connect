//  Created by Alexandr Nikishin on 28/01/2017.
//  Copyright © 2017 Alexandr Nikishin. All rights reserved.

import Foundation

open class OBDConnection: OBDConnectionProtocol {
    
    // MARK: - Connection properties -
    open let host: String
    open let port: UInt32
    open let completionQueue: DispatchQueue
    open var requestTimeout: TimeInterval
    
    // MARK: - State handling & data received callback -
    /// Tthe main queue is always used to dispatch this block.
    open var onStateChanged: OBDConnectionStateCallback? = nil
    open private(set) var state: OBDConnectionState = .closed {
        didSet { stateValueChanged(oldValue: oldValue) }
    }
    
    // MARK: - Streams -
    private var streamsDelegate: OBDStreamDelegate!
    private var streamQueue = DispatchQueue(label: "OBDConnectionQueue", qos: .utility, attributes: .concurrent)
    private var input: InputStream?
    private var output: OutputStream?
    
    // MARK: - Request handling -
    private var requestResponse: String = ""
    private var timeoutTimer: Timer?
    private var resultCompletion: OBDResultCallback?
    
    // MARK: - Init -
    public init(host: String = "192.168.0.10",
                port: UInt32 = 35000,
                completionQueue: DispatchQueue = DispatchQueue.main,
                requestTimeout: TimeInterval = 0.100) {
        
        self.host = host
        self.port = port
        self.completionQueue = completionQueue
        self.requestTimeout = requestTimeout
        streamsDelegate = OBDStreamDelegate() { [weak self] stream, event in
            self?.handleEvent(code: event, inStream: stream)
        }
    }
    
    deinit {
        flushConnection()
    }
    
    private func stateValueChanged(oldValue: OBDConnectionState) {
        guard state != oldValue else { return }
        
        let newState = state
        DispatchQueue.main.async(flags: .barrier, execute: { [weak self] in
            self?.onStateChanged?(newState)
        })
    }
    
    // MARK: - Open -
    open func open() {
        guard state == .closed || state == .error(.unknown) else { return }
        
        state = .connecting
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host as CFString, port, &readStream, &writeStream)
        
        input = readStream?.takeRetainedValue()
        output = writeStream?.takeRetainedValue()
        streamQueue.async { [weak self] in
            
            self?.configureAndOpen(stream: self?.input)
            self?.configureAndOpen(stream: self?.output)
            RunLoop.current.run()
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
    /// 3) Request timeout is reached, all currently available response will be sent
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
            self?.resultCompletion = completion
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
        let completion = resultCompletion
        resultCompletion = nil
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
        timeoutTimer = Timer.scheduledTimer(timeInterval: requestTimeout, target: self, selector: #selector(timeoutReached), userInfo: nil, repeats: false)
    }
    
    @objc private func timeoutReached() {
        finishTransmission(result: .failure(.requestTimeout))
    }
    
    private func flushTimeoutTimer() {
        
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
}
