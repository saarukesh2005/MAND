import Foundation

/// The contents of the pairing QR code (protocol §4).
public struct PairingInvitation: Equatable, Sendable {
    public static let scheme = "mand"
    public static let invitationVersion = 1
    static let maxHosts = 8
    static let hostCharacters = Set("0123456789abcdefABCDEF.:%")

    public let name: String
    public let hosts: [String]
    public let port: UInt16
    public let fingerprint: Fingerprint
    public let secret: Data
    public let expiresAt: Int64

    public enum ParseError: Error, Equatable { case invalid(String) }

    public init(name: String, hosts: [String], port: UInt16, fingerprint: Fingerprint, secret: Data, expiresAt: Int64) {
        self.name = name
        self.hosts = hosts
        self.port = port
        self.fingerprint = fingerprint
        self.secret = secret
        self.expiresAt = expiresAt
    }

    public var url: String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Self.invitationVersion)),
            URLQueryItem(name: "n", value: name),
            URLQueryItem(name: "h", value: hosts.joined(separator: ",")),
            URLQueryItem(name: "p", value: String(port)),
            URLQueryItem(name: "f", value: fingerprint.hex),
            URLQueryItem(name: "s", value: secret.base64URLEncoded),
            URLQueryItem(name: "x", value: String(expiresAt)),
        ]
        return components.string ?? ""
    }

    public init(url: String) throws(ParseError) {
        guard let components = URLComponents(string: url),
              components.scheme == Self.scheme, components.host == "pair" else { throw .invalid("not a M’AND pairing code") }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }

        guard query["v"] == String(Self.invitationVersion) else { throw .invalid("unsupported pairing code version") }
        let name = query["n"] ?? ""
        guard name.count <= Message.maxNameLength else { throw .invalid("name too long") }

        let hosts = (query["h"] ?? "").split(separator: ",").map(String.init)
        guard !hosts.isEmpty, hosts.count <= Self.maxHosts,
              hosts.allSatisfy({ !$0.isEmpty && $0.count <= 64 && $0.allSatisfy(Self.hostCharacters.contains) })
        else { throw .invalid("bad host list") }

        guard let portValue = query["p"].flatMap({ UInt16($0) }), portValue > 0 else { throw .invalid("bad port") }
        guard let fingerprint = query["f"].flatMap({ Fingerprint(hex: $0.lowercased()) }) else { throw .invalid("bad fingerprint") }
        guard let secret = query["s"].flatMap({ Data(base64URL: $0) }),
              secret.count == PairingProof.secretByteCount else { throw .invalid("bad secret") }
        guard let expiresAt = query["x"].flatMap({ Int64($0) }) else { throw .invalid("bad expiry") }

        self.init(name: name, hosts: hosts, port: portValue, fingerprint: fingerprint, secret: secret, expiresAt: expiresAt)
    }

    public func isExpired(now: Date = Date()) -> Bool {
        Int64(now.timeIntervalSince1970) >= expiresAt
    }
}
