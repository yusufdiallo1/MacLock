//
//  PermissionRow.swift
//  LockGuard
//
//  A single node on the sentry rail: one permission, its rationale, and the
//  control to grant it. The rail node to the left lights amber once armed.
//

import SwiftUI

struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let isLast: Bool
    let onGrant: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isGranted: Bool { status.isGranted }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            rail
            content
        }
    }

    // MARK: - Sentry rail

    private var rail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isGranted ? Theme.signal : Theme.surface)
                    .overlay(Circle().strokeBorder(isGranted ? Theme.signal : Theme.hairline, lineWidth: 1.5))
                    .frame(width: 30, height: 30)
                    .shadow(color: isGranted ? Theme.signal.opacity(0.5) : .clear, radius: 8)

                Image(systemName: isGranted ? "checkmark" : permission.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isGranted ? Theme.ground : Theme.steel)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: isGranted)

            if !isLast {
                Rectangle()
                    .fill(isGranted ? Theme.signal.opacity(0.5) : Theme.hairline)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isGranted)
            }
        }
        .frame(width: 30)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(permission.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                control
            }

            Text(permission.rationale)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, isLast ? 0 : 22)
    }

    @ViewBuilder
    private var control: some View {
        switch status {
        case .granted:
            Text("Armed")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.signal)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.signalSoft))
        case .denied:
            Button(action: onGrant) {
                Text("Open Settings")
            }
            .buttonStyle(GrantButtonStyle(emphasis: false))
        case .notDetermined:
            Button(action: onGrant) {
                Text("Grant")
            }
            .buttonStyle(GrantButtonStyle(emphasis: true))
        }
    }
}

/// Small, quiet button. Emphasis fills with signal; otherwise it's outlined.
private struct GrantButtonStyle: ButtonStyle {
    let emphasis: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(emphasis ? Theme.ground : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(emphasis ? Theme.signal : Color.clear)
                    .overlay(Capsule().strokeBorder(emphasis ? Color.clear : Theme.hairline, lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
