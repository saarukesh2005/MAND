# M’AND

**Connect Android and macOS in one seamless ecosystem.**

M’AND links your Android phone and your Mac over your own Wi-Fi. No cloud, no accounts and no subscriptions. Everything stays on your local network, encrypted end to end.

| Part | What it is | Code name |
|---|---|---|
| Mac app | The main control centre (SwiftUI, menu bar + window) | `MandMac` |
| Android app | The secure companion (Kotlin, Jetpack Compose) | `MandAndroid` |
| Shared protocol | How the two talk, plus test cases both apps must pass | `protocol/` |

## What works today (Milestone 1: connection)

- **Pairing:** scan a QR code on the Mac, then click **Allow**. Nothing is trusted until you approve it.
- **Encryption:** TLS 1.3, where each device proves its identity and accepts only the exact device it paired with.
- **Status:** the Mac shows whether the phone is connected, plus its name and when it was last seen.
- **Test messages:** send a short text either way to check the link.
- **Reconnecting:** disconnects are detected within 45 seconds, and the phone reconnects automatically after Wi-Fi drops or restarts.
- **Forget device:** either side can unpair at any time.

See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next: files, clipboard, notifications, battery and screen mirroring. See [docs/TESTING.md](docs/TESTING.md) for exactly what has and hasn't been verified.

## Run it

**Mac app**
```bash
scripts/create-dev-signing-cert.sh   # once: a free local signing identity
scripts/build-mac-app.sh             # builds dist/M’AND.app
open "dist/M’AND.app"
```

**Android app.** You need Android Studio first; see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

**Tests**
```bash
scripts/test-mac.sh                  # Mac: protocol + real TLS tests
cd android && ./gradlew :core:test   # Android protocol tests (after Android Studio is installed)
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md): how the apps are built and how they talk
- [Security](docs/SECURITY.md): what protects you, and the known gaps
- [Development setup](docs/DEVELOPMENT.md)
- [Roadmap](docs/ROADMAP.md)
- [Testing and verification status](docs/TESTING.md)
- [Decisions](docs/DECISIONS.md): why things are built this way
- [Protocol specification](protocol/PROTOCOL.md)
