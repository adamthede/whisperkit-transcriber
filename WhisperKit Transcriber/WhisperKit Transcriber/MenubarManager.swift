//
//  MenubarManager.swift
//  WhisperKit Transcriber
//
//  Manages menubar icon and menu
//

import AppKit
import SwiftUI

class MenubarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?

    @Published var isMenubarMode = false

    init() {
        // Load preference from UserDefaults
        isMenubarMode = UserDefaults.standard.bool(forKey: "menubarMode")

        if isMenubarMode {
            setupMenubar()
        }

        // Listen for menubar mode toggle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenubarToggle(_:)),
            name: .toggleMenubarMode,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleMenubarToggle(_ notification: Notification) {
        if let enabled = notification.object as? Bool {
            isMenubarMode = enabled
            if enabled {
                setupMenubar()
                NSApp.setActivationPolicy(.accessory)
            } else {
                removeMenubar()
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    func setupMenubar() {
        guard statusItem == nil else { return }

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem,
              let button = statusItem.button else {
            return
        }

        // Set icon
        if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisperKit Transcriber") {
            image.isTemplate = true
            button.image = image
        }

        button.action = #selector(togglePopover(_:))
        button.target = self

        // Add right-click menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quick Transcribe", action: #selector(showQuickTranscribe), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Main Window", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Set targets for menu items
        if let quickTranscribeItem = menu.item(withTitle: "Quick Transcribe") {
            quickTranscribeItem.target = self
        }
        if let openWindowItem = menu.item(withTitle: "Open Main Window") {
            openWindowItem.target = self
        }
        if let prefsItem = menu.item(withTitle: "Preferences...") {
            prefsItem.target = self
        }

        statusItem.menu = menu

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 500)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenubarQuickView()
        )

        // Setup event monitor to close popover when clicking outside
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                self?.closePopover()
            }
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let popover = popover,
              let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            showPopover(button: button)
        }
    }

    func showPopover(button: NSStatusBarButton) {
        guard let popover = popover else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
    }

    func closePopover() {
        popover?.performClose(nil)
        eventMonitor?.stop()
    }

    @objc func showQuickTranscribe() {
        guard let button = statusItem?.button else { return }
        showPopover(button: button)
    }

    @objc func openMainWindow() {
        // Try to find existing window
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible == false || $0.title.contains("WhisperKit") }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // If no window found, just activate the app which should create one
            NSApp.activate(ignoringOtherApps: true)
        }
        closePopover()
    }

    @objc func showPreferences() {
        openMainWindow()
        // Preferences would be in the main window
    }

    func removeMenubar() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
        eventMonitor = nil
    }

    func toggleMenubarMode() {
        isMenubarMode.toggle()
        UserDefaults.standard.set(isMenubarMode, forKey: "menubarMode")

        if isMenubarMode {
            setupMenubar()
            // Optionally hide dock icon
            NSApp.setActivationPolicy(.accessory)
        } else {
            removeMenubar()
            // Show dock icon
            NSApp.setActivationPolicy(.regular)
        }
    }
}

// Event monitor for detecting clicks outside popover
class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// Notification name for menubar mode toggle
extension Notification.Name {
    static let toggleMenubarMode = Notification.Name("toggleMenubarMode")
}
