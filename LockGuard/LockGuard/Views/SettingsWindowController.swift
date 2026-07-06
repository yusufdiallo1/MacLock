//
//  SettingsWindowController.swift
//  LockGuard
//
//  Hosts SettingsView in a titled window, opened from the popover's gear
//  button. Reuses the shared service singletons so changes take effect live.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    private var window: NSWindow?

    func present() {
        if window == nil {
            let root = SettingsView(
                password: .shared,
                face: .shared,
                onClose: { [weak self] in self?.dismiss() }
            )
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .fullSizeContentView, .closable]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Theme.ground)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
