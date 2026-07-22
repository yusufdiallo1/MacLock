//
//  AuthenticationPane.swift
//  LockGuard — Settings
//
//  Face enrollment/re-enrollment, sensitivity, camera picker, Touch ID and
//  app-password fallback, and the convenience-auth security notice. Lifted
//  verbatim from the original SettingsView; behavior unchanged.
//

import SwiftUI
import AVFoundation

struct AuthenticationPane: View {
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
