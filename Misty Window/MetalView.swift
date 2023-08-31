import MetalKit
import SwiftUI
import Foundation
import MetalPerformanceShaders
import CoreMotion

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
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MetalView>) {
    }

    class Coordinator : NSObject, MTKViewDelegate {
        struct Raindrop {
            var position: SIMD2<Float>
            var hidden: Bool
        }
        
        var parent: MetalView
        let motion = CMMotionManager()
        var gyroscopeTimer: Timer?
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        var mapTextureFunction: MTLFunction!
        var displayTextureFunction: MTLFunction!
        var addMistKernelFunction: MTLFunction!
        var blurredTexture: MTLTexture?
        var mistRatioTexture: MTLTexture?
        var raindrops: [Raindrop] = []
        var raindropPositions: [SIMD2<Float>] = []
        var touches: [SIMD2<Float>] = []

        init(_ parent: MetalView) {
            self.parent = parent
            self.metalDevice = MTLCreateSystemDefaultDevice()
            self.metalCommandQueue = metalDevice.makeCommandQueue()!

            let library = metalDevice.makeDefaultLibrary()
            self.mapTextureFunction = library!.makeFunction(name: "mapTexture")
            self.displayTextureFunction = library!.makeFunction(name: "displayTexture")
            self.addMistKernelFunction = library!.makeFunction(name: "addMist")
            
            super.init()

            self.raindrops = createRaindrops()
            if motion.isDeviceMotionAvailable {
                motion.startDeviceMotionUpdates()
            } else {
                print("Device motion not available. You won't get anything out of rotating your device then.")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }
        
        func draw(in view: MTKView) {
            guard let cameraTexture = parent.cameraInput.texture
            else {
                print("No camera input yet")
                return
            }

            updateRaindrops()
            updateTouches(view: view)
            
            if textureIsMissingOrWrongDimensions(blurredTexture, asTexture: cameraTexture) {
                blurredTexture = buildIdenticalTexture(asTexture: cameraTexture)
            }
            blurTexture(sourceTexture: cameraTexture, destinationTexture: blurredTexture!)
            
            if textureIsMissingOrWrongDimensions(mistRatioTexture, asTexture: cameraTexture) {
                mistRatioTexture = buildTexture(withSizeFrom: cameraTexture, pixelFormat: .r32Float)
            }
            addMist(mistRatioTexture!)

            renderFinalImage(in: view, cameraTexture: cameraTexture)
        }

        func createRaindrops() -> [Raindrop] {
            var result: [Raindrop] = []
            for _ in 0..<50 {
                result.append(Raindrop(
                    position: SIMD2<Float>(Float.random(in: 0..<1), Float.random(in: 0..<1)),
                    hidden: false
                ))
            }
            return result
        }
        
        func updateRaindrops() {
            let gravity = currentGravity()
            
            // Very ugly, old-school for loop. Idiomatic Swift for loop doesn't let me change
            // the array elements. Maybe there's something better I can do here?
            for i in 0..<raindrops.count {
                var raindrop = raindrops[i]
                
                // Follow gravity
                let downwardSpeed = Float.random(in: 0..<0.004)
                raindrop.position.x += downwardSpeed * gravity.x
                raindrop.position.y += downwardSpeed * gravity.y
                
                // ...but also go a tiny bit sideways
                let sidewaysSpeed = Float.random(in: -0.001..<0.001)
                raindrop.position.x += sidewaysSpeed * gravity.y
                raindrop.position.y += sidewaysSpeed * gravity.x

                if raindrop.position.x < 0 || raindrop.position.x > 1 || raindrop.position.y < 0 || raindrop.position.y > 1 {
                    if abs(gravity.x) > abs(gravity.y) {
                        // Place drops to the left or the right
                        if gravity.x < 0 {
                            // Place drops to the right
                            raindrop.position.x = 1
                        } else {
                            raindrop.position.x = 0
                        }
                        raindrop.position.y = Float.random(in: 0..<1)
                    } else {
                        // Place drops at the top or bottom
                        if gravity.y < 0 {
                            // Place tops at the bottom
                            raindrop.position.y = 1
                        } else {
                            raindrop.position.y = 0
                        }
                        raindrop.position.x = Float.random(in: 0..<1)
                    }
                    raindrop.hidden = false
                }
                raindrops[i] = raindrop
            }
            
            self.raindropPositions = raindrops
                .filter({!$0.hidden})
                .map({$0.position})
            if self.raindropPositions.isEmpty {
                // Metal cannot handle an empty buffer, so we'll just add a dummy raindrop position
                self.raindropPositions = [SIMD2<Float>(-1, -1)]
            }
        }
        
        func currentGravity() -> SIMD2<Float> {
            if let deviceMotion = motion.deviceMotion {
                // Weird swapping and negating because our view is sideways...
                return SIMD2<Float>(Float(-deviceMotion.gravity.y), Float(-deviceMotion.gravity.x))
            }
            // Just in case we cannot get the gravity data, we're always letting drops go down
            return SIMD2<Float>(0, 1)
        }
        
        func updateTouches(view: MTKView) {
            let uiTouches = (view as! MTKTouchAwareView).currentTouches
            self.touches = uiTouches.map({ touch in
                let location = touch.location(in: view)
                // Divide both x and y location by width, since we want normalized
                // coordinates for our shader
                let x = location.x / view.frame.width
                let y = location.y / view.frame.width
                return SIMD2<Float>(Float(x), Float(y))
            })
            
            // Hide wiped-out raindrops
            for i in 0..<raindrops.count {
                var raindrop = raindrops[i]
                touches.forEach({touch in
                    let distX = touch.x - raindrop.position.x
                    let distY = touch.y - raindrop.position.y
                    let distanceSquared = (distX*distX) + (distY*distY)
                    let fingerRadius = Float(0.05)
                    if distanceSquared < (fingerRadius*fingerRadius) {
                        raindrop.hidden = true
                    }
                })
                raindrops[i] = raindrop
            }
            
            if self.touches.isEmpty {
                // Metal cannot handle an empty buffer, so we'll just add a dummy touch
                self.touches = [SIMD2<Float>(-1, -1)]
            }
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
                
                let buffer = metalCommandQueue.makeCommandBuffer()!
                let encoder = buffer.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(pipeline)
                encoder.setTexture(texture, index: 0)

                var raindropPositionsCount: Float = Float(raindropPositions.count)
                encoder.setBytes(&raindropPositionsCount, length: MemoryLayout<Float>.stride, index: 0)
                encoder.setBytes(&raindropPositions, length: MemoryLayout<SIMD2<Float>>.stride * Int(raindropPositionsCount), index: 1)
                
                var touchesCount: Float = Float(touches.count)
                encoder.setBytes(&touchesCount, length: MemoryLayout<Float>.stride, index: 2)
                encoder.setBytes(&touches, length: MemoryLayout<SIMD2<Float>>.stride * Int(touchesCount), index: 3)

                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupCounts)
                encoder.endEncoding()
                
                buffer.commit()
                buffer.waitUntilCompleted()
            } catch {
                print("Unexpected error adding mist: \(error)")
            }
        }
        
        func renderFinalImage(in view: MTKView, cameraTexture: MTLTexture) {
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .invalid
            pipelineDescriptor.vertexFunction = mapTextureFunction
            pipelineDescriptor.fragmentFunction = displayTextureFunction
            
            var renderPipelineState: MTLRenderPipelineState?
            do {
                try renderPipelineState = metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            }
            catch {
                print("Failed creating a render state pipeline. Can't render the texture without one. \(error)")
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

            var raindropPositionsCount: Float = Float(raindropPositions.count)
            encoder.setFragmentBytes(&raindropPositionsCount, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentBytes(&raindropPositions, length: MemoryLayout<SIMD2<Float>>.stride * Int(raindropPositionsCount), index: 1)

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            encoder.popDebugGroup()
            encoder.endEncoding()
            
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
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
    }
}

struct MetalView_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
