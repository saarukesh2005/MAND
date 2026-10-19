# Architecture

## Big picture

```
 Android phone (client)                         Mac (server)
┌──────────────────────────┐                ┌─────────────────────────────┐
│ Compose UI (HomeScreen)  │                │ SwiftUI (Home/Devices/…)    │
│        ▲ StateFlow       │                │        ▲ @Observable        │
│ BridgeClient             │  TLS 1.3,      │ AppModel                    │
│  pairing · reconnect ·   │  mutual auth,  │        ▲ events             │
│  liveness · chat         │  pinned certs  │ BridgeServer                │
│ MacSession ──────────────┼───────────────►│  listener · pairing window ·│
│ MacDiscovery (NSD) ◄─────┼── Bonjour ─────┤  approval · sessions · ping │
│ KeystoreIdentity         │  _mand._tcp    │ DeviceIdentity (Keychain)   │
│ PairedMacStore (DataStore)│               │ PairedDeviceStore (Keychain)│
│ BridgeService (FGS)      │                │                             │
│ :core  (Kotlin protocol) │ ◄── same ───►  │ MandCore (Swift protocol)   │
└──────────────────────────┘    vectors     └─────────────────────────────┘
```

- **The Mac listens; the phone connects.** The Mac is the always-on side. Android limits background apps, so the phone keeps an outgoing connection alive from a foreground service.
- **Local network only.** There are no servers, accounts or analytics.

## Repository layout

```
protocol/            PROTOCOL.md (the spec) + vectors/protocol-v1.json (shared test cases)
mac/                 Swift package
  Sources/MandCore      protocol logic (no networking, no UI)
  Sources/MandMacKit    identity, TLS, BridgeServer, AppModel, QR rendering
  Sources/MandMac       SwiftUI app (thin)
  Tests/                Swift Testing: unit + real localhost TLS integration tests
android/             Gradle project
  core/                 Kotlin protocol logic (mirrors MandCore), JVM unit tests
  app/                  Android app
scripts/             build, test, signing and icon helpers
docs/                these documents
```

## Protocol in one paragraph

Every message is a 4-byte length followed by a JSON envelope `{v, type, id, ts, body}`. Frames are capped at 1 MiB.
- **Handshake:** both sides send `hello` (name, platform, supported versions). The highest shared version is used.
- **Pairing:** an unpaired phone sends `pair.request` with a proof derived from the QR secret.
- **Session:** once the Mac sends `session.ready`, the link carries `text`, `ping`/`pong` (every 15 s, dead after 45 s), `bye` and `error`.
- **Compatibility:** unknown message types are ignored, so newer apps can add features without breaking older ones.

Full details: [protocol/PROTOCOL.md](../protocol/PROTOCOL.md).

## Keeping two languages in sync

The protocol is implemented twice, in Swift (`MandCore`) and Kotlin (`:core`). Both test suites load the **same** `protocol/vectors/protocol-v1.json`, which covers framing, valid and malformed messages, version negotiation, pairing proofs and QR codes. A change that breaks either side fails its tests. All string limits are in UTF-8 bytes, so both languages count them identically.

## Mac app

| Piece | Responsibility |
|---|---|
| `DeviceIdentity` | P-256 key and self-signed certificate in the login Keychain; created once, reused forever |
| `TLS` | Builds Network.framework TLS 1.3 options with a fingerprint-pinning verify block |
| `FramedConnection` | One connection: framing, decoding, sending; closes on any protocol violation |
| `BridgeServer` | Listener, Bonjour, pairing window, approval, per-connection state machine, heartbeat, forget |
| `AppModel` | UI state built **only** from server events (no fake data) |
| Views | Home (status, test message, troubleshooting, feature list), Devices, Activity, Pairing sheet, menu bar |

Everything in `BridgeServer` runs on one serial queue, so there are no data races. Events reach the UI through the main queue in order.

## Android app

| Piece | Responsibility |
|---|---|
| `KeystoreIdentity` | P-256 key inside Android Keystore (never exportable), key manager, pinning trust manager |
| `MacSession` | One TLS connection with a single reader coroutine feeding a channel |
| `BridgeClient` | Pairing, reconnect loop (1→30 s backoff; immediate retry on network change), liveness, chat, forget |
| `MacDiscovery` | NSD discovery of `_mand._tcp`; suggests addresses only (pinning decides trust) |
| `PairedMacStore` | Paired Mac's fingerprint, name and last address (DataStore; excluded from backups) |
| `BridgeService` | `connectedDevice` foreground service that keeps the link alive in the background |
| `HomeScreen` | Compose UI driven by `LinkState` |

## Building without Xcode

The Mac app builds with Apple's free Command Line Tools:
- **`@State`:** SwiftUI's `@State` needs an Xcode-only compiler plugin with the macOS 27 SDK, so app-wide UI state lives in small `@Observable` objects instead.
- **Packaging:** `scripts/build-mac-app.sh` wraps the binary into `M’AND.app` and signs it with a stable local identity.
- **Tests:** `scripts/test-mac.sh` works around the Command Line Tools' testing-plugin loader issue.

See [DECISIONS.md](DECISIONS.md).
