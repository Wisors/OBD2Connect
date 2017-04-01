//  Created by Alexandr Nikishin on 28/01/2017.
//  Copyright © 2017 Alexandr Nikishin. All rights reserved.

import Foundation

/// Protocol covers properties and methods of the connection to an OBD adapter.
public protocol OBDConnectionProtocol: class {
    
    var requestTimeout: TimeInterval { get set }
    
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
