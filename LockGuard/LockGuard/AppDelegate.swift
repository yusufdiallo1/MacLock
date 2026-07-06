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
