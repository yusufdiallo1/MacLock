//
//  AppDelegate.swift
//  LockGuard
//
//  Owns the status item, the onboarding window, and first-launch coordination.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusItemController?
    private var onboardingWindow: OnboardingWindowController?
    private let permissions = PermissionsManager.shared
    // Held so its activation observer lives for the app's lifetime.
    private let appLock = AppLockService.shared
    private let overlay = WindowOverlayService()
    private let passwordAuth = PasswordAuthService.shared
    private var killSwitchMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: Info.plist LSUIElement already hides the dock
        // icon, but set the policy explicitly so debug builds behave too.
        NSApp.setActivationPolicy(.accessory)

        statusController = StatusItemController(permissions: permissions)
        statusController?.onShowOnboarding = { [weak self] in
            self?.presentOnboarding()
        }

        observeAuthOverlayRequests()
        installKillSwitchHotkey()

        permissions.refreshAll()

        if !LaunchState.hasCompletedOnboarding {
            presentOnboarding()
        }
    }

    /// Bridge the enforcement pipeline to the auth overlay. When a locked app
    /// is activated, AppLockService posts this notification; we resolve the
    /// running app's PID and present WindowOverlayService over its window.
    private func observeAuthOverlayRequests() {
        // When the overlay resolves (auth passed or cancelled), release the
        // challenge guard so the same app can challenge again next activation.
        overlay.onResolved = { [weak self] in self?.appLock.clearPending() }

        NotificationCenter.default.publisher(for: .lockGuardShouldPresentAuthOverlay)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let app = note.userInfo?[AppLockService.lockedAppUserInfoKey] as? LockedApp
                else { return }
                self?.presentOverlay(for: app)
            }
            .store(in: &cancellables)
    }

    private func presentOverlay(for app: LockedApp) {
        // Resolve the running instance's PID from the bundle ID. If the app
        // isn't actually running (rare race), there's nothing to cover.
        guard let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: app.bundleID).first
        else {
            NSLog("LockGuard: %@ not running; nothing to overlay", app.bundleID)
            appLock.clearPending()
            return
        }
        overlay.present(forPID: running.processIdentifier, appName: app.name)
    }

    // MARK: - Emergency kill switch

    /// Ctrl+Option+Shift+Delete, system-wide. A global monitor covers other
    /// apps; a local monitor covers the case where LockGuard itself is focused.
    /// Requires Accessibility permission for the global monitor to see keys in
    /// other apps (already part of onboarding).
    ///
    /// LIMITATION: NSEvent global monitors are observe-only — they can't consume
    /// the event. So when another app is frontmost, the combo also reaches that
    /// app (Delete + modifiers). The kill switch still fires correctly; only the
    /// keystroke isn't swallowed. Suppressing it system-wide would require a
    /// CGEventTap. The local monitor DOES swallow it when LockGuard is focused.
    private func installKillSwitchHotkey() {
        let handler: (NSEvent) -> Bool = { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let wanted: NSEvent.ModifierFlags = [.control, .option, .shift]
            // keyCode 51 = Delete (Backspace). Require exactly the three mods.
            guard event.keyCode == 51, mods == wanted else { return false }
            self?.passwordAuth.triggerKillSwitch()
            return true
        }

        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handler(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Swallow the event if it was our shortcut.
            handler(event) ? nil : event
        }
        killSwitchMonitors = [global, local].compactMap { $0 }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The menu bar app outlives its windows.
        false
    }

    private func presentOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(permissions: permissions) { [weak self] in
                LaunchState.hasCompletedOnboarding = true
                self?.onboardingWindow = nil
            }
        }
        onboardingWindow?.present()
    }
}
