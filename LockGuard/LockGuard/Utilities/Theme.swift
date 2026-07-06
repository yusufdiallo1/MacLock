//
//  Theme.swift
//  LockGuard
//
//  The onboarding flow's visual language. LockGuard guards a Mac by presence —
//  it arms like a small piece of security hardware. The palette leans on a
//  single "signal amber" that lights up as each permission is granted, against
//  a graphite ground. One accent, used with restraint.
//

import SwiftUI

enum Theme {
    // Ground & surfaces
    static let ground     = Color(hex: 0x1C1E26)   // deep graphite
    static let surface    = Color(hex: 0x24262F)   // raised panel
    static let hairline   = Color(hex: 0x363944)   // dividers, rail track

    // Ink
    static let ink        = Color(hex: 0xF2F3F5)   // primary text
    static let inkMuted   = Color(hex: 0x9AA0AD)   // secondary text
    static let inkFaint   = Color(hex: 0x646A78)   // captions

    // Signal — the single accent. FaceGate purple = armed / active.
    static let signal     = Color(hex: 0x8B7CF6)
    static let signalSoft = Color(hex: 0x8B7CF6).opacity(0.16)

    /// Semantic aliases so views can read `Theme.accent` instead of `signal`.
    static let accent     = signal
    static let accentSoft = signalSoft

    /// Destructive / error red, used for "Delete", failures, danger states.
    static let danger     = Color(hex: 0xE0675A)

    /// The reference's blue "Add Apps" action button.
    static let actionBlue = Color(hex: 0x0A84FF)

    // Pending / steel — the not-yet-armed state.
    static let steel      = Color(hex: 0x5B6170)

    // MARK: - Liquid Glass

    // The frosted popover reads as glass over a dark scene rather than a solid
    // panel. These tokens layer on top of `.ultraThinMaterial` (or the native
    // `.glassEffect` on macOS 26+) to give it edge highlights and depth.

    /// Faint top-edge highlight where light catches the glass rim.
    static let glassHighlight = Color.white.opacity(0.16)
    /// Hairline that traces the glass edge, darker on the bottom.
    static let glassEdge      = Color.white.opacity(0.08)
    /// Tint washed over the material so it stays in the graphite family.
    static let glassTint      = Color(hex: 0x1C1E26).opacity(0.28)
    /// Fill for a row when hovered — a brighter frost, not a solid block.
    static let rowHover       = Color.white.opacity(0.06)
    /// Fill behind an item's icon so it sits on a small chip of glass.
    static let iconWell       = Color.white.opacity(0.05)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
