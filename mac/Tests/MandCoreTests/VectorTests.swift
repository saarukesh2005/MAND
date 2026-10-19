import Foundation
import Testing
@testable import MandCore

@Suite("Shared protocol vectors")
struct VectorTests {
    @Test("Framing", arguments: SharedVectors.names("framing"))
    func framing(name: String) throws {
        let vector = SharedVectors.named("framing", name)
        let input = Data(hexString: vector["hex"] as! String)!
        var decoder = FrameDecoder()

        switch vector["expect"] as! String {
        case "frame":
            #expect(try decoder.append(input) == [Data(hexString: vector["payloadHex"] as! String)!])
        case "frames":
            let expected = (vector["payloadsHex"] as! [String]).map { Data(hexString: $0)! }
            #expect(try decoder.append(input) == expected)
        case "incomplete":
            #expect(try decoder.append(input).isEmpty)
            #expect(decoder.pendingByteCount == input.count)
        case "error":
            let code = ProtocolError(rawValue: vector["code"] as! String)!
            #expect(throws: code) { _ = try decoder.append(input) }
        default:
            Issue.record("unknown expectation")
        }
    }

    @Test("Envelopes", arguments: SharedVectors.names("envelopes"))
    func envelopes(name: String) throws {
        let vector = SharedVectors.named("envelopes", name)
        let data = Data((vector["json"] as! String).utf8)

        if vector["expect"] as! String == "ok" {
            let envelope = try EnvelopeCodec.decode(data)
            let expectedType = vector["type"] as! String
            if expectedType == "unknown" {
                guard case .unknown = envelope.message else { Issue.record("expected unknown"); return }
            } else {
                #expect(envelope.message.type == expectedType)
            }
        } else {
            let code = ProtocolError(rawValue: vector["code"] as! String)!
            #expect(throws: code) { _ = try EnvelopeCodec.decode(data) }
        }
    }

    @Test("Version negotiation")
    func versionNegotiation() {
        for vector in SharedVectors.cases("versionNegotiation") {
            let local = vector["local"] as! [Int]
            let remote = vector["remote"] as! [Int]
            let expected = vector["expect"] as? Int
            #expect(ProtocolVersion.negotiate(local: local[0]...local[1], remote: remote[0]...remote[1]) == expected)
        }
    }

    @Test("Pairing proof", arguments: SharedVectors.names("pairingProof"))
    func pairingProof(name: String) {
        let vector = SharedVectors.named("pairingProof", name)
        let secret = Data(base64URL: vector["secretB64"] as! String)!
        let phone = Fingerprint(hex: vector["phoneFpHex"] as! String)!
        let mac = Fingerprint(hex: vector["macFpHex"] as! String)!
        let proof = Data(base64URL: vector["proofB64"] as! String)!
        let valid = vector["valid"] as! Bool

        #expect(PairingProof.verify(proof, secret: secret, phone: phone, mac: mac) == valid)
        if valid {
            #expect(PairingProof.compute(secret: secret, phone: phone, mac: mac) == proof)
        }
    }

    @Test("Invitations", arguments: SharedVectors.names("invitations"))
    func invitations(name: String) throws {
        let vector = SharedVectors.named("invitations", name)
        let url = vector["url"] as! String

        guard vector["expect"] as! String == "ok" else {
            #expect(throws: PairingInvitation.ParseError.self) { _ = try PairingInvitation(url: url) }
            return
        }
        let fields = vector["fields"] as! [String: Any]
        let invitation = try PairingInvitation(url: url)
        #expect(invitation.name == fields["name"] as! String)
        #expect(invitation.hosts == fields["hosts"] as! [String])
        #expect(Int(invitation.port) == fields["port"] as! Int)
        #expect(invitation.fingerprint.hex == fields["fingerprintHex"] as! String)
        #expect(invitation.secret.base64URLEncoded == fields["secretB64"] as! String)
        #expect(invitation.expiresAt == Int64(fields["expiresAt"] as! Int))
        // Round trip through our own encoder.
        #expect(try PairingInvitation(url: invitation.url) == invitation)
    }
}

@Suite("Shared file-name vectors")
struct FileNameVectorTests {
    @Test("Safe file names")
    func fileNames() {
        for vector in SharedVectors.cases("fileNames") {
            let input = vector["input"] as! String
            if let expected = vector["expect"] as? [String] {
                #expect((try? SafeFileName.components(of: input)) == expected, "input: \(input.prefix(40))")
            } else {
                #expect(throws: SafeFileName.Failure.self, "input: \(input.prefix(40))") {
                    _ = try SafeFileName.components(of: input)
                }
            }
        }
    }

    @Test("Unique names")
    func uniqueNames() {
        for vector in SharedVectors.cases("uniqueNames") {
            let existing = Set(vector["existing"] as! [String])
            #expect(SafeFileName.uniqueName(vector["name"] as! String, exists: existing.contains) == vector["expect"] as! String)
        }
    }
}
