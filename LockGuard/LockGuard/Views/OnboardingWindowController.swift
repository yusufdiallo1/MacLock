//
//  OnboardingWindowController.swift
//  LockGuard
//
//  Hosts the SwiftUI onboarding view in a borderless, centered panel. Because
//  LockGuard is an accessory app with no main window, this controller also
//  temporarily brings the app forward so the panel takes focus.
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {

    private var window: NSWindow?
    private let permissions: PermissionsManager
    private let onFinish: () -> Void

    init(permissions: PermissionsManager, onFinish: @escaping () -> Void) {
        self.permissions = permissions
        self.onFinish = onFinish
    }

    func present() {
        if window == nil {
            let root = OnboardingView(permissions: permissions) { [weak self] in
                self?.dismiss()
            }

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
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.center()   // always re-center on present
        window?.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.close()
        window = nil
        onFinish()
    }
}
