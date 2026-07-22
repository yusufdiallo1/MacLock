//
//  BehaviorPane.swift
//  LockGuard — Settings
//
//  Startup, uninstall protection, locking/timeout, scheduled lock, face-unlock
//  schedule, and the emergency kill shortcut. Lifted verbatim from the original
//  SettingsView; behavior unchanged.
//

import SwiftUI

struct BehaviorPane: View {
    @ObservedObject var password: PasswordAuthService
    @ObservedObject var behavior: BehaviorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupLabel(text: "Startup")
            SettingsCard {
                HStack { Text("Launch LockGuard at Login").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                    Toggle("", isOn: Binding(
                        get: { behavior.launchAtLogin },
                        set: { on in behavior.launchAtLogin = on; LaunchAgentService.shared.setLaunchAtLogin(on) }
                    )).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
            }

            GroupLabel(text: "Uninstall Protection")
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
                Text("When enabled, LockGuard restarts within seconds if it's quit or killed. (It cannot prevent the app bundle from being deleted.)")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).padding(.top, 6)
            }

            GroupLabel(text: "Locking")
            SettingsCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Session Timeout").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer(); Text(behavior.sessionTimeoutMinutes < 1 ? "Immediately" : (behavior.sessionTimeoutMinutes >= 31 ? "Until manual" : "\(Int(behavior.sessionTimeoutMinutes)) min"))
                            .font(.system(size: 12)).foregroundStyle(Theme.inkMuted) }
                    Slider(value: $behavior.sessionTimeoutMinutes, in: 0...31, step: 1).tint(Theme.accent)
                    Text("After unlocking, an app stays unlocked this long before re-locking. 0 = immediately, 31 = until you lock manually.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                HStack { Text("Timer Mode").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                    Picker("", selection: $behavior.timerMode) {
                        ForEach(BehaviorSettings.TimerMode.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 180) }
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                row("Lock all apps when Mac sleeps or locks", isOn: $behavior.lockOnSleep)
            }

            GroupLabel(text: "Scheduled Lock")
            SettingsCard {
                row("Lock all apps on a schedule", isOn: $behavior.scheduledLockEnabled)
                if behavior.scheduledLockEnabled {
                    timeRange("From", $behavior.scheduledStartMinutes); timeRange("Until", $behavior.scheduledEndMinutes)
                }
            }

            GroupLabel(text: "Face Unlock Schedule")
            SettingsCard {
                row("Disable Face Unlock during certain hours", isOn: $behavior.faceScheduleEnabled)
                if behavior.faceScheduleEnabled {
                    timeRange("From", $behavior.faceStartMinutes); timeRange("Until", $behavior.faceEndMinutes)
                }
            }

            GroupLabel(text: "Emergency")
            SettingsCard {
                HStack { Text("Emergency Kill Shortcut").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                    HStack(spacing: 6) {
                        ForEach(["control", "option", "shift", "delete.left"], id: \.self) { s in
                            Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
                                .frame(width: 26, height: 24).background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface)) } } }
                Text("Instantly locks everything and disables Face Unlock for 60 seconds — only your password unlocks.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).padding(.top, 6)
                if password.killSwitchActive {
                    Text("Active — \(password.killSwitchSecondsRemaining)s remaining").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.danger).padding(.top, 4)
                }
            }
        }
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack { Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
    }
    private func timeRange(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink); Spacer()
                Text(BehaviorSettings.timeLabel(value.wrappedValue)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent).monospacedDigit() }
            Slider(value: value, in: 0...1439, step: 15).tint(Theme.accent)
        }.padding(.top, 8)
    }
}
