//
//  FolderLockService.swift
//  LockGuard
//
//  Guards folders by making their contents unavailable until the user
//  authenticates.
//
//  ⚠️ SECURITY WARNING — CONVENIENCE, NOT REAL ENCRYPTION.
//  When a locked folder is accessed, its contents are XOR-"encrypted" with a
//  fixed key and moved into a hidden container. XOR with a static key is
//  trivially reversible and is a PLACEHOLDER only — anyone with disk access can
//  recover the data. This deters casual snooping, nothing more. Replace the XOR
//  in `FolderCrypto` with AES-GCM (CryptoKit) + a Keychain-held key before this
//  guards anything that matters. See the marked TODO.
//
//  When a locked folder is opened in Finder (watched via a DispatchSource
//  file-system observer), the service moves its contents to the hidden
//  container, shows the auth overlay full-screen (folders can't target a
//  window), and restores the contents on successful auth.
//

import AppKit
import Combine

@MainActor
final class FolderLockService: ObservableObject {
    static let shared = FolderLockService()

    struct LockedFolder: Codable, Equatable, Identifiable {
        let path: String
        let name: String
        /// Whether the contents are currently stashed away (locked state).
        var isStashed: Bool
        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
    }

    @Published private(set) var lockedFolders: [LockedFolder] = []

    private let defaultsKey = "LockGuard.folderLock.v1"
    /// Hidden container holding stashed, XOR-scrambled contents, keyed by folder.
    private let containerRoot: URL
    /// One file-system watcher per locked folder.
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        containerRoot = appSupport.appendingPathComponent("LockGuard/.locked", isDirectory: true)
        try? FileManager.default.createDirectory(at: containerRoot, withIntermediateDirectories: true)
        load()
        for folder in lockedFolders where !folder.isStashed { startWatching(folder) }
    }

    // MARK: - Public: manage locked folders

    /// Pick folders via NSOpenPanel and start guarding them.
    func presentAddFolders(completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Choose Folders to Lock"
        panel.prompt = "Lock"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            if response == .OK { for url in panel.urls { self?.addFolder(url) } }
            completion?()
        }
    }

    func addFolder(_ url: URL) {
        let path = url.path
        guard !lockedFolders.contains(where: { $0.path == path }) else { return }
        let folder = LockedFolder(path: path, name: url.lastPathComponent, isStashed: false)
        lockedFolders.append(folder)
        save()
        startWatching(folder)
    }

    func removeFolder(_ path: String) {
        // Make sure contents are restored before we stop guarding.
        if let f = lockedFolders.first(where: { $0.path == path }), f.isStashed {
            restore(f)
        }
        stopWatching(path)
        lockedFolders.removeAll { $0.path == path }
        save()
    }

    func isLocked(path: String) -> Bool {
        lockedFolders.contains { $0.path == path }
    }

    // MARK: - Watching (DispatchSource file-system observer)

    private func startWatching(_ folder: LockedFolder) {
        stopWatching(folder.path)
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.attrib, .extend, .write, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.folderAccessed(folder.path) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[folder.path] = source
    }

    private func stopWatching(_ path: String) {
        watchers[path]?.cancel()
        watchers[path] = nil
    }

    /// A locked folder was touched → stash it and challenge the user.
    private func folderAccessed(_ path: String) {
        guard let idx = lockedFolders.firstIndex(where: { $0.path == path }),
              !lockedFolders[idx].isStashed else { return }

        stash(lockedFolders[idx])

        // Folders can't target a window, so the overlay is always full-screen.
        // Any running PID works to anchor the overlay; use our own.
        WindowOverlayService.shared.present(
            forPID: ProcessInfo.processInfo.processIdentifier,
            appName: lockedFolders[idx].name,
            forceFullScreen: true
        )
        WindowOverlayService.shared.onResolved = { [weak self] in
            guard let self, let f = self.lockedFolders.first(where: { $0.path == path })
            else { return }
            self.restore(f)
        }
    }

    // MARK: - Stash / restore (move contents ↔ hidden container)

    private func containerURL(for folder: LockedFolder) -> URL {
        // Stable per-path directory name (hashed) inside the hidden container.
        let key = String(folder.path.hashValue, radix: 16)
        return containerRoot.appendingPathComponent(key, isDirectory: true)
    }

    /// Move the folder's contents into the hidden container, XOR-scrambled.
    private func stash(_ folder: LockedFolder) {
        let fm = FileManager.default
        let dest = containerURL(for: folder)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)

        guard let entries = try? fm.contentsOfDirectory(
            at: folder.url, includingPropertiesForKeys: nil, options: []
        ) else { return }

        for item in entries {
            let target = dest.appendingPathComponent(item.lastPathComponent)
            // Best-effort XOR on files; directories are moved as-is (placeholder).
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? fm.moveItem(at: item, to: target)
            } else if let data = try? Data(contentsOf: item) {
                let scrambled = FolderCrypto.xor(data)
                try? scrambled.write(to: target)
                try? fm.removeItem(at: item)
            }
        }
        setStashed(folder.path, true)
        stopWatching(folder.path)   // don't re-trigger while stashed
    }

    /// Restore the folder's contents from the hidden container.
    private func restore(_ folder: LockedFolder) {
        let fm = FileManager.default
        let src = containerURL(for: folder)
        guard let entries = try? fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: nil, options: []
        ) else { setStashed(folder.path, false); return }

        for item in entries {
            let target = folder.url.appendingPathComponent(item.lastPathComponent)
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? fm.moveItem(at: item, to: target)
            } else if let data = try? Data(contentsOf: item) {
                let unscrambled = FolderCrypto.xor(data)   // XOR is its own inverse
                try? unscrambled.write(to: target)
                try? fm.removeItem(at: item)
            }
        }
        try? fm.removeItem(at: src)
        setStashed(folder.path, false)
        if let f = lockedFolders.first(where: { $0.path == folder.path }) {
            startWatching(f)   // resume guarding
        }
    }

    private func setStashed(_ path: String, _ stashed: Bool) {
        guard let idx = lockedFolders.firstIndex(where: { $0.path == path }) else { return }
        lockedFolders[idx].isStashed = stashed
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(lockedFolders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let folders = try? JSONDecoder().decode([LockedFolder].self, from: data)
        else { return }
        lockedFolders = folders
    }
}

// MARK: - Placeholder crypto

/// ⚠️ PLACEHOLDER ONLY. XOR with a static key is NOT encryption — it's trivially
/// reversible. Replace with AES-GCM (CryptoKit `AES.GCM.seal/open`) using a key
/// stored in the Keychain before relying on this for anything sensitive.
enum FolderCrypto {
    // TODO: replace with AES-GCM + Keychain-held symmetric key.
    private static let key: [UInt8] = Array("LockGuardPlaceholderKey".utf8)

    static func xor(_ data: Data) -> Data {
        var out = Data(count: data.count)
        for i in data.indices {
            out[i] = data[i] ^ key[i % key.count]
        }
        return out
    }
}
