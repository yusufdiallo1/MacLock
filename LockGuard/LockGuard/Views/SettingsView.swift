//
//  SettingsView.swift
//  LockGuard
//
//  The Settings window (gear button). A Liquid Glass sidebar with three tabs:
//  Locked Apps, Authentication, and Behavior — each a clean Form of rows with
//  purple controls, on the graphite Theme.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var face: FaceAuthService
    let onClose: () -> Void

    @StateObject private var lockManager = LockManager.shared
    @StateObject private var behavior = BehaviorSettings.shared

    enum Tab: String, CaseIterable, Identifiable {
        case apps = "Locked Apps"
        case auth = "Authentication"
        case behavior = "Behavior"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .apps:     return "square.grid.2x2.fill"
            case .auth:     return "faceid"
            case .behavior: return "slider.horizontal.3"
            }
        }
    }
    @State private var tab: Tab = .apps

    static let accent = Theme.accent

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            content
        }
        .frame(width: 620, height: 560)
        .background(Theme.ground)
    }

    // MARK: - Liquid Glass sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.accent)
                Text("LockGuard")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 14)

            ForEach(Tab.allCases) { t in
                sidebarItem(t)
            }
            Spacer()
            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    Text("Close").font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain).focusable(false)
            .keyboardShortcut(.cancelAction)
            .padding(.bottom, 12)
        }
        .frame(width: 176)
        .background(.ultraThinMaterial)
        .overlay(Theme.glassTint)
    }

    private func sidebarItem(_ t: Tab) -> some View {
        Button { tab = t } label: {
            HStack(spacing: 10) {
                Image(systemName: t.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(t.rawValue).font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(tab == t ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(tab == t ? Self.accent.opacity(0.22) : .clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain).focusable(false)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch tab {
                case .apps:     LockedAppsTab(lockManager: lockManager)
                case .auth:     AuthTab(password: password, face: face, behavior: behavior)
                case .behavior: BehaviorTab(password: password, behavior: behavior)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared row chrome

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 9)
    }
}

struct TabTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.bottom, 8)
    }
}

// MARK: - Tab 1: Locked Apps

private struct LockedAppsTab: View {
    @ObservedObject var lockManager: LockManager
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TabTitle(text: "Locked Apps")
                Spacer()
                Button { showPicker = true } label: {
                    Label("Add Apps", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(SettingsView.accent))
                }
                .buttonStyle(.plain).focusable(false)
            }

            if lockManager.apps.isEmpty {
                emptyState
            } else {
                ForEach(lockManager.apps) { item in
                    appRow(item)
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            InstalledAppsPicker(lockManager: lockManager) { showPicker = false }
        }
    }

    private func appRow(_ item: LockedItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: item.icon).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            Spacer()
            // Locked toggle
            Toggle("", isOn: Binding(
                get: { item.isLocked },
                set: { lockManager.setLocked($0, for: item) }
            ))
            .labelsHidden().toggleStyle(.switch).tint(SettingsView.accent)
            // Remove
            Button { lockManager.remove(item) } label: {
                Image(systemName: "trash").font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xE0675A))
            }
            .buttonStyle(.plain).focusable(false)
        }
        .padding(.vertical, 7)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28)).foregroundStyle(Theme.steel)
            Text("No apps locked yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Add apps to require authentication when they're opened.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// Installed-apps picker sheet for the Locked Apps tab.
private struct InstalledAppsPicker: View {
    @ObservedObject var lockManager: LockManager
    let onDone: () -> Void
    @State private var apps: [PickableItem] = []
    @State private var query = ""

    private var filtered: [PickableItem] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Apps to Lock").font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Done", action: onDone).focusable(false)
            }
            .padding(16)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 12.5))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .padding(.horizontal, 16).padding(.bottom, 8)
            Divider().overlay(Theme.hairline)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { app in
                        Button { lockManager.lockPickedApp(app) } label: {
                            HStack(spacing: 11) {
                                Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                                Text(app.name).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: lockManager.isAppLocked(app) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(lockManager.isAppLocked(app) ? SettingsView.accent : Theme.inkFaint)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusable(false)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 380, height: 440)
        .background(Theme.ground)
        .onAppear { if apps.isEmpty { apps = InstalledItems.installedApps() } }
    }
}

// MARK: - Tab 2: Authentication

private struct AuthTab: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var face: FaceAuthService
    @ObservedObject var behavior: BehaviorSettings

    @State private var currentPass = ""
    @State private var newPass = ""
    @State private var confirmPass = ""
    @State private var note: (String, Bool)?
    @State private var cameras: [AVCaptureDevice] = []
    @State private var selectedCamera = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabTitle(text: "Authentication")

            // Face
            group("Face Unlock") {
                SettingsRow(title: face.isEnrolled ? "Face is enrolled" : "No face enrolled",
                            subtitle: "A presence gate — captured from multiple angles.") {
                    HStack(spacing: 8) {
                        Button(face.isEnrolled ? "Re-enroll" : "Set Up") {
                            EnrollWindowController.shared.present()
                        }.focusable(false)
                        if face.isEnrolled {
                            Button("Remove") { face.removeEnrollment() }.focusable(false)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Sensitivity").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer(); Text(sensitivityLabel).font(.system(size: 11)).foregroundStyle(Theme.inkMuted) }
                    Slider(value: $face.sensitivity, in: 0.5...0.95).tint(SettingsView.accent)
                    HStack { Text("Permissive").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                        Spacer(); Text("Strict").font(.system(size: 10)).foregroundStyle(Theme.inkFaint) }
                }
                if cameras.count > 1 {
                    SettingsRow(title: "Camera", subtitle: "Choose which camera to use.") {
                        Picker("", selection: $selectedCamera) {
                            ForEach(cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                        }.labelsHidden().frame(width: 160)
                    }
                }
            }

            // Touch ID
            group("Touch ID") {
                SettingsRow(title: "Allow Touch ID",
                            subtitle: behavior.biometricsAvailable
                                ? "Use your fingerprint as an unlock method."
                                : "No Touch ID hardware detected on this Mac.") {
                    Toggle("", isOn: $behavior.touchIDEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(SettingsView.accent)
                        .disabled(!behavior.biometricsAvailable)
                }
            }

            // Password
            group(password.isPasswordSet ? "Change Password" : "Set Password") {
                if password.isPasswordSet {
                    SecureField("Current password", text: $currentPass).textFieldStyle(FieldStyle())
                }
                SecureField(password.isPasswordSet ? "New password" : "Password", text: $newPass).textFieldStyle(FieldStyle())
                SecureField("Confirm password", text: $confirmPass).textFieldStyle(FieldStyle())
                if let note { Text(note.0).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(note.1 ? SettingsView.accent : Color(hex: 0xE0675A)) }
                Button(action: submitPassword) {
                    Text(password.isPasswordSet ? "Change Password" : "Set Password")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(SettingsView.accent))
                }.buttonStyle(.plain).focusable(false)
            }
        }
        .onAppear {
            cameras = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                mediaType: .video, position: .unspecified).devices
            selectedCamera = cameras.first?.uniqueID ?? ""
        }
    }

    @ViewBuilder private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.inkFaint)
            content()
        }
    }

    private var sensitivityLabel: String {
        switch face.sensitivity {
        case ..<0.62: return "Permissive"; case ..<0.78: return "Balanced"
        case ..<0.9: return "Strict"; default: return "Very strict" }
    }

    private func submitPassword() {
        let r: PasswordAuthService.PasswordResult = password.isPasswordSet
            ? password.changePassword(current: currentPass, new: newPass, confirm: confirmPass)
            : password.setPassword(newPass, confirm: confirmPass)
        switch r {
        case .success: note = ("Saved.", true); currentPass = ""; newPass = ""; confirmPass = ""
        case .mismatch: note = ("Passwords don't match.", false)
        case .tooShort: note = ("Use at least \(PasswordAuthService.minimumLength) characters.", false)
        case .wrongCurrent: note = ("Current password is incorrect.", false)
        case .notSet: note = ("No password set yet.", false)
        case .storageFailed: note = ("Couldn't save to Keychain.", false)
        }
    }
}

// MARK: - Tab 3: Behavior

private struct BehaviorTab: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var behavior: BehaviorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabTitle(text: "Behavior")

            group("Auto-Lock") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Session timeout").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(behavior.sessionTimeoutMinutes < 1 ? "Never"
                             : "\(Int(behavior.sessionTimeoutMinutes)) min")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkMuted) }
                    Slider(value: $behavior.sessionTimeoutMinutes, in: 0...31, step: 1).tint(SettingsView.accent)
                    Text("Lock after this much inactivity.").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                SettingsRow(title: "Lock on sleep", subtitle: "Lock everything when the Mac sleeps.") {
                    Toggle("", isOn: $behavior.lockOnSleep).labelsHidden().toggleStyle(.switch).tint(SettingsView.accent)
                }
            }

            group("Scheduled Lock") {
                SettingsRow(title: "Lock on a schedule", subtitle: "Auto-lock during a daily time window.") {
                    Toggle("", isOn: $behavior.scheduledLockEnabled).labelsHidden().toggleStyle(.switch).tint(SettingsView.accent)
                }
                if behavior.scheduledLockEnabled {
                    timeRange("From", $behavior.scheduledStartMinutes)
                    timeRange("Until", $behavior.scheduledEndMinutes)
                }
            }

            group("Face Unlock Schedule") {
                SettingsRow(title: "Limit face unlock to hours",
                            subtitle: "Outside these hours, only your password unlocks.") {
                    Toggle("", isOn: $behavior.faceScheduleEnabled).labelsHidden().toggleStyle(.switch).tint(SettingsView.accent)
                }
                if behavior.faceScheduleEnabled {
                    timeRange("From", $behavior.faceStartMinutes)
                    timeRange("Until", $behavior.faceEndMinutes)
                }
            }

            group("Emergency Kill Switch") {
                SettingsRow(title: "Shortcut",
                            subtitle: "Instantly locks everything and disables face unlock for 60s.") {
                    HStack(spacing: 6) {
                        ForEach(["control", "option", "shift", "delete.left"], id: \.self) { s in
                            Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
                                .frame(width: 26, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
                        }
                    }
                }
                if password.killSwitchActive {
                    Text("Active — \(password.killSwitchSecondsRemaining)s remaining")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(hex: 0xE0675A))
                }
            }
        }
    }

    private func timeRange(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer(); Text(BehaviorSettings.timeLabel(value.wrappedValue))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(SettingsView.accent)
                    .monospacedDigit() }
            Slider(value: value, in: 0...1439, step: 15).tint(SettingsView.accent)
        }
    }

    @ViewBuilder private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.inkFaint)
            content()
        }
    }
}

// MARK: - Field style

private struct FieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1)))
    }
}
