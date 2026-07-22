//
//  ThemeStore.swift
//  LockGuard — DesignSystem
//
//  The runtime-tunable half of the design system. Colors and glass are static
//  tokens by default (Colors.swift, LiquidGlass.swift); this store lets the
//  Appearance pane override the accent and glass feel at runtime. Everything is
//  @AppStorage-backed under `LG.theme.*` keys, so it persists locally and is
//  ready for Prompt 24's SyncService to mirror the non-secret look across Macs.
//
//  `Theme.accent` (and friends) and `LGGlass` read `ThemeStore.shared`, so a
//  change here propagates without editing the ~53 token call sites — the views
//  that host tunable surfaces observe the store and re-render.
//

import SwiftUI

// MARK: - Accent choices

/// The curated accent set. Each maps to a primary hex; the paired secondary is
/// the gold unless the user picked gold-forward, in which case purple pairs it.
enum AccentChoice: String, CaseIterable, Identifiable {
    case purple, blue, teal, magenta, gold
    var id: String { rawValue }

    var label: String {
        switch self {
        case .purple:  return "Purple"
        case .blue:    return "Blue"
        case .teal:    return "Teal"
        case .magenta: return "Magenta"
        case .gold:    return "Gold"
        }
    }

    var primaryHex: UInt {
        switch self {
        case .purple:  return 0x7C5CFF   // the default lgAccentPrimary
        case .blue:    return 0x4C7BFF
        case .teal:    return 0x2FD4C4
        case .magenta: return 0xE85CC4
        case .gold:    return 0xC9A96E
        }
    }

    /// The paired secondary accent. Gold pairs everything except gold-forward,
    /// which pairs back to purple so the two accents stay distinct.
    var secondaryHex: UInt {
        self == .gold ? 0x7C5CFF : 0xC9A96E
    }

    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }
}

// MARK: - Store

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    /// Chosen accent. Stored as its raw string.
    @AppStorage("LG.theme.accent") private var accentRaw = AccentChoice.purple.rawValue {
        willSet { objectWillChange.send() }
    }

    /// Glass tint strength, subtle (0) → vivid (1). Near the floor the surfaces
    /// approach solid. Separate from the OS Reduce Transparency setting.
    @AppStorage("LG.theme.glassIntensity") var glassIntensity = 0.6 {
        willSet { objectWillChange.send() }
    }

    /// In-app high-contrast: thickens strokes + heavier text. Composes with the
    /// system Increase Contrast flag (either one turns it on).
    @AppStorage("LG.theme.highContrast") var highContrast = false {
        willSet { objectWillChange.send() }
    }

    /// In-app "reduce glass": pushes surfaces toward solid, independent of the
    /// OS Reduce Transparency setting (either one solidifies).
    @AppStorage("LG.theme.reduceGlass") var reduceGlass = false {
        willSet { objectWillChange.send() }
    }

    /// Corner style for cards/panels: continuous (default) vs plain rounded.
    @AppStorage("LG.theme.cornerContinuous") var cornerContinuous = true {
        willSet { objectWillChange.send() }
    }

    /// In-app reduce-motion: disables the animated glass-border sheen + emitters.
    /// Composes with the system Reduce Motion flag (either one disables).
    @AppStorage("LG.theme.reduceMotion") var reduceMotionInApp = false {
        willSet { objectWillChange.send() }
    }

    private init() {}

    // MARK: Derived color tokens

    var accentChoice: AccentChoice {
        get { AccentChoice(rawValue: accentRaw) ?? .purple }
        set { accentRaw = newValue.rawValue }
    }

    var accent: Color { accentChoice.primary }
    var accentSecondary: Color { accentChoice.secondary }
    var accentSoft: Color { accentChoice.primary.opacity(0.16) }

    /// The rounded-rect style the glass system should use for its corners.
    var cornerStyle: RoundedCornerStyle { cornerContinuous ? .continuous : .circular }
}
