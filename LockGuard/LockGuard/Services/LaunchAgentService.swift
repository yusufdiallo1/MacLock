//
//  LaunchAgentService.swift
//  LockGuard
//
//  "App Deletion Protection": a launchd LaunchAgent with KeepAlive that
//  relaunches LockGuard within seconds if it's quit or killed. Also handles
//  Launch-at-Login via SMAppService.
//
//  HONEST SCOPE: this cannot prevent the .app bundle from being deleted (no
//  macOS API allows that for an unsandboxed app). It restarts the *process* if
//  it dies. The UI copy says exactly that.
//

import Foundation
import ServiceManagement
import AppKit

@MainActor
final class LaunchAgentService {
    static let shared = LaunchAgentService()

    private let agentLabel = "com.lockguard.agent"
    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private init() {}

    // MARK: - Deletion protection (KeepAlive LaunchAgent)

    var isDeletionProtectionInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setDeletionProtection(_ enabled: Bool) {
        enabled ? installAgent() : removeAgent()
    }

    private func installAgent() {
        guard let exePath = Bundle.main.executablePath else { return }
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [exePath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: plistURL, options: .atomic)

        // Load it into the current GUI session so it takes effect now.
        let uid = getuid()
        runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        runLaunchctl(["enable", "gui/\(uid)/\(agentLabel)"])
    }

    private func removeAgent() {
        let uid = getuid()
        runLaunchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private func runLaunchctl(_ args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = nil
        task.standardError = nil
        do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 0 }
        catch { return false }
    }

    // MARK: - Launch at login (SMAppService)

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LockGuard: launch-at-login toggle failed: %@", error.localizedDescription)
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
