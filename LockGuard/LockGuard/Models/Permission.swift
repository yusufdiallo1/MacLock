//
//  Permission.swift
//  LockGuard
//
//  Value types describing the permissions LockGuard needs and their state.
//

import Foundation

/// A capability LockGuard must be granted before it can guard the Mac.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .camera:        return "Camera"
        }
    }

    /// SF Symbol representing the permission in the onboarding sheet.
    var symbol: String {
        switch self {
        case .accessibility: return "hand.raised.fill"
        case .camera:        return "camera.fill"
        }
    }

    /// Plain-language reason, written from the user's side of the screen.
    var rationale: String {
        switch self {
        case .accessibility:
            return "Lets LockGuard lock your Mac and dismiss the screen when you step away."
        case .camera:
            return "Recognizes your face so your Mac unlocks the moment you sit back down."
        }
    }
}

/// Where a single permission stands right now.
enum PermissionStatus: Equatable {
    case notDetermined   // never asked
    case denied          // asked, refused (or revoked in System Settings)
    case granted

    var isGranted: Bool { self == .granted }
}
