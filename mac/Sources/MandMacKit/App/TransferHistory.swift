import Foundation

/// A finished transfer, remembered across launches (last 100) in Application Support.
public struct TransferRecord: Identifiable, Equatable, Codable, Sendable {
    public let item: FileTransferService.Item
    public let deviceName: String
    public let finishedAt: Date
    public var id: String { item.id }
}

/// Small JSON-file store for transfer history. Never stores file contents, only names and outcomes.
public struct TransferHistoryStore: Sendable {
    public static let limit = 100
    let url: URL

    public init(url: URL = TransferHistoryStore.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("M’AND/transfer-history.json")
    }

    public func load() -> [TransferRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TransferRecord].self, from: data)) ?? []
    }

    public func save(_ records: [TransferRecord]) {
        let trimmed = Array(records.suffix(Self.limit))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(trimmed) { try? data.write(to: url, options: .atomic) }
    }
}
