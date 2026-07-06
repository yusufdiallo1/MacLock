//
//  LockedItem.swift
//  LockGuard
//
//  A thing LockGuard can lock: an installed application or a folder on disk.
//  Value type — the store owns the array and mutates `isLocked` in place.
//

import AppKit

/// What kind of thing is being guarded. Drives the fallback SF Symbol and
/// how we resolve an icon when none is cached.
enum LockedItemKind: String, Codable {
    case app
    case folder

    /// SF Symbol used when a real icon can't be loaded.
    var fallbackSymbol: String {
        switch self {
        case .app:    return "app.dashed"
        case .folder: return "folder.fill"
        }
    }
}

/// A single guarded item. Identity is the file-system path, which is stable
/// across launches and lets us persist the set without storing icons.
///
/// Apps also carry a `bundleID`: activation-watching keys off the bundle
/// identifier (that's the stable identity `NSRunningApplication` exposes),
/// while the path drives the icon and display name.
struct LockedItem: Identifiable, Equatable, Codable {
    /// Absolute file-system path — also the stable identity.
    let path: String
    /// Bundle identifier, for apps. `nil` for folders.
    let bundleID: String?
    /// Display name (app name or folder name).
    let name: String
    let kind: LockedItemKind
    /// Whether this item is currently armed.
    var isLocked: Bool

    var id: String { path }

    var url: URL { URL(fileURLWithPath: path) }

    init(path: String, bundleID: String? = nil, name: String, kind: LockedItemKind, isLocked: Bool) {
        self.path = path
        self.bundleID = bundleID
        self.name = name
        self.kind = kind
        self.isLocked = isLocked
    }

    // MARK: Codable — icons are resolved at runtime, never persisted.

    enum CodingKeys: String, CodingKey {
        case path, bundleID, name, kind, isLocked
    }
}

extension LockedItem {
    /// Best-available icon for this item, resolved live from the file system.
    /// Falls back to a tinted SF Symbol image if the path no longer exists.
    var icon: NSImage {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        return NSImage(systemSymbolName: kind.fallbackSymbol,
                       accessibilityDescription: name)?
            .withSymbolConfiguration(config)
            ?? NSImage()
    }
}
