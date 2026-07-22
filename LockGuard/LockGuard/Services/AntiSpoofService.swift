//
//  AntiSpoofService.swift
//  LockGuard
//
//  Impostor + phishing defense. Two threats:
//   (a) a malicious app drawing a fake LockGuard prompt to steal the password —
//       defended by the per-install SECRET INDICATOR shown only in genuine
//       prompts, so a fake prompt (which can't know it) is recognizable.
//   (b) an impostor app (lookalike bundle id / name, different Team ID) slipping
//       past locking — defended by pinning the locked app's signed identity and
//       verifying the running process against it on every activation.
//
//  Policy (confirmed): warn, don't block, when there's no pin yet (unsigned /
//  first-sighting apps) — we never lock the user out of a legitimate app. We
//  hard-block only the clear impostor case: same bundle id but a different Team
//  ID, a broken signature where a valid one was pinned, or a threat-feed match.
//
//  Honest bounds (documented, not overstated):
//   • The secret indicator defends generic fakes. A targeted attacker who
//     screen-scraped a genuine prompt once could copy it — out of scope here.
//   • Overlay occlusion is a best-effort check; macOS cannot guarantee no other
//     window covers ours. We log a warning, we do not claim to prevent it.
//

import AppKit
import Combine
import Security

@MainActor
final class AntiSpoofService: ObservableObject {
    static let shared = AntiSpoofService()

    /// The threat-signature source. Local today; SupabaseThreatFeed in Prompt 24.
    private let feed: ThreatFeed = LocalThreatFeed()

    /// Recent detections, surfaced in the Security pane.
    @Published private(set) var detections: [Detection] = []

    /// Pinned signing identity per locked bundle id.
    private var pins: [String: SigningIdentity] = [:]
    /// Bundle ids the user explicitly blocked ("block this app").
    private var blocklist: Set<String> = []

    private let pinURL = CryptoBox.appSupportDirectory().appendingPathComponent("identity-pins.json")
    private let blockURL = CryptoBox.appSupportDirectory().appendingPathComponent("blocklist.json")

    private init() {
        load()
    }

    // MARK: - Detection model

    struct Detection: Identifiable, Codable {
        enum Kind: String, Codable { case impostor, lookalike, threatFeed }
        let id: UUID
        let kind: Kind
        let bundleID: String
        let appName: String
        let detail: String
        let date: Date
        var blocked: Bool
        init(kind: Kind, bundleID: String, appName: String, detail: String, blocked: Bool) {
            self.id = UUID(); self.kind = kind; self.bundleID = bundleID
            self.appName = appName; self.detail = detail; self.date = Date(); self.blocked = blocked
        }
    }

    enum Verdict {
        case allow                     // safe — present the normal auth overlay
        case warn(Detection)           // proceed, but a detection was recorded
        case block(Detection)          // impostor — deny, don't present the prompt
    }

    // MARK: - Pinning (called when an app is locked)

    /// Capture and store the signed identity of a locked app from its on-disk
    /// bundle, so later activations can be verified against it.
    func pinIdentity(forBundleAt url: URL, bundleID: String) {
        guard let identity = CodeSignature.identity(forBundleAt: url) else { return }
        // Only pin something meaningful. An unsigned/ad-hoc app has nothing to
        // pin — we record nil so verify() knows it was seen but not pinnable.
        pins[bundleID] = identity
        save()
    }

    // MARK: - Verification (called on each activation, before the overlay)

    /// Check a newly-activated locked app against its pin, the threat feed, the
    /// blocklist, and lookalike heuristics. Called from AppLockService before
    /// presenting the auth overlay.
    func verify(pid: pid_t, bundleID: String, appName: String,
                trustedApps: [(bundleID: String, name: String, teamID: String?)]) -> Verdict {

        // 0. Explicit user blocklist always denies.
        if blocklist.contains(bundleID) {
            let d = record(.impostor, bundleID, appName, "You blocked this app.", blocked: true)
            return .block(d)
        }

        let live = CodeSignature.identity(forPID: pid)
        let sigs = feed.current()

        // 1. Threat feed: known-bad team id or impersonating bundle id.
        if let team = live?.teamID, sigs.maliciousTeamIDs.contains(team) {
            let d = record(.threatFeed, bundleID, appName, "Signed by a Team ID flagged as malicious.", blocked: true)
            logBlocked(appName)
            return .block(d)
        }
        if sigs.impersonatingBundleIDs.contains(bundleID) {
            let d = record(.threatFeed, bundleID, appName, "Bundle ID flagged as a known impersonator.", blocked: true)
            logBlocked(appName)
            return .block(d)
        }

        // 2. Pin check — the core hard control.
        if let pin = pins[bundleID], pin.isPinnable {
            if let live {
                // A valid pin exists; the running process must match its team.
                if let liveTeam = live.teamID, liveTeam != pin.teamID {
                    let d = record(.impostor, bundleID, appName,
                                   "This app's developer identity changed (expected \(pin.teamID ?? "?"), got \(liveTeam)).", blocked: true)
                    logBlocked(appName)
                    return .block(d)
                }
                // Was validly signed when pinned; now broken/ad-hoc → impostor.
                if !live.isValid || live.isAdhoc || live.teamID == nil {
                    let d = record(.impostor, bundleID, appName,
                                   "This app was properly signed when locked but its signature is now invalid.", blocked: true)
                    logBlocked(appName)
                    return .block(d)
                }
            } else {
                // Couldn't read the running process's signature at all.
                let d = record(.impostor, bundleID, appName,
                               "Couldn't verify this app's signature against its pinned identity.", blocked: true)
                logBlocked(appName)
                return .block(d)
            }
        } else {
            // 3. No (pinnable) pin yet — warn, don't block. Capture what we can
            //    so a later identity CHANGE can be caught.
            if let live { pins[bundleID] = live; save() }
        }

        // 4. Lookalike heuristic (never blocks — surfaces a warning).
        if let d = lookalikeDetection(bundleID: bundleID, appName: appName,
                                      liveTeam: live?.teamID, trustedApps: trustedApps) {
            return .warn(d)
        }

        return .allow
    }

    // MARK: - Lookalike detection

    private func lookalikeDetection(bundleID: String, appName: String, liveTeam: String?,
                                    trustedApps: [(bundleID: String, name: String, teamID: String?)]) -> Detection? {
        for t in trustedApps where t.bundleID != bundleID {
            let nameClose = Self.editDistance(appName.lowercased(), t.name.lowercased()) <= 2 && appName.lowercased() != t.name.lowercased()
            let idClose = Self.editDistance(bundleID.lowercased(), t.bundleID.lowercased()) <= 2 && bundleID.lowercased() != t.bundleID.lowercased()
            let differentTeam = (liveTeam != nil && t.teamID != nil && liveTeam != t.teamID)
            if (nameClose || idClose) && differentTeam {
                return record(.lookalike, bundleID, appName,
                              "Looks like “\(t.name)” but is signed by a different developer.", blocked: false)
            }
        }
        return nil
    }

    /// Iterative Levenshtein edit distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            for j in 1...t.count {
                let cost = s[i-1] == t[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }

    // MARK: - User actions

    /// One-tap "block this app" from the Security pane.
    func blockApp(bundleID: String) {
        blocklist.insert(bundleID)
        if let i = detections.firstIndex(where: { $0.bundleID == bundleID }) {
            detections[i].blocked = true
        }
        save()
    }

    func unblockApp(bundleID: String) {
        blocklist.remove(bundleID)
        save()
    }

    func isBlocked(bundleID: String) -> Bool { blocklist.contains(bundleID) }

    func clearDetections() { detections.removeAll() }

    // MARK: - Secret indicator (anti-phishing for the overlay)

    private let keychainService = "com.lockguard.app"
    private let indicatorAccount = "lg.secretIndicator"

    /// Curated defaults so an indicator always EXISTS before onboarding sets one.
    static let curatedIndicators = ["🦊", "🛡️", "🔑", "🌙", "⚡️", "🐙", "🍀", "🎯", "🧭", "🔥", "🦉", "💎"]

    /// The per-install secret shown only in genuine LockGuard prompts. Generated
    /// on first access if unset (deterministic-random via a stored seed so it's
    /// stable). Users are told: no indicator → don't type your password.
    var secretIndicator: String {
        if let existing = readIndicator() { return existing }
        // Pick a stable default from the curated set, seeded by the install's
        // app-support path hash so it's consistent without Date/random at init.
        let seed = abs(pinURL.path.hashValue)
        let choice = Self.curatedIndicators[seed % Self.curatedIndicators.count]
        _ = writeIndicator(choice)
        return choice
    }

    @discardableResult
    func setSecretIndicator(_ value: String) -> Bool {
        writeIndicator(value)
    }

    private func readIndicator() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: indicatorAccount,
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    @discardableResult
    private func writeIndicator(_ value: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: indicatorAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Overlay occlusion (best-effort — NOT a guarantee)

    /// Best-effort check that no other window sits above our overlay. macOS
    /// cannot guarantee this (another app can raise its level), so this only
    /// logs a warning; it never hard-blocks on this signal alone.
    func overlayIsFrontmost(windowNumber: Int) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenAboveWindow], CGWindowID(windowNumber)) as? [[String: Any]]
        else { return true }
        // Ignore our own windows and the desktop; anything else above is suspect.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let intruders = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) != Int(ownPID) }
        if !intruders.isEmpty {
            NSLog("[AntiSpoof] Warning: \(intruders.count) window(s) above the auth overlay (best-effort check).")
            return false
        }
        return true
    }

    // MARK: - Recording + persistence

    @discardableResult
    private func record(_ kind: Detection.Kind, _ bundleID: String, _ appName: String,
                        _ detail: String, blocked: Bool) -> Detection {
        let d = Detection(kind: kind, bundleID: bundleID, appName: appName, detail: detail, blocked: blocked)
        detections.insert(d, at: 0)
        if detections.count > 50 { detections.removeLast(detections.count - 50) }
        return d
    }

    private func logBlocked(_ appName: String) {
        AuthLogService.shared.log(method: .password, success: false,
                                  context: "Blocked impostor: \(appName)", event: "phishing_blocked")
    }

    private func save() {
        let enc = JSONEncoder()
        if let d = try? enc.encode(pins) { try? d.write(to: pinURL, options: .atomic) }
        if let d = try? enc.encode(Array(blocklist)) { try? d.write(to: blockURL, options: .atomic) }
    }

    private func load() {
        let dec = JSONDecoder()
        if let d = try? Data(contentsOf: pinURL),
           let p = try? dec.decode([String: SigningIdentity].self, from: d) { pins = p }
        if let d = try? Data(contentsOf: blockURL),
           let b = try? dec.decode([String].self, from: d) { blocklist = Set(b) }
    }
}
