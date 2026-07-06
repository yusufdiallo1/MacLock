//
//  GlassBackground.swift
//  LockGuard
//
//  The Liquid Glass surface used by the menu-bar popover. On macOS 26+ this
//  uses the native `.glassEffect` API; on 14/15 it falls back to
//  `.ultraThinMaterial` dressed with a tint and edge highlights so it still
//  reads as frosted glass rather than a flat panel.
//

import SwiftUI

/// Applies a rounded Liquid Glass surface behind the content.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Theme.glassTint),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay(edgeHighlight)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.fill(Theme.glassTint))
                .overlay(edgeHighlight)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// A soft rim: brighter along the top edge, fading toward the bottom, so
    /// the glass looks lit from above the way native Liquid Glass does.
    private var edgeHighlight: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [Theme.glassHighlight, Theme.glassEdge.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }
}

/// A smaller glass chip used for pills, icon wells, and buttons inside the
/// popover. Same gating as `GlassSurface` but tuned for interactive elements.
struct GlassChip: ViewModifier {
    var cornerRadius: CGFloat = 12
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let effect: Glass = interactive ? .regular.interactive() : .regular
            content
                .glassEffect(effect, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.glassEdge, lineWidth: 1))
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension View {
    /// Frosted Liquid Glass surface for the popover container.
    func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }

    /// Smaller glass chip for pills, wells, and buttons.
    func glassChip(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius, interactive: interactive))
    }
}
