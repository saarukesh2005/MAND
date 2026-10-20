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
// The throwaway keychain file is deleted on exit (signals from the test script, or a listener failure).
let keychainPath = path
@Sendable func cleanup() { unlink(keychainPath) }
signal(SIGTERM) { _ in unlink(keychainPath); exit(0) }
signal(SIGINT) { _ in unlink(keychainPath); exit(0) }

let identity = try DeviceIdentity.loadOrCreate(label: "M’AND Interop Mac", keychain: keychain, commonName: "Interop Mac")
final class Box: @unchecked Sendable { var server: BridgeServer? }
let box = Box()
let server = BridgeServer(identity: identity, store: InMemoryPairedDeviceStore(), deviceName: "Interop Mac",
                          preferredPort: 0, advertise: false, addresses: { ["127.0.0.1"] }) { event in
    switch event {
    case .listening:
        box.server?.openPairingWindow()
    case .pairingWindowOpened(let invitation):
        print("INVITE \(invitation.url)")
    case .approvalNeeded(let request):
        print("APPROVE \(request.name)")
        box.server?.resolvePairing(id: request.id, approved: true)
    case .phoneConnected(let device, _, let features):
        print("CONNECTED \(device.name) features=\(features.sorted().joined(separator: ","))")
    case .phoneDisconnected(_, let reason):
        print("DISCONNECTED \(reason)")
    case .textReceived(let text, _):
        print("TEXT \(text)")
        box.server?.sendText("echo:\(text)")
    case .featureMessage(let message):
        switch message {
        case .clipboardText(let text): box.server?.send(.clipboardText("echo:\(text)"))
        case .deviceStatus(let battery, let charging): box.server?.sendText("battery:\(battery):\(charging)")
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
