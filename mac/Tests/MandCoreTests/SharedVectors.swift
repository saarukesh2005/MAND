import Foundation

/// Loads `protocol/vectors/protocol-v1.json`, shared with the Android tests.
enum SharedVectors {
    // Read-only after first load, so sharing it across test threads is safe.
    nonisolated(unsafe) static let root: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MandCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // mac
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("protocol/vectors/protocol-v1.json")
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    static func cases(_ section: String) -> [[String: Any]] {
        root[section] as! [[String: Any]]
    }

    static func names(_ section: String) -> [String] {
        cases(section).map { ($0["name"] as? String) ?? "\($0)" }
    }

    static func named(_ section: String, _ name: String) -> [String: Any] {
        cases(section).first { ($0["name"] as? String) == name }!
    }
}
