import Foundation
import MandCore
import Network

/// The Mac side of M’AND: listens for phones, runs pairing, and keeps the session alive.
/// Everything runs on one serial queue; events are reported through `onEvent` on that queue.
public final class BridgeServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 47821
    public static let serviceType = "_mand._tcp"
    static let handshakeTimeout: TimeInterval = 15
    static let tickInterval: TimeInterval = 1

    public struct PairingRequest: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let fingerprint: Fingerprint
    }

    public enum Event: Sendable {
        case listening(port: UInt16)
        case listenerFailed(String)
        case advertising(Bool, String?)
        case pairingWindowOpened(PairingInvitation)
        case pairingWindowClosed
        case pairingUnavailable(String)
        case approvalNeeded(PairingRequest)
        case pairingFinished(name: String, outcome: String)
        case devicesChanged([PairedDevice])
        case phoneConnected(PairedDevice, address: String?)
        case phoneDisconnected(PairedDevice, reason: String)
        case textReceived(String, from: PairedDevice)
        case log(String)
    }

    public let identity: DeviceIdentity
    public let queue = DispatchQueue(label: "dev.mand.mac.server")
    private let store: PairedDeviceStore
    private let deviceName: String
    private let preferredPort: UInt16
    private let advertise: Bool
    private let addresses: @Sendable () -> [String]
    private let onEvent: @Sendable (Event) -> Void

    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var devices: [PairedDevice] = []
    private var sessions: [UUID: Session] = [:]
    private var activeSessionID: UUID?
    private var window: PairingWindow?
    public private(set) var port: UInt16?

    public init(identity: DeviceIdentity, store: PairedDeviceStore, deviceName: String,
                preferredPort: UInt16 = defaultPort, advertise: Bool = true,
                addresses: @escaping @Sendable () -> [String] = LocalAddresses.privateIPv4,
                onEvent: @escaping @Sendable (Event) -> Void) {
        self.identity = identity
        self.store = store
        self.deviceName = deviceName.truncated(toUTF8Bytes: Message.maxNameBytes)
        self.preferredPort = preferredPort
        self.advertise = advertise
        self.addresses = addresses
        self.onEvent = onEvent
    }

    // MARK: - Public API (safe to call from any thread)

    public func start() {
        queue.async {
            do {
                self.devices = try self.store.load()
            } catch {
                self.emit(.log("Could not read paired devices: \(error)"))
            }
            self.emit(.devicesChanged(self.devices))
            self.startListener(port: self.preferredPort)
            self.startTimer()
        }
    }

    public func stop() {
        queue.async {
            for session in self.sessions.values { session.framed.sendAndClose(.bye(reason: "shutdown"), reason: "M’AND quit") }
            self.listener?.cancel()
            self.timer?.cancel()
        }
    }

    public func openPairingWindow() {
        queue.async {
            guard let port = self.port else {
                self.emit(.pairingUnavailable("M’AND isn’t ready to accept connections yet.")); return
            }
            let hosts = self.addresses()
            guard !hosts.isEmpty else {
                self.emit(.pairingUnavailable("This Mac isn’t connected to a Wi-Fi or local network.")); return
            }
            let window = PairingWindow.open()
            self.window = window
            let invitation = PairingInvitation(
                name: self.deviceName, hosts: hosts, port: port, fingerprint: self.identity.fingerprint,
                secret: window.secret, expiresAt: Int64(window.expiresAt.timeIntervalSince1970))
            self.emit(.log("Pairing window opened for 5 minutes"))
            self.emit(.pairingWindowOpened(invitation))
        }
    }

    public func closePairingWindow() {
        queue.async { self.endPairingWindow(reason: "Pairing window closed") }
    }

    public func resolvePairing(id: UUID, approved: Bool) {
        queue.async { self.finishApproval(id: id, approved: approved) }
    }

    public func sendText(_ text: String) {
        queue.async {
            guard let session = self.activeSession else { self.emit(.log("Not sent: no phone connected")); return }
            session.framed.send(.text(text), version: session.version)
            self.emit(.log("Sent a test message"))
        }
    }

    public func forget(_ fingerprint: Fingerprint) {
        queue.async {
            let name = self.devices.first { $0.fingerprint == fingerprint }?.name ?? "device"
            self.updateDevices(self.devices.filter { $0.fingerprint != fingerprint })
            for session in self.sessions.values where session.peer == fingerprint {
                session.framed.sendAndClose(.bye(reason: "unpaired"), reason: "device forgotten")
            }
            self.emit(.log("Forgot \(name)"))
        }
    }

    // MARK: - Listener

    private func startListener(port: UInt16) {
        let parameters = TLS.parameters(identity: identity, requireClientCertificate: true, queue: queue) {
            [unowned self] fingerprint in self.isAcceptable(fingerprint)
        }
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port), let listener = try? NWListener(using: parameters, on: nwPort) else {
            emit(.listenerFailed("Could not create the network listener.")); return
        }
        if advertise { listener.service = NWListener.Service(name: deviceName, type: Self.serviceType) }
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            switch change {
            case .add: self?.emit(.advertising(true, nil))
            case .remove: self?.emit(.advertising(false, "Bonjour advertising stopped"))
            @unknown default: break
            }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready:
                self.port = listener.port?.rawValue
                self.emit(.listening(port: self.port ?? 0))
                self.emit(.log("Listening on port \(self.port ?? 0)"))
            case .failed(let error):
                listener.cancel()
                if port != 0, case .posix(let code) = error, code == .EADDRINUSE {
                    self.emit(.log("Port \(port) is busy; using another port"))
                    self.startListener(port: 0)
                } else {
                    self.emit(.listenerFailed(FramedConnection.describe(error)))
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        listener.start(queue: queue)
    }

    /// Called from the TLS verify block (on `queue`).
    private func isAcceptable(_ fingerprint: Fingerprint) -> Bool {
        devices.contains { $0.fingerprint == fingerprint } || (window?.isUsable(at: Date()) ?? false)
    }

    private func accept(_ connection: NWConnection) {
        let session = Session(framed: FramedConnection(connection: connection, queue: queue))
        sessions[session.id] = session
        session.framed.start { [weak self, id = session.id] event in self?.handle(event, sessionID: id) }
    }

    // MARK: - Session state machine

    private func handle(_ event: FramedConnection.Event, sessionID: UUID) {
        guard let session = sessions[sessionID] else { return }
        switch event {
        case .ready(let peer):
            guard let peer else { session.framed.close(reason: "no client certificate"); return }
            session.peer = peer
            session.framed.send(.hello(Hello(name: deviceName, platform: .mac,
                                             versions: ProtocolVersion.supported, app: AppInfo.version)))
        case .envelope(let envelope):
            if case .ping = envelope.message {
                session.framed.send(.pong(ref: envelope.id), version: session.version)
            } else {
                handle(envelope.message, in: session)
            }
        case .protocolViolation(let error):
            emit(.log("Closed a connection that broke the protocol (\(error.rawValue))"))
        case .closed(let reason):
            sessions[sessionID] = nil
            if activeSessionID == sessionID, let device = session.device {
                activeSessionID = nil
                markSeen(device.fingerprint, address: session.framed.remoteAddress)
                emit(.phoneDisconnected(device, reason: reason))
                emit(.log("\(device.name) disconnected: \(reason)"))
            }
        }
    }

    private func handle(_ message: Message, in session: Session) {
        switch (session.state, message) {
        case (.awaitingHello, .hello(let hello)):
            guard let version = ProtocolVersion.negotiate(local: ProtocolVersion.supported, remote: hello.versions) else {
                reject(session, .versionUnsupported); return
            }
            session.version = version
            session.helloName = hello.name
            if let peer = session.peer, let device = devices.first(where: { $0.fingerprint == peer }) {
                makeReady(session, device: device)
            } else if window?.isUsable(at: Date()) == true {
                session.state = .awaitingPairRequest
            } else {
                reject(session, .notPaired)
            }

        case (.awaitingPairRequest, .pairRequest(let proofText)):
            verifyPairing(session, proofText: proofText)

        case (.ready, .text(let text)):
            guard let device = session.device else { return }
            emit(.textReceived(text, from: device))
            emit(.log("Received a message from \(device.name)"))

        case (.ready, .bye(let reason)):
            if reason == "unpaired", let peer = session.peer {
                updateDevices(devices.filter { $0.fingerprint != peer })
                emit(.log("The phone removed this pairing"))
            }
            session.framed.close(reason: reason == "unpaired" ? "phone unpaired" : "phone closed the app")

        case (_, .error(let code, _)):
            emit(.log("Phone reported an error: \(code)"))

        case (_, .pong), (_, .unknown), (.awaitingApproval, _):
            break

        case (.ready, _):
            emit(.log("Ignored unexpected \(message.type)"))

        default:
            reject(session, .notPaired)
        }
    }

    private func verifyPairing(_ session: Session, proofText: String) {
        guard let current = window, let peer = session.peer else { reject(session, .pairingExpired); return }
        let proof = Data(base64URL: proofText) ?? Data()
        let (outcome, next) = current.attempt(proof: proof, phone: peer, mac: identity.fingerprint, now: Date())
        window = next
        switch outcome {
        case .verified:
            let request = PairingRequest(id: session.id, name: session.helloName ?? "Android phone", fingerprint: peer)
            session.state = .awaitingApproval(request)
            emit(.approvalNeeded(request))
        case .rejected(let error):
            emit(.log("Pairing attempt rejected: \(error.rawValue)"))
            if error == .pairingTooManyAttempts { endPairingWindow(reason: "Too many failed pairing attempts") }
            reject(session, error, asPairResult: true)
        }
    }

    private func finishApproval(id: UUID, approved: Bool) {
        guard let session = sessions[id], case .awaitingApproval(let request) = session.state else { return }
        endPairingWindow(reason: nil, keeping: session.id)
        guard approved else {
            emit(.pairingFinished(name: request.name, outcome: "declined"))
            reject(session, .pairingRejected, asPairResult: true)
            return
        }
        let device = PairedDevice(fingerprint: request.fingerprint, name: request.name, pairedAt: Date())
        updateDevices(devices.filter { $0.fingerprint != request.fingerprint } + [device])
        session.framed.send(.pairResult(accepted: true, reason: nil), version: session.version)
        emit(.pairingFinished(name: request.name, outcome: "paired"))
        emit(.log("Paired with \(request.name)"))
        makeReady(session, device: device)
    }

    private func makeReady(_ session: Session, device: PairedDevice) {
        if let previous = activeSessionID, previous != session.id, let old = sessions[previous] {
            old.device = nil // don't report a disconnect for the replaced connection
            old.framed.close(reason: "replaced by a newer connection")
        }
        session.state = .ready
        session.device = device
        activeSessionID = session.id
        session.framed.send(.sessionReady, version: session.version)
        let seen = markSeen(device.fingerprint, address: session.framed.remoteAddress, name: session.helloName) ?? device
        session.device = seen
        emit(.phoneConnected(seen, address: session.framed.remoteAddress))
        emit(.log("\(seen.name) connected"))
    }

    private func reject(_ session: Session, _ error: ProtocolError, asPairResult: Bool = false) {
        session.state = .closing
        let message: Message = asPairResult
            ? .pairResult(accepted: false, reason: error.rawValue)
            : .error(code: error.rawValue, message: nil)
        session.framed.sendAndClose(message, reason: error.rawValue)
    }

    // MARK: - Timers, pairing window, storage

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        if let window, !window.isUsable(at: now) {
            endPairingWindow(reason: window.isConsumed ? nil : "Pairing QR code expired")
        }
        for session in sessions.values {
            switch session.state {
            case .ready:
                if ConnectionTiming.isDead(lastReceived: session.framed.lastReceived.timeIntervalSince1970,
                                           now: now.timeIntervalSince1970) {
                    session.framed.close(reason: "no response for 45 seconds")
                } else if now.timeIntervalSince(session.lastPingSent) >= ConnectionTiming.pingInterval {
                    session.lastPingSent = now
                    session.framed.send(.ping, version: session.version)
                }
            case .awaitingHello, .awaitingPairRequest:
                if now.timeIntervalSince(session.createdAt) > Self.handshakeTimeout {
                    session.framed.close(reason: "handshake timed out")
                }
            case .awaitingApproval, .closing:
                break
            }
        }
    }

    /// Closes the window and rejects anyone still waiting for approval.
    private func endPairingWindow(reason: String?, keeping kept: UUID? = nil) {
        guard window != nil else { return }
        window = nil
        for session in sessions.values where session.id != kept {
            if case .awaitingApproval = session.state { reject(session, .pairingExpired, asPairResult: true) }
            if case .awaitingPairRequest = session.state { reject(session, .pairingExpired, asPairResult: true) }
        }
        if let reason { emit(.log(reason)) }
        emit(.pairingWindowClosed)
    }

    @discardableResult
    private func markSeen(_ fingerprint: Fingerprint, address: String?, name: String? = nil) -> PairedDevice? {
        guard let index = devices.firstIndex(where: { $0.fingerprint == fingerprint }) else { return nil }
        let updated = devices[index].seen(at: Date(), address: address, name: name)
        var next = devices
        next[index] = updated
        updateDevices(next)
        return updated
    }

    private func updateDevices(_ next: [PairedDevice]) {
        devices = next
        do {
            try store.save(next)
        } catch {
            emit(.log("Could not save paired devices: \(error)"))
        }
        emit(.devicesChanged(next))
    }

    private var activeSession: Session? { activeSessionID.flatMap { sessions[$0] } }

    private func emit(_ event: Event) { onEvent(event) }
}

/// One phone connection. Only touched on the server queue.
final class Session {
    enum State {
        case awaitingHello, awaitingPairRequest
        case awaitingApproval(BridgeServer.PairingRequest)
        case ready, closing
    }

    let id = UUID()
    let framed: FramedConnection
    let createdAt = Date()
    var state: State = .awaitingHello
    var peer: Fingerprint?
    var helloName: String?
    var version = ProtocolVersion.current
    var device: PairedDevice?
    var lastPingSent = Date()

    init(framed: FramedConnection) { self.framed = framed }
}

public enum AppInfo {
    public static let version = "0.1.0"
}
