import MetalKit
import SwiftUI
import Foundation
import MetalPerformanceShaders

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
        var mapTextureFunction: MTLFunction!
        var displayTextureFunction: MTLFunction!
        var addMistKernelFunction: MTLFunction!
        var blurredTexture: MTLTexture?
        var mistRatioTexture: MTLTexture?
        var raindrops: [SIMD2<Float>] = []

        init(_ parent: MetalView) {
            self.parent = parent
            self.metalDevice = MTLCreateSystemDefaultDevice()
            let library = metalDevice.makeDefaultLibrary()
            self.mapTextureFunction = library!.makeFunction(name: "mapTexture")
            self.displayTextureFunction = library!.makeFunction(name: "displayTexture")
            self.addMistKernelFunction = library!.makeFunction(name: "addMist")

            self.metalCommandQueue = metalDevice.makeCommandQueue()!
            
            super.init()

            self.raindrops = createRaindrops()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }

        func draw(in view: MTKView) {
            guard let cameraTexture = parent.cameraInput.texture
            else {
                print("No camera input yet")
                return
            }
            
            if textureIsMissingOrWrongDimensions(blurredTexture, asTexture: cameraTexture) {
                blurredTexture = buildIdenticalTexture(asTexture: cameraTexture)
            }
            blurTexture(sourceTexture: cameraTexture, destinationTexture: blurredTexture!)
            
            if textureIsMissingOrWrongDimensions(mistRatioTexture, asTexture: cameraTexture) {
                mistRatioTexture = buildTexture(withSizeFrom: cameraTexture, pixelFormat: .r32Float)
            }
            addMist(mistRatioTexture!)
            updateRaindrops()

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.sampleCount = 1
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .invalid
            pipelineDescriptor.vertexFunction = mapTextureFunction
            pipelineDescriptor.fragmentFunction = displayTextureFunction
            
            var renderPipelineState: MTLRenderPipelineState?
            do {
                try renderPipelineState = metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
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
            encoder.setFragmentTexture(cameraTexture, index: 0)
            encoder.setFragmentTexture(blurredTexture, index: 1)
            encoder.setFragmentTexture(mistRatioTexture, index: 2)

            var raindropsCount: Float = Float(raindrops.count)
            encoder.setFragmentBytes(&raindropsCount, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentBytes(&raindrops, length: MemoryLayout<SIMD2<Float>>.stride * Int(raindropsCount), index: 1)

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            encoder.popDebugGroup()
            encoder.endEncoding()
            
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }

        func createRaindrops() -> [SIMD2<Float>] {
            var result: [SIMD2<Float>] = []
            for _ in 0..<50 {
                result.append(SIMD2<Float>(Float.random(in: 0..<1), Float.random(in: 0..<1)))
            }
            return result
        }
        
        func updateRaindrops() {
            for i in 0..<raindrops.count {
                var raindrop = raindrops[i]
                raindrop.y += 0.002
                if raindrop.y > 1 {
                    raindrop.y = 0
                    raindrop.x = Float.random(in: 0..<1)
                }
                raindrops[i] = raindrop
            }
        }
        
        func textureIsMissingOrWrongDimensions(_ texture: MTLTexture?, asTexture: MTLTexture) -> Bool {
            return texture == nil
                || texture!.width != asTexture.width
                || texture!.height != asTexture.height
        }
        
        func buildIdenticalTexture(asTexture texture: MTLTexture) -> MTLTexture {
            return buildTexture(withSizeFrom: texture, pixelFormat: texture.pixelFormat)
        }
        
        func buildTexture(withSizeFrom texture: MTLTexture, pixelFormat: MTLPixelFormat) -> MTLTexture {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: texture.width,
                height: texture.height,
                mipmapped: false)
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            return metalDevice.makeTexture(descriptor: textureDescriptor)!
        }
        
        func blurTexture(sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
            let buffer = metalCommandQueue.makeCommandBuffer()!
            let blur = MPSImageGaussianBlur(device: metalDevice, sigma: 40)
            blur.encode(commandBuffer: buffer, sourceTexture: sourceTexture, destinationTexture: destinationTexture)
            buffer.commit()
            buffer.waitUntilCompleted()
        }
        
        func addMist(_ texture: MTLTexture) {
            do {
                let pipeline = try metalDevice.makeComputePipelineState(function: addMistKernelFunction)
                
                let threadgroupCounts = MTLSizeMake(8, 8, 1);
                let threadgroups = MTLSizeMake(texture.width / threadgroupCounts.width,
                                               texture.height / threadgroupCounts.height,
                                               1);
                
                // let pipeline=...
                let buffer = metalCommandQueue.makeCommandBuffer()!
                let encoder = buffer.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(pipeline)
                encoder.setTexture(texture, index: 0)
                // TODO: Configure argument table with finger position

                var raindropsCount: Float = Float(raindrops.count)
                encoder.setBytes(&raindropsCount, length: MemoryLayout<Float>.stride, index: 0)
                encoder.setBytes(&raindrops, length: MemoryLayout<SIMD2<Float>>.stride * Int(raindropsCount), index: 1)

                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupCounts)
                encoder.endEncoding()
                
                buffer.commit()
                buffer.waitUntilCompleted()
            } catch {
                print("Unexpected error: \(error)")
            }
        }
    }
}

struct MetalView_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
