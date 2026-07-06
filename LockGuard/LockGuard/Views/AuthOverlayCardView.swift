//
//  AuthOverlayCardView.swift
//  LockGuard
//
//  The card that floats at the center of the auth overlay. For now it's a
//  placeholder: a face glyph, the locked app's name, and an "Unlock" button
//  that stands in for face recognition. When the real auth lands it calls the
//  same `onSuccess` / `onCancel` callbacks, so nothing downstream changes.
//

import SwiftUI

struct AuthOverlayCardView: View {
    let appName: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
    }

    var body: some View {
        VStack(spacing: 18) {
            faceBadge

            VStack(spacing: 5) {
                Text("\(appName) is locked")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Look at the camera to unlock, or authenticate to continue.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 260)

            unlockButton

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction) // Esc
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .frame(width: 320)
        .background(cardBackground)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(spring) { appeared = true } }
    }

    // MARK: - Pieces

    private var faceBadge: some View {
        ZStack {
            Circle()
                .fill(Theme.signalSoft)
                .frame(width: 68, height: 68)
            Circle()
                .strokeBorder(Theme.signal.opacity(0.45), lineWidth: 1)
                .frame(width: 68, height: 68)
            Image(systemName: "faceid")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.signal)
        }
    }

    private var unlockButton: some View {
        Button(action: onSuccess) {
            HStack(spacing: 7) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Unlock")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.signal))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction) // Return
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.glassTint))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.glassHighlight, Theme.glassEdge.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
    }
}
