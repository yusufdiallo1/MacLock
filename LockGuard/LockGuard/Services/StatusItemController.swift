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
    private let settingsWindow = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()

    /// True while a modal picker is up so `popoverDidClose` doesn't tear down
    /// state we intend to keep. See `runKeepingPopoverOpen`.
    private var isPresentingModal = false

    private let appLock: AppLockService
    /// True when a locked app is waiting for the user to authenticate.
    private var authPending = false

    init(permissions: PermissionsManager,
         lockManager: LockManager = .shared,
         appLock: AppLockService = .shared) {
        self.permissions = permissions
        self.lockManager = lockManager
        self.appLock = appLock
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

        // Status dot: red while a locked app is pending authentication.
        appLock.$pendingApp
            .receive(on: RunLoop.main)
            .sink { [weak self] pending in
                self?.authPending = (pending != nil)
                self?.updateAppearance()
            }
            .store(in: &cancellables)

        // Play the lock-close animation whenever everything (re)locks.
        NotificationCenter.default.publisher(for: .lockGuardDidLockAll)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.playLockAnimation() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.toolTip = "LockGuard"
        button.action = #selector(togglePopover)
        button.target = self
        updateAppearance()
    }

    private func configurePopover() {
        // Transient behavior gives a spring-in / fade-out feel and closes on
        // outside interaction. Our own monitor covers the remaining edges.
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Add-app/-folder now happens inline in the popover via PickerView, so
        // there's no modal panel to coordinate here.
        let root = LockPopoverView(
            lockManager: lockManager,
            permissions: permissions,
            onShowSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.quit() }
        )

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 320, height: 420)
    }

    /// The base lock symbol. `lock.shield` when armed (per spec), `lock.open`
    /// when setup is incomplete. Template image → auto light/dark.
    private func lockImage(symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LockGuard")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        // Always the face-scan glyph — matches the app icon/logo — regardless of
        // setup state. Template image → auto light/dark in the menu bar.
        button.image = lockImage(symbolName: "faceid")
        // State conveyed by tint, not a different glyph: red when an app is
        // pending auth, otherwise the plain template color.
        button.contentTintColor = authPending ? .systemRed : nil
    }

    /// Spring "lock closing" animation: a quick squash-and-settle on the button
    /// layer, played when apps are (re)locked.
    func playLockAnimation() {
        guard let layer = statusItem.button?.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.7
        spring.toValue = 1.0
        spring.damping = 8
        spring.stiffness = 180
        spring.mass = 0.4
        spring.initialVelocity = 6
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "lockBounce")
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

    /// Present an async file picker without the popover dismissing underneath
    /// it. `.transient` closes the popover the instant the panel takes key
    /// focus, so we drop to `.applicationDefined` and disarm the outside-click
    /// monitor while the panel is open, then restore both in the completion.
    /// The picker uses `begin` (not `runModal`), so the popover's run loop keeps
    /// spinning and SwiftUI still updates as items are added.
    ///
    /// `body` receives the LockManager and a completion it must call when the
    /// panel finishes.
    private func presentPicker(_ body: @escaping (LockManager, @escaping () -> Void) -> Void) {
        isPresentingModal = true
        stopMonitoringOutsideClicks()
        popover.behavior = .applicationDefined

        body(lockManager) { [weak self] in
            guard let self else { return }
            self.popover.behavior = .transient
            self.isPresentingModal = false
            // Re-arm only if the popover is still on screen after the picker.
            if self.popover.isShown {
                self.popover.contentViewController?.view.window?.makeKey()
                self.startMonitoringOutsideClicks()
            }
        }
    }

    // MARK: - Actions

    private func showOnboarding() {
        closePopover()
        permissions.refreshAll()
        onShowOnboarding?()
    }

    /// Gear button → authenticate, then open the real Settings window.
    private func showSettings() {
        closePopover()
        Task {
            if await AuthCoordinator.shared.requireAuth(reason: "Authenticate to open Settings") {
                settingsWindow.present()
            }
        }
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
