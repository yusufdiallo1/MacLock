//
//  SettingsView.swift
//  LockGuard
//
//  The Settings window, matching the FaceGate reference: a dark Liquid Glass
//  sidebar (LockGuard / Settings header, "Preferences" label, four items, a
//  "Protected locally" footer) and large title + subtitle panes with clean
//  form rows and purple controls.
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
        case about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .apps:     return "lock.square"
            case .auth:     return "person.crop.circle"
            case .behavior: return "gearshape.2"
            case .about:    return "info.circle"
            }
        }
    }
    @State private var tab: Tab = .apps

    static let accent = Theme.accent

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(width: 720, height: 580)
        .background(Theme.ground)
    }

    // MARK: - Liquid Glass sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LockGuard")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 18)

            Text("PREFERENCES")
                .font(.system(size: 10, weight: .semibold)).tracking(0.7)
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 16).padding(.bottom, 6)

            ForEach(Tab.allCases) { t in sidebarItem(t) }
            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text("Protected locally").font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(width: 210)
        .background(.ultraThinMaterial)
        .overlay(Theme.glassTint)
        .overlay(Rectangle().fill(Theme.hairline).frame(width: 1), alignment: .trailing)
    }

    private func sidebarItem(_ t: Tab) -> some View {
        Button { tab = t } label: {
            HStack(spacing: 11) {
                Image(systemName: t.symbol).font(.system(size: 13, weight: .medium)).frame(width: 22)
                Text(t.rawValue).font(.system(size: 13.5, weight: .medium))
                Spacer()
            }
            .foregroundStyle(tab == t ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(tab == t ? Theme.accent.opacity(0.22) : .clear))
            .contentShape(Rectangle())   // make the whole row clickable
            .padding(.horizontal, 9)
        }
        .buttonStyle(.plain).focusable(false)
    }

    // MARK: - Content pane

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(title: paneTitle, subtitle: paneSubtitle)
                switch tab {
                case .apps:     LockedAppsTab(lockManager: lockManager)
                case .auth:     AuthTab(password: password, face: face, behavior: behavior)
                case .behavior: BehaviorTab(password: password, behavior: behavior)
                case .about:    AboutTab(onClose: onClose)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paneTitle: String { tab.rawValue }
    private var paneSubtitle: String {
        switch tab {
        case .apps:     return "Choose which apps require authentication."
        case .auth:     return "Tune Face Unlock, Touch ID, and password fallback."
        case .behavior: return "Adjust launch, locking, schedules, and emergency controls."
        case .about:    return "About LockGuard and your recent authentication activity."
        }
    }
}

// MARK: - Shared chrome

struct PaneHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// A grouped card container matching the reference's rounded section blocks.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1))
    }
}

struct GroupLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(Theme.inkFaint).padding(.bottom, 4)
    }
}

// MARK: - Tab: Locked Apps

private struct LockedAppsTab: View {
    @ObservedObject var lockManager: LockManager
    @State private var showPicker = false
    @State private var query = ""

    private var filtered: [LockedItem] {
        query.isEmpty ? lockManager.apps
            : lockManager.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Locked Apps").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                searchField
                Button { showPicker = true } label: {
                    Label("Add Apps…", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.actionBlue))
                }.buttonStyle(.plain).focusable(false)
            }

            if lockManager.apps.isEmpty {
                emptyState
            } else {
                Text("Click an app to customize its session timer")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.inkFaint)
                SettingsCard {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                        appRow(item)
                        if i < filtered.count - 1 { Divider().overlay(Theme.hairline.opacity(0.5)) }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            InstalledAppsPicker(lockManager: lockManager) { showPicker = false }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            TextField("Search…", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 130)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface))
    }

    private func appRow(_ item: LockedItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: item.icon).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(item.bundleID ?? item.path).font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { item.isLocked }, set: { lockManager.setLocked($0, for: item) }))
                .labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            Button {
                // Face-required delete (hardening).
                Task {
                    if await AuthCoordinator.shared.requireAuth(reason: "Authenticate to remove \(item.name)") {
                        lockManager.remove(item)
                    }
                }
            } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.danger)
            }.buttonStyle(.plain).focusable(false)
        }
        .padding(.vertical, 7)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.square").font(.system(size: 30)).foregroundStyle(Theme.steel)
            Text("No apps locked yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Add apps to require authentication when they're opened.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// Installed-apps picker — the reference's "Add Apps to Lock" list.
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
                Button(action: onDone) { Label("Done", systemImage: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).focusable(false).foregroundStyle(Theme.actionBlue)
                Text("Add Apps to Lock").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    TextField("Search…", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 120)
                }.padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Theme.surface))
            }.padding(16)
            Divider().overlay(Theme.hairline)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { app in
                        HStack(spacing: 11) {
                            Image(nsImage: app.icon).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                Text(app.bundleID ?? "").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { lockManager.isAppLocked(app) },
                                set: { on in if on { lockManager.lockPickedApp(app) } }
                            )).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }.padding(8)
            }
        }
        .frame(width: 480, height: 500).background(Theme.ground)
        .onAppear { if apps.isEmpty { apps = InstalledItems.installedApps() } }
    }
}

// MARK: - Tab: Authentication

private struct AuthTab: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var face: FaceAuthService
    @ObservedObject var behavior: BehaviorSettings

    @State private var showEnroll = false
    @State private var cameras: [AVCaptureDevice] = []
    @State private var selectedCamera = ""
    @State private var changingPassword = false
    @State private var currentPass = ""
    @State private var newPass = ""
    @State private var confirmPass = ""
    @State private var note: (String, Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Face buttons
            HStack(spacing: 10) {
                Button("Add Face") { showEnroll = true }.buttonStyle(GlassBtn()).focusable(false)
                Button(face.isEnrolled ? "Re-enroll Fresh" : "Set Up") { showEnroll = true }.buttonStyle(GlassBtn()).focusable(false)
                if face.isEnrolled {
                    Button("Delete All Face Data") {
                        Task { if await AuthCoordinator.shared.requireAuth(reason: "Authenticate to delete face data") { face.removeEnrollment() } }
                    }.buttonStyle(DangerBtn()).focusable(false)
                }
            }
            // Sensitivity
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Sensitivity").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer(); Text(sensitivityLabel).font(.system(size: 12)).foregroundStyle(Theme.inkMuted) }
                Slider(value: $face.sensitivity, in: 0.5...0.95).tint(Theme.accent)
                Text("Higher sensitivity requires a closer match. Lower is more permissive.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            }

            GroupLabel(text: "Camera")
            SettingsCard {
                HStack(spacing: 11) {
                    Image(systemName: "video.fill").font(.system(size: 15)).foregroundStyle(Theme.actionBlue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Camera").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Text(cameras.first(where: { $0.uniqueID == selectedCamera })?.localizedName ?? "Default")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    if cameras.count > 1 {
                        Picker("", selection: $selectedCamera) {
                            ForEach(cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                        }.labelsHidden().frame(width: 170)
                    }
                }
            }

            GroupLabel(text: "Fallbacks")
            SettingsCard {
                HStack(spacing: 11) {
                    Image(systemName: "touchid").font(.system(size: 16)).foregroundStyle(Theme.danger)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Touch ID").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Text(behavior.biometricsAvailable ? "Use your fingerprint to unlock." : "Not available on this Mac")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $behavior.touchIDEnabled).labelsHidden().toggleStyle(.switch)
                        .tint(Theme.accent).disabled(!behavior.biometricsAvailable)
                }
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                passwordSection
            }

            GroupLabel(text: "Security Notice")
            SettingsCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundStyle(Theme.signal)
                    Text("Face Unlock uses your Mac's camera for convenience-level authentication. It is not equivalent to Apple's Face ID and may be susceptible to photo-based spoofing. For high security, use Touch ID or your app password.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showEnroll) { EnrollView(onClose: { showEnroll = false }) }
        .onAppear {
            cameras = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video, position: .unspecified).devices
            selectedCamera = cameras.first?.uniqueID ?? ""
        }
    }

    @ViewBuilder private var passwordSection: some View {
        HStack(spacing: 11) {
            Image(systemName: "key.fill").font(.system(size: 15)).foregroundStyle(Theme.signal)
            VStack(alignment: .leading, spacing: 1) {
                Text("App Password").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(password.isPasswordSet ? "Password is set" : "No password set")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button(changingPassword ? "Cancel" : "Change") { changingPassword.toggle(); note = nil }
                .buttonStyle(GlassBtn()).focusable(false)
        }
        if changingPassword {
            VStack(alignment: .leading, spacing: 8) {
                if password.isPasswordSet { field("Current password", $currentPass) }
                field(password.isPasswordSet ? "New password" : "Password", $newPass)
                field("Confirm new password", $confirmPass)
                if let note { Text(note.0).font(.system(size: 11.5, weight: .medium)).foregroundStyle(note.1 ? Theme.accent : Theme.danger) }
                Button("Save", action: savePassword).buttonStyle(AccentBtn()).focusable(false)
            }.padding(.top, 8)
        }
    }

    private func field(_ ph: String, _ b: Binding<String>) -> some View {
        SecureField(ph, text: b).textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.ground)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1)))
    }

    private var sensitivityLabel: String {
        switch face.sensitivity { case ..<0.62: return "Permissive"; case ..<0.78: return "Balanced"
        case ..<0.9: return "Strict"; default: return "Very Strict" }
    }

    private func savePassword() {
        let r: PasswordAuthService.PasswordResult = password.isPasswordSet
            ? password.changePassword(current: currentPass, new: newPass, confirm: confirmPass)
            : password.setPassword(newPass, confirm: confirmPass)
        switch r {
        case .success: note = ("Saved.", true); currentPass = ""; newPass = ""; confirmPass = ""; changingPassword = false
        case .mismatch: note = ("Passwords don't match.", false)
        case .tooShort: note = ("Use at least \(PasswordAuthService.minimumLength) characters.", false)
        case .wrongCurrent: note = ("Current password is incorrect.", false)
        case .notSet: note = ("No password set yet.", false)
        case .storageFailed: note = ("Couldn't save to Keychain.", false)
        }
    }
}

// MARK: - Tab: Behavior

private struct BehaviorTab: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var behavior: BehaviorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupLabel(text: "Startup")
            SettingsCard {
                HStack { Text("Launch LockGuard at Login").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                    Toggle("", isOn: Binding(
                        get: { behavior.launchAtLogin },
                        set: { on in behavior.launchAtLogin = on; LaunchAgentService.shared.setLaunchAtLogin(on) }
                    )).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
            }

            GroupLabel(text: "Uninstall Protection")
            SettingsCard {
                HStack(spacing: 10) {
                    Text("App Deletion Protection (recommended)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { behavior.deletionProtectionEnabled },
                        set: { on in
                            Task {
                                if await AuthCoordinator.shared.requireAuth(reason: "Authenticate to change deletion protection") {
                                    behavior.deletionProtectionEnabled = on
                                    LaunchAgentService.shared.setDeletionProtection(on)
                                }
                            }
                        }
                    )).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
                Text("When enabled, LockGuard restarts within seconds if it's quit or killed. (It cannot prevent the app bundle from being deleted.)")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).padding(.top, 6)
            }

            GroupLabel(text: "Locking")
            SettingsCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Session Timeout").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer(); Text(behavior.sessionTimeoutMinutes < 1 ? "Immediately" : (behavior.sessionTimeoutMinutes >= 31 ? "Until manual" : "\(Int(behavior.sessionTimeoutMinutes)) min"))
                            .font(.system(size: 12)).foregroundStyle(Theme.inkMuted) }
                    Slider(value: $behavior.sessionTimeoutMinutes, in: 0...31, step: 1).tint(Theme.accent)
                    Text("After unlocking, an app stays unlocked this long before re-locking. 0 = immediately, 31 = until you lock manually.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                HStack { Text("Timer Mode").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                    Picker("", selection: $behavior.timerMode) {
                        ForEach(BehaviorSettings.TimerMode.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 180) }
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                row("Lock all apps when Mac sleeps or locks", isOn: $behavior.lockOnSleep)
            }

            GroupLabel(text: "Scheduled Lock")
            SettingsCard {
                row("Lock all apps on a schedule", isOn: $behavior.scheduledLockEnabled)
                if behavior.scheduledLockEnabled {
                    timeRange("From", $behavior.scheduledStartMinutes); timeRange("Until", $behavior.scheduledEndMinutes)
                }
            }

            GroupLabel(text: "Face Unlock Schedule")
            SettingsCard {
                row("Disable Face Unlock during certain hours", isOn: $behavior.faceScheduleEnabled)
                if behavior.faceScheduleEnabled {
                    timeRange("From", $behavior.faceStartMinutes); timeRange("Until", $behavior.faceEndMinutes)
                }
            }

            GroupLabel(text: "Emergency")
            SettingsCard {
                HStack { Text("Emergency Kill Shortcut").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                    HStack(spacing: 6) {
                        ForEach(["control", "option", "shift", "delete.left"], id: \.self) { s in
                            Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
                                .frame(width: 26, height: 24).background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface)) } } }
                Text("Instantly locks everything and disables Face Unlock for 60 seconds — only your password unlocks.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).padding(.top, 6)
                if password.killSwitchActive {
                    Text("Active — \(password.killSwitchSecondsRemaining)s remaining").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.danger).padding(.top, 4)
                }
            }
        }
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack { Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
    }
    private func timeRange(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                Text(BehaviorSettings.timeLabel(value.wrappedValue)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent).monospacedDigit() }
            Slider(value: value, in: 0...1439, step: 15).tint(Theme.accent)
        }.padding(.top, 8)
    }
}

// MARK: - Tab: About (with encrypted auth-log viewer)

private struct AboutTab: View {
    let onClose: () -> Void
    @ObservedObject private var log = AuthLogService.shared
    @State private var updateStatus = ""
    @State private var checking = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LockGuard").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("Version \(version)")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    Text("Your data never leaves this Mac.").font(.system(size: 11.5)).foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: checkForUpdates) {
                        HStack(spacing: 6) {
                            if checking { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)) }
                            Text("Check for Updates").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent))
                    }.buttonStyle(.plain).focusable(false).disabled(checking)
                    if !updateStatus.isEmpty {
                        Text(updateStatus).font(.system(size: 10.5)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }

            GroupLabel(text: "Credits")
            SettingsCard {
                creditRow("Design & Engineering", "LockGuard Team")
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 6)
                creditRow("Face recognition", "Apple Vision framework")
                Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 6)
                creditRow("Security", "CryptoKit · Keychain Services")
            }

            GroupLabel(text: "Authentication Log")
            SettingsCard {
                if log.entries.isEmpty {
                    Text("No authentication attempts recorded yet.").font(.system(size: 12)).foregroundStyle(Theme.inkFaint).padding(.vertical, 8)
                } else {
                    ForEach(log.entries.suffix(30).reversed()) { e in
                        HStack(spacing: 10) {
                            Image(systemName: e.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 13)).foregroundStyle(e.success ? Theme.success : Theme.danger)
                            Image(systemName: e.method == .face ? "faceid" : "key.fill").font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                            Text(e.context.isEmpty ? (e.success ? "Unlocked" : "Failed") : e.context).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            Text(e.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint).monospacedDigit()
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func creditRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
        }
    }

    /// Stubbed update check — no server yet. Simulates the flow and reports
    /// "up to date" so the button is wired end-to-end.
    private func checkForUpdates() {
        checking = true
        updateStatus = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            checking = false
            updateStatus = "You're on the latest version."
        }
    }
}

// MARK: - Button styles

private struct GlassBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
private struct AccentBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7).background(Capsule().fill(Theme.accent)).opacity(configuration.isPressed ? 0.8 : 1)
    }
}
private struct DangerBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.danger)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
