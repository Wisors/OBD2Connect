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

/// Protocol covers properties and methods of the connection to an OBD adapter.
public protocol OBDConnectionProtocol: class {
    
    var configuration: OBDConnectionConfiguration { get }
    
    // MARK: State
    var state: OBDConnectionState { get }
    var onStateChanged: OBDConnectionStateCallback? { get set }
    
    // MARK: Data transmitting
    func send(data: Data, completion: OBDResultCallback?)
    
    // MARK: Connection hadling methods
    func open()
    func close()
}

public enum OBDConnectionState: CustomStringConvertible {
    
    case closed
    case connecting
    case open
    case transmitting
    case error(OBDConnectionError)
    
    public var description: String {
        
        switch self {
            
            case .closed: return "Connection closed"
            case .connecting: return "Trying to connect to OBD adapter"
            case .open: return "Connection ready to send data"
            case .transmitting: return "Transmitting data between host and adapter"
            case .error(let error): return "Error: \(String(describing: error))"
        }
    }
}

extension OBDConnectionState: Equatable {}

public func == (lhs: OBDConnectionState, rhs: OBDConnectionState) -> Bool {
    
    switch (lhs, rhs) {
        
        case (.closed, .closed): return true
        case (.connecting, .connecting): return true
        case (.open, .open): return true
        case (.transmitting, .transmitting): return true
        case (.error(_), .error(_)): return true
        default: return false
    }
}
