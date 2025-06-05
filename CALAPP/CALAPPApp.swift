//
//  CALAPPApp.swift
//  CALAPP
//
//  Created by Michael Knaap on 05/06/2025.
//

import SwiftUI

@main
struct CALAPPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(.ultraThinMaterial)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
    }
}
