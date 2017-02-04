//  Created by Alexandr Nikishin on 28/01/2017.
//  Copyright © 2017 Alexandr Nikishin. All rights reserved.

import Foundation

public enum OBDResult<Value> {
    
    case failure(OBDConnectionError)
    case success(Value)
    
    public func onSuccess(block: (Value) -> Void) {
        
        if case .success(let result) = self {
            block(result)
        }
    }
    
    public func onFailure(block: (OBDConnectionError) -> Void) {
        
        if case .failure(let error) = self {
            block(error)
        }
    }
}
