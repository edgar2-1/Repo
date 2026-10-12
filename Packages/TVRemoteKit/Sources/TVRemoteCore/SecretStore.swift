import Foundation
#if canImport(Security) && !os(Linux)
import Security
#endif

/// Keychain sharing between the app and its extensions (App Intents run in
/// the widget extension). Set to the App Group id at launch; nil keeps items
/// private to the app.
public enum KeychainConfig {
    private static let lock = NSLock()
    private static var _accessGroup: String?

    public static var accessGroup: String? {
        get { lock.lock(); defer { lock.unlock() }; return _accessGroup }
        set { lock.lock(); _accessGroup = newValue; lock.unlock() }
    }

    #if canImport(Security) && !os(Linux)
    /// Adds the access group to a keychain query when one is configured.
    public static func scoped(_ query: [CFString: Any]) -> [CFString: Any] {
        guard let accessGroup, !accessGroup.isEmpty else { return query }
        var scoped = query
        scoped[kSecAttrAccessGroup] = accessGroup
        return scoped
    }
    #endif
}

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
        guard SecItemCopyMatching(KeychainConfig.scoped(query) as CFDictionary, &result) == errSecSuccess,
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
        SecItemDelete(KeychainConfig.scoped(base) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = KeychainConfig.scoped(base)
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        #else
        lock.lock(); defer { lock.unlock() }
        memory[tvID.uuidString] = value
        #endif
    }
}
