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

    // Signal — the single accent. Amber = armed / active.
    static let signal     = Color(hex: 0xE8A33D)
    static let signalSoft = Color(hex: 0xE8A33D).opacity(0.14)

    // Pending / steel — the not-yet-armed state.
    static let steel      = Color(hex: 0x5B6170)
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
