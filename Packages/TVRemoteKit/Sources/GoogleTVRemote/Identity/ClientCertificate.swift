import Foundation
import X509
import SwiftASN1
import _CryptoExtras

/// A freshly generated self-signed RSA certificate + private key.
///
/// The TV identifies a paired remote by its client certificate, so the pair
/// produced here must be stored (see `ClientIdentity`) and reused on every
/// connection.
public struct ClientCertificate: Sendable {
    /// X.509 certificate, DER encoded.
    public let certificateDER: [UInt8]
    /// RSA private key, PKCS#1 DER encoded (what `SecKeyCreateWithData` expects).
    public let privateKeyDER: [UInt8]
    /// Modulus / exponent of the public key, used for the pairing secret.
    public let publicKey: RSAPublicKey

    public init(certificateDER: [UInt8], privateKeyDER: [UInt8], publicKey: RSAPublicKey) {
        self.certificateDER = certificateDER
        self.privateKeyDER = privateKeyDER
        self.publicKey = publicKey
    }

    public static func generate(
        commonName: String = "GoogleTV Watch Remote",
        organization: String = "GoogleTVWatchRemote",
        validFor years: Int = 10
    ) throws -> ClientCertificate {
        let rsaKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let privateKey = Certificate.PrivateKey(rsaKey)

        let name = try DistinguishedName {
            CommonName(commonName)
            OrganizationName(organization)
        }
        let now = Date()
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: privateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-24 * 3600),
            notValidAfter: now.addingTimeInterval(Double(years) * 365 * 24 * 3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: privateKey
        )

        var serializer = DER.Serializer()
        try serializer.serialize(certificate)

        let publicKey = try RSAPublicKey(der: Array(rsaKey.publicKey.derRepresentation))
        return ClientCertificate(
            certificateDER: serializer.serializedBytes,
            privateKeyDER: Array(rsaKey.derRepresentation),
            publicKey: publicKey
        )
    }
}
