//
//  AuthCoordinator.swift
//  LockGuard
//
//  The single auth brain shared by every gate (app overlay, folder overlay,
//  Settings gate, destructive-action confirmation). It:
//   • presents a reusable centered auth modal — `requireAuth(reason:) async`
//   • rate-limits failures — after 5 fails, face is disabled + 30 s cooldown,
//     password-only, per the hardening spec
//   • wipes the in-memory face profile after 3 min of inactivity, forcing a
//     Keychain reload (re-auth) on next use
//   • is the single choke point that logs every attempt (AuthLogService, later)
//
//  Rate-limit + inactivity state is @Published so the auth card can react.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AuthCoordinator: ObservableObject {
    static let shared = AuthCoordinator()

    // MARK: - Rate limiting (hardening: 5 fails → password-only + 30 s cooldown)

    static let failureThreshold = 5
    static let cooldownSeconds = 30

    @Published private(set) var failureCount = 0
    @Published private(set) var faceLockedOut = false
    @Published private(set) var cooldownSecondsRemaining = 0

    // MARK: - Inactivity wipe (hardening: 3 min idle → evict in-memory face)

    static let inactivityWipeSeconds: TimeInterval = 180

    private var cooldownTimer: AnyCancellable?
    private var cooldownDeadline: Date?
    private var inactivityTimer: AnyCancellable?

    private var gateWindow: NSWindow?

    private init() {
        armInactivityTimer()
    }

    // MARK: - Whether face is allowed right now

    /// Face unlock is permitted only when not locked out, not in kill-switch,
    /// and (if a face-unlock schedule is set) within the allowed hours.
    var faceAllowedNow: Bool {
        guard !faceLockedOut, cooldownSecondsRemaining == 0 else { return false }
        guard !FaceAuthService.shared.isKillSwitchActive else { return false }
        return faceScheduleAllowsNow
    }

    private var faceScheduleAllowsNow: Bool {
        let b = BehaviorSettings.shared
        guard b.faceScheduleEnabled else { return true }
        let now = Self.minutesSinceMidnight(Date())
        let start = Int(b.faceStartMinutes), end = Int(b.faceEndMinutes)
        // Face unlock is DISABLED during the configured window (per reference:
        // "Disable Face Unlock during certain hours").
        let inWindow = start <= end
            ? (now >= start && now < end)
            : (now >= start || now < end)   // window wraps midnight
        return !inWindow
    }

    // MARK: - Reusable modal auth

    /// Present a centered auth modal and resolve `true` only on verified success.
    /// Short-circuits `true` when nothing is set up yet (first run), so the user
    /// can reach Settings to configure a password / face.
    func requireAuth(reason: String, allowFace: Bool = true) async -> Bool {
        noteActivity()

        // Nothing to authenticate against yet → allow through.
        if !PasswordAuthService.shared.isPasswordSet && !FaceAuthService.shared.isEnrolled {
            return true
        }

        return await withCheckedContinuation { continuation in
            presentGate(reason: reason, allowFace: allowFace) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// The pending gate's resolver. Owned by the coordinator (not a view/closure)
    /// so EVERY teardown path resolves it exactly once — never a leaked
    /// continuation (which would hang `requireAuth` forever), never a double
    /// resume. `resolve(_:)` is idempotent.
    private var pendingCompletion: ((Bool) -> Void)?

    private func resolve(_ success: Bool) {
        guard let completion = pendingCompletion else { return }
        pendingCompletion = nil
        completion(success)
    }

    private func presentGate(
        reason: String,
        allowFace: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        // Tear down any existing gate first — its continuation resolves false.
        dismissGate()
        pendingCompletion = completion

        // Password/face outcomes are recorded by AuthGateView with the correct
        // method; the coordinator only resolves + dismisses here.
        let root = AuthGateView(
            title: "Authenticate to proceed",
            subtitle: reason,
            icon: NSApp.applicationIconImage,
            allowFace: allowFace && faceAllowedNow,
            verifyPassword: { PasswordAuthService.shared.verify($0) },
            onSuccess: { [weak self] in self?.dismissGate(resolveWith: true) },
            onCancel: { [weak self] in self?.dismissGate(resolveWith: false) }
        )

        let hosting = NSHostingController(rootView: root)
        let window = GateWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .modalPanel
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        // If the window is closed by any other path, resolve false (no hang).
        window.onClose = { [weak self] in self?.resolve(false) }
        window.center()
        gateWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Dismiss the gate and resolve the pending continuation. Called by success/
    /// cancel, re-entrant presentGate, and any external teardown — always
    /// resolves so `requireAuth` can never hang.
    func dismissGate(resolveWith success: Bool = false) {
        if let window = gateWindow as? GateWindow { window.onClose = nil }
        gateWindow?.orderOut(nil)
        gateWindow = nil
        FaceAuthService.shared.cancel()
        resolve(success)
    }

    // MARK: - Record outcomes (single choke point → training + logging)

    enum Method { case face, password }

    func recordSuccess(method: Method, context: String = "") {
        noteActivity()
        EnforcementService.shared.noteUnlockActivity()   // reset session timer
        failureCount = 0
        faceLockedOut = false
        stopCooldown()
        AuthLogService.shared.log(method: method, success: true, context: context)
    }

    func recordFailure(method: Method, context: String = "") {
        noteActivity()
        failureCount += 1
        AuthLogService.shared.log(method: method, success: false, context: context)
        if failureCount >= Self.failureThreshold {
            startCooldown()
        }
    }

    // MARK: - Cooldown

    private func startCooldown() {
        faceLockedOut = true
        cooldownDeadline = Date().addingTimeInterval(TimeInterval(Self.cooldownSeconds))
        cooldownSecondsRemaining = Self.cooldownSeconds
        cooldownTimer?.cancel()
        cooldownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickCooldown() }
    }

    private func tickCooldown() {
        guard let deadline = cooldownDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { endCooldown() }
        else { cooldownSecondsRemaining = Int(remaining.rounded(.up)) }
    }

    private func endCooldown() {
        stopCooldown()
        faceLockedOut = false
        failureCount = 0   // give face another chance after the cooldown
    }

    private func stopCooldown() {
        cooldownTimer?.cancel()
        cooldownTimer = nil
        cooldownDeadline = nil
        cooldownSecondsRemaining = 0
    }

    // MARK: - Inactivity → wipe in-memory face profile

    /// Reset the 3-minute idle timer. Call on any auth activity / Settings open.
    func noteActivity() {
        cooldownDeadline.map { _ in }   // no-op, keeps cooldown independent
        armInactivityTimer()
    }

    private func armInactivityTimer() {
        inactivityTimer?.cancel()
        inactivityTimer = Timer.publish(every: Self.inactivityWipeSeconds, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in self?.wipeFaceFromMemory() }
    }

    private func wipeFaceFromMemory() {
        FaceAuthService.shared.evictInMemoryProfile()
        // Re-arm so the next window of activity is timed afresh.
        armInactivityTimer()
    }

    // MARK: - Helpers

    private static func minutesSinceMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// A borderless auth window that reports when it closes for any reason, so the
/// coordinator can always resolve its pending continuation (never a hang).
private final class GateWindow: NSWindow {
    var onClose: (() -> Void)?
    override func close() { onClose?(); onClose = nil; super.close() }
}
