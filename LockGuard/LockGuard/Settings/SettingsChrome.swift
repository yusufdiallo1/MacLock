//
//  SettingsChrome.swift
//  LockGuard — Settings
//
//  Shared building blocks used by every Settings pane: the pane header, the
//  grouped card container, the small uppercase group label, the reusable
//  button styles, and the honest "coming soon" body for panes whose backing
//  service lands in a later prompt.
//

import SwiftUI

// MARK: - Header + containers

struct PaneHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// A grouped card container matching the reference's rounded section blocks.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1))
    }
}

struct GroupLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(Theme.inkFaint).padding(.bottom, 4)
    }
}

// MARK: - Coming-soon body

/// The honest placeholder for panes whose backing service arrives in a later
/// prompt. It never fakes working controls — it states what's coming and, when
/// given `realState`, shows genuine read-only info that's already true today.
struct ComingSoonPane<RealState: View>: View {
    let icon: String
    let headline: String
    let detail: String
    /// Real, already-true read-only content (e.g. "local-only mode", live token
    /// swatches). Rendered above the notice so the pane isn't purely empty.
    @ViewBuilder var realState: () -> RealState

    init(icon: String, headline: String, detail: String,
         @ViewBuilder realState: @escaping () -> RealState = { EmptyView() }) {
        self.icon = icon
        self.headline = headline
        self.detail = detail
        self.realState = realState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            realState()
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.accent)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(detail).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Label("Arrives in a later update", systemImage: "clock")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                            .padding(.top, 2)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Button styles

struct GlassBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct AccentBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7).background(Capsule().fill(Theme.accent)).opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct DangerBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.danger)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
