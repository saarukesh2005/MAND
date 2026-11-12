import Foundation
@testable import MandContext
import Testing

/// Loads protocol/vectors/context-v1.json — the same cases android/core runs.
enum ContextVectors {
    nonisolated(unsafe) static let root: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("protocol/vectors/context-v1.json")
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    static func cases(_ key: String) -> [[String: Any]] { root[key] as! [[String: Any]] }
}

@Suite("Shared context vectors")
struct ContextVectorTests {
    @Test("Fold produces the expected capsules and conflicts")
    func fold() throws {
        for vector in ContextVectors.cases("fold") {
            let name = vector["name"] as! String
            let events = try (vector["events"] as! [[String: Any]]).map { try ContextCodec.event($0) }
            let asOf = (vector["asOf"] as? NSNumber)?.int64Value
            let summary = ContextSummary.of(CapsuleReducer.fold(events, asOf: asOf))
            let expected = vector["expect"] as! [String: Any]
            #expect((summary as NSDictionary).isEqual(expected), "\(name): \(summary)")
            // Every permutation-independent: reversing the input gives the same result.
            let reversed = ContextSummary.of(CapsuleReducer.fold(events.reversed(), asOf: asOf))
            #expect((reversed as NSDictionary).isEqual(expected), "\(name) (reversed)")
        }
    }

    @Test("Invalid events are rejected")
    func invalid() {
        for vector in ContextVectors.cases("invalid") {
            #expect(throws: ContextCodec.Failure.self, "\(vector["name"]!)") {
                _ = try ContextCodec.event(vector["event"] as! [String: Any])
            }
        }
    }

    @Test("Valid events decode and round-trip")
    func valid() throws {
        for vector in ContextVectors.cases("valid") {
            let event = try ContextCodec.event(vector["event"] as! [String: Any])
            let again = try ContextCodec.decode(try ContextCodec.encode([event]))
            #expect(again == [event], "\(vector["name"]!)")
        }
    }
}

@Suite("Time Machine")
struct TimeMachineTests {
    var author = ContextAuthor(origin: "mac")

    mutating func capsuleWithHistory() -> (events: [ContextEvent], id: String) {
        let id = "cma"
        var events = [author.make(capsule: id, body: .capsuleCreated(title: "Partnership", description: ""), time: 1_000)]
        events.append(author.make(capsule: id, item: "n1", body: .itemAdded(ItemSeed(kind: .note, title: "Q1", text: "v1")), time: 2_000))
        events.append(author.make(capsule: id, body: .tagged("CMA"), time: 3_000))
        let state = CapsuleReducer.fold(events)
        events.append(author.make(capsule: id, item: "n1", body: .itemSet(.text, .string("v2 (wrong)"),
                                  base: state.lastWriter[ContextState.key(id, "n1", "text")]), time: 4_000))
        events.append(author.make(capsule: id, item: "n1", body: .itemRemoved, time: 5_000))
        return (events, id)
    }

    @Test("Past state, diff and selective restore by appending events")
    mutating func restore() throws {
        let (events, id) = capsuleWithHistory()
        let now = try #require(CapsuleReducer.fold(events).capsules[id])
        let past = try #require(CapsuleReducer.fold(events, asOf: 3_000).capsules[id])
        #expect(now.items.isEmpty)
        #expect(past.items.map(\.text) == ["v1"])

        let changes = TimeMachine.diff(from: now, to: past)
        #expect(changes.map(\.id) == ["item+.n1"])

        let current = CapsuleReducer.fold(events)
        var all = events
        for (item, body) in TimeMachine.restore(changes, capsule: id, state: current) {
            all.append(author.make(capsule: id, item: item, body: body, time: 6_000))
        }
        let restored = try #require(CapsuleReducer.fold(all).capsules[id])
        #expect(restored.items.map(\.text) == ["v1"])
        #expect(CapsuleReducer.fold(all).conflicts.isEmpty)
        // History is intact: the 5 original events are untouched and still visible.
        #expect(TimeMachine.timeline(all, capsule: id).count == events.count + 1)
    }

    @Test("Undo a restore by restoring the state from just before it")
    mutating func undo() throws {
        let (events, id) = capsuleWithHistory()
        var all = events
        let before = CapsuleReducer.fold(all)
        let title = TimeMachine.diff(from: before.capsules[id]!, to: { var c = before.capsules[id]!; c.title = "Renamed"; return c }())
        for (item, body) in TimeMachine.restore(title, capsule: id, state: before) {
            all.append(author.make(capsule: id, item: item, body: body, time: 7_000))
        }
        #expect(CapsuleReducer.fold(all).capsules[id]?.title == "Renamed")
        let undo = TimeMachine.diff(from: CapsuleReducer.fold(all).capsules[id]!, to: before.capsules[id]!)
        for (item, body) in TimeMachine.restore(undo, capsule: id, state: CapsuleReducer.fold(all)) {
            all.append(author.make(capsule: id, item: item, body: body, time: 8_000))
        }
        #expect(CapsuleReducer.fold(all).capsules[id]?.title == "Partnership")
    }

    @Test("Author clock always moves past observed events")
    func clock() {
        var a = ContextAuthor(origin: "mac")
        a.observe([ContextEvent(id: "x", origin: "pixel", seq: 9, lamport: 41, time: 0, capsule: "c", body: .capsuleOpened)])
        let e = a.make(capsule: "c", body: .capsuleOpened)
        #expect(e.lamport == 42)
        #expect(e.seq == 1)
    }
}
