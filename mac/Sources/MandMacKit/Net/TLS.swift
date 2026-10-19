import Foundation
import MandCore
import Network
import Security

/// TLS 1.3 settings shared by the Mac server and the test client (protocol §1).
/// Chains are never validated against a CA; trust is decided only by the fingerprint policy.
public enum TLS {
    /// Decides whether to accept a peer's leaf-certificate fingerprint.
    public typealias PeerPolicy = @Sendable (Fingerprint) -> Bool

    public static func parameters(identity: DeviceIdentity, requireClientCertificate: Bool,
                                  queue: DispatchQueue, policy: @escaping PeerPolicy) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        if let local = sec_identity_create(identity.secIdentity) {
            sec_protocol_options_set_local_identity(options, local)
        }
        if requireClientCertificate {
            sec_protocol_options_set_peer_authentication_required(options, true)
        }
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            guard let fingerprint = leafFingerprint(of: trust) else { complete(false); return }
            complete(policy(fingerprint))
        }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.connectionTimeout = 10
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }

    static func leafFingerprint(of trust: sec_trust_t) -> Fingerprint? {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else {
            return nil
        }
        return Fingerprint.of(certificateDER: SecCertificateCopyData(leaf) as Data)
    }

    /// The fingerprint of the certificate the peer actually used on this connection.
    public static func peerFingerprint(of connection: NWConnection) -> Fingerprint? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else { return nil }
        var leaf: Fingerprint?
        sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
            guard leaf == nil else { return }
            let secCertificate = sec_certificate_copy_ref(certificate).takeRetainedValue()
            leaf = Fingerprint.of(certificateDER: SecCertificateCopyData(secCertificate) as Data)
        }
        return leaf
    }
}
