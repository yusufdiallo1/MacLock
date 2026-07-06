//
//  EnrollWindowController.swift
//  LockGuard
//
//  Hosts EnrollView (multi-angle face enrollment) in a centered window.
//

import AppKit
import SwiftUI

@MainActor
final class EnrollWindowController {
    static let shared = EnrollWindowController()
    private var window: NSWindow?

    func present() {
        if window == nil {
            let root = EnrollView(onClose: { [weak self] in self?.dismiss() })
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
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
