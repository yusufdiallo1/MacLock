//
//  LockManager.swift
//  LockGuard
//
//  The popover's view of what's guarded. Folders are owned here; the app list
//  is delegated to AppLockService (the single source of truth for locked apps,
//  keyed by bundle ID) so the popover UI and enforcement never disagree.
//
//  This store owns *what folders* are guarded and *whether* each is armed;
//  app locking — including activation-watching — lives in AppLockService.
//

import AppKit
import Combine

@MainActor
final class LockManager: ObservableObject {
    static let shared = LockManager()

    /// Guarded folders, in insertion order. Apps live in `appLock`.
    @Published private(set) var folders: [LockedItem] = []

    private let appLock: AppLockService
    private let defaultsKey = "LockGuard.lockedFolders.v1"
    private var cancellables = Set<AnyCancellable>()

    private init(appLock: AppLockService = .shared) {
        self.appLock = appLock
        load()
        // Re-publish when the app list changes so the popover refreshes.
        appLock.$lockedApps
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    /// Guarded applications, projected from AppLockService.
    var apps: [LockedItem] { appLock.lockedItems }

    /// Every guarded item, apps first.
    var allItems: [LockedItem] { apps + folders }

    /// True when at least one item exists and every one of them is locked.
    /// Apps are always locked while present, so this reduces to the folders.
    var everythingLocked: Bool {
        let items = allItems
        return !items.isEmpty && items.allSatisfy(\.isLocked)
    }

    /// True when nothing is guarded yet — drives the empty state.
    var isEmpty: Bool { apps.isEmpty && folders.isEmpty }

    // MARK: - Toggling

    /// Flip a single item's locked state and persist. For apps, "unlocking"
    /// means removing them from the locked set (presence == locked).
    func toggle(_ item: LockedItem) {
        setLocked(!item.isLocked, for: item)
    }

    func setLocked(_ locked: Bool, for item: LockedItem) {
        switch item.kind {
        case .app:
            guard let bundleID = item.bundleID else { return }
            if locked {
                appLock.lockApp(bundleID: bundleID, name: item.name, path: item.path)
            } else {
                appLock.unlockApp(bundleID: bundleID)
            }
        case .folder:
            if let i = folders.firstIndex(where: { $0.id == item.id }) {
                folders[i].isLocked = locked
                save()
            }
        }
    }

    /// Arm every guarded item. Backs the "Lock All Now" button. Apps in the
    /// list are already locked; this re-arms the folders.
    func lockAll() {
        for i in folders.indices { folders[i].isLocked = true }
        save()
    }

    // MARK: - Removal

    func remove(_ item: LockedItem) {
        switch item.kind {
        case .app:
            if let bundleID = item.bundleID { appLock.unlockApp(bundleID: bundleID) }
        case .folder:
            folders.removeAll { $0.id == item.id }
            save()
        }
    }

    // MARK: - Adding via pickers

    /// Browse /Applications and lock the chosen apps (delegated to AppLockService).
    func presentAddApps() {
        appLock.presentAddApps()
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

    private func addFolder(at url: URL) {
        let path = url.path
        guard !folders.contains(where: { $0.path == path }) else { return }
        let name = FileManager.default.displayName(atPath: path)
        folders.append(LockedItem(path: path, name: name, kind: .folder, isLocked: true))
        save()
    }

    // MARK: - Persistence

    // The app runs unsandboxed (see LockGuard.entitlements), so raw paths are
    // durable identities across launches — no security-scoped bookmarks needed.
    // Icons fall back to an SF Symbol if a path becomes unreadable.

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let items = try? JSONDecoder().decode([LockedItem].self, from: data)
        else { return }
        folders = items.filter { $0.kind == .folder }
    }
}
