//
//  BehaviorSettings.swift
//  LockGuard
//
//  User-tunable behavior: session timeout, lock-on-sleep, a scheduled lock
//  window, a face-unlock schedule, and the Touch ID preference. Persisted to
//  UserDefaults. The Behavior settings tab binds directly to these.
//
//  NOTE: These are stored preferences; the enforcement that reads them (auto-
//  lock timers, sleep observers, schedule checks) is wired incrementally — the
//  values live here so the UI and any enforcement share one source of truth.
//

import Foundation
import Combine
import LocalAuthentication

@MainActor
final class BehaviorSettings: ObservableObject {
    static let shared = BehaviorSettings()

    /// Minutes of inactivity before auto-lock (0 = never … 31).
    @Published var sessionTimeoutMinutes: Double {
        didSet { UserDefaults.standard.set(sessionTimeoutMinutes, forKey: "LG.sessionTimeout") }
    }
    /// Lock everything when the Mac goes to sleep.
    @Published var lockOnSleep: Bool {
        didSet { UserDefaults.standard.set(lockOnSleep, forKey: "LG.lockOnSleep") }
    }
    /// Enable a daily scheduled-lock window.
    @Published var scheduledLockEnabled: Bool {
        didSet { UserDefaults.standard.set(scheduledLockEnabled, forKey: "LG.schedEnabled") }
    }
    /// Scheduled-lock start/end, stored as minutes-since-midnight.
    @Published var scheduledStartMinutes: Double {
        didSet { UserDefaults.standard.set(scheduledStartMinutes, forKey: "LG.schedStart") }
    }
    @Published var scheduledEndMinutes: Double {
        didSet { UserDefaults.standard.set(scheduledEndMinutes, forKey: "LG.schedEnd") }
    }
    /// Only allow face unlock during a time window (e.g. work hours).
    @Published var faceScheduleEnabled: Bool {
        didSet { UserDefaults.standard.set(faceScheduleEnabled, forKey: "LG.faceSchedEnabled") }
    }
    @Published var faceStartMinutes: Double {
        didSet { UserDefaults.standard.set(faceStartMinutes, forKey: "LG.faceSchedStart") }
    }
    @Published var faceEndMinutes: Double {
        didSet { UserDefaults.standard.set(faceEndMinutes, forKey: "LG.faceSchedEnd") }
    }
    /// Allow Touch ID (via LocalAuthentication) as an unlock method.
    @Published var touchIDEnabled: Bool {
        didSet { UserDefaults.standard.set(touchIDEnabled, forKey: "LG.touchID") }
    }

    private init() {
        let d = UserDefaults.standard
        sessionTimeoutMinutes = d.object(forKey: "LG.sessionTimeout") as? Double ?? 5
        lockOnSleep = d.object(forKey: "LG.lockOnSleep") as? Bool ?? true
        scheduledLockEnabled = d.bool(forKey: "LG.schedEnabled")
        scheduledStartMinutes = d.object(forKey: "LG.schedStart") as? Double ?? (22 * 60)
        scheduledEndMinutes = d.object(forKey: "LG.schedEnd") as? Double ?? (7 * 60)
        faceScheduleEnabled = d.bool(forKey: "LG.faceSchedEnabled")
        faceStartMinutes = d.object(forKey: "LG.faceSchedStart") as? Double ?? (9 * 60)
        faceEndMinutes = d.object(forKey: "LG.faceSchedEnd") as? Double ?? (17 * 60)
        touchIDEnabled = d.bool(forKey: "LG.touchID")
    }

    /// Whether this Mac actually has Touch ID / biometrics available.
    var biometricsAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// "22:00" style label from minutes-since-midnight.
    static func timeLabel(_ minutes: Double) -> String {
        let m = Int(minutes)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
