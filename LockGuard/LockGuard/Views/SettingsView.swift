//
//  SettingsView.swift
//  LockGuard
//
//  The real Settings window (opened by the popover's gear button). Groups the
//  master password, face-unlock sensitivity + enrollment, and the emergency
//  kill switch. Matches the graphite/amber Theme.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var face: FaceAuthService
    let onClose: () -> Void

    enum Tab: String, CaseIterable {
        case password = "Password"
        case face = "Face Unlock"
        case security = "Security"
        var symbol: String {
            switch self {
            case .password: return "key.fill"
            case .face:     return "faceid"
            case .security: return "exclamationmark.shield.fill"
            }
        }
    }
    @State private var tab: Tab = .password

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            Divider().overlay(Theme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case .password: PasswordSection(password: password)
                    case .face:     FaceSection(face: face)
                    case .security: KillSwitchSection(password: password)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 460, height: 560)
        .background(Theme.ground)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.symbol).font(.system(size: 11, weight: .semibold))
                        Text(t.rawValue).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(tab == t ? Theme.ground : Theme.inkMuted)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(
                        Capsule().fill(tab == t ? Theme.signal : Theme.surface)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.signal)
            Text("LockGuard Settings")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }
}

// MARK: - Section chrome

private struct SectionHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.signal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StatusNote: View {
    let text: String
    let good: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(good ? Theme.signal : Color(hex: 0xE07A6B))
    }
}

// MARK: - Password

private struct PasswordSection: View {
    @ObservedObject var password: PasswordAuthService

    @State private var newPass = ""
    @State private var confirmPass = ""
    @State private var currentPass = ""
    @State private var note: (String, Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                symbol: "key.fill",
                title: "Master Password",
                subtitle: password.isPasswordSet
                    ? "Used to unlock when face isn't available, and during the kill switch."
                    : "Set a password so you can always unlock, even without your face."
            )

            if password.isPasswordSet {
                SecureField("Current password", text: $currentPass)
                    .textFieldStyle(GlassFieldStyle())
            }
            SecureField(password.isPasswordSet ? "New password" : "Password", text: $newPass)
                .textFieldStyle(GlassFieldStyle())
            SecureField("Confirm password", text: $confirmPass)
                .textFieldStyle(GlassFieldStyle())

            if let note {
                StatusNote(text: note.0, good: note.1)
            }

            Button(action: submit) {
                Text(password.isPasswordSet ? "Change Password" : "Set Password")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.signal))
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() {
        let result: PasswordAuthService.PasswordResult
        if password.isPasswordSet {
            result = password.changePassword(current: currentPass, new: newPass, confirm: confirmPass)
        } else {
            result = password.setPassword(newPass, confirm: confirmPass)
        }
        switch result {
        case .success:
            note = (password.isPasswordSet ? "Password changed." : "Password set.", true)
            newPass = ""; confirmPass = ""; currentPass = ""
        case .mismatch:     note = ("The two passwords don't match.", false)
        case .tooShort:     note = ("Use at least \(PasswordAuthService.minimumLength) characters.", false)
        case .wrongCurrent: note = ("Current password is incorrect.", false)
        case .notSet:       note = ("No password is set yet.", false)
        case .storageFailed: note = ("Couldn't save to the Keychain. Try again.", false)
        }
    }
}

// MARK: - Face

private struct FaceSection: View {
    @ObservedObject var face: FaceAuthService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                symbol: "faceid",
                title: "Face Unlock",
                subtitle: "Recognizes you at the camera. A presence gate — not a replacement for your password."
            )

            HStack {
                Text(face.isEnrolled ? "Face is enrolled" : "No face enrolled")
                    .font(.system(size: 12.5))
                    .foregroundStyle(face.isEnrolled ? Theme.signal : Theme.inkMuted)
                Spacer()
                if face.isEnrolled {
                    Button("Re-enroll") { EnrollWindowController.shared.present() }
                        .buttonStyle(GlassButtonStyle())
                    Button("Remove") { face.removeEnrollment() }
                        .buttonStyle(GlassButtonStyle())
                } else {
                    Button("Set Up Face Unlock") { EnrollWindowController.shared.present() }
                        .buttonStyle(GlassButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sensitivity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(sensitivityLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkMuted)
                }
                Slider(value: $face.sensitivity, in: 0.5...0.95)
                    .tint(Theme.signal)
                HStack {
                    Text("Permissive").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Text("Strict").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    private var sensitivityLabel: String {
        switch face.sensitivity {
        case ..<0.62: return "Permissive"
        case ..<0.78: return "Balanced"
        case ..<0.9:  return "Strict"
        default:      return "Very strict"
        }
    }
}

// MARK: - Kill switch

private struct KillSwitchSection: View {
    @ObservedObject var password: PasswordAuthService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                symbol: "exclamationmark.shield.fill",
                title: "Emergency Kill Switch",
                subtitle: "Instantly locks everything and disables face unlock for 60 seconds — only your password unlocks."
            )
            HStack(spacing: 8) {
                ForEach(["control", "option", "shift", "delete.left"], id: \.self) { key in
                    Image(systemName: keySymbol(key))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                }
            }
            if password.killSwitchActive {
                StatusNote(text: "Active — face unlock disabled for \(password.killSwitchSecondsRemaining)s.", good: false)
            }
        }
    }

    private func keySymbol(_ key: String) -> String {
        switch key {
        case "control": return "control"
        case "option":  return "option"
        case "shift":   return "shift"
        default:        return "delete.left"
        }
    }
}

// MARK: - Small styles

private struct GlassFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1))
            )
    }
}

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
