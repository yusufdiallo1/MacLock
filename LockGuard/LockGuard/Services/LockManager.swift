//
//  LockManager.swift
//  LockGuard
//
//  Source of truth for the set of guarded apps and folders. Persists the set
//  (paths + locked flags) to UserDefaults, resolves live icons at display time,
//  and offers a picker to add new items.
//
//  Enforcement (actually blocking launches / access) is a separate concern —
//  this store owns *what* is guarded and *whether* each item is armed.
//

import AppKit
import Combine

@MainActor
final class LockManager: ObservableObject {
    static let shared = LockManager()

    /// Guarded applications, in insertion order.
    @Published private(set) var apps: [LockedItem] = []
    /// Guarded folders, in insertion order.
    @Published private(set) var folders: [LockedItem] = []

    private let defaultsKey = "LockGuard.lockedItems.v1"

    private init() {
        load()
    }

    // MARK: - Derived state

    /// Every guarded item, apps first.
    var allItems: [LockedItem] { apps + folders }

    /// True when at least one item exists and every one of them is locked.
    var everythingLocked: Bool {
        let items = allItems
        return !items.isEmpty && items.allSatisfy(\.isLocked)
    }

    /// True when nothing is guarded yet — drives the empty state.
    var isEmpty: Bool { apps.isEmpty && folders.isEmpty }

    // MARK: - Toggling

    /// Flip a single item's locked state and persist.
    func toggle(_ item: LockedItem) {
        setLocked(!item.isLocked, for: item)
    }

    func setLocked(_ locked: Bool, for item: LockedItem) {
        if let i = apps.firstIndex(where: { $0.id == item.id }) {
            apps[i].isLocked = locked
        } else if let i = folders.firstIndex(where: { $0.id == item.id }) {
            folders[i].isLocked = locked
        }
        save()
    }

    /// Arm every guarded item. Backs the "Lock All Now" button.
    func lockAll() {
        for i in apps.indices { apps[i].isLocked = true }
        for i in folders.indices { folders[i].isLocked = true }
        save()
    }

    // MARK: - Removal

    func remove(_ item: LockedItem) {
        apps.removeAll { $0.id == item.id }
        folders.removeAll { $0.id == item.id }
        save()
    }

    // MARK: - Adding via pickers

    /// Present an open panel scoped to /Applications so the user can pick apps
    /// to guard. New items start locked. Ignores duplicates.
    func presentAddApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Lock"
        panel.prompt = "Lock"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addApp(at: url) }
    }

    /// Present an open panel to pick folders to guard. New items start locked.
    func presentAddFolders() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folders to Lock"
        panel.prompt = "Lock"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addFolder(at: url) }
    }

    /// True if any guarded item already has this path. `id == path`, so letting
    /// the same path in twice (e.g. an .app bundle picked as both app and
    /// folder) would create duplicate SwiftUI ForEach IDs.
    private func alreadyGuarded(_ path: String) -> Bool {
        apps.contains { $0.path == path } || folders.contains { $0.path == path }
    }

    private func addApp(at url: URL) {
        let path = url.path
        guard !alreadyGuarded(path) else { return }
        let name = FileManager.default.displayName(atPath: path)
            .replacingOccurrences(of: ".app", with: "")
        apps.append(LockedItem(path: path, name: name, kind: .app, isLocked: true))
        save()
    }

    private func addFolder(at url: URL) {
        let path = url.path
        guard !alreadyGuarded(path) else { return }
        let name = FileManager.default.displayName(atPath: path)
        folders.append(LockedItem(path: path, name: name, kind: .folder, isLocked: true))
        save()
    }

    // MARK: - Persistence

    // NOTE: Under the sandbox, access to user-picked files only survives a
    // relaunch if we persist *security-scoped bookmarks*, not raw paths. We
    // store paths here so the list and toggles are correct within a session and
    // across relaunches for items that remain readable; wiring bookmarks (and
    // start/stopAccessingSecurityScopedResource) is a follow-up for when
    // enforcement lands. Icons fall back to an SF Symbol if a path is unreadable.

    private func save() {
        let all = apps + folders
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let items = try? JSONDecoder().decode([LockedItem].self, from: data)
        else { return }
        apps = items.filter { $0.kind == .app }
        folders = items.filter { $0.kind == .folder }
    }
}
