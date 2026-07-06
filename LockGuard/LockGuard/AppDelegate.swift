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

    /// Bridge the enforcement pipeline to the (not-yet-built) auth overlay.
    /// When a locked app is activated, AppLockService posts this notification;
    /// for now we bring LockGuard forward and log which app tripped the lock.
    /// Replace the body with the real overlay presentation once it exists.
    private func observeAuthOverlayRequests() {
        NotificationCenter.default.publisher(for: .lockGuardShouldPresentAuthOverlay)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                let app = note.userInfo?[AppLockService.lockedAppUserInfoKey] as? LockedApp
                NSLog("LockGuard: locked app activated — %@", app?.bundleID ?? "unknown")
                self?.presentAuthOverlayPlaceholder(for: app)
            }
            .store(in: &cancellables)
    }

    private func presentAuthOverlayPlaceholder(for app: LockedApp?) {
        // TODO: present the real full-screen auth overlay + face recognition,
        // and call appLock.clearPending() when auth passes or is cancelled.
        // We deliberately do NOT clear here: the challenge guard must stay set
        // until the locked app deactivates, or focus bouncing back to it would
        // re-fire immediately. Just surface LockGuard so the trigger is visible.
        NSApp.activate(ignoringOtherApps: true)
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
