import CryptoKit
import Foundation
import MandCore
import Security
import X509

/// This device's long-term TLS identity: a P-256 private key that never leaves the Keychain,
/// plus a self-signed certificate. Its fingerprint is what paired phones pin.
public struct DeviceIdentity: @unchecked Sendable {
    // SecIdentity and SecCertificate are immutable, thread-safe CF objects.
    public let secIdentity: SecIdentity
    public let certificate: SecCertificate
    public let fingerprint: Fingerprint

    public enum IdentityError: Error, CustomStringConvertible {
        case keychain(OSStatus, String)
        case certificate(String)

        public var description: String {
            switch self {
            case .keychain(let status, let step):
                "Keychain error \(status) while \(step): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
            case .certificate(let reason): "Could not create certificate: \(reason)"
            }
        }
    }

    public static let defaultLabel = "M’AND Device Identity"

    /// Loads the identity from the Keychain, creating it on first use.
    /// - Parameter keychain: `nil` uses the user's login keychain; tests pass a temporary keychain.
    public static func loadOrCreate(label: String = defaultLabel, keychain: SecKeychain? = nil,
                                    commonName: String) throws -> DeviceIdentity {
        if let existing = try load(label: label, keychain: keychain) { return existing }
        return try create(label: label, keychain: keychain, commonName: commonName)
    }

    static func load(label: String, keychain: SecKeychain?) throws -> DeviceIdentity? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: label,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let keychain { query[kSecMatchSearchList] = [keychain] }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result, CFGetTypeID(result) == SecCertificateGetTypeID() else {
            throw IdentityError.keychain(status, "looking up the certificate")
        }
        return try make(certificate: result as! SecCertificate, keychain: keychain)
    }

    static func create(label: String, keychain: SecKeychain?, commonName: String) throws -> DeviceIdentity {
        // Generate in memory, then add explicitly so the key lands in exactly the chosen keychain
        // (SecKeyCreateRandomKey ignores kSecUseKeychain and would always use the login keychain).
        let keyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: false],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else {
            throw IdentityError.certificate("key generation failed: \(error!.takeRetainedValue())")
        }
        // The legacy keychain pairs a certificate with its key via SHA-1 of the public key,
        // so the key must carry that hash as its application label.
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicBytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw IdentityError.certificate("could not read the public key")
        }
        var keyQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: privateKey,
            kSecAttrLabel: label,
            kSecAttrApplicationLabel: Data(Insecure.SHA1.hash(data: publicBytes)),
        ]
        if let keychain { keyQuery[kSecUseKeychain] = keychain }
        let keyStatus = SecItemAdd(keyQuery as CFDictionary, nil)
        guard keyStatus == errSecSuccess else { throw IdentityError.keychain(keyStatus, "saving the private key") }

        let der: [UInt8]
        do {
            der = try selfSignedCertificateDER(privateKey: privateKey, commonName: commonName)
        } catch {
            throw IdentityError.certificate(String(describing: error))
        }
        guard let certificate = SecCertificateCreateWithData(nil, Data(der) as CFData) else {
            throw IdentityError.certificate("Security framework rejected the certificate")
        }

        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: label,
        ]
        if let keychain { addQuery[kSecUseKeychain] = keychain }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw IdentityError.keychain(status, "saving the certificate") }
        return try make(certificate: certificate, keychain: keychain)
    }

    private static func make(certificate: SecCertificate, keychain: SecKeychain?) throws -> DeviceIdentity {
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(keychain, certificate, &identity)
        guard status == errSecSuccess, let identity else {
            throw IdentityError.keychain(status, "pairing the certificate with its private key")
        }
        let der = SecCertificateCopyData(certificate) as Data
        return DeviceIdentity(secIdentity: identity, certificate: certificate,
                              fingerprint: Fingerprint.of(certificateDER: der))
    }

    /// Builds a long-lived self-signed certificate usable for both TLS server and client auth.
    static func selfSignedCertificateDER(privateKey: SecKey, commonName: String) throws -> [UInt8] {
        let key = try Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName {
            CommonName(String(commonName.prefix(64)))
            OrganizationName("M’AND")
        }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: key.publicKey,
            notValidBefore: now.addingTimeInterval(-86_400),
            notValidAfter: now.addingTimeInterval(20 * 365 * 86_400),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth, .clientAuth])
            },
            issuerPrivateKey: key
        )
        return try certificate.serializeAsPEM().derBytes
    }
}
