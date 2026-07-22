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
    @ObservedObject private var antiSpoof = AntiSpoofService.shared
    @State private var editingIndicator = false

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

            GroupLabel(text: "Prompt Verification")
            SettingsCard {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 16)).foregroundStyle(Theme.success)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your secret indicator").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Shown only in genuine LockGuard prompts. If a prompt is missing it, don't type your password.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(antiSpoof.secretIndicator).font(.system(size: 22))
                    Button(editingIndicator ? "Done" : "Change") { editingIndicator.toggle() }
                        .buttonStyle(GlassBtn()).focusable(false)
                }
                if editingIndicator {
                    let cols = [GridItem(.adaptive(minimum: 40))]
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(AntiSpoofService.curatedIndicators, id: \.self) { emoji in
                            Button { antiSpoof.setSecretIndicator(emoji) } label: {
                                Text(emoji).font(.system(size: 22))
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(antiSpoof.secretIndicator == emoji ? Theme.accent.opacity(0.25) : Theme.surface))
                            }.buttonStyle(.plain).focusable(false)
                        }
                    }.padding(.top, 10)
                }
            }

            GroupLabel(text: "Impostor & Lookalike Detection")
            SettingsCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.badge.shield.checkmark").font(.system(size: 15)).foregroundStyle(Theme.accent)
                    Text("LockGuard pins each locked app's developer identity (code signature + Team ID) and blocks an impostor that presents the same name or bundle id but a different signer. Local rules are active now; a cloud threat feed arrives with sync.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                if !antiSpoof.detections.isEmpty {
                    Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                    ForEach(antiSpoof.detections.prefix(8)) { d in
                        detectionRow(d)
                        if d.id != antiSpoof.detections.prefix(8).last?.id {
                            Divider().overlay(Theme.hairline.opacity(0.4)).padding(.vertical, 6)
                        }
                    }
                } else {
                    Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                    Text("No impostor or lookalike apps detected.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    private func detectionRow(_ d: AntiSpoofService.Detection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: d.kind == .lookalike ? "exclamationmark.triangle.fill" : "xmark.shield.fill")
                .font(.system(size: 13)).foregroundStyle(d.blocked ? Theme.danger : Theme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(d.appName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
                Text(d.detail).font(.system(size: 10.5)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            Spacer()
            if d.blocked {
                Text("Blocked").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.danger)
            } else {
                Button("Block") { antiSpoof.blockApp(bundleID: d.bundleID) }
                    .buttonStyle(DangerBtn()).focusable(false)
            }
        }
        .padding(.vertical, 2)
    }

    private func readonlyRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.accent)
        }
    }
}
