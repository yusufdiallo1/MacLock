//
//  SettingsView.swift
//  LockGuard — Settings
//
//  The Settings window shell: a Liquid Glass sidebar with a search field and a
//  ten-pane registry, and a scrolling content area that routes to one pane
//  view at a time. The pane registry (`SettingsPane`) is the single source of
//  truth for the sidebar rows, the cross-pane search index, and (later) the
//  notification deep-links from Prompt 30.
//
//  Six panes are fully backed today (Locked Apps, Locked Folders,
//  Authentication, Security, Behavior, Advanced). Four await services from
//  later prompts (Appearance/37, Sync & Devices/24+28, Notifications/30,
//  Account/31) — those render an honest ComingSoonPane, never faked controls.
//

import SwiftUI

// MARK: - Pane registry

/// Every Settings pane. `available` is false for panes whose backing service
/// arrives in a later prompt; flipping it to true (and adding the real body in
/// the router) is the wiring point for that prompt.
enum SettingsPane: String, CaseIterable, Identifiable {
    case apps          = "Locked Apps"
    case folders       = "Locked Folders"
    case authentication = "Authentication"
    case security      = "Security"
    case behavior      = "Behavior"
    case appearance    = "Appearance"
    case sync          = "Sync & Devices"
    case notifications = "Notifications"
    case account       = "Account & Licensing"
    case advanced      = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .apps:           return "lock.square"
        case .folders:        return "folder.fill.badge.gearshape"
        case .authentication: return "person.crop.circle"
        case .security:       return "shield.lefthalf.filled"
        case .behavior:       return "gearshape.2"
        case .appearance:     return "paintpalette"
        case .sync:           return "arrow.triangle.2.circlepath"
        case .notifications:  return "bell.badge"
        case .account:        return "person.text.rectangle"
        case .advanced:       return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .apps:           return "Choose which apps require authentication."
        case .folders:        return "Hide and gate folders behind authentication."
        case .authentication: return "Tune Face Unlock, Touch ID, and password fallback."
        case .security:       return "Kill switch, rate limiting, and anti-tamper controls."
        case .behavior:       return "Adjust launch, locking, schedules, and emergency controls."
        case .appearance:     return "Accent color, glass intensity, contrast, and motion."
        case .sync:           return "Cloud sync and this Mac's device registration."
        case .notifications:  return "Choose which events notify you."
        case .account:        return "Sign in for cloud sync, plan, and billing."
        case .advanced:       return "Export/import, reset, logs, and diagnostics."
        }
    }

    /// Extra terms the search field matches beyond the title.
    var keywords: [String] {
        switch self {
        case .apps:           return ["app", "lock", "block", "picker", "timer"]
        case .folders:        return ["folder", "directory", "hide", "stash", "files"]
        case .authentication: return ["face", "faceid", "camera", "touch id", "password", "biometric", "enroll", "sensitivity"]
        case .security:       return ["kill switch", "rate limit", "cooldown", "lockout", "phishing", "impostor", "tamper", "deletion protection"]
        case .behavior:       return ["timeout", "session", "sleep", "schedule", "launch at login", "emergency", "shortcut"]
        case .appearance:     return ["accent", "color", "glass", "theme", "contrast", "transparency", "motion", "dark"]
        case .sync:           return ["sync", "cloud", "supabase", "device", "backup", "remote"]
        case .notifications:  return ["notify", "alert", "notification", "badge"]
        case .account:        return ["account", "sign in", "login", "license", "plan", "billing", "subscription"]
        case .advanced:       return ["export", "import", "reset", "log", "diagnostics", "version", "build", "json"]
        }
    }

    /// Whether a real, functional body exists today.
    var available: Bool {
        switch self {
        case .apps, .folders, .authentication, .security, .behavior, .advanced:
            return true
        case .appearance, .sync, .notifications, .account:
            return false   // backing service arrives in a later prompt
        }
    }
}

// MARK: - Shell

struct SettingsView: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var face: FaceAuthService
    let onClose: () -> Void

    @StateObject private var lockManager = LockManager.shared
    @StateObject private var behavior = BehaviorSettings.shared

    /// Persisted so re-opening Settings lands on the last pane the user used.
    @AppStorage("settings.lastPane") private var lastPaneRaw = SettingsPane.apps.rawValue
    @State private var pane: SettingsPane = .apps
    @State private var search = ""

    private var visiblePanes: [SettingsPane] {
        guard !search.isEmpty else { return SettingsPane.allCases }
        let q = search.lowercased()
        return SettingsPane.allCases.filter { p in
            p.rawValue.lowercased().contains(q) || p.keywords.contains { $0.contains(q) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(width: 760, height: 600)
        .background(Theme.ground)
        .onAppear { pane = SettingsPane(rawValue: lastPaneRaw) ?? .apps }
        .onChange(of: pane) { _, new in lastPaneRaw = new.rawValue }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LockGuard").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Text("Settings").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 14)

            searchField.padding(.horizontal, 12).padding(.bottom, 12)

            Text("PREFERENCES").font(.system(size: 10, weight: .semibold)).tracking(0.7)
                .foregroundStyle(Theme.inkFaint).padding(.horizontal, 16).padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visiblePanes) { sidebarItem($0) }
                    if visiblePanes.isEmpty {
                        Text("No settings match “\(search)”.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.inkFaint)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                Text("Protected locally").font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(width: 220)
        .lgGlass(.panel)
        .overlay(Rectangle().fill(Theme.hairline).frame(width: 1), alignment: .trailing)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            TextField("Search settings…", text: $search).textFieldStyle(.plain).font(.system(size: 12.5))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }.buttonStyle(.plain).focusable(false)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface))
    }

    private func sidebarItem(_ p: SettingsPane) -> some View {
        Button { pane = p } label: {
            HStack(spacing: 11) {
                Image(systemName: p.symbol).font(.system(size: 13, weight: .medium)).frame(width: 22)
                Text(p.rawValue).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if !p.available {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                }
            }
            .foregroundStyle(pane == p ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(pane == p ? Theme.accent.opacity(0.22) : .clear))
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
        }
        .buttonStyle(.plain).focusable(false)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(title: pane.rawValue, subtitle: pane.subtitle)
                paneBody
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch pane {
        case .apps:           LockedAppsPane(lockManager: lockManager)
        case .folders:        LockedFoldersPane(lockManager: lockManager)
        case .authentication: AuthenticationPane(password: password, face: face, behavior: behavior)
        case .security:       SecurityPane(password: password, behavior: behavior)
        case .behavior:       BehaviorPane(password: password, behavior: behavior)
        case .appearance:     AppearancePane()
        case .sync:           SyncDevicesPane()
        case .notifications:  NotificationsPane()
        case .account:        AccountPane()
        case .advanced:       AdvancedPane(behavior: behavior, onClose: onClose)
        }
    }
}
