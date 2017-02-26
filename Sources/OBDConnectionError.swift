//  Created by Alexandr Nikishin on 28/01/2017.
//  Copyright © 2017 Alexandr Nikishin. All rights reserved.

import Foundation

public enum OBDConnectionError: Error, CustomStringConvertible {
    
    case unknown
    case streamError(Error)
    case sendingIsNotAvailable
    case sendingDidFail
    case sendingInvalidData
    case responseIsInvaid
    case requestTimeout
    case connectionDidEnd
    
    public var description: String {
        
        switch self {
            
            case .unknown: return "Unexpected socket error occured"
            case .streamError(let error): return error.localizedDescription
            case .sendingIsNotAvailable: return "Connection is not ready to send data"
            case .sendingDidFail: return "A error occured during writing to an output stream."
            case .sendingInvalidData: return "Trying to send invalid data."
            case .responseIsInvaid: return "Response is malformed"
            case .requestTimeout: return "Request timeout reached"
            case .connectionDidEnd: return "Connection was unexpectedly closed"
        }
    }
}
