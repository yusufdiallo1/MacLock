//
//  AuthGateView.swift
//  LockGuard
//
//  The reusable Liquid Glass auth card used by every gate: the app-lock overlay,
//  the Settings gate, and destructive-action confirmations. Live camera with a
//  circular guide, a "Looking for your face…" status, and a password fallback.
//  Honors AuthCoordinator's rate-limit lockout (hides face, shows cooldown).
//
//  Matches the FaceGate reference: face-scan logo, title/subtitle, camera guide,
//  "— or authenticate with — [Password]", Cancel. Purple accent.
//

import SwiftUI
import AVFoundation

struct AuthGateView: View {
    let title: String
    var subtitle: String? = nil
    var icon: NSImage? = nil
    var allowFace: Bool = true
    let verifyPassword: (String) -> Bool
    let onSuccess: () -> Void
    let onCancel: () -> Void
    var onQuitApp: (() -> Void)? = nil

    @ObservedObject private var face = FaceAuthService.shared
    @ObservedObject private var coordinator = AuthCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var password = ""
    @State private var appeared = false
    @State private var showPasswordField = false
    @State private var shake = 0.0
    @State private var didSucceed = false

    private let accent = Theme.accent

    /// Face is offered only if enrolled, allowed by the caller, and permitted
    /// right now (not locked out / kill-switched / out-of-schedule).
    private var faceOffered: Bool {
        allowFace && face.isEnrolled && coordinator.faceAllowedNow
    }

    var body: some View {
        VStack(spacing: 18) {
            logo
            titleBlock
            if faceOffered { cameraBlock } else { lockedFaceBlock }
            divider
            passwordBlock
            footer
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .frame(width: 360)
        .background(cardBackground)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .offset(x: shake)
        .onAppear(perform: start)
        .onDisappear { face.cancel() }
        .onChange(of: face.state) { _, s in reactToFace(s) }
    }

    // MARK: - Pieces

    private var logo: some View {
        Image(systemName: "faceid")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(accent)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text("LockGuard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cameraBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                AuthCameraPreview(session: face.captureSession)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Circle()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 132, height: 132)
                if didSucceed {
                    RoundedRectangle(cornerRadius: 18).fill(Theme.success.opacity(0.25))
                        .frame(width: 150, height: 150)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.success)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(statusText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.surface))
        }
    }

    private var lockedFaceBlock: some View {
        VStack(spacing: 8) {
            Image(systemName: coordinator.faceLockedOut ? "lock.trianglebadge.exclamationmark" : "faceid.slash")
                .font(.system(size: 34)).foregroundStyle(Theme.inkFaint)
            Text(lockedFaceMessage)
                .font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(height: 150)
    }

    private var lockedFaceMessage: String {
        if coordinator.faceLockedOut {
            return "Too many attempts — face unlock locked for \(coordinator.cooldownSecondsRemaining)s. Use your password."
        }
        if face.isKillSwitchActive { return "Face unlock is disabled. Use your password." }
        if face.isEnrolled { return "Face unlock unavailable right now. Use your password." }
        return "Enter your password to continue."
    }

    private var statusText: String {
        if didSucceed { return "Unlocked" }
        switch face.state {
        case .failed: return "Not recognized — try your password"
        default:      return "Looking for your face…"
        }
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.glassEdge).frame(height: 1)
            Text("or authenticate with").font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint).fixedSize()
            Rectangle().fill(Theme.glassEdge).frame(height: 1)
        }
    }

    private var passwordBlock: some View {
        VStack(spacing: 10) {
            SecureField("Password", text: $password)
                .textFieldStyle(.plain).font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.35), lineWidth: 1))
                )
                .onSubmit(submitPassword)
            Button(action: submitPassword) {
                Text("Unlock")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain).focusable(false).keyboardShortcut(.defaultAction)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain).focusable(false).keyboardShortcut(.cancelAction)
            if let onQuitApp {
                Button(action: onQuitApp) {
                    Label("Quit App", systemImage: "xmark.circle").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.danger).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Capsule().strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain).focusable(false)
            }
        }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.glassTint))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [accent.opacity(0.4), Theme.glassEdge.opacity(0)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 34, y: 20)
    }

    // MARK: - Behavior

    private func start() {
        let spring: Animation? = reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
        withAnimation(spring) { appeared = true }
        if faceOffered { face.authenticate { _ in /* state drives UI */ } }
    }

    private func reactToFace(_ s: FaceAuthService.State) {
        // onChange only fires on transitions, but guard anyway so one face
        // attempt records at most one success or one failure (never per-frame).
        switch s {
        case .success:
            guard !didSucceed else { return }
            AuthCoordinator.shared.recordSuccess(method: .face, context: title)
            succeed()
        case .failed:
            AuthCoordinator.shared.recordFailure(method: .face, context: title)
        default: break
        }
    }

    private func submitPassword() {
        if verifyPassword(password) { succeed() }
        else { fail() }
    }

    private func succeed() {
        guard !didSucceed else { return }
        didSucceed = true
        let spring: Animation? = reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)
        withAnimation(spring) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.25)) { appeared = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onSuccess() }
        }
    }

    private func fail() {
        password = ""
        guard !reduceMotion else { return }
        for (i, x) in [-10.0, 9, -7, 5, -3, 0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                withAnimation(.easeInOut(duration: 0.05)) { shake = x }
            }
        }
    }
}

// MARK: - Live camera preview

struct AuthCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView(); v.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        v.previewLayer = preview; v.layer = preview
        return v
    }
    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.previewLayer?.session = session
    }
    final class PreviewNSView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        override func layout() { super.layout(); previewLayer?.frame = bounds }
    }
}
