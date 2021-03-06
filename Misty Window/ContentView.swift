import SwiftUI
import MetalKit

struct ContentView: View {
    var body: some View {
        MetalView(mtkView: MTKTouchAwareView())
            // Hacky, but this is the size I get from my iPhone 11 camera input...
            .aspectRatio(CGSize(width: 1920, height: 1080), contentMode: .fill)
            // Make full-screen
            .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
