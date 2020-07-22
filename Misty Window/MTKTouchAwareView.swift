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
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        currentTouches.subtract(touches)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        currentTouches.subtract(touches)
    }
}
