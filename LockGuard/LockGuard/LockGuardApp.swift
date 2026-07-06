//
//  LockGuardApp.swift
//  LockGuard
//
//  Menu bar only app entry point. The app has no main window and no dock
//  icon (LSUIElement = YES). All lifecycle work is driven from AppDelegate.
//

import SwiftUI

@main
struct LockGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A menu-bar-only app has no Scene of its own. Settings{} is an empty,
        // never-presented scene that satisfies the App protocol without adding
        // a window to the dock or app switcher.
        Settings {
            EmptyView()
        }
    }
}
