//
//  AuthOverlayView.swift
//  LockGuard
//
//  The frosted Liquid Glass auth card shown over a locked app/folder. Live
//  camera preview with an animated scanning ring, a password fallback, and
//  success/failure animations. Purple accent, SF Pro typography.
//
//  Callbacks:
//   • onSuccess  — auth passed (face or password); dismiss + unlock.
//   • onCancel   — user dismissed without unlocking (re-locks / hides target).
//   • onQuitApp  — quit the locked app entirely.
//

import SwiftUI
import AVFoundation

struct AuthOverlayView: View {
    let appName: String
    let appIcon: NSImage?
    /// Verifies a typed password. Returns true on match.
    let verifyPassword: (String) -> Bool
    let onSuccess: () -> Void
    let onCancel: () -> Void
    let onQuitApp: () -> Void

    @ObservedObject private var face = FaceAuthService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var password = ""
    @State private var appeared = false
    @State private var ringAngle = 0.0
    @State private var phase: Phase = .scanning
    @State private var shake = 0.0

    private enum Phase { case scanning, success, failure }

    // FaceGate purple accent (centralized in Theme).
    private let accent = Theme.accent
    private let accentSoft = Theme.accentSoft

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
    }

    var body: some View {
        VStack(spacing: 20) {
            logo
            targetApp
            cameraCircle
            statusLine
            secretIndicator
            divider
            passwordField
            authButton
            footerButtons
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .frame(width: 360)
        .lgGlass(.card)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .offset(x: shake)
        .onAppear { onAppear() }
        .onDisappear { face.cancel() }
        .onChange(of: face.state) { _, newState in reactTo(newState) }
    }

    // MARK: - Pieces

    private var logo: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
            Text("LockGuard")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
    }

    private var targetApp: some View {
        HStack(spacing: 9) {
            if let appIcon {
                Image(nsImage: appIcon).resizable().frame(width: 26, height: 26)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20)).foregroundStyle(Theme.inkMuted)
            }
            Text("\(appName) is locked")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    /// Live camera preview in a circle with a rotating gradient scanning ring.
    private var cameraCircle: some View {
        ZStack {
            // scanning ring
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [accent.opacity(0), accent, .white, accent, accent.opacity(0)],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 138, height: 138)
                .rotationEffect(.degrees(ringAngle))
                .opacity(phase == .scanning ? 1 : 0)

            // camera preview, clipped to a circle
            CameraPreview(session: face.captureSession)
                .frame(width: 122, height: 122)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.glassEdge, lineWidth: 1))

            // success / failure overlays
            if phase == .success {
                Circle().fill(Theme.success.opacity(0.22)).frame(width: 122, height: 122)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.success)
                    .transition(.scale.combined(with: .opacity))
            } else if phase == .failure {
                Circle().strokeBorder(.red, lineWidth: 3).frame(width: 122, height: 122)
            }
        }
        .frame(height: 138)
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.system(size: 12.5))
            .foregroundStyle(phase == .failure ? Theme.danger : Theme.inkMuted)
            .animation(spring, value: statusText)
    }

    private var statusText: String {
        switch phase {
        case .scanning: return face.isKillSwitchActive
            ? "Face unlock disabled — enter your password"
            : "Looking for your face…"
        case .success:  return "Unlocked"
        case .failure:  return "Not recognized. Try your password."
        }
    }

    /// The per-install secret shown only in genuine LockGuard prompts — a fake
    /// prompt can't know it, so its absence is the tell. Defends generic fakes.
    private var secretIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(Theme.success)
            Text("Your secret").font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint)
            Text(AntiSpoofService.shared.secretIndicator).font(.system(size: 13))
            Text("· only genuine prompts show this").font(.system(size: 9.5)).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Theme.surface))
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.glassEdge).frame(height: 1)
            Text("or authenticate with")
                .font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint)
                .fixedSize()
            Rectangle().fill(Theme.glassEdge).frame(height: 1)
        }
    }

    private var passwordField: some View {
        SecureField("Password", text: $password)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.35), lineWidth: 1))
            )
            .onSubmit(submitPassword)
    }

    private var authButton: some View {
        Button(action: submitPassword) {
            Text("Authenticate")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(accent))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .keyboardShortcut(.defaultAction)
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain).focusable(false)
            .keyboardShortcut(.cancelAction)

            Button(action: onQuitApp) {
                Label("Quit App", systemImage: "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain).focusable(false)
        }
    }

    // MARK: - Behavior

    private func onAppear() {
        withAnimation(spring) { appeared = true }
        if !reduceMotion {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                ringAngle = 360
            }
        }
        // Start face authentication; success routes through onChange(state).
        if face.isEnrolled && !face.isKillSwitchActive {
            face.authenticate { _ in /* state drives the UI */ }
        }
    }

    private func reactTo(_ state: FaceAuthService.State) {
        switch state {
        case .success:
            guard phase != .success else { return }
            AuthCoordinator.shared.recordSuccess(method: .face, context: appName)
            succeed()
        case .failed:
            AuthCoordinator.shared.recordFailure(method: .face, context: appName)
            fail()
        default: break
        }
    }

    private func submitPassword() {
        if verifyPassword(password) {
            AuthCoordinator.shared.recordSuccess(method: .password, context: appName)
            succeed()
        } else {
            AuthCoordinator.shared.recordFailure(method: .password, context: appName)
            fail()
        }
    }

    private func succeed() {
        guard phase != .success else { return }
        withAnimation(spring) { phase = .success }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.3)) { appeared = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSuccess() }
        }
    }

    private func fail() {
        withAnimation(spring) { phase = .failure }
        // red shake
        if !reduceMotion {
            let sequence: [Double] = [-10, 9, -7, 5, -3, 0]
            for (i, x) in sequence.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                    withAnimation(.easeInOut(duration: 0.05)) { shake = x }
                }
            }
        }
        password = ""
        // Return to scanning after a beat so the user can retry.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(spring) { if phase == .failure { phase = .scanning } }
        }
    }
}

// MARK: - Live camera preview

/// Wraps AVCaptureVideoPreviewLayer in an NSView for SwiftUI.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.previewLayer = preview
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.previewLayer?.session = session
    }

    final class PreviewNSView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }
}
