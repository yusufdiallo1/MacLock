//
//  CodeSignature.swift
//  LockGuard
//
//  The crypto-backed half of impostor detection. macOS code-signing is a real,
//  hard identity: an app can lie about its bundle id and name, but it cannot
//  forge another developer's Team ID without that developer's private key. So
//  we pin a locked app's Team ID and, on each activation, verify the *running*
//  process still presents the same signed identity.
//
//  Reading another process's signature requires no special entitlement for an
//  unsandboxed app: SecCodeCopyGuestWithAttributes resolves a running pid to a
//  SecCode, and SecStaticCode does the same for an on-disk bundle.
//
//  Honest bounds: an unsigned or ad-hoc-signed app has no Team ID to pin —
//  those are handled by the caller's "warn, don't block" policy, never a hard
//  lockout of a legitimate unsigned app.
//

import Foundation
import Security

/// A snapshot of a process's / bundle's signing identity.
struct SigningIdentity: Equatable, Codable {
    /// The Apple Developer Team ID (e.g. "AB12CD34E5"), or nil if unsigned /
    /// ad-hoc (no team).
    let teamID: String?
    /// Whether the signature passed `SecCodeCheckValidity` (dynamic) or
    /// `SecStaticCodeCheckValidity` (static). False for broken/tampered.
    let isValid: Bool
    /// Ad-hoc signed (signed with no identity — the "-" signer). Common for
    /// locally-built and some dev tools; carries no Team ID.
    let isAdhoc: Bool

    /// A signature we can meaningfully pin against (has a real team + is valid).
    var isPinnable: Bool { isValid && teamID != nil && !isAdhoc }
}

enum CodeSignature {

    /// The signing identity of a *running* process, or nil if the process is
    /// gone / unreadable.
    static func identity(forPID pid: pid_t) -> SigningIdentity? {
        var pidValue = pid
        guard let pidNum = CFNumberCreate(nil, .intType, &pidValue) else { return nil }
        let attrs = [kSecGuestAttributePid: pidNum] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return nil }

        // Convert the dynamic SecCode to a static one to read signing info.
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        return identity(of: staticCode, checkValidity: {
            SecCodeCheckValidity(code, [], nil) == errSecSuccess
        })
    }

    /// The signing identity of an on-disk app bundle, or nil if it can't be
    /// read. Used to pin a locked app's identity from its bundle at lock time.
    static func identity(forBundleAt url: URL) -> SigningIdentity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        return identity(of: staticCode, checkValidity: {
            SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
        })
    }

    // MARK: - Shared reader

    private static func identity(of staticCode: SecStaticCode,
                                 checkValidity: () -> Bool) -> SigningIdentity? {
        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            // No signing information at all → treat as unsigned.
            return SigningIdentity(teamID: nil, isValid: false, isAdhoc: true)
        }

        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String

        // Ad-hoc: the signer flags carry the adhoc bit, or there's a signature
        // but no team identifier and no certificate chain.
        var isAdhoc = false
        if let flagsValue = info[kSecCodeInfoFlags as String] as? UInt32 {
            isAdhoc = (flagsValue & SecCodeSignatureFlags.adhoc.rawValue) != 0
        }
        let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        if (certs?.isEmpty ?? true) && teamID == nil { isAdhoc = true }

        return SigningIdentity(teamID: teamID, isValid: checkValidity(), isAdhoc: isAdhoc)
    }
}
