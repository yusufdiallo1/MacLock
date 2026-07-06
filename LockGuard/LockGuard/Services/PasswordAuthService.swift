//
//  PasswordAuthService.swift
//  LockGuard
//
//  Master-password authentication. The password is NEVER stored in plaintext:
//  only a SHA-256 hash of (salt ‖ password) plus the random salt live in the
//  Keychain (kSecClassGenericPassword, WhenUnlockedThisDeviceOnly). Verifying
//  hashes the input with the stored salt and compares.
//
//  Also owns the emergency kill switch (Ctrl+Option+Shift+Delete): it locks all
//  guarded apps immediately and disables face unlock for a cool-down window, so
//  only the master password can unlock during that time.
//
//  NOTE: SHA-256 of a salted password is fast to brute-force compared to a
//  proper KDF (PBKDF2/scrypt/Argon2). This matches the requested spec; if this
//  ever guards something valuable, move to a slow KDF. Documented so it's a
//  known trade-off, not an oversight.
//

import Foundation
import CryptoKit
import Combine

@MainActor
final class PasswordAuthService: ObservableObject {
    static let shared = PasswordAuthService()

    /// Whether a master password has been set. Drives first-launch setup.
    @Published private(set) var isPasswordSet: Bool = false

    /// True while the emergency kill switch's cool-down is active — face unlock
    /// is suppressed and only the master password will unlock.
    @Published private(set) var killSwitchActive: Bool = false
    /// Seconds remaining in the kill-switch cool-down, for UI.
    @Published private(set) var killSwitchSecondsRemaining: Int = 0

    /// Result of setting or changing a password.
    enum PasswordResult: Equatable {
        case success
        case mismatch          // confirmation didn't match
        case tooShort          // below the minimum length
        case wrongCurrent      // change flow: current password incorrect
        case notSet            // change flow: no password exists yet
        case storageFailed     // Keychain write failed
    }

    // MARK: - Config

    static let minimumLength = 4
    static let killSwitchCooldown: TimeInterval = 60
    private static let keychainService = "com.lockguard.password"
    private static let keychainAccount = "master-password-v1"

    private var cooldownTimer: AnyCancellable?
    private var cooldownDeadline: Date?

    private init() {
        isPasswordSet = (Self.loadRecord() != nil)
    }

    // MARK: - Set / change

    /// Set the master password for the first time. `confirm` must match.
    @discardableResult
    func setPassword(_ password: String, confirm: String) -> PasswordResult {
        guard password.count >= Self.minimumLength else { return .tooShort }
        guard password == confirm else { return .mismatch }
        guard let record = Self.makeRecord(for: password) else { return .storageFailed }
        guard Self.store(record) else { return .storageFailed }
        isPasswordSet = true
        return .success
    }

    /// Change the master password. Requires the current password first.
    @discardableResult
    func changePassword(current: String, new: String, confirm: String) -> PasswordResult {
        guard Self.loadRecord() != nil else { return .notSet }
        guard verify(current) else { return .wrongCurrent }
        guard new.count >= Self.minimumLength else { return .tooShort }
        guard new == confirm else { return .mismatch }
        guard let record = Self.makeRecord(for: new), Self.store(record) else {
            return .storageFailed
        }
        return .success
    }

    // MARK: - Verify

    /// Constant-time-ish comparison of the input's salted hash against the
    /// stored hash. Returns false if no password is set.
    func verify(_ password: String) -> Bool {
        guard let record = Self.loadRecord() else { return false }
        let candidate = Self.hash(password: password, salt: record.salt)
        // SHA256.Digest / Data compare; use constant-time to avoid timing leaks.
        return Self.constantTimeEqual(candidate, record.hash)
    }

    // MARK: - Emergency kill switch

    /// Fired by the Ctrl+Option+Shift+Delete hotkey. Locks everything now and
    /// disables face unlock for the cool-down; only the master password unlocks.
    func triggerKillSwitch() {
        LockManager.shared.lockAll()
        FaceAuthService.shared.setKillSwitch(active: true)

        killSwitchActive = true
        cooldownDeadline = Date().addingTimeInterval(Self.killSwitchCooldown)
        killSwitchSecondsRemaining = Int(Self.killSwitchCooldown)

        cooldownTimer?.cancel()
        cooldownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickCooldown() }
    }

    private func tickCooldown() {
        guard let deadline = cooldownDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            endKillSwitch()
        } else {
            killSwitchSecondsRemaining = Int(remaining.rounded(.up))
        }
    }

    private func endKillSwitch() {
        cooldownTimer?.cancel()
        cooldownTimer = nil
        cooldownDeadline = nil
        killSwitchSecondsRemaining = 0
        killSwitchActive = false
        FaceAuthService.shared.setKillSwitch(active: false)
    }

    // MARK: - Remove (e.g. reset)

    func removePassword() {
        Self.deleteRecord()
        isPasswordSet = false
    }
}

// MARK: - Crypto + storage

private extension PasswordAuthService {

    /// The stored record: a random salt and the SHA-256 of (salt ‖ password).
    struct Record {
        var salt: Data
        var hash: Data
    }

    static func hash(password: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(password.utf8))
        let digest = SHA256.hash(data: input)
        return Data(digest)
    }

    static func makeRecord(for password: String) -> Record? {
        var salt = Data(count: 16)
        let ok = salt.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return SecRandomCopyBytes(kSecRandomDefault, 16, base) == errSecSuccess
        }
        guard ok else { return nil }
        return Record(salt: salt, hash: hash(password: password, salt: salt))
    }

    /// Constant-time equality so verify() doesn't leak via timing.
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    // Serialized as [UInt8 saltLen][salt][hash]. Plaintext never touches this.

    static func encode(_ record: Record) -> Data {
        var data = Data()
        data.append(UInt8(record.salt.count))
        data.append(record.salt)
        data.append(record.hash)
        return data
    }

    static func decode(_ data: Data) -> Record? {
        guard let saltLen = data.first.map(Int.init),
              saltLen > 0, data.count > 1 + saltLen else { return nil }
        let salt = data.subdata(in: 1..<(1 + saltLen))
        let hash = data.subdata(in: (1 + saltLen)..<data.count)
        guard !hash.isEmpty else { return nil }
        return Record(salt: salt, hash: hash)
    }

    static func store(_ record: Record) -> Bool {
        let data = encode(record)
        deleteRecord()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // Data-protection keychain → silent self-access, no system prompt.
            kSecUseDataProtectionKeychain as String: true,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadRecord() -> Record? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return decode(data)
    }

    static func deleteRecord() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
