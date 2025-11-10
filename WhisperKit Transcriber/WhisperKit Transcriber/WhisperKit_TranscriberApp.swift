//
//  WhisperKit_TranscriberApp.swift
//  WhisperKit Transcriber
//
//  Created for batch WhisperKit transcription
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Stop watching on app quit
        // This will be handled by WatchFolderManager deinit, but explicit stop is cleaner
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Resume watching if needed
    }
}

@main
struct WhisperKit_TranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 900)
    }
}
