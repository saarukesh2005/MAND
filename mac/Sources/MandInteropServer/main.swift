// Test-only server for scripts/interop-test.sh: runs the real BridgeServer with a throwaway keychain,
// auto-approves pairing, and echoes messages so the Kotlin/JSSE client can verify interoperability.
// Never shipped in the app.
import Foundation
import MandCore
import MandMacKit
import Security

setvbuf(stdout, nil, _IOLBF, 0)
let path = NSTemporaryDirectory() + "mand-interop-\(UUID().uuidString).keychain"
var keychainRef: SecKeychain?
guard SecKeychainCreate(path, 4, "test", false, nil, &keychainRef) == errSecSuccess, let keychain = keychainRef else {
    print("ERROR keychain"); exit(1)
}
// Never auto-lock the throwaway keychain (a locked one makes macOS show a password prompt mid-test).
var noLock = SecKeychainSettings(version: UInt32(SEC_KEYCHAIN_SETTINGS_VERS1), lockOnSleep: false,
                                 useLockInterval: false, lockInterval: UInt32.max)
SecKeychainSetSettings(keychain, &noLock)
// The throwaway keychain file is deleted on exit (signals from the test script, or a listener failure).
let keychainPath = path
@Sendable func cleanup() { unlink(keychainPath) }
signal(SIGTERM) { _ in unlink(keychainPath); exit(0) }
signal(SIGINT) { _ in unlink(keychainPath); exit(0) }

let identity = try DeviceIdentity.loadOrCreate(label: "M’AND Interop Mac", keychain: keychain, commonName: "Interop Mac")
final class Box: @unchecked Sendable {
    var server: BridgeServer?
    var windowOpened = false
    var listening = false
    var listLoaded = false
    /// Pairing opens once the server listens AND the trusted list has loaded (they finish in either order).
    func openWhenReady() {
        guard listening, listLoaded, !windowOpened else { return }
        windowOpened = true
        server?.openPairingWindow()
    }
    var frames = 0
    var decoded = 0
    var depacketizer = H264Depacketizer()
}
// Optional settings for running against an emulator or a phone: MAND_HOSTS (comma-separated addresses put
// in the QR invite), MAND_PORT (listen port), MAND_TEST_SCREEN=1 (ask the phone to share its screen).
let env = ProcessInfo.processInfo.environment
let hosts = env["MAND_HOSTS"].map { $0.split(separator: ",").map(String.init) } ?? ["127.0.0.1"]
let port = env["MAND_PORT"].flatMap(UInt16.init) ?? 0
let askForScreen = env["MAND_TEST_SCREEN"] == "1"
let testControl = env["MAND_TEST_CONTROL"] == "1"
let box = Box()
let server = BridgeServer(identity: identity, store: InMemoryPairedDeviceStore(), deviceName: "Interop Mac",
                          preferredPort: port, advertise: false, addresses: { hosts }) { event in
    switch event {
    case .listening(let port):
        print("LISTENING \(port)")
        box.server?.queue.async { box.listening = true; box.openWhenReady() }
    case .devicesChanged:
        box.server?.queue.async { box.listLoaded = true; box.openWhenReady() }
    case .pairingUnavailable(let reason):
        print("PAIRING UNAVAILABLE \(reason)")
    case .pairingWindowOpened(let invitation):
        print("INVITE \(invitation.url)")
    case .approvalNeeded(let request):
        print("APPROVE \(request.name)")
        box.server?.resolvePairing(id: request.id, approved: true)
    case .phoneConnected(let device, _, let features):
        print("CONNECTED \(device.name) features=\(features.sorted().joined(separator: ","))")
        if askForScreen { box.server?.send(.screenRequest, to: device.fingerprint) }
    case .phoneDisconnected(_, let reason):
        print("DISCONNECTED \(reason)")
    case .textReceived(let text, let device):
        print("TEXT \(text)")
        box.server?.sendText("echo:\(text)", to: device.fingerprint)
    case .featureMessage(let message, let device):
        switch message {
        case .clipboardText(let text): box.server?.send(.clipboardText("echo:\(text)"), to: device.fingerprint)
        case .deviceStatus(let battery, let charging):
            box.server?.sendText("battery:\(battery):\(charging)", to: device.fingerprint)
        case .callState(.ringing, _): box.server?.send(.callAction(.decline), to: device.fingerprint)
        case .deviceInfo(let info): print("INFO \(info.model) | \(info.os) | free=\(info.storageFree) total=\(info.storageTotal)")
        case .linkOpen(let url, _): print("LINK \(url)")
        case .findState(let ringing): print("FIND ringing=\(ringing)")
        case .tapReady(let on): print("TAP READY phone=\(on)")
        case .screenStart(let w, let h): print("SCREEN START \(w)x\(h)")
        case .screenStop(let reason): print("SCREEN STOP \(reason)")
        case .controlState(let available):
            print("CONTROL available=\(available)")
            if available && testControl {
                // Press Home on the phone, then tap the middle of the screen, a moment later.
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    box.server?.send(.controlKey(.home), to: device.fingerprint)
                    print("CONTROL sent home")
                }
            }
        case .screenFrame(_, let key, let data):
            box.frames += 1
            if (try? box.depacketizer.sampleBuffer(for: data, key: key)) != nil { box.decoded += 1 }
            if box.frames == 1 || box.frames % 30 == 0 {
                print("SCREEN FRAMES \(box.frames) decodable=\(box.decoded) last=\(data.count)B key=\(key)")
            }
        default: break
        }
    case .listenerFailed(let reason):
        print("ERROR \(reason)"); cleanup(); exit(1)
    default:
        break
    }
}
box.server = server
server.start()
dispatchMain()
