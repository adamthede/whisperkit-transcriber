//
//  WhisperKit_TranscriberApp.swift
//  WhisperKit Transcriber
//
//  Created for batch WhisperKit transcription
//

import SwiftUI
import AppKit

@main
struct WhisperKit_TranscriberApp: App {
    @StateObject private var menubarManager = MenubarManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(menubarManager)
                .onAppear {
                    // If menubar-only mode is enabled, close the main window
                    // Users can reopen it from the menubar
                    if menubarManager.isMenubarMode {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApplication.shared.windows.first {
                                window.close()
                            }
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 900)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    // Open preferences (main window with settings visible)
                    if let window = NSApplication.shared.windows.first {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup is handled by MenubarManager init
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If menubar mode and no visible windows, don't automatically reopen
        if UserDefaults.standard.bool(forKey: "menubarMode") && !flag {
            return false
        }

        // Otherwise, reopen the window
        if !flag {
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }
}
