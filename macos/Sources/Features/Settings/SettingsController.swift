import Foundation
import Cocoa
import SwiftUI

class SettingsController: NSWindowController, NSWindowDelegate {
    static let shared: SettingsController = SettingsController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: 520, height: 440)
        window.maxSize = NSSize(width: 900, height: 800)
        window.setFrameAutosaveName("GhosttySettings")
        self.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView())
    }

    // MARK: - Functions

    func show() {
        // Only center if no saved frame (first launch)
        if !window!.setFrameUsingName("GhosttySettings") {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.close()
    }

    // MARK: - First Responder

    @IBAction func close(_ sender: Any) {
        self.window?.performClose(sender)
    }

    @IBAction func closeWindow(_ sender: Any) {
        self.window?.performClose(sender)
    }

    @objc func cancel(_ sender: Any?) {
        close()
    }
}
