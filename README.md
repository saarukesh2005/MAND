# M’AND

**Connect Android and macOS in one seamless ecosystem.**

M’AND links your Android phone and your Mac over your own Wi-Fi. No cloud, no accounts and no subscriptions. Everything stays on your local network, encrypted end to end.

| Part | What it is | Code name |
|---|---|---|
| Mac app | The main control centre (SwiftUI window, menu bar and Settings) | `MandMac` |
| Android app | The secure companion (Kotlin, Jetpack Compose) | `MandAndroid` |
| Shared protocol | How the two talk, plus test cases both apps must pass | `protocol/` |

## Features

| Feature | Mac | Android |
|---|---|---|
| **Secure pairing:** scan a QR code, then click Allow | ✅ | ✅ |
| **Connection status**, last seen, auto-reconnect, forget device | ✅ | ✅ |
| **Files both ways:** drag and drop, Share sheet, folders, progress and speed, resume after a dropped connection, SHA-256 check, never overwrites | ✅ | ✅ |
| **Clipboard text:** off by default; passwords never sent; Quick Settings tile on the phone | ✅ | ✅ |
| **Phone notifications on the Mac:** you choose the apps; dismiss on the Mac and it's dismissed on the phone | ✅ | ✅ |
| **Battery level and charging** on the Mac | ✅ | ✅ |
| **Screen mirroring** with the free scrcpy tool (USB); view-only unless you allow control | ✅ | needs USB debugging |
| Open at login / reconnect after the phone restarts | ✅ | ✅ |

**Honest limits:**
- Calls and SMS aren't mirrored beyond their notifications.
- Android only lets the app on screen read the clipboard, so sending from the phone always takes a tap.

Details are in [docs/ROADMAP.md](docs/ROADMAP.md).

**Verification status:** everything has been built and automatically tested on this Mac, including a real Mac↔Java TLS interop test. **Nothing has been tested on a real Android phone yet.** See [docs/TESTING.md](docs/TESTING.md).

## Run it

**Mac app**
```bash
scripts/create-dev-signing-cert.sh   # once: a free local signing identity
scripts/build-mac-app.sh             # builds dist/M’AND.app
open "dist/M’AND.app"
```

**Android app.** Plug in the phone with USB debugging on (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)), then run:
```bash
scripts/install-android.sh
```

**Tests**
```bash
scripts/test-mac.sh                   # Mac: protocol, real TLS, file transfer (43 tests)
(cd android && ./gradlew :core:test)  # Kotlin protocol core + shared vectors
scripts/interop-test.sh               # Swift server ↔ Kotlin/Java TLS client
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md): how the apps are built and how they talk
- [Security](docs/SECURITY.md): what protects you, the permissions used, and the known gaps
- [Development setup](docs/DEVELOPMENT.md)
- [Roadmap](docs/ROADMAP.md)
- [Testing and verification status](docs/TESTING.md)
- [Decisions](docs/TECHNICAL_DECISIONS.md): why things are built this way
- [References](docs/REFERENCES.md): open-source projects we learn from, and licence rules
- [Protocol specification](protocol/PROTOCOL.md)
