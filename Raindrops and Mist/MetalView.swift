import MetalKit
import SwiftUI
import Foundation

struct MetalView: UIViewRepresentable {
    typealias UIViewType = MTKView
    var mtkView: MTKView
    let cameraInput = CameraInput()

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: UIViewRepresentableContext<MetalView>) -> MTKView {
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        //mtkView.enableSetNeedsDisplay = true
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        //mtkView.enableSetNeedsDisplay = true
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MetalView>) {
    }

    class Coordinator : NSObject, MTKViewDelegate {
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        
        init(_ parent: MetalView) {
            self.parent = parent
            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }
            self.metalCommandQueue = metalDevice.makeCommandQueue()!
            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }

        func draw(in view: MTKView) {
            guard let texture = parent.cameraInput.texture
            else {
                print("No camera input yet")
                return
            }
            guard
                let device = self.metalDevice,
                let library = metalDevice.makeDefaultLibrary()
            else {
                print("Missing texture or metal device")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.sampleCount = 1
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .invalid
            
            /**
             *  Vertex function to map the texture to the view controller's view
             */
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "mapTexture")
            /**
             *  Fragment function to display texture's pixels in the area bounded by vertices of `mapTexture` shader
             */
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "displayTexture")
            
            
            var renderPipelineState: MTLRenderPipelineState?
            do {
                try renderPipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            }
            catch {
                print("Failed creating a render state pipeline. Can't render the texture without one.")
                return
            }
            
            let commandBuffer = metalCommandQueue.makeCommandBuffer()!
            guard
                let currentRenderPassDescriptor = view.currentRenderPassDescriptor,
                let currentDrawable = view.currentDrawable,
                renderPipelineState != nil
            else {
                print("Missing something...")
                return
            }
            
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor)!
            encoder.pushDebugGroup("RenderFrame")
            encoder.setRenderPipelineState(renderPipelineState!)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            encoder.popDebugGroup()
            encoder.endEncoding()
            
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }
    }
}

struct MetalView_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
