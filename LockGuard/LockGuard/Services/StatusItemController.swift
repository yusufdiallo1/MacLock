//
//  StatusItemController.swift
//  LockGuard
//
//  Owns the NSStatusItem in the menu bar and the Liquid Glass popover it
//  presents. Left-click toggles the popover; the popover hosts the SwiftUI
//  LockPopoverView. A transient event monitor closes it on outside clicks.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusItemController: NSObject {

    /// Invoked when the user chooses to (re)open the onboarding / setup flow.
    var onShowOnboarding: (() -> Void)?

    private let statusItem: NSStatusItem
    private let permissions: PermissionsManager
    private let lockManager: LockManager
    private let popover: NSPopover
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// True while a modal picker is up so `popoverDidClose` doesn't tear down
    /// state we intend to keep. See `runKeepingPopoverOpen`.
    private var isPresentingModal = false

    init(permissions: PermissionsManager, lockManager: LockManager = .shared) {
        self.permissions = permissions
        self.lockManager = lockManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureButton()
        configurePopover()

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
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func configurePopover() {
        // Transient behavior gives a spring-in / fade-out feel and closes on
        // outside interaction. Our own monitor covers the remaining edges.
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // The picker callbacks are routed through the controller so it can
        // suspend the popover's transient auto-dismiss while a modal panel is
        // up — otherwise the panel taking focus would close the popover.
        let root = LockPopoverView(
            lockManager: lockManager,
            permissions: permissions,
            onAddApps: { [weak self] in self?.presentPicker { $0.presentAddApps() } },
            onAddFolders: { [weak self] in self?.presentPicker { $0.presentAddFolders() } },
            onShowSettings: { [weak self] in self?.showOnboarding() },
            onQuit: { [weak self] in self?.quit() }
        )

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 320, height: 420)
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

    // MARK: - Popover presentation

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        permissions.refreshAll()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Bring the popover window forward so it can take key input. On macOS 14+
        // the argument-less activate() cooperates with the window server instead
        // of yanking focus the way ignoringOtherApps: true does.
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        startMonitoringOutsideClicks()
    }

    private func closePopover() {
        // Teardown happens in popoverDidClose, the one path every close routes
        // through — including .transient auto-dismiss.
        popover.performClose(nil)
    }

    /// A global monitor so a click in another app closes the popover. The
    /// `.transient` behavior already handles clicks within our own windows.
    private func startMonitoringOutsideClicks() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Modal pickers

    /// Present a modal picker without the popover dismissing underneath it.
    /// `.transient` closes the popover the instant the panel takes key focus,
    /// so we drop to `.applicationDefined`, disarm the outside-click monitor
    /// for the duration, run the (blocking) picker, then restore both.
    private func presentPicker(_ body: @escaping (LockManager) -> Void) {
        isPresentingModal = true
        stopMonitoringOutsideClicks()
        popover.behavior = .applicationDefined

        body(lockManager)

        popover.behavior = .transient
        isPresentingModal = false
        // Re-arm only if the popover is still on screen after the picker.
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
            startMonitoringOutsideClicks()
        }
    }

    // MARK: - Actions

    private func showOnboarding() {
        closePopover()
        permissions.refreshAll()
        onShowOnboarding?()
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSPopoverDelegate

extension StatusItemController: NSPopoverDelegate {
    /// The single teardown choke point: whether the popover closed via our
    /// button, an outside click, Esc, or `.transient` auto-dismiss, we always
    /// land here — so the global monitor can never leak. Skipped while a modal
    /// picker is deliberately holding the popover open.
    func popoverDidClose(_ notification: Notification) {
        guard !isPresentingModal else { return }
        stopMonitoringOutsideClicks()
    }
}
