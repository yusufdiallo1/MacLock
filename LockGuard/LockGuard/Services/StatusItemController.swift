//
//  StatusItemController.swift
//  LockGuard
//
//  Owns the NSStatusItem in the menu bar and its menu.
//

import AppKit
import Combine

@MainActor
final class StatusItemController {

    /// Invoked when the user chooses to (re)open the onboarding / setup flow.
    var onShowOnboarding: (() -> Void)?

    private let statusItem: NSStatusItem
    private let permissions: PermissionsManager
    private var cancellables = Set<AnyCancellable>()

    init(permissions: PermissionsManager) {
        self.permissions = permissions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        buildMenu()

        // Keep the icon in sync with whether we're fully armed.
        permissions.$accessibility
            .combineLatest(permissions.$camera)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateAppearance() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = lockImage(armed: permissions.allGranted)
        button.image?.isTemplate = true
        button.toolTip = "LockGuard"
    }

    /// Custom SF Symbol lock icon; closed + shielded when armed, open when not.
    private func lockImage(armed: Bool) -> NSImage? {
        let symbol = armed ? "lock.shield.fill" : "lock.open"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: "LockGuard")?
            .withSymbolConfiguration(config)
    }

    private func updateAppearance() {
        statusItem.button?.image = lockImage(armed: permissions.allGranted)
        statusItem.button?.image?.isTemplate = true
    }

    private func buildMenu() {
        let menu = NSMenu()

        let setupItem = NSMenuItem(
            title: "Set Up LockGuard…",
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit LockGuard",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showOnboarding() {
        permissions.refreshAll()
        onShowOnboarding?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
