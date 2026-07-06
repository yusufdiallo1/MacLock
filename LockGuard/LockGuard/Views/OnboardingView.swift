//
//  OnboardingView.swift
//  LockGuard
//
//  First-launch setup. Presents the two permissions LockGuard needs as nodes
//  on a "sentry rail" that arms as each is granted. No product UI beyond this.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsManager
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            rail
            footer
        }
        .frame(width: 460)
        .background(Theme.ground)
        .onAppear { permissions.refreshAll() }
        // Re-check when the user returns from System Settings.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            permissions.refreshAll()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(permissions.allGranted ? Theme.signal : Theme.hairline, lineWidth: 1)
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: permissions.allGranted ? "lock.shield.fill" : "lock.open")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(permissions.allGranted ? Theme.signal : Theme.steel)
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6),
                               value: permissions.allGranted)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("LockGuard")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Two permissions arm the guard. Grant them to continue.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: - Rail of permissions

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Permission.allCases.enumerated()), id: \.element.id) { index, permission in
                PermissionRow(
                    permission: permission,
                    status: permissions.status(for: permission),
                    isLast: index == Permission.allCases.count - 1,
                    onGrant: { grant(permission) }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(permissions.allGranted ? "The guard is armed." : "You can change these later in the menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(permissions.allGranted ? Theme.signal : Theme.inkFaint)

            Spacer()

            Button(action: onFinish) {
                Text(permissions.allGranted ? "Done" : "Not Now")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(permissions.allGranted ? Theme.ground : Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(permissions.allGranted ? Theme.signal : Color.clear)
                            .overlay(Capsule().strokeBorder(
                                permissions.allGranted ? Color.clear : Theme.hairline, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private func grant(_ permission: Permission) {
        Task { await permissions.request(permission) }
    }
}
