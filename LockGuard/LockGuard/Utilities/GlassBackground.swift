//
//  GlassBackground.swift
//  LockGuard
//
//  Thin compatibility shims over the Liquid Glass system in
//  DesignSystem/LiquidGlass.swift. Existing call sites keep using
//  `.glassSurface()` / `.glassChip()`; both now delegate to `LGGlass` presets
//  so there is one glass engine underneath. NEW code should prefer
//  `.lgGlass(.card / .panel / .bar)` directly.
//
//  Mapping: a popover-style surface and its chips are both `.bar` material;
//  chips just use a smaller radius and can be interactive. `LGGlass` reads the
//  radius from its preset, so the `cornerRadius` argument is retained for
//  source compatibility but the preset governs the material/tint/specular.
//

import SwiftUI

/// Frosted Liquid Glass surface for the popover container (→ `.glassBar`).
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20
    func body(content: Content) -> some View {
        content.lgGlass(.bar)
    }
}

/// Smaller glass chip for pills, wells, and buttons inside the popover
/// (→ `.glassBar`, optionally interactive).
struct GlassChip: ViewModifier {
    var cornerRadius: CGFloat = 12
    var interactive: Bool = false
    func body(content: Content) -> some View {
        content.lgGlass(.bar, interactive: interactive)
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
