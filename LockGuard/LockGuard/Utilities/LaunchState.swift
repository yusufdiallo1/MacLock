//
//  LaunchState.swift
//  LockGuard
//
//  Thin, typed wrapper over the small amount of state we persist in defaults.
//

import Foundation

enum LaunchState {
    private static let onboardingKey = "com.lockguard.hasCompletedOnboarding"

    /// True once the user has finished (or explicitly dismissed) onboarding.
    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }
}
