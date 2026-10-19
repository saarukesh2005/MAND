import Foundation
import MandCore
import Network

/// Sends and receives protocol envelopes over one NWConnection.
/// All state is confined to `queue`; callbacks are delivered on `queue`.
public final class FramedConnection: @unchecked Sendable {
    public enum Event: Sendable {
        case ready(peer: Fingerprint?)
        case envelope(Envelope)
        /// The peer violated the protocol; an `error` was sent and the connection is closing.
        case protocolViolation(ProtocolError)
        case closed(reason: String)
    }

    public let connection: NWConnection
    public let queue: DispatchQueue
    public private(set) var lastReceived = Date()
    private var decoder = FrameDecoder()
    private var isClosed = false
    private var onEvent: (@Sendable (Event) -> Void)?

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public var remoteAddress: String? {
        if case .hostPort(let host, _) = connection.endpoint { return "\(host)" }
        return nil
    }

    public func start(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
        connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
        connection.start(queue: queue)
    }

    public func send(_ message: Message, version: Int = ProtocolVersion.current) {
        guard !isClosed else { return }
        do {
            let frame = try Framing.encode(EnvelopeCodec.encode(Envelope(message: message, version: version)))
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error { self?.close(reason: "send failed: \(error.localizedDescription)") }
            })
        } catch {
            close(reason: "could not encode \(message.type)")
        }
    }

    /// Sends a final message, then closes once it has been handed to the network.
    public func sendAndClose(_ message: Message, reason: String) {
        guard !isClosed else { return }
        guard let frame = try? Framing.encode(EnvelopeCodec.encode(Envelope(message: message))) else {
            close(reason: reason); return
        }
        connection.send(content: frame, completion: .contentProcessed { [weak self] _ in
            self?.close(reason: reason)
        })
    }

    public func close(reason: String) {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        onEvent?(.closed(reason: reason))
        onEvent = nil
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            lastReceived = Date()
            onEvent?(.ready(peer: TLS.peerFingerprint(of: connection)))
            receive()
        case .failed(let error):
            close(reason: Self.describe(error))
        case .waiting(let error):
            close(reason: Self.describe(error))
        case .cancelled:
            close(reason: "cancelled")
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.lastReceived = Date()
                do throws(ProtocolError) {
                    for payload in try self.decoder.append(data) {
                        guard !self.isClosed else { return }
                        self.onEvent?(.envelope(try EnvelopeCodec.decode(payload)))
                    }
                } catch {
                    self.onEvent?(.protocolViolation(error))
                    self.sendAndClose(.error(code: error.rawValue, message: nil), reason: "protocol violation: \(error.rawValue)")
                    return
                }
            }
            if isComplete { self.close(reason: "peer closed the connection"); return }
            if let error { self.close(reason: Self.describe(error)); return }
            self.receive()
        }
    }

    static func describe(_ error: NWError) -> String {
        switch error {
        case .tls(let status): "secure connection refused (TLS \(status))"
        case .posix(let code): "network error: \(code)"
        case .dns(let code): "address lookup failed (\(code))"
        default: error.localizedDescription
        }
    }
}
