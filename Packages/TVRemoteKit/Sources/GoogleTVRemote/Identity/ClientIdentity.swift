#if canImport(Security) && !os(Linux)
import Foundation
import Security
import TVRemoteCore

public enum ClientIdentityError: Error, Sendable {
    case keychain(OSStatus, String)
    case invalidCertificate
    case invalidPrivateKey(String)
    case identityNotFound
    case publicKeyUnavailable
}

/// The persistent TLS client identity of this remote.
///
/// Stored in the keychain so the same certificate is presented to the TV on
/// every connection; the TV only accepts remotes whose certificate completed
/// pairing.
public final class ClientIdentity: @unchecked Sendable {
    public let identity: SecIdentity
    public let certificate: SecCertificate
    public let publicKey: RSAPublicKey

    static let certificateLabel = "GoogleTVWatchRemote.client-certificate"
    static let keyTag = "GoogleTVWatchRemote.client-key".data(using: .utf8)!

    private init(identity: SecIdentity, certificate: SecCertificate) throws {
        self.identity = identity
        self.certificate = certificate
        self.publicKey = try Self.extractPublicKey(from: certificate)
    }

    // MARK: Loading / creation

    /// Loads the stored identity, creating a new one if none exists yet.
    public static func loadOrCreate() throws -> ClientIdentity {
        if let existing = try load() { return existing }
        let generated = try ClientCertificate.generate()
        try store(generated)
        guard let created = try load() else { throw ClientIdentityError.identityNotFound }
        return created
    }

    /// Loads the stored identity, or returns `nil` if none has been created.
    public static func load() throws -> ClientIdentity? {
        guard let certificate = try storedCertificate() else { return nil }
        let certificateData = SecCertificateCopyData(certificate) as Data

        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnRef: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(KeychainConfig.scoped(query) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ClientIdentityError.keychain(status, "listing identities")
        }
        let identities = (result as? [SecIdentity]) ?? []
        for identity in identities {
            var identityCert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &identityCert) == errSecSuccess,
                  let identityCert else { continue }
            if (SecCertificateCopyData(identityCert) as Data) == certificateData {
                return try ClientIdentity(identity: identity, certificate: certificate)
            }
        }
        return nil
    }

    /// Deletes the stored certificate and key. Pairing must be redone afterwards.
    public static func reset() {
        _ = SecItemDelete(KeychainConfig.scoped([
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: certificateLabel,
        ]) as CFDictionary)
        _ = SecItemDelete(KeychainConfig.scoped([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keyTag,
        ]) as CFDictionary)
    }

    // MARK: Transfer between devices

    /// DER blobs of the certificate and private key, for copying the identity to
    /// a paired device so both control the same TVs. Treat the key as a secret.
    public func exportDER() throws -> (certificate: Data, privateKey: Data) {
        var key: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key else {
            throw ClientIdentityError.keychain(errSecItemNotFound, "private key")
        }
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw ClientIdentityError.invalidPrivateKey((error?.takeRetainedValue()).map { String(describing: $0) } ?? "not exportable")
        }
        return (SecCertificateCopyData(certificate) as Data, keyData)
    }

    /// Replaces the stored identity with one exported from another device.
    @discardableResult
    public static func install(certificateDER: Data, privateKeyDER: Data) throws -> ClientIdentity {
        reset()
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw ClientIdentityError.invalidCertificate
        }
        let publicKey = try extractPublicKey(from: certificate)
        try store(ClientCertificate(certificateDER: Array(certificateDER), privateKeyDER: Array(privateKeyDER), publicKey: publicKey))
        guard let installed = try load() else { throw ClientIdentityError.identityNotFound }
        return installed
    }

    // MARK: Internals

    private static func storedCertificate() throws -> SecCertificate? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: certificateLabel,
            kSecReturnRef: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(KeychainConfig.scoped(query) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result else {
            throw ClientIdentityError.keychain(status, "loading certificate")
        }
        return (result as! SecCertificate)
    }

    private static func store(_ generated: ClientCertificate) throws {
        guard let certificate = SecCertificateCreateWithData(nil, Data(generated.certificateDER) as CFData) else {
            throw ClientIdentityError.invalidCertificate
        }

        let keyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(Data(generated.privateKeyDER) as CFData,
                                                    keyAttributes as CFDictionary, &error) else {
            let message = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "unknown"
            throw ClientIdentityError.invalidPrivateKey(message)
        }

        let addKey: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: privateKey,
            kSecAttrApplicationTag: keyTag,
            kSecAttrLabel: "GoogleTVWatchRemote.client-key",
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemAdd(KeychainConfig.scoped(addKey) as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClientIdentityError.keychain(status, "storing private key")
        }

        let addCertificate: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: certificateLabel,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        status = SecItemAdd(KeychainConfig.scoped(addCertificate) as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClientIdentityError.keychain(status, "storing certificate")
        }
    }

    static func extractPublicKey(from certificate: SecCertificate) throws -> RSAPublicKey {
        guard let key = SecCertificateCopyKey(certificate) else {
            throw ClientIdentityError.publicKeyUnavailable
        }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw ClientIdentityError.publicKeyUnavailable
        }
        return try RSAPublicKey(der: Array(data))
    }
}
#endif
