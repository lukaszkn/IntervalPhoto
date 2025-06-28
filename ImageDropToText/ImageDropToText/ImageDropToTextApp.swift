//
//  ImageDropToTextApp.swift
//  ImageDropToText
//
//  Created by Lukasz on 23/04/2025.
//

import SwiftUI

@main
struct ImageDropToTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    appDelegate.makeWindowAlwaysOnTop()
                }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            self.window = window
        }
    }

    func makeWindowAlwaysOnTop() {
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            
            window.level = .floating
            window.collectionBehavior = .canJoinAllSpaces
            window.sharingType = .none
            
//            window.isOpaque = false
//            window.alphaValue = 0.65  // 1.0 is fully opaque
//            window.backgroundColor = NSColor.white
        }
    }
}
