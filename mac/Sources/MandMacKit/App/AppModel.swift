import Foundation
import MandCore
import Observation

/// Everything the Mac UI shows, derived only from real server events.
@MainActor
@Observable
public final class AppModel {
    public enum ServerStatus: Equatable {
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    public struct ChatLine: Identifiable, Equatable {
        public enum Direction { case fromPhone, fromMac }
        public let id = UUID()
        public let direction: Direction
        public let text: String
        public let date: Date
    }

    public struct LogLine: Identifiable, Equatable {
        public let id = UUID()
        public let date: Date
        public let text: String
    }

    public static let maxLogLines = 200
    public static let maxChatLines = 100

    public private(set) var serverStatus: ServerStatus = .starting
    public private(set) var isAdvertising = false
    public private(set) var devices: [PairedDevice] = []
    public private(set) var connected: PairedDevice?
    public private(set) var connectedAddress: String?
    public private(set) var lastDisconnect: (name: String, reason: String, date: Date)?
    public private(set) var invitation: PairingInvitation?
    public private(set) var pairingNotice: String?
    public private(set) var chat: [ChatLine] = []
    public private(set) var log: [LogLine] = []
    public private(set) var startupError: String?
    public var pendingApproval: BridgeServer.PairingRequest?

    public let macName: String
    private var server: BridgeServer?

    public init(macName: String) {
        self.macName = macName
    }

    public var isConnected: Bool { connected != nil }
    public var macFingerprint: Fingerprint? { server?.identity.fingerprint }

    // MARK: - Lifecycle

    /// Loads (or creates) this Mac's identity and starts listening.
    public func start(identityProvider: () throws -> DeviceIdentity,
                      store: PairedDeviceStore = KeychainPairedDeviceStore()) {
        guard server == nil else { return }
        let identity: DeviceIdentity
        do {
            identity = try identityProvider()
        } catch {
            startupError = "M’AND couldn’t set up its security key: \(error)"
            return
        }
        let server = BridgeServer(identity: identity, store: store, deviceName: macName) { [weak self] event in
            // Main-queue FIFO keeps events in the order the server produced them.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(event) } }
        }
        self.server = server
        server.start()
    }

    public func stop() { server?.stop() }

    // MARK: - User actions

    public func startPairing() {
        pairingNotice = nil
        server?.openPairingWindow()
    }

    public func cancelPairing() {
        server?.closePairingWindow()
        invitation = nil
    }

    public func respondToPairing(approved: Bool) {
        guard let request = pendingApproval else { return }
        pendingApproval = nil
        server?.resolvePairing(id: request.id, approved: approved)
    }

    /// Returns false (and sends nothing) if the text is empty, too long, or no phone is connected.
    @discardableResult
    public func sendTestMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !trimmed.isEmpty, trimmed.utf8.count <= Message.maxTextBytes else { return false }
        server?.sendText(trimmed)
        appendChat(ChatLine(direction: .fromMac, text: trimmed, date: Date()))
        return true
    }

    public func forget(_ device: PairedDevice) {
        server?.forget(device.fingerprint)
    }

    // MARK: - Event handling

    func apply(_ event: BridgeServer.Event) {
        switch event {
        case .listening(let port):
            serverStatus = .listening(port: port)
        case .listenerFailed(let reason):
            serverStatus = .failed(reason)
        case .advertising(let active, _):
            isAdvertising = active
        case .pairingWindowOpened(let invitation):
            self.invitation = invitation
        case .pairingWindowClosed:
            invitation = nil
        case .pairingUnavailable(let reason):
            invitation = nil
            pairingNotice = reason
        case .approvalNeeded(let request):
            pendingApproval = request
        case .pairingFinished(let name, let outcome):
            invitation = nil
            if pendingApproval != nil { pendingApproval = nil }
            pairingNotice = switch outcome {
            case "paired": "Paired with \(name)."
            case "timed out": "Pairing with \(name) timed out. Show a new QR code to try again."
            case "cancelled": "\(name) stopped pairing before it was approved."
            default: "Pairing with \(name) was declined."
            }
        case .devicesChanged(let devices):
            self.devices = devices
            if let current = connected, !devices.contains(where: { $0.fingerprint == current.fingerprint }) {
                connected = nil
            }
        case .phoneConnected(let device, let address):
            connected = device
            connectedAddress = address
        case .phoneDisconnected(let device, let reason):
            if connected?.fingerprint == device.fingerprint {
                connected = nil
                connectedAddress = nil
            }
            lastDisconnect = (device.name, reason, Date())
        case .textReceived(let text, _):
            appendChat(ChatLine(direction: .fromPhone, text: text, date: Date()))
        case .log(let text):
            log = Array((log + [LogLine(date: Date(), text: text)]).suffix(Self.maxLogLines))
        }
    }

    private func appendChat(_ line: ChatLine) {
        chat = Array((chat + [line]).suffix(Self.maxChatLines))
    }
}
