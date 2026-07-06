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

    private let accent = Color(hex: 0x8B7CF6)

    var body: some View {
        VStack(spacing: 20) {
            header
            cameraViewer
            guidance
            progressBar
            footer
        }
        .padding(28)
        .frame(width: 380, height: 520)
        .background(Theme.ground)
        .onAppear { if !isDone { face.enroll() } }
        .onDisappear { face.cancel() }
    }

    // MARK: - Derived

    private var progress: (done: Int, total: Int) {
        if case let .enrolling(n, total) = face.state { return (n, total) }
        return (0, 1)
    }
    private var isDone: Bool { if case .success = face.state { return true }; return false }
    private var isFailed: Bool { if case .failed = face.state { return true }; return false }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("Set Up Face Unlock")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.plain).focusable(false)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var cameraViewer: some View {
        ZStack {
            // progress ring around the circle
            Circle()
                .trim(from: 0, to: CGFloat(progress.done) / CGFloat(max(progress.total, 1)))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 210, height: 210)
                .animation(.easeOut(duration: 0.3), value: progress.done)

            EnrollCameraPreview(session: face.captureSession)
                .frame(width: 190, height: 190)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.glassEdge, lineWidth: 1))
                .saturation(isDone ? 1 : 0.95)

            if isDone {
                Circle().fill(Color.green.opacity(0.22)).frame(width: 190, height: 190)
                Image(systemName: "checkmark")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if let pose = face.enrollPose {
                // pose direction arrow, drifting toward the requested side
                Image(systemName: pose.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(poseOffset(pose))
                    .opacity(pose == .center ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: face.enrollPose)
            }
        }
        .frame(height: 210)
    }

    private func poseOffset(_ pose: FaceAuthService.EnrollPose) -> CGSize {
        switch pose {
        case .center: return .zero
        case .left:   return CGSize(width: -118, height: 0)
        case .right:  return CGSize(width: 118, height: 0)
        case .up:     return CGSize(width: 0, height: -118)
        case .down:   return CGSize(width: 0, height: 118)
        }
    }

    private var guidance: some View {
        VStack(spacing: 4) {
            Text(guidanceTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isFailed ? Color(hex: 0xE0675A) : Theme.ink)
                .multilineTextAlignment(.center)
            Text("Move slowly so we capture every angle.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
                .opacity(isDone || isFailed ? 0 : 1)
        }
        .frame(height: 44)
        .animation(.easeInOut, value: guidanceTitle)
    }

    private var guidanceTitle: String {
        if isDone { return "Face enrolled 🎉" }
        if case let .failed(reason) = face.state { return reason }
        return face.enrollPose?.instruction ?? "Getting ready…"
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
        Group {
            if isDone {
                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain).focusable(false)
            } else if isFailed {
                Button(action: { face.enroll() }) {
                    Text("Try Again")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain).focusable(false)
            } else {
                Text("\(progress.done) / \(progress.total) captures")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(height: 40)
            }
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
