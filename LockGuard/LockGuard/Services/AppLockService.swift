//
//  AppLockService.swift
//  LockGuard
//
//  The enforcement side of app locking. Owns the set of locked apps (keyed by
//  bundle identifier — the stable identity NSRunningApplication exposes),
//  persists it across launches, and watches for a locked app coming to the
//  foreground. When one is activated it records the app and posts a
//  notification so the auth overlay can challenge the user.
//
//  This is THE store for locked apps: LockManager delegates its app list here
//  so the popover UI and enforcement never disagree.
//

import AppKit
import Combine

extension Notification.Name {
    /// Posted when a locked app is activated and the user must authenticate.
    /// `userInfo[AppLockService.lockedAppUserInfoKey]` holds the `LockedApp`.
    static let lockGuardShouldPresentAuthOverlay = Notification.Name(
        "com.lockguard.shouldPresentAuthOverlay"
    )
    /// Posted when AntiSpoofService blocks a confirmed impostor instead of
    /// presenting the auth overlay. `userInfo` carries the `LockedApp`.
    static let lockGuardDidBlockImpostor = Notification.Name(
        "com.lockguard.didBlockImpostor"
    )
}

/// A locked application. Bundle ID is the identity; path + name are resolved
/// when the app is added and cached for display, so the popover has an icon and
/// label even when the app isn't running.
struct LockedApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    /// Last-known path on disk, for the icon. May be stale if the app moved.
    var path: String

    var id: String { bundleID }
}

@MainActor
final class AppLockService: ObservableObject {
    static let shared = AppLockService()

    /// UserInfo key carrying the `LockedApp` on the auth-overlay notification.
    static let lockedAppUserInfoKey = "lockedApp"

    /// Locked apps, in insertion order. Published so the popover reacts.
    @Published private(set) var lockedApps: [LockedApp] = []

    /// The app that most recently tripped the lock — set just before the
    /// auth-overlay notification is posted, for the overlay to read.
    @Published private(set) var pendingApp: LockedApp?

    private let defaultsKey = "LockGuard.lockedAppBundleIDs.v1"
    private var activateObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?

    /// The bundle ID currently behind the auth overlay. While set, re-activating
    /// the same app won't re-trigger — otherwise every return of focus to the
    /// locked app (including dismissing the overlay) would spam a new challenge.
    /// Cleared when the app deactivates or auth completes (`clearPending`).
    private var challengingBundleID: String?

    private init() {
        load()
        startObserving()
    }

    // MARK: - Activation watching

    /// Observe app activation and deactivation on the *workspace* notification
    /// center (not the default one — workspace notifications are only delivered
    /// there). The observer block runs on the main queue; because everything it
    /// touches is main-actor state, we assume-isolated onto the main actor
    /// rather than deferring through a Task (which would delay the challenge by
    /// a run-loop hop).
    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated { self?.handleActivation(of: app) }
        }
        // Also catch launches that don't bring the app to the foreground
        // (e.g. `open -g`, login items) — those fire didLaunch but not
        // didActivate, so they'd otherwise slip through until first focus.
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated { self?.handleActivation(of: app) }
        }
        deactivateObserver = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated { self?.handleDeactivation(of: app) }
        }
    }

    /// Apps unlocked this session — they won't re-challenge until re-locked
    /// (sleep / timeout / manual "Lock All"). This is the "grant 1 session of
    /// access" behavior.
    private var sessionUnlocked: Set<String> = []

    private func handleActivation(of app: NSRunningApplication?) {
        guard
            let app,
            let bundleID = app.bundleIdentifier,
            // Never challenge on our own activation (e.g. showing the overlay).
            bundleID != Bundle.main.bundleIdentifier,
            // Already challenging this app — don't re-fire while the overlay is
            // up or focus is bouncing back to it.
            bundleID != challengingBundleID,
            // Already unlocked this session — grant access without re-challenging.
            !sessionUnlocked.contains(bundleID),
            let locked = lockedApp(for: bundleID)
        else { return }

        // 0. Anti-spoof: verify the running process's signed identity against
        //    the pinned one before we ever show the password prompt. A confirmed
        //    impostor is denied outright — we never present the auth UI to it.
        let trusted = lockedApps.map { (bundleID: $0.bundleID, name: $0.name,
                                        teamID: CodeSignature.identity(forBundleAt: URL(fileURLWithPath: $0.path))?.teamID) }
        let verdict = AntiSpoofService.shared.verify(
            pid: app.processIdentifier, bundleID: bundleID, appName: locked.name, trustedApps: trusted)

        if case .block = verdict {
            // Deny: hide the impostor and don't present the genuine prompt (which
            // would invite the user to type their password into a fake context).
            challengingBundleID = nil
            app.hide()
            NotificationCenter.default.post(name: .lockGuardDidBlockImpostor, object: self,
                                            userInfo: [Self.lockedAppUserInfoKey: locked])
            return
        }
        // .warn and .allow both proceed to the normal prompt; .warn has already
        // recorded a detection surfaced in the Security pane.

        // 1. Record which app was activated.
        challengingBundleID = bundleID
        pendingApp = locked

        // 2. Post the notification that triggers the auth overlay.
        NotificationCenter.default.post(
            name: .lockGuardShouldPresentAuthOverlay,
            object: self,
            userInfo: [Self.lockedAppUserInfoKey: locked]
        )
    }

    /// When the challenged app loses focus, allow it to challenge again next
    /// time it's activated.
    private func handleDeactivation(of app: NSRunningApplication?) {
        guard let bundleID = app?.bundleIdentifier,
              bundleID == challengingBundleID else { return }
        challengingBundleID = nil
    }

    // MARK: - Query

    func isLocked(bundleID: String) -> Bool {
        lockedApps.contains { $0.bundleID == bundleID }
    }

    private func lockedApp(for bundleID: String) -> LockedApp? {
        lockedApps.first { $0.bundleID == bundleID }
    }

    // MARK: - Mutation

    /// Lock an app by bundle ID. Resolves the app's name and path from the
    /// bundle ID when available so the popover can show its icon. No-op if
    /// already locked.
    func lockApp(bundleID: String, name: String? = nil, path: String? = nil) {
        // Hardening: LockGuard can never lock itself (would trap the user out
        // of the one app that unlocks everything).
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        guard !isLocked(bundleID: bundleID) else { return }

        let resolvedPath = path ?? Self.pathForApp(bundleID: bundleID)
        let resolvedName = name
            ?? resolvedPath.map { FileManager.default.displayName(atPath: $0)
                .replacingOccurrences(of: ".app", with: "") }
            ?? bundleID

        lockedApps.append(
            LockedApp(bundleID: bundleID, name: resolvedName, path: resolvedPath ?? "")
        )
        // Pin the app's signed identity so later activations can be verified
        // against it (impostor detection).
        if let p = resolvedPath {
            AntiSpoofService.shared.pinIdentity(forBundleAt: URL(fileURLWithPath: p), bundleID: bundleID)
        }
        save()
    }

    /// Lock an app straight from its on-disk URL (used by the /Applications
    /// browser), reading its bundle ID from the bundle.
    func lockApp(at url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        lockApp(bundleID: bundleID, name: name, path: url.path)
    }

    func unlockApp(bundleID: String) {
        guard isLocked(bundleID: bundleID) else { return }
        lockedApps.removeAll { $0.bundleID == bundleID }
        if pendingApp?.bundleID == bundleID { pendingApp = nil }
        if challengingBundleID == bundleID { challengingBundleID = nil }
        save()
    }

    /// Clear the pending app once the overlay has been dealt with (auth passed
    /// or was cancelled). Also drops the re-trigger guard so a later activation
    /// of the same app challenges again.
    func clearPending() {
        pendingApp = nil
        challengingBundleID = nil
    }

    /// Auth succeeded for `bundleID` → grant it a session of access. It won't
    /// re-challenge until everything is re-locked (sleep / timeout / manual).
    func grantSession(bundleID: String) {
        sessionUnlocked.insert(bundleID)
        pendingApp = nil
        challengingBundleID = nil
    }

    /// The bundle ID currently being challenged, for the resolver to grant.
    var challengingApp: String? { challengingBundleID }

    /// Re-lock all apps: end every granted session and drop challenge state so
    /// every locked app challenges again on its next activation. Used by sleep /
    /// timeout / kill switch / manual "Lock All".
    func relockAll() {
        sessionUnlocked.removeAll()
        pendingApp = nil
        challengingBundleID = nil
    }

    // MARK: - Browsing /Applications

    /// Present an open panel scoped to /Applications so the user can pick apps
    /// to lock. New apps are locked immediately. Uses the async `begin` API (not
    /// `runModal`) so it doesn't block the popover's run loop; the panel closes
    /// itself when the user is done. `completion` fires after selections apply.
    func presentAddApps(completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Lock"
        panel.prompt = "Lock"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.begin { [weak self] response in
            if response == .OK {
                for url in panel.urls { self?.lockApp(at: url) }
            }
            completion?()
        }
    }

    // MARK: - Path resolution

    /// Best-effort path for a bundle ID: prefer a running instance, else ask
    /// LaunchServices where the app is installed.
    private static func pathForApp(bundleID: String) -> String? {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first,
           let url = running.bundleURL {
            return url.path
        }
        return NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)?.path
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(lockedApps) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let apps = try? JSONDecoder().decode([LockedApp].self, from: data)
        else { return }
        lockedApps = apps
    }
}

extension AppLockService {
    /// The locked apps projected as `LockedItem`s for the popover. This is a
    /// pure map over cached fields — no disk or LaunchServices lookups — so it
    /// is safe to read from a SwiftUI `body` on every render. The path is
    /// resolved once at lock time and stored; `isLocked` is always true here
    /// because presence in this list *is* the locked state.
    var lockedItems: [LockedItem] {
        lockedApps.map { app in
            LockedItem(
                path: app.path,
                bundleID: app.bundleID,
                name: app.name,
                kind: .app,
                isLocked: true
            )
        }
    }
}
