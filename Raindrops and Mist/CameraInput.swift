import Foundation
import AVFoundation

class CameraInput: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    
    // Texture cache we will use for converting frame images to textures
    var textureCache: CVMetalTextureCache!

    // `MTLDevice` we need to initialize texture cache
    var metalDevice = MTLCreateSystemDefaultDevice()

    var texture: MTLTexture?
    
    override init() {
        super.init()
        
        guard let
            metalDevice = metalDevice, CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache) == kCVReturnSuccess
        else {
            print("Could not create texture cache")
            return
        }

        AVCaptureDevice.requestAccess(for: AVMediaType.video) {
            (granted: Bool) -> Void in
            guard granted else {
                print("No access to the camera")
                return
            }
            
            print("Yay, got access to the camera")
            
            guard let inputDevice = AVCaptureDevice.default(for: .video) else {
                print("Did not get input device")
                return
            }
            
            var captureInput: AVCaptureDeviceInput!
            do {
                captureInput = try AVCaptureDeviceInput(device: inputDevice)
            }
            catch {
                print("Could not create input capture")
                return
            }
            
            self.captureSession.beginConfiguration()

            guard self.captureSession.canAddInput(captureInput) else {
                print("Could not add input")
                return
            }

            self.captureSession.addInput(captureInput)
            
            let outputData = AVCaptureVideoDataOutput()
            outputData.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_32BGRA)
            ]
            
            let captureSessionQueue = DispatchQueue(label: "CameraSessionQueue", attributes: [])
            outputData.setSampleBufferDelegate(self, queue: captureSessionQueue)
            
            guard self.captureSession.canAddOutput(outputData) else {
                print("Cannot add output")
                return
            }

            self.captureSession.addOutput(outputData)
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        texture = convertToTexture(sampleBuffer: sampleBuffer)
    }
    
    func convertToTexture(sampleBuffer: CMSampleBuffer) -> MTLTexture? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Could not convert CMSampleBuffer to CVImageBuvver")
            return nil
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        var imageTexture: CVMetalTexture?
        let pixelFormat = MTLPixelFormat.bgra8Unorm
        let planeIndex = 0
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, nil, pixelFormat, width, height, planeIndex, &imageTexture)
        
        guard
            let unwrappedImageTexture = imageTexture,
            let texture = CVMetalTextureGetTexture(unwrappedImageTexture),
            result == kCVReturnSuccess
        else {
            print("Could not create texture")
            return nil
        }
        
        return texture
    }
}
