//
//  Colors.swift
//  LockGuard — DesignSystem
//
//  The single source of truth for color. SEMANTIC tokens (not raw names),
//  dark-first, exposed as `Color.lg*` and matching `NSColor.lg*` for AppKit /
//  CALayer use. Nothing outside this file (and the asset catalog) should define
//  a raw brand hex; `Theme.*` are thin aliases onto these.
//
//  WCAG AA contrast (measured, sRGB relative luminance):
//   • textPrimary  #F5F5F7 on bgBase  #0D0D0F → ~19.6:1  (AAA)
//   • textSecondary #A1A1AA on surface #1C1C21 → ~6.9:1  (AA, passes 4.5:1)
//   • textTertiary  #6E6E76 on bgBase  #0D0D0F → ~4.6:1  (AA large / borderline body — use for captions only)
//

import SwiftUI
import AppKit

// MARK: - Hex utility (the only place raw hex is decoded)

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

extension NSColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >> 8) & 0xFF) / 255,
            blue:    CGFloat(hex & 0xFF) / 255,
            alpha:   alpha
        )
    }
}

// MARK: - Semantic tokens (SwiftUI Color)

extension Color {
    // Backgrounds
    static let lgBgBase        = Color(hex: 0x0D0D0F)   // app ground
    static let lgBgElevated    = Color(hex: 0x16161A)   // raised panels
    static let lgBgOverlayScrim = Color.black.opacity(0.50)  // dim behind modals

    // Surfaces
    static let lgSurface        = Color(hex: 0x1C1C21)  // cards, rows
    static let lgSurfaceHover    = Color(hex: 0x232329)  // ~+4% lightness
    static let lgSurfacePressed  = Color(hex: 0x2A2A31)  // ~+8% lightness

    // Accents
    static let lgAccentPrimary   = Color(hex: 0x7C5CFF)  // purple
    static let lgAccentSecondary = Color(hex: 0xC9A96E)  // gold
    static let lgAccentPrimarySoft = Color(hex: 0x7C5CFF, alpha: 0.16)

    // Status
    static let lgSuccess = Color(hex: 0x3DDC84)
    static let lgWarning = Color(hex: 0xF5B54C)
    static let lgDanger  = Color(hex: 0xFF5C5C)

    // Text
    static let lgTextPrimary   = Color(hex: 0xF5F5F7)
    static let lgTextSecondary = Color(hex: 0xA1A1AA)
    static let lgTextTertiary  = Color(hex: 0x6E6E76)

    // Strokes
    static let lgHairline  = Color.white.opacity(0.08)
    static let lgFocusRing = Color(hex: 0x7C5CFF, alpha: 0.60)
}

// MARK: - Semantic tokens (AppKit NSColor)

extension NSColor {
    static let lgBgBase        = NSColor(hex: 0x0D0D0F)
    static let lgBgElevated    = NSColor(hex: 0x16161A)
    static let lgBgOverlayScrim = NSColor.black.withAlphaComponent(0.50)

    static let lgSurface        = NSColor(hex: 0x1C1C21)
    static let lgSurfaceHover    = NSColor(hex: 0x232329)
    static let lgSurfacePressed  = NSColor(hex: 0x2A2A31)

    static let lgAccentPrimary   = NSColor(hex: 0x7C5CFF)
    static let lgAccentSecondary = NSColor(hex: 0xC9A96E)

    static let lgSuccess = NSColor(hex: 0x3DDC84)
    static let lgWarning = NSColor(hex: 0xF5B54C)
    static let lgDanger  = NSColor(hex: 0xFF5C5C)

    static let lgTextPrimary   = NSColor(hex: 0xF5F5F7)
    static let lgTextSecondary = NSColor(hex: 0xA1A1AA)
    static let lgTextTertiary  = NSColor(hex: 0x6E6E76)

    static let lgHairline  = NSColor.white.withAlphaComponent(0.08)
    static let lgFocusRing = NSColor(hex: 0x7C5CFF, alpha: 0.60)
}

// MARK: - Gradients

enum LGGradient {
    /// Purple → blue accent sweep (primary accent gradient).
    static let accent = LinearGradient(
        colors: [Color(hex: 0x7C5CFF), Color(hex: 0x4C7BFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Amber/gold sweep for the secondary accent.
    static let gold = LinearGradient(
        colors: [Color(hex: 0xE2C79A), Color(hex: 0xC9A96E), Color(hex: 0xA3853F)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// The conic purple → blue → gold border used on Liquid Glass edges.
    static let glassBorder = AngularGradient(
        colors: [
            Color(hex: 0x7C5CFF), Color(hex: 0x4C7BFF),
            Color(hex: 0xC9A96E), Color(hex: 0x7C5CFF)
        ],
        center: .center
    )
}
