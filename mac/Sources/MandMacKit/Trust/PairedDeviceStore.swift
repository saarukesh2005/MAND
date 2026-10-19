import Foundation
import MandCore
import Security

/// A phone the user explicitly approved.
public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    public let fingerprint: Fingerprint
    public let name: String
    public let pairedAt: Date
    public let lastSeen: Date?
    public let lastAddress: String?

    public var id: String { fingerprint.hex }

    public init(fingerprint: Fingerprint, name: String, pairedAt: Date,
                lastSeen: Date? = nil, lastAddress: String? = nil) {
        self.fingerprint = fingerprint
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.lastAddress = lastAddress
    }

    public func seen(at date: Date, address: String?, name newName: String? = nil) -> PairedDevice {
        PairedDevice(fingerprint: fingerprint, name: newName ?? name, pairedAt: pairedAt,
                     lastSeen: date, lastAddress: address ?? lastAddress)
    }
}

/// Where the list of trusted phones is kept.
public protocol PairedDeviceStore: Sendable {
    func load() throws -> [PairedDevice]
    func save(_ devices: [PairedDevice]) throws
}

/// Test/preview store kept in memory.
public final class InMemoryPairedDeviceStore: PairedDeviceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [PairedDevice]

    public init(_ devices: [PairedDevice] = []) { self.devices = devices }

    public func load() throws -> [PairedDevice] { lock.withLock { devices } }
    public func save(_ devices: [PairedDevice]) throws { lock.withLock { self.devices = devices } }
}

/// Stores the trusted-phone list as one Keychain item so it can't be edited by other apps.
public struct KeychainPairedDeviceStore: PairedDeviceStore {
    static let service = "dev.mand.mac.paired-devices"
    static let account = "devices.v1"

    public init() {}

    public func load() throws -> [PairedDevice] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DeviceIdentity.IdentityError.keychain(status, "reading paired devices")
        }
        return try JSONDecoder().decode([PairedDevice].self, from: data)
    }

    public func save(_ devices: [PairedDevice]) throws {
        let data = try JSONEncoder().encode(devices)
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
        ]
        let update = SecItemUpdate(match as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw DeviceIdentity.IdentityError.keychain(update, "updating paired devices")
        }
        var add = match
        add[kSecValueData] = data
        add[kSecAttrLabel] = "M’AND paired devices"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw DeviceIdentity.IdentityError.keychain(status, "saving paired devices") }
    }
}
