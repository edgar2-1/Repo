import Foundation
#if canImport(Security) && !os(Linux)
import Security
#endif

/// Stores per-TV secrets (Samsung token, LG client key) in the keychain.
/// Falls back to an in-memory dictionary where the keychain is unavailable
/// (Linux test runs).
public final class SecretStore: @unchecked Sendable {
    public static let shared = SecretStore()

    private let service = "com.googletvwatchremote.tv-credentials"
    private let lock = NSLock()
    private var memory: [String: String] = [:]

    public init() {}

    public func credential(for tvID: UUID) -> String? {
        #if canImport(Security) && !os(Linux)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tvID.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        lock.lock(); defer { lock.unlock() }
        return memory[tvID.uuidString]
        #endif
    }

    public func setCredential(_ value: String?, for tvID: UUID) {
        #if canImport(Security) && !os(Linux)
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tvID.uuidString,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        #else
        lock.lock(); defer { lock.unlock() }
        memory[tvID.uuidString] = value
        #endif
    }
}
