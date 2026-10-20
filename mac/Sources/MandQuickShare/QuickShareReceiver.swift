// Receive-only Quick Share (Nearby Share) endpoint for M’AND.
// Advertising, endpoint-info and type definitions adapted from NearDrop's NearbyConnectionManager
// by Grishka (https://github.com/grishka/NearDrop), Unlicense. Sending, device discovery and QR
// code support from NearDrop are intentionally not included.
import Foundation
import Network

// MARK: - Types shared with the connection code

public struct RemoteDeviceInfo {
    public let name: String
    public let type: DeviceType

    public enum DeviceType: Int32 {
        case unknown = 0, phone, tablet, computer

        public static func fromRawValue(value: Int) -> DeviceType { DeviceType(rawValue: Int32(value)) ?? .unknown }
    }
}

public enum NearbyError: Error {
    case protocolError(_ message: String)
    case requiredFieldMissing(_ message: String)
    case ukey2
    case inputOutput
}

public struct TransferMetadata {
    public let files: [FileMetadata]
    public let id: String
    public let pinCode: String?
    public let textDescription: String?

    init(files: [FileMetadata], id: String, pinCode: String?, textDescription: String? = nil) {
        self.files = files
        self.id = id
        self.pinCode = pinCode
        self.textDescription = textDescription
    }
}

public struct FileMetadata {
    public let name: String
    public let size: Int64
    public let mimeType: String
}

/// Where received files go, and limits. Set by the receiver; read by connections on their queue.
struct QuickShareConfig: @unchecked Sendable {
    static let maxFiles = 500
    static let maxFileSize: Int64 = 1 << 40
    static let maxTextSize: Int64 = 1 << 20
    static let freeSpaceMargin: Int64 = 200 * 1_048_576

    let destination: @Sendable () -> URL
    let partialFolder: URL

    func availableSpace() -> Int64 {
        let values = try? destination().deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? .max) - Self.freeSpaceMargin
    }

    nonisolated(unsafe) static var current = QuickShareConfig(
        destination: { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] },
        partialFolder: FileManager.default.temporaryDirectory)
}

/// The endpoint description Android shows in its Quick Share sheet (format from NearDrop).
struct EndpointInfo {
    let name: String
    let deviceType: RemoteDeviceInfo.DeviceType

    func serialize() -> Data {
        // 1 byte: version(3) | visibility(1) | device type(3) | reserved(1); then 16 random bytes,
        // then the UTF-8 name prefixed with its length.
        var bytes: [UInt8] = [UInt8(deviceType.rawValue << 1)]
        for _ in 0..<16 { bytes.append(UInt8.random(in: 0...255)) }
        let name = Array(name.utf8.prefix(255))
        bytes.append(UInt8(name.count))
        bytes.append(contentsOf: name)
        return Data(bytes)
    }
}

// MARK: - Public API

/// A pending incoming transfer awaiting the user's decision.
public struct QuickShareRequest: Identifiable, Sendable, Equatable {
    public let id: String
    public let senderName: String
    public let pinCode: String?
    public let fileNames: [String]
    public let totalBytes: Int64
    public let linkTitle: String?
}

public enum QuickShareEvent: Sendable {
    case advertising(Bool)
    case requestNeedsConsent(QuickShareRequest)
    case progress(id: String, received: Int64, total: Int64)
    /// Finished (or ended). `savedFiles` were fully received; `link` is an http(s) link the user chose to accept.
    case finished(id: String, sender: String, savedFiles: [URL], link: URL?, error: String?)
}

/// Makes this Mac visible to Android's Quick Share on the local network (receive only).
/// Off until `start()` is called; every transfer needs `respond(to:accept:)`.
public final class QuickShareReceiver: NSObject, NetServiceDelegate, InboundNearbyConnectionDelegate, @unchecked Sendable {
    private static let serviceType = "_FC9F5ED42C8A._tcp."
    private static let maxConnections = 8

    private let deviceName: String
    private let onEvent: @Sendable (QuickShareEvent) -> Void
    private let endpointID: [UInt8] = QuickShareReceiver.generateEndpointID()
    private var listener: NWListener?
    private var service: NetService?
    private var connections: [String: InboundNearbyConnection] = [:]
    private var senders: [String: String] = [:]

    public init(deviceName: String, destination: @escaping @Sendable () -> URL, partialFolder: URL,
                onEvent: @escaping @Sendable (QuickShareEvent) -> Void) {
        self.deviceName = deviceName
        self.onEvent = onEvent
        QuickShareConfig.current = QuickShareConfig(destination: destination, partialFolder: partialFolder)
        super.init()
    }

    /// Starts listening and advertising. Call on the main thread.
    public func start() {
        guard listener == nil, let listener = try? NWListener(using: NWParameters(tls: nil)) else { return }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: DispatchQueue.main.async { self.advertise(port: listener.port?.rawValue ?? 0) }
            case .failed, .cancelled: self.onEvent(.advertising(false))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            DispatchQueue.main.async { self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: NearbyConnection.queue)
    }

    /// Stops advertising and drops all Quick Share connections. Call on the main thread.
    public func stop() {
        service?.stop()
        service = nil
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.disconnectFromApp() }
        connections.removeAll()
        onEvent(.advertising(false))
    }

    /// The TCP port while listening (nil before it's ready).
    public var listeningPort: UInt16? {
        guard let port = listener?.port?.rawValue, port != 0 else { return nil }
        return port
    }

    public func respond(to requestID: String, accept: Bool) {
        connections[requestID]?.submitUserConsent(accepted: accept)
    }

    // MARK: - Private

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let id = UUID().uuidString
        let inbound = InboundNearbyConnection(connection: connection, id: id)
        inbound.delegate = self
        connections[id] = inbound
        inbound.start()
    }

    private func advertise(port: UInt16) {
        let nameBytes: [UInt8] = [0x23, endpointID[0], endpointID[1], endpointID[2], endpointID[3], 0xFC, 0x9F, 0x5E, 0, 0]
        let name = Data(nameBytes).urlSafeBase64EncodedString()
        let info = EndpointInfo(name: deviceName, deviceType: .computer)
        let service = NetService(domain: "", type: Self.serviceType, name: name, port: Int32(port))
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: ["n": Data(info.serialize().urlSafeBase64EncodedString().utf8)]))
        service.publish()
        self.service = service
    }

    private static func generateEndpointID() -> [UInt8] {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        return (0..<4).map { _ in alphabet.randomElement()! }
    }

    public func netServiceDidPublish(_ sender: NetService) { onEvent(.advertising(true)) }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) { onEvent(.advertising(false)) }

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, connection: InboundNearbyConnection) {
        let sender = Self.displaySafe(device.name)
        senders[connection.id] = sender
        onEvent(.requestNeedsConsent(QuickShareRequest(
            id: connection.id, senderName: sender, pinCode: transfer.pinCode,
            fileNames: transfer.files.map(\.name), totalBytes: transfer.files.reduce(0) { $0 + $1.size },
            linkTitle: transfer.textDescription)))
    }

    func transferProgress(id: String, received: Int64, total: Int64, filesDone: Int) {
        onEvent(.progress(id: id, received: received, total: total))
    }

    func connectionWasTerminated(connection: InboundNearbyConnection, error: Error?) {
        connections[connection.id] = nil
        let sender = senders.removeValue(forKey: connection.id)
        guard let sender else { return } // never reached the consent stage: nothing to report
        let saved = connection.savedFiles
        let message: String? = error.map { _ in saved.isEmpty ? "The transfer didn’t finish." : "Some files didn’t finish." }
        onEvent(.finished(id: connection.id, sender: sender, savedFiles: saved, link: connection.receivedLink, error: message))
    }

    /// Strips control and direction-override characters from a peer-supplied device name.
    static func displaySafe(_ name: String) -> String {
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter {
            switch $0.properties.generalCategory {
            case .control, .format: false
            default: true
            }
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Android device" : String(cleaned.prefix(64))
    }
}

extension InboundNearbyConnection {
    /// Closes the connection on the user's behalf (Quick Share turned off).
    func disconnectFromApp() {
        NearbyConnection.queue.async { self.disconnect() }
    }
}
