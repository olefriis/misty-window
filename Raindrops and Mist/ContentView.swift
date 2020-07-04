//
//  ContentView.swift
//  Raindrops and Mist
//
//  Created by Ole Friis Østergaard on 03/07/2020.
//  Copyright © 2020 Retrofit Games. All rights reserved.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    var body: some View {
        MetalView(mtkView: MTKView())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
