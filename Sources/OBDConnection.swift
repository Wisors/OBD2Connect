//  Created by Alexandr Nikishin on 28/01/2017.
//  Copyright © 2017 Alexandr Nikishin. All rights reserved.

import Foundation

open class OBDConnection: OBDConnectionProtocol {
    
    // MARK: - Connection properties -
    open let host: String
    open let port: UInt32
    
    // MARK: - State handling & data received callback -
    open var onStateChanged: OBDConnectionStateCallback? = nil
    open private(set) var state: OBDConnectionState = .closed {
        didSet {
            if state != oldValue {
                onStateChanged?(state)
            }
        }
    }
    
    // MARK: - Streams -
    private var streamsDelegate: WS_StreamDelegate!
    private var input: InputStream?
    private var output: OutputStream?
    private var resultCallback: OBDDataResultCallback? = nil
    
    // MARK: - Init -
    public init(host: String = "192.168.0.10", port: UInt32 = 35000) {
        
        self.host = host
        self.port = port
        streamsDelegate = WS_StreamDelegate() { [weak self] stream, event in
            self?.handleEvent(code: event, inStream: stream)
        }
    }
    
    deinit {
        closeStreams()
    }
    
    // MARK: - Open -
    open func open() {
        guard state != .connecting && state != .open else { return }
        
        state = .connecting
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host as CFString, port, &readStream, &writeStream)
        
        input = readStream?.takeRetainedValue()
        output = writeStream?.takeRetainedValue()
        configureAndOpen(stream: input)
        configureAndOpen(stream: output)
    }
    
    private func configureAndOpen(stream: Stream?) {
        
        stream?.delegate = streamsDelegate
        stream?.schedule(in: RunLoop.current, forMode: .defaultRunLoopMode)
        stream?.open()
    }
    
    // MARK: - Close -
    open func close() {
        guard state != .closed else { return }
        
        closeStreams()
        state = .closed
    }
    
    private func close(withError error: OBDConnectionError) {
        
        closeStreams()
        state = .error(error)
    }
    
    private func closeStreams() {
        
        output?.close()
        output?.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
        input?.close()
        output?.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
    }
    
    // MARK: - Data transmitting -
    open func send(data: Data, completion: OBDDataResultCallback?) {
        guard data.count > 0 else {
            
            completion?(.failure(.sendingInvalidData))
            return
        }
        guard let output = output, state == .open else {
        
            completion?(.failure(.sendingIsNotAvailable))
            return
        }
        
        state = .transmitting
        guard data.withUnsafeBytes({ output.write($0, maxLength: data.count) }) == data.count else {
            
            state = .open
            completion?(.failure(.sendingDidFail))
            return
        }
        resultCallback = completion
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
        
        var buffer = [UInt8](repeating: 0, count: 1024)
        while input.hasBytesAvailable {
            
            let len = input.read(&buffer, maxLength: buffer.count)
            finishTransmission(withData: Data(buffer[0..<len]))
        }
    }
    
    private func finishTransmission(withData data: Data) {
        
        resultCallback?(.success(data))
        resultCallback = nil
        state = .open
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
}

private class WS_StreamDelegate: NSObject, StreamDelegate {
    
    let streamEventHandler: (Stream, Stream.Event) -> Void
    
    init(streamEventHandler: @escaping (Stream, Stream.Event) -> Void) {
        self.streamEventHandler = streamEventHandler
    }
    
    // MARK: - StreamDelegate -
    @objc open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        streamEventHandler(aStream, eventCode)
    }
}
