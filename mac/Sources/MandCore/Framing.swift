import Foundation

/// Length-prefixed framing (protocol §2): UInt32 big-endian length, then the payload.
public enum Framing {
    public static let maxPayloadBytes = 1_048_576
    static let headerBytes = 4

    public static func encode(_ payload: Data) throws(ProtocolError) -> Data {
        guard !payload.isEmpty else { throw .malformed }
        guard payload.count <= maxPayloadBytes else { throw .tooLarge }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: headerBytes)
        frame.append(payload)
        return frame
    }
}

/// Incrementally splits a TCP byte stream into frames.
/// After it throws, the connection must be closed; the decoder is not reusable.
public struct FrameDecoder: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    /// Appends received bytes and returns every complete payload now available.
    public mutating func append(_ data: Data) throws(ProtocolError) -> [Data] {
        buffer.append(contentsOf: data)
        var payloads: [Data] = []
        var offset = 0
        while buffer.count - offset >= Framing.headerBytes {
            let length = buffer[offset..<offset + Framing.headerBytes]
                .reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0 else { throw .malformed }
            guard length <= Framing.maxPayloadBytes else { throw .tooLarge }
            let start = offset + Framing.headerBytes
            guard buffer.count - start >= length else { break }
            payloads.append(Data(buffer[start..<start + length]))
            offset = start + length
        }
        buffer.removeFirst(offset)
        return payloads
    }

    /// Bytes held while waiting for the rest of a frame.
    public var pendingByteCount: Int { buffer.count }
}
