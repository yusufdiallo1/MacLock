//
//  SecurityPane.swift
//  LockGuard — Settings
//
//  The security surface. The real half is backed today: kill-switch status,
//  rate-limit + cooldown values (read-only constants from AuthCoordinator), and
//  app-deletion protection. The anti-phishing half (impostor blocking, secret
//  overlay indicator, threat feed, lookalike warnings) arrives in a later
//  prompt and is shown as an honest coming-soon section — never faked.
//

import SwiftUI

struct SecurityPane: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var behavior: BehaviorSettings
    @ObservedObject private var coordinator = AuthCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupLabel(text: "Emergency Kill Switch")
            SettingsCard {
                HStack(spacing: 11) {
                    Image(systemName: "bolt.shield.fill").font(.system(size: 16)).foregroundStyle(Theme.danger)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kill Switch").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Text(password.killSwitchActive
                             ? "Active — face unlock disabled for \(password.killSwitchSecondsRemaining)s"
                             : "Press ⌃⌥⇧⌫ to instantly lock everything and force password-only unlock.")
                            .font(.system(size: 11)).foregroundStyle(password.killSwitchActive ? Theme.danger : Theme.inkMuted)
                    }
                    Spacer()
                    Circle().fill(password.killSwitchActive ? Theme.danger : Theme.success)
                        .frame(width: 9, height: 9)
                }
            }

            GroupLabel(text: "Rate Limiting")
            SettingsCard {
                readonlyRow("Failed attempts before lockout", "\(AuthCoordinator.failureThreshold)")
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                readonlyRow("Cooldown after lockout", "\(AuthCoordinator.cooldownSeconds)s")
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                HStack {
                    Text("Current failure count").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(coordinator.failureCount)")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(coordinator.faceLockedOut ? Theme.danger : Theme.inkMuted)
                    if coordinator.faceLockedOut {
                        Text("· locked \(coordinator.cooldownSecondsRemaining)s")
                            .font(.system(size: 11)).foregroundStyle(Theme.danger)
                    }
                }
                Text("After too many failures, face unlock is disabled and only your password works until the cooldown elapses.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).padding(.top, 6)
            }

            GroupLabel(text: "Anti-Tamper")
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
                Text("Restarts LockGuard within seconds if it's quit or killed. Changing this requires authentication.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).padding(.top, 6)
            }

            GroupLabel(text: "Anti-Phishing & Impostor Detection")
            ComingSoonPane(
                icon: "person.fill.questionmark",
                headline: "Impostor blocking, threat feed, and lookalike warnings",
                detail: "Live-face (anti-spoof) impostor blocking, a secret overlay-indicator you can verify, a lookalike-app threat feed, and lookalike warnings will land here."
            ) { EmptyView() }
        }
    }

    private func readonlyRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.accent)
        }
    }
}
