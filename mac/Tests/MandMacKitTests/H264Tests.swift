import CoreMedia
import Foundation
@testable import MandMacKit
import Testing

@Suite("H.264 for built-in mirroring")
struct H264Tests {
    // A real 16×16 Baseline SPS/PPS pair (from an encoder) and a tiny IDR slice.
    let sps: [UInt8] = [0x67, 0x42, 0xC0, 0x0A, 0xDA, 0x0F, 0x88, 0x8D, 0x40, 0x40, 0x40, 0x50, 0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x03, 0x03, 0xC8, 0xF1, 0x22, 0xA8]
    let pps: [UInt8] = [0x68, 0xCE, 0x3C, 0x80]
    let idr: [UInt8] = [0x65, 0x88, 0x84, 0x00, 0x33, 0xFF]

    func annexB(_ units: [[UInt8]], long: Bool = true) -> Data {
        Data(units.flatMap { (long ? [0, 0, 0, 1] : [0, 0, 1]) + $0 })
    }

    @Test("Splits Annex B on both start-code lengths")
    func split() {
        let data = annexB([sps]) + annexB([pps], long: false) + annexB([idr])
        let units = H264Depacketizer.nalUnits(in: data)
        #expect(units.map(H264Depacketizer.type) == [7, 8, 5])
        #expect(units[1] == Data(pps))
    }

    @Test("A key frame with SPS/PPS becomes a sample buffer in AVCC form")
    func keyFrame() throws {
        var depacketizer = H264Depacketizer()
        let sample = try #require(try depacketizer.sampleBuffer(for: annexB([sps, pps, idr]), key: true))
        #expect(CMSampleBufferGetTotalSampleSize(sample) == idr.count + 4)
        #expect(CMSampleBufferGetFormatDescription(sample) != nil)
    }

    @Test("Config-only data is remembered; a picture without parameters is refused")
    func parameters() throws {
        var fresh = H264Depacketizer()
        #expect(throws: H264Depacketizer.Failure.noParameterSets) { try fresh.sampleBuffer(for: annexB([idr]), key: true) }
        var depacketizer = H264Depacketizer()
        #expect(try depacketizer.sampleBuffer(for: annexB([sps, pps]), key: true) == nil)
        #expect(try depacketizer.sampleBuffer(for: annexB([idr]), key: true) != nil)
    }

    @Test("Garbage never crashes")
    func garbage() {
        var depacketizer = H264Depacketizer()
        for bytes in [[UInt8](), [0, 0, 1], [0, 0, 0, 1, 0x67], [0xFF, 0xFF, 0xFF]] {
            _ = try? depacketizer.sampleBuffer(for: Data(bytes), key: true)
        }
    }
}
