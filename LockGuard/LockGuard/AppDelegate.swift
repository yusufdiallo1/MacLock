//
//  AppDelegate.swift
//  LockGuard
//
//  Owns the status item, the onboarding window, and first-launch coordination.
//

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusItemController?
    private var onboardingWindow: OnboardingWindowController?
    private let permissions = PermissionsManager.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: Info.plist LSUIElement already hides the dock
        // icon, but set the policy explicitly so debug builds behave too.
        NSApp.setActivationPolicy(.accessory)

        statusController = StatusItemController(permissions: permissions)
        statusController?.onShowOnboarding = { [weak self] in
            self?.presentOnboarding()
        }

        permissions.refreshAll()

        if !LaunchState.hasCompletedOnboarding {
            presentOnboarding()
        }
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
