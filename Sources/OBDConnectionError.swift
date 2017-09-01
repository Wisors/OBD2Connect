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
