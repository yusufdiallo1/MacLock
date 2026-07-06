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

    func log(method: Method, success: Bool, context: String) {
        let entry = Entry(timestamp: Date(), method: method, success: success, context: context)
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
        if let existing = loadKey() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        storeKey(fresh)
        return fresh
    }

    private static func loadKey() -> SymmetricKey? {
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
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
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
