import Foundation
import MandCore
@testable import MandMacKit
import Testing

/// AppModel state, driven by the same events BridgeServer emits (no network needed).
@MainActor
@Suite("App model")
struct AppModelTests {
    let model: AppModel
    let phoneA = PairedDevice(fingerprint: .of(certificateDER: Data("A".utf8)), name: "Pixel", pairedAt: Date())
    let phoneB = PairedDevice(fingerprint: .of(certificateDER: Data("B".utf8)), name: "Galaxy", pairedAt: Date())

    init() {
        let defaults = UserDefaults(suiteName: "mand-test-\(UUID().uuidString)")!
        let history = TransferHistoryStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("mand-history-\(UUID().uuidString).json"))
        model = AppModel(macName: "Test Mac", settings: AppSettings(defaults: defaults), historyStore: history)
        model.apply(.devicesChanged([phoneA, phoneB]))
    }

    @Test("Two phones connect; the first stays selected; disconnecting it selects the other")
    func multiPhoneSelection() {
        model.apply(.phoneConnected(phoneA, address: "10.0.0.2", features: Set(Feature.all)))
        model.apply(.phoneConnected(phoneB, address: "10.0.0.3", features: []))
        #expect(model.phones.count == 2)
        #expect(model.connected?.name == "Pixel")
        #expect(model.phoneSupports(Feature.files))
        model.apply(.phoneDisconnected(phoneA, reason: "test"))
        #expect(model.connected?.name == "Galaxy")
        #expect(!model.phoneSupports(Feature.files))
    }

    @Test("Battery and notifications are kept per phone")
    func perPhoneState() {
        model.apply(.phoneConnected(phoneA, address: nil, features: Set(Feature.all)))
        model.apply(.phoneConnected(phoneB, address: nil, features: Set(Feature.all)))
        model.apply(.featureMessage(.deviceStatus(battery: 80, charging: true), from: phoneB))
        let note = PhoneNotification(key: "k", app: "a", appName: "App", title: "Hi", text: nil, time: 1)
        model.apply(.featureMessage(.notificationPosted(note), from: phoneB))
        #expect(model.phoneStatus == nil) // Pixel is selected
        model.select(model.phones.first { $0.device.name == "Galaxy" }!)
        #expect(model.phoneStatus?.battery == 80)
        #expect(model.notifications.map(\.key) == ["k"])
        model.apply(.featureMessage(.notificationRemoved(key: "k"), from: phoneB))
        #expect(model.notifications.isEmpty)
    }

    @Test("A ringing call shows; idle clears it")
    func calls() {
        model.apply(.phoneConnected(phoneA, address: nil, features: Set(Feature.all)))
        model.apply(.featureMessage(.callState(.ringing, caller: "Amma"), from: phoneA))
        #expect(model.ringingPhone?.call?.caller == "Amma")
        model.apply(.featureMessage(.callState(.active, caller: "Amma"), from: phoneA))
        #expect(model.ringingPhone == nil)
        model.apply(.featureMessage(.callState(.idle, caller: nil), from: phoneA))
        #expect(model.phones.first?.call == nil)
    }

    @Test("Forgetting a phone removes it from the connected list")
    func forgottenPhoneRemoved() {
        model.apply(.phoneConnected(phoneA, address: nil, features: []))
        model.apply(.devicesChanged([phoneB]))
        #expect(model.phones.isEmpty)
    }

    @Test("Battery readings older than 10 minutes are stale")
    func staleBattery() {
        let old = AppModel.PhoneStatus(battery: 50, charging: false, updated: Date().addingTimeInterval(-11 * 60))
        #expect(old.isStale())
        #expect(!AppModel.PhoneStatus(battery: 50, charging: false, updated: Date()).isStale())
    }

    @Test("Transfer history survives a restart")
    func historyPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mand-h-\(UUID().uuidString).json")
        let store = TransferHistoryStore(url: url)
        let item = FileTransferService.Item(id: "t1", name: "a.txt", direction: .incoming, size: 3, transferred: 3,
                                            bytesPerSecond: 0, state: .done, savedURL: nil)
        store.save([TransferRecord(item: item, deviceName: "Pixel", finishedAt: Date())])
        #expect(TransferHistoryStore(url: url).load().map(\.id) == ["t1"])
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Phone details, latency and find-my-phone state are kept per phone")
    func phoneDetails() {
        model.apply(.phoneConnected(phoneA, address: nil, features: Set(Feature.all)))
        let info = DeviceInfo(model: "Pixel 7a", os: "Android 16", storageFree: 5, storageTotal: 10)
        model.apply(.featureMessage(.deviceInfo(info), from: phoneA))
        model.apply(.latency(phoneA, milliseconds: 23))
        model.apply(.featureMessage(.findState(ringing: true), from: phoneA))
        #expect(model.selected?.info == info)
        #expect(model.selected?.latencyMs == 23)
        #expect(model.selected?.isRinging == true)
        model.apply(.featureMessage(.findState(ringing: false), from: phoneA))
        #expect(model.selected?.isRinging == false)
    }

    @Test("Renaming a phone changes its name everywhere on this Mac, and can be undone")
    func rename() {
        model.apply(.phoneConnected(phoneA, address: nil, features: Set(Feature.all)))
        model.renameDevice(phoneA, to: "  Work phone ")
        #expect(model.devices.first { $0.fingerprint == phoneA.fingerprint }?.name == "Work phone")
        #expect(model.connected?.name == "Work phone")
        model.apply(.phoneConnected(phoneA, address: nil, features: Set(Feature.all))) // reconnect keeps the name
        #expect(model.connected?.name == "Work phone")
        model.renameDevice(phoneA, to: "")
        #expect(model.connected?.name == "Pixel")
    }

    @Test("Only web links are sent to the phone")
    func sendLink() {
        #expect(model.sendLink("file:///etc/passwd") == .invalid)
        #expect(model.sendLink("https://example.com") == .notConnected)
    }

    @Test("Control positions are clamped fractions of 10,000")
    func controlScale() {
        #expect(AppModel.scaled(0) == 0)
        #expect(AppModel.scaled(0.5) == 5_000)
        #expect(AppModel.scaled(1.7) == 10_000)
        #expect(AppModel.scaled(-1) == 0)
        #expect(AppModel.scaled(.nan) == 0)
    }

    @Test("The phone says when it accepts control")
    func controlState() {
        model.apply(.phoneConnected(phoneA, address: nil, features: Set(Feature.all)))
        #expect(model.selected?.canControl == false)
        model.apply(.featureMessage(.controlState(available: true), from: phoneA))
        #expect(model.selected?.canControl == true)
    }
}
