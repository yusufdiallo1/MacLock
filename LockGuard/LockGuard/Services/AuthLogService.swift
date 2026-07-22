//
//  AuthLogService.swift
//  LockGuard
//
//  Append-only, AES-GCM-encrypted log of every auth attempt (timestamp, method,
//  success/fail, context). Written to a local file under Application Support;
//  the symmetric key lives in the Keychain (data-protection, silent access).
//
//  This is real encryption (CryptoKit AES-GCM), not the XOR placeholder used by
//  the folder stash. The same key is reused by FaceProfileStore for the
//  adaptive-training samples.
//

import Foundation
import CryptoKit

@MainActor
final class AuthLogService: ObservableObject {
    static let shared = AuthLogService()

    enum Method: String, Codable { case face, password }

    struct Entry: Codable, Identifiable {
        let timestamp: Date
        let method: Method
        let success: Bool
        let context: String
        /// Optional structured event type (e.g. "phishing_blocked") for events
        /// beyond ordinary auth attempts. Optional + decoded-if-present so older
        /// logs written before this field still decode.
        var event: String? = nil
        var id: Date { timestamp }
    }

    @Published private(set) var entries: [Entry] = []

    private let fileURL: URL

    private init() {
        fileURL = CryptoBox.appSupportDirectory().appendingPathComponent("auth.log.enc")
        entries = readAll()
    }

    // MARK: - Log

    func log(method: AuthCoordinator.Method, success: Bool, context: String) {
        let m: Method = (method == .face) ? .face : .password
        log(method: m, success: success, context: context)
    }

    func log(method: Method, success: Bool, context: String, event: String? = nil) {
        let entry = Entry(timestamp: Date(), method: method, success: success, context: context, event: event)
        entries.append(entry)
        // Persist the full set (small; re-encrypt whole log each write is fine).
        persist()
    }

    // MARK: - Read

    func readAll() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let plaintext = CryptoBox.decrypt(data),
              let decoded = try? JSONDecoder().decode([Entry].self, from: plaintext)
        else { return [] }
        return decoded
    }

    // MARK: - Persist

    private func persist() {
        guard let plaintext = try? JSONEncoder().encode(entries),
              let sealed = CryptoBox.encrypt(plaintext)
        else { return }
        try? sealed.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Shared crypto box (AES-GCM with a Keychain-held key)

/// Real encryption for LockGuard's local data files (auth log, training
/// samples). AES-GCM via CryptoKit; the symmetric key is generated once and
/// stored in the data-protection Keychain (silent app-scoped access).
enum CryptoBox {
    private static let keychainService = "com.lockguard.cryptobox"
    private static let keychainAccount = "aes-key-v1"

    static func appSupportDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LockGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func encrypt(_ plaintext: Data) -> Data? {
        guard let sealed = try? AES.GCM.seal(plaintext, using: key()) else { return nil }
        return sealed.combined
    }

    static func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(box, using: key())
        else { return nil }
        return plaintext
    }

    // MARK: - Key management

    private static func key() -> SymmetricKey {
        switch loadKey() {
        case .found(let k):
            return k
        case .notFound:
            let fresh = SymmetricKey(size: .bits256)
            storeKey(fresh)
            return fresh
        case .unreadable:
            // Key exists but can't be read right now (e.g. keychain locked).
            // Do NOT overwrite it — that would permanently orphan all prior
            // encrypted data. Return an ephemeral key; this session's writes
            // won't decrypt later, but existing data stays recoverable.
            return SymmetricKey(size: .bits256)
        }
    }

    private enum KeyLookup { case found(SymmetricKey), notFound, unreadable }

    private static func loadKey() -> KeyLookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data { return .found(SymmetricKey(data: data)) }
            return .unreadable
        case errSecItemNotFound:
            return .notFound
        default:
            return .unreadable   // locked / ACL / other — never overwrite
        }
    }

    private static func storeKey(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(del as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
