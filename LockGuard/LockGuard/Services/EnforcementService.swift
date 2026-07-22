//
//  EnforcementService.swift
//  LockGuard
//
//  Wires the Behavior preferences to real behavior:
//   • Accessibility revocation watcher — if Accessibility is turned off mid-
//     session, lock everything immediately and prompt to re-grant.
//   • Lock on sleep / screen lock — re-lock everything when the Mac sleeps.
//   • Session timeout — re-lock everything after the configured idle window.
//
//  Started once from AppDelegate. All timers/observers live for the app's life.
//

import AppKit
import Combine
import ApplicationServices

@MainActor
final class EnforcementService {
    static let shared = EnforcementService()

    private var accessibilityTimer: AnyCancellable?
    private var sessionTimer: AnyCancellable?
    private var lastAccessibilityGranted = AXIsProcessTrusted()
    private var lastUnlockActivity = Date()
    private var cancellables = Set<AnyCancellable>()

    /// Called when Accessibility is revoked mid-session.
    var onAccessibilityRevoked: (() -> Void)?

    private init() {}

    func start() {
        watchAccessibility()
        watchSleepAndScreenLock()
        watchSessionTimeout()
    }

    /// Reset the session-timeout clock (call on a successful unlock).
    func noteUnlockActivity() { lastUnlockActivity = Date() }

    // MARK: - Accessibility revocation

    private func watchAccessibility() {
        accessibilityTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkAccessibility() }
    }

    private func checkAccessibility() {
        let granted = AXIsProcessTrusted()
        if lastAccessibilityGranted && !granted {
            // Just revoked → lock everything now.
            LockManager.shared.lockAll()
            AppLockService.shared.relockAll()
            onAccessibilityRevoked?()
            PermissionsManager.shared.openSystemSettings(pane: "Privacy_Accessibility")
        }
        lastAccessibilityGranted = granted
    }

    // MARK: - Sleep / screen lock

    private func watchSleepAndScreenLock() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.lockIfEnabledOnSleep() }
            .store(in: &cancellables)
        wsnc.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.lockIfEnabledOnSleep() }
            .store(in: &cancellables)
        // Screen lock (login-window session).
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in self?.lockIfEnabledOnSleep() }
            .store(in: &cancellables)
    }

    private func lockIfEnabledOnSleep() {
        guard BehaviorSettings.shared.lockOnSleep else { return }
        LockManager.shared.lockAll()
        AppLockService.shared.relockAll()
    }

    // MARK: - Session timeout

    private func watchSessionTimeout() {
        sessionTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkSessionTimeout() }
    }

    private func checkSessionTimeout() {
        let minutes = BehaviorSettings.shared.sessionTimeoutMinutes
        // 0 = immediate (handled elsewhere), 31 = never (until manual).
        guard minutes >= 1, minutes < 31 else { return }
        let elapsed = Date().timeIntervalSince(lastUnlockActivity)
        if elapsed >= minutes * 60 {
            LockManager.shared.lockAll()
            AppLockService.shared.relockAll()
            lastUnlockActivity = Date()   // avoid repeat firing
        }
    }
}
