//
//  InstalledItems.swift
//  LockGuard
//
//  Enumerates things the user can pick to lock — installed apps and the
//  contents of common folders — so the picker can show an in-app list instead
//  of a Finder open panel.
//

import AppKit

/// A pickable app or folder, resolved from disk.
struct PickableItem: Identifiable, Equatable {
    let path: String
    let name: String
    let bundleID: String?   // apps only
    var id: String { path }

    var url: URL { URL(fileURLWithPath: path) }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }
}

/// A common folder location the user can drill into when picking folders.
struct FolderLocation: Identifiable, Equatable {
    let name: String
    let path: String
    let symbol: String
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

enum InstalledItems {

    // MARK: - Apps

    /// All installed applications, sorted by name. Scans the standard app
    /// directories; each `.app` bundle becomes one PickableItem.
    static func installedApps() -> [PickableItem] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications",
                    (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]

        var seen = Set<String>()
        var apps: [PickableItem] = []
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(entry)
                guard !seen.contains(path) else { continue }
                seen.insert(path)
                let name = (entry as NSString).deletingPathExtension
                let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                // Hardening: never offer LockGuard itself as a lockable app.
                guard bundleID != Bundle.main.bundleIdentifier else { continue }
                apps.append(PickableItem(path: path, name: name, bundleID: bundleID))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Folder locations

    /// Common places to start when picking folders to lock.
    static func folderLocations() -> [FolderLocation] {
        let home = NSHomeDirectory()
        func loc(_ name: String, _ sub: String, _ symbol: String) -> FolderLocation? {
            let path = (home as NSString).appendingPathComponent(sub)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return FolderLocation(name: name, path: path, symbol: symbol)
        }
        return [
            loc("Desktop", "Desktop", "menubar.dock.rectangle"),
            loc("Downloads", "Downloads", "arrow.down.circle"),
            loc("Documents", "Documents", "doc"),
            loc("Pictures", "Pictures", "photo"),
            loc("Home", "", "house"),
        ].compactMap { $0 }
    }

    /// The subfolders directly inside a location (hidden folders skipped).
    static func subfolders(of location: FolderLocation) -> [PickableItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: location.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { PickableItem(path: $0.path, name: $0.lastPathComponent, bundleID: nil) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
