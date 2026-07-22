//
//  ScaffoldPanes.swift
//  LockGuard — Settings
//
//  The four panes whose backing services arrive in later prompts:
//  Appearance (37), Sync & Devices (24+28), Notifications (30), and Account &
//  Licensing (31). None fake functionality. Where real state already exists
//  today (live design tokens, this Mac's name, local-only auth mode), the pane
//  shows it read-only above an honest "arrives in a later update" notice.
//

import SwiftUI

// MARK: - Appearance (Prompt 37)

struct AppearancePane: View {
    var body: some View {
        ComingSoonPane(
            icon: "paintpalette.fill",
            headline: "Live accent, glass intensity, contrast & motion",
            detail: "You'll be able to change the accent color, dial glass intensity from subtle to vivid, toggle high-contrast and reduce-glass, and preview it all live."
        ) {
            // Real, already-true read-only content: the current design tokens.
            GroupLabel(text: "Current Theme")
            SettingsCard {
                swatchRow("Accent (primary)", Color.lgAccentPrimary)
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                swatchRow("Accent (secondary)", Color.lgAccentSecondary)
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                swatchRow("Success", Color.lgSuccess)
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                swatchRow("Warning", Color.lgWarning)
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                swatchRow("Danger", Color.lgDanger)
            }
        }
    }

    private func swatchRow(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color)
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Sync & Devices (Prompts 24 + 28)

struct SyncDevicesPane: View {
    var body: some View {
        ComingSoonPane(
            icon: "arrow.triangle.2.circlepath",
            headline: "Cloud sync and device management",
            detail: "Sign in to sync your non-secret settings across Macs and manage this and your other trusted devices. Face data and passwords never sync — they stay on each device."
        ) {
            GroupLabel(text: "This Mac")
            SettingsCard {
                infoRow("Device", Host.current().localizedName ?? "This Mac")
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 8)
                infoRow("Status", "Not registered — local only")
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
        }
    }
}

// MARK: - Notifications (Prompt 30)

struct NotificationsPane: View {
    /// Preview of the categories that will be toggleable — shown disabled.
    private let categories = [
        ("Failed unlock attempts", "exclamationmark.shield"),
        ("New device signed in", "laptopcomputer"),
        ("Scheduled lock activated", "clock.badge"),
        ("Kill switch triggered", "bolt.shield"),
    ]

    var body: some View {
        ComingSoonPane(
            icon: "bell.badge.fill",
            headline: "Per-category notifications",
            detail: "Choose which security events notify you. These categories will each get their own toggle."
        ) {
            GroupLabel(text: "Categories (preview)")
            SettingsCard {
                ForEach(Array(categories.enumerated()), id: \.offset) { i, cat in
                    HStack(spacing: 11) {
                        Image(systemName: cat.1).font(.system(size: 14)).foregroundStyle(Theme.inkFaint).frame(width: 20)
                        Text(cat.0).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                        Spacer()
                        Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).disabled(true)
                    }
                    .padding(.vertical, 5)
                    if i < categories.count - 1 { Divider().overlay(Theme.hairline.opacity(0.4)) }
                }
            }
        }
    }
}

// MARK: - Account & Licensing (Prompt 31)

struct AccountPane: View {
    var body: some View {
        ComingSoonPane(
            icon: "person.text.rectangle.fill",
            headline: "Sign in for sync, plan & billing",
            detail: "An account is optional — all locking works offline. Signing in enables cloud sync and remote device management, and is where your plan and billing will live."
        ) {
            GroupLabel(text: "Account")
            SettingsCard {
                HStack(spacing: 11) {
                    Image(systemName: "person.crop.circle.badge.xmark").font(.system(size: 18)).foregroundStyle(Theme.inkFaint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Not signed in").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Local-only mode. Sync and remote features stay off until you sign in.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Sign In") {}.buttonStyle(GlassBtn()).focusable(false).disabled(true)
                }
            }
        }
    }
}
