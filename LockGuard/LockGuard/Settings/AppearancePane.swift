//
//  AppearancePane.swift
//  LockGuard — Settings
//
//  Live-tune the color + Liquid Glass system. Every control writes to
//  ThemeStore (@AppStorage-backed), which Theme.accent and LGGlass read at
//  runtime — so the preview at the top and the whole app update instantly. The
//  in-app accessibility toggles compose with the OS flags (either one wins
//  toward more restriction).
//

import SwiftUI

struct AppearancePane: View {
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupLabel(text: "Live Preview")
            AuthPreviewCard()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            GroupLabel(text: "Accent")
            SettingsCard {
                HStack(spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        swatch(choice)
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text("Paired with").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    Circle().fill(theme.accentSecondary).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    Text(theme.accentChoice == .gold ? "purple" : "gold")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                }.padding(.top, 10)
            }

            GroupLabel(text: "Glass")
            SettingsCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Glass Intensity").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(intensityLabel).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    }
                    Slider(value: $theme.glassIntensity, in: 0...1).tint(Theme.accent)
                    Text("Subtle keeps surfaces close to solid; vivid gives a stronger frosted tint. Independent of the system Reduce Transparency setting.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                toggleRow("Reduce glass", "Push surfaces toward solid. Also respects the system Reduce Transparency flag.", $theme.reduceGlass)
            }

            GroupLabel(text: "Contrast & Motion")
            SettingsCard {
                toggleRow("High contrast", "Thicker strokes and stronger separation. Also respects the system Increase Contrast flag.", $theme.highContrast)
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.vertical, 10)
                toggleRow("Reduce motion", "Disable the animated glass sheen and emitters. Also respects the system Reduce Motion flag.", $theme.reduceMotionInApp)
            }

            GroupLabel(text: "Corner Style")
            SettingsCard {
                HStack {
                    Text("Card & panel corners").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Picker("", selection: $theme.cornerContinuous) {
                        Text("Continuous").tag(true)
                        Text("Rounded").tag(false)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
                }
            }

            SettingsCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 14)).foregroundStyle(Theme.inkFaint)
                    Text("Appearance settings are stored on this Mac. When you sign in, your look will sync across your Macs — secrets never sync.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    // TODO(Prompt 24): mirror LG.theme.* via SyncService.
                }
            }
        }
    }

    // MARK: Pieces

    private func swatch(_ choice: AccentChoice) -> some View {
        let selected = theme.accentChoice == choice
        return Button { theme.accentChoice = choice } label: {
            VStack(spacing: 5) {
                Circle().fill(choice.primary)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    .shadow(color: selected ? choice.primary.opacity(0.5) : .clear, radius: 6)
                Text(choice.label).font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
            }
        }.buttonStyle(.plain).focusable(false)
    }

    private func toggleRow(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
        }
    }

    private var intensityLabel: String {
        switch theme.glassIntensity {
        case ..<0.25: return "Subtle"
        case ..<0.55: return "Balanced"
        case ..<0.8:  return "Rich"
        default:      return "Vivid"
        }
    }
}

// MARK: - Live preview mock

/// A miniature, non-interactive mock of the auth overlay — logo, app name,
/// camera ring, and two buttons — rendered through the current theme + glass
/// settings so the user sees accent/intensity/corner/contrast changes live
/// without opening a real lock prompt. No camera or face objects.
struct AuthPreviewCard: View {
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "faceid").font(.system(size: 26)).foregroundStyle(Theme.accent)
            VStack(spacing: 2) {
                Text("LockGuard").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                Text("Authenticate to continue").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            }
            // "Camera ring" — accent-stroked circle standing in for the live feed.
            ZStack {
                Circle().fill(Theme.surface).frame(width: 76, height: 76)
                Circle().strokeBorder(Theme.accent.opacity(0.9), lineWidth: 3).frame(width: 76, height: 76)
                Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(Theme.inkFaint)
            }
            HStack(spacing: 8) {
                Text("Cancel").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                Text("Unlock").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(width: 280)
        .lgGlass(.card)
    }
}
