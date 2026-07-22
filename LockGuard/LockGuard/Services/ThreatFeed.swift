//
//  ThreatFeed.swift
//  LockGuard
//
//  The source of known-bad signatures that AntiSpoofService matches against.
//  The matching logic is real and runs today against a LocalThreatFeed (a
//  bundled seed list, empty by default). When cloud sync lands (Prompt 24), a
//  SupabaseThreatFeed conforming to this same protocol pulls `threat_signatures`
//  rows periodically — a drop-in with no change to the matching code.
//

import Foundation

/// Known-bad indicators, matched locally against apps as they're locked/opened.
struct ThreatSignatures: Codable, Equatable {
    /// Team IDs known to sign malware / impersonating apps.
    var maliciousTeamIDs: Set<String> = []
    /// Bundle IDs known to impersonate legitimate apps.
    var impersonatingBundleIDs: Set<String> = []
    /// Domains used in phishing (reserved for future URL/link checks).
    var phishingDomains: Set<String> = []

    var isEmpty: Bool {
        maliciousTeamIDs.isEmpty && impersonatingBundleIDs.isEmpty && phishingDomains.isEmpty
    }
}

/// A source of threat signatures. Sync-time implementations refresh from the
/// network; the local one is static.
protocol ThreatFeed: AnyObject {
    /// The signatures to match against right now.
    func current() -> ThreatSignatures
    /// Refresh from the source. A no-op for local feeds.
    func refresh() async
}

/// The local feed used until cloud sync exists. Ships a bundled seed (empty by
/// default) so the match path is fully exercised without a network.
final class LocalThreatFeed: ThreatFeed {
    private let seed: ThreatSignatures

    /// `seed` defaults to empty; a future build can bundle a small static list
    /// of known-bad Team IDs here without touching the matching logic.
    init(seed: ThreatSignatures = ThreatSignatures()) {
        self.seed = seed
    }

    func current() -> ThreatSignatures { seed }
    func refresh() async { /* no network source yet — see Prompt 24 */ }
}

// TODO(Prompt 24): SupabaseThreatFeed: ThreatFeed — pull `threat_signatures`
// (phishing_domain, impersonating_bundle_id, malicious_team_id) on launch and
// periodically, cache locally, and return them from current().
