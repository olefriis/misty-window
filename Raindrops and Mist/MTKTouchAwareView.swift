//
//  MTKTouchAwareView.swift
//  Raindrops and Mist
//
//  Created by Ole Friis Østergaard on 18/07/2020.
//  Copyright © 2020 Retrofit Games. All rights reserved.
//

import Foundation
import MetalKit

class MTKTouchAwareView : MTKView {
    var currentTouches = Set<UITouch>()
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        self.isMultipleTouchEnabled = true
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.isMultipleTouchEnabled = true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        currentTouches.formUnion(touches)
        print("Touches began. Now \(currentTouches.count) touches.")
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        currentTouches.subtract(touches)
        print("Touches ended. Now \(currentTouches.count) touches.")
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        print("Touches moved. Now \(currentTouches.count) touches.")
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        currentTouches.subtract(touches)
        print("Touches cancelled. Now \(currentTouches.count) touches.")
    }
}
