//
//  AdvancedPane.swift
//  LockGuard — Settings
//
//  Export/import settings (JSON, secrets excluded), reset to defaults (behind a
//  confirmation), reveal the encrypted log location, diagnostics, and the
//  version/build. Secrets — the app password (Keychain) and face embeddings
//  (FaceProfileStore) — live outside UserDefaults and are never in the export.
//

import SwiftUI
import AppKit

struct AdvancedPane: View {
    @ObservedObject var behavior: BehaviorSettings
    let onClose: () -> Void

    @State private var confirmReset = false
    @State private var note: (String, Bool)?

    /// The non-secret settings keys eligible for export/import. These are the
    /// Behavior toggles only — no password, no face data.
    private static let exportKeys = [
        "LG.sessionTimeout", "LG.lockOnSleep", "LG.schedEnabled", "LG.schedStart",
        "LG.schedEnd", "LG.faceSchedEnabled", "LG.faceSchedStart", "LG.faceSchedEnd",
        "LG.touchID", "LG.timerMode", "LG.launchAtLogin", "LG.deletionProtection",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupLabel(text: "Settings")
            SettingsCard {
                actionRow("Export Settings…", "Save your non-secret preferences as JSON. Passwords and face data are never included.",
                          system: "square.and.arrow.up", action: exportSettings)
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                actionRow("Import Settings…", "Load preferences from an exported JSON file.",
                          system: "square.and.arrow.down", action: importSettings)
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 15)).foregroundStyle(Theme.danger).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Reset to Defaults").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Restore all Behavior settings. Does not touch your password or face enrollment.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Reset") { confirmReset = true }.buttonStyle(DangerBtn()).focusable(false)
                }
                if let note {
                    Text(note.0).font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(note.1 ? Theme.success : Theme.danger).padding(.top, 8)
                }
            }

            GroupLabel(text: "Diagnostics")
            SettingsCard {
                actionRow("Open Log Location", "Reveal the encrypted authentication log in Finder.",
                          system: "folder", action: openLogLocation)
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                diagnosticRow("Version", version)
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                diagnosticRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                diagnosticRow("Bundle ID", Bundle.main.bundleIdentifier ?? "—")
            }
        }
        .confirmationDialog("Reset all Behavior settings to their defaults?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive, action: resetToDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your password and face enrollment are not affected.")
        }
    }

    // MARK: Rows

    private func actionRow(_ title: String, _ detail: String, system: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: system).font(.system(size: 15)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(title.replacingOccurrences(of: "…", with: ""), action: action).buttonStyle(GlassBtn()).focusable(false)
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: Actions

    private func exportSettings() {
        let d = UserDefaults.standard
        var dict: [String: Any] = [:]
        for k in Self.exportKeys where d.object(forKey: k) != nil { dict[k] = d.object(forKey: k) }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            note = ("Couldn't serialize settings.", false); return
        }
        let panel = NSSavePanel()
        panel.title = "Export LockGuard Settings"
        panel.nameFieldStringValue = "LockGuard-Settings.json"
        panel.allowedContentTypes = [.json]
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); note = ("Exported \(dict.count) settings.", true) }
            catch { note = ("Export failed: \(error.localizedDescription)", false) }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Import LockGuard Settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                note = ("Couldn't read that file.", false); return
            }
            let d = UserDefaults.standard
            var applied = 0
            for k in Self.exportKeys where dict[k] != nil { d.set(dict[k], forKey: k); applied += 1 }
            behavior.reload()
            note = ("Imported \(applied) settings.", true)
        }
    }

    private func resetToDefaults() {
        let d = UserDefaults.standard
        for k in Self.exportKeys { d.removeObject(forKey: k) }
        behavior.reload()
        note = ("Settings reset to defaults.", true)
    }

    private func openLogLocation() {
        let url = CryptoBox.appSupportDirectory().appendingPathComponent("auth.log.enc")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([CryptoBox.appSupportDirectory()])
        }
    }
}
