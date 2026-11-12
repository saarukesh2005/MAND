import CoreMedia
import Foundation

/// Turns H.264 Annex B access units (what Android's MediaCodec produces) into CMSampleBuffers that
/// AVSampleBufferDisplayLayer can decode and show. Pure data handling; input is untrusted.
public struct H264Depacketizer {
    public enum Failure: Error, Equatable { case noParameterSets, badParameterSets, noPicture, coreMedia(OSStatus) }

    private(set) var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?

    public init() {}

    /// NAL units in an Annex B byte stream (split on 00 00 01 / 00 00 00 01 start codes).
    public static func nalUnits(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(index: Int, length: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 { starts.append((i, 3)); i += 3; continue }
                if i + 3 < bytes.count, bytes[i + 2] == 0, bytes[i + 3] == 1 { starts.append((i, 4)); i += 4; continue }
            }
            i += 1
        }
        var units: [Data] = []
        for (n, start) in starts.enumerated() {
            let from = start.index + start.length
            let to = n + 1 < starts.count ? starts[n + 1].index : bytes.count
            if to > from { units.append(Data(bytes[from..<to])) }
        }
        return units
    }

    public static func type(of nal: Data) -> UInt8 { (nal.first ?? 0) & 0x1F }

    /// A sample buffer for one access unit, or nil for config-only data (SPS/PPS are remembered).
    public mutating func sampleBuffer(for accessUnit: Data, key: Bool) throws(Failure) -> CMSampleBuffer? {
        var picture: [Data] = []
        var newParameters = false
        for nal in Self.nalUnits(in: accessUnit) {
            switch Self.type(of: nal) {
            case 7: if nal != sps { sps = nal; newParameters = true }
            case 8: if nal != pps { pps = nal; newParameters = true }
            case 9, 6: continue // access unit delimiter, SEI: not needed for display
            default: picture.append(nal)
            }
        }
        if newParameters || format == nil {
            guard let sps, let pps else {
                if picture.isEmpty { return nil }
                throw .noParameterSets
            }
            format = try Self.makeFormat(sps: sps, pps: pps)
        }
        guard !picture.isEmpty else { return nil }
        guard let format else { throw .noParameterSets }

        // AVCC: each NAL prefixed by its 4-byte big-endian length.
        var avcc = Data(capacity: picture.reduce(0) { $0 + $1.count + 4 })
        for nal in picture {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }
        return try Self.makeSample(avcc, format: format, key: key)
    }

    static func makeFormat(sps: Data, pps: Data) throws(Failure) -> CMVideoFormatDescription {
        guard sps.count >= 4, pps.count >= 1 else { throw .badParameterSets }
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsBuf in
            pps.withUnsafeBytes { ppsBuf in
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBuf.bindMemory(to: UInt8.self).baseAddress!, ppsBuf.bindMemory(to: UInt8.self).baseAddress!,
                ]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
        }
        guard status == noErr, let format else { throw .badParameterSets }
        return format
    }

    static func makeSample(_ avcc: Data, format: CMVideoFormatDescription, key: Bool) throws(Failure) -> CMSampleBuffer {
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else { throw .coreMedia(status) }
        status = avcc.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                       offsetIntoDestination: 0, dataLength: avcc.count) }
        guard status == noErr else { throw .coreMedia(status) }

        var sample: CMSampleBuffer?
        var size = avcc.count
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                           sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                           sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw .coreMedia(status) }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            if !key {
                CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                     Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return sample
    }
}
