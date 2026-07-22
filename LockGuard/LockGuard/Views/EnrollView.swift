//
//  EnrollView.swift
//  LockGuard
//
//  Multi-angle face enrollment: a live camera viewer with pose guidance
//  (look center, turn left/right, tilt up/down) and a progress ring. Reads
//  FaceAuthService.enrollPose / state and drives the whole capture.
//

import SwiftUI
import AVFoundation

struct EnrollView: View {
    let onClose: () -> Void

    @ObservedObject private var face = FaceAuthService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = Theme.accent

    var body: some View {
        VStack(spacing: 18) {
            logoHeader
            liveStatus
            cameraViewer
            progressBar
            captureCount
            footer
        }
        .padding(28)
        .frame(width: 420, height: 560)
        .background(Theme.ground)
        .onAppear { if !isDone { face.enroll() } }
        .onDisappear { face.cancel() }
    }

    // MARK: - Reference-matching header + live status

    private var logoHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "faceid").font(.system(size: 30)).foregroundStyle(Theme.actionBlue)
            Text("Face Enrollment").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Follow the prompts on the camera screen").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
        }
    }

    private var liveStatus: some View {
        Group {
            if isDone {
                Text("Face enrolled 🎉").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
            } else if isFailed {
                Text(failReason).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
            } else if !face.faceDetected {
                Text("No face detected — look at the camera").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
            } else if let pose = face.enrollPose {
                Text(pose.instruction).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            } else {
                Text("Getting ready…").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(height: 20)
        .animation(.easeInOut, value: face.faceDetected)
    }

    private var failReason: String {
        if case let .failed(r) = face.state { return r }
        return "Enrollment failed"
    }

    private var captureCount: some View {
        Text("\(progress.done) of \(progress.total) captures")
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkFaint)
    }

    // MARK: - Derived

    private var progress: (done: Int, total: Int) {
        if case let .enrolling(n, total) = face.state { return (n, total) }
        return (0, 1)
    }
    private var isDone: Bool { if case .success = face.state { return true }; return false }
    private var isFailed: Bool { if case .failed = face.state { return true }; return false }

    // MARK: - Pieces

    /// Large rounded live preview with a circular face-guide (reference layout).
    private var cameraViewer: some View {
        ZStack {
            EnrollCameraPreview(session: face.captureSession)
                .frame(width: 300, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.glassEdge, lineWidth: 1))
            // circular face guide
            Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                .frame(width: 190, height: 190)

            if isDone {
                RoundedRectangle(cornerRadius: 20).fill(Theme.success.opacity(0.22)).frame(width: 300, height: 220)
                Image(systemName: "checkmark").font(.system(size: 56, weight: .bold)).foregroundStyle(Theme.success)
                    .transition(.scale.combined(with: .opacity))
            } else if let pose = face.enrollPose, pose != .center, face.faceDetected {
                Image(systemName: pose.symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(accent)
                    .offset(poseOffset(pose))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: face.enrollPose)
            }
        }
        .frame(height: 220)
    }

    private func poseOffset(_ pose: FaceAuthService.EnrollPose) -> CGSize {
        switch pose {
        case .center: return .zero
        case .left:   return CGSize(width: -110, height: 0)
        case .right:  return CGSize(width: 110, height: 0)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule().fill(accent)
                    .frame(width: geo.size.width * CGFloat(progress.done) / CGFloat(max(progress.total, 1)))
                    .animation(.easeOut(duration: 0.3), value: progress.done)
            }
        }
        .frame(height: 6)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if isDone {
                Button(action: onClose) {
                    Text("Done").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.actionBlue))
                }.buttonStyle(.plain).focusable(false)
            } else {
                // Recapture restarts the whole capture (reference "Recapture").
                Button(action: { face.enroll() }) {
                    Text("Recapture").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.actionBlue)
                            .overlay(Capsule().strokeBorder(accent, lineWidth: 2)))
                }.buttonStyle(.plain).focusable(false)
            }
            Button(action: onClose) {
                Text("Cancel").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.inkMuted)
            }.buttonStyle(.plain).focusable(false).keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - Camera preview

private struct EnrollCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView()
        v.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        v.previewLayer = preview
        v.layer = preview
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
