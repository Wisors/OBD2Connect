//  Created by Alex Nikishin on 28/03/2017.
//  Copyright © 2017 Wisors. All rights reserved.

import Foundation

class OBDStreamDelegate: NSObject, StreamDelegate {
    
    let streamEventHandler: (Stream, Stream.Event) -> Void
    
    init(streamEventHandler: @escaping (Stream, Stream.Event) -> Void) {
        self.streamEventHandler = streamEventHandler
    }
    
    // MARK: - StreamDelegate -
    @objc open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        streamEventHandler(aStream, eventCode)
    }
}
