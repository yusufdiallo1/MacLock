//
//  Theme.swift
//  LockGuard
//
//  Thin semantic aliases onto the design tokens in DesignSystem/Colors.swift.
//  Views may keep using `Theme.*`; every value resolves to a `Color.lg*` token,
//  so the whole app shares one source of truth. NEW code should prefer the
//  `Color.lg*` tokens directly. Nothing here defines a raw hex — see Colors.swift.
//

import SwiftUI

enum Theme {
    // Ground & surfaces
    static let ground   = Color.lgBgBase
    static let surface  = Color.lgSurface
    static let hairline = Color.lgHairline

    // Ink → text scale
    static let ink      = Color.lgTextPrimary
    static let inkMuted = Color.lgTextSecondary
    static let inkFaint = Color.lgTextTertiary

    // Accent (purple) + soft variant
    // The accent family is user-tunable at runtime (Prompt 37) — these read the
    // ThemeStore so changing the accent in the Appearance pane repaints the app
    // without editing any of the ~53 `Theme.accent` call sites. Everything else
    // in this file stays a static `let`; only the accent is adjustable.
    static var signal: Color     { ThemeStore.shared.accent }
    static var signalSoft: Color { ThemeStore.shared.accentSoft }
    static var accent: Color     { ThemeStore.shared.accent }
    static var accentSoft: Color { ThemeStore.shared.accentSoft }
    /// Gold secondary accent (Prompt 34), paired to the chosen accent (Prompt 37).
    static var accentSecondary: Color { ThemeStore.shared.accentSecondary }

    // Status
    static let success = Color.lgSuccess
    static let warning = Color.lgWarning
    static let danger  = Color.lgDanger

    /// The blue "Add Apps" action button — distinct from the accent, kept as a
    /// deliberate action color (not part of the semantic token spec).
    static let actionBlue = Color(hex: 0x0A84FF)

    // Not-yet-armed / pending tone.
    static let steel = Color.lgTextTertiary

    // MARK: - Liquid Glass (owned by the glass system; see GlassBackground.swift)

    static let glassHighlight = Color.white.opacity(0.16)
    static let glassEdge      = Color.white.opacity(0.08)
    static let glassTint      = Color.lgBgBase.opacity(0.28)
    static let rowHover       = Color.white.opacity(0.06)
    static let iconWell       = Color.white.opacity(0.05)
}
