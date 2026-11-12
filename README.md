# M’AND

**Connect Android and macOS in one seamless ecosystem.**

M’AND links your Android phone and your Mac over your own Wi-Fi:
- No cloud, no accounts, no subscriptions.
- Everything stays on your local network, encrypted end to end (mutual TLS 1.3 with pinned certificates).

## Download

Get the latest version from **[Releases](https://github.com/saarukesh2005/MAND/releases/latest)**:

| File | For | Needs |
|---|---|---|
| `MAND-<version>.apk` | Android phone | Android 14 or newer |
| `MAND-<version>-mac.zip` | Mac | macOS 14 or newer, Apple Silicon (M1 or later) |

### Install on Android
1. Open the release page on your phone and download the `.apk`.
2. Tap the downloaded file. If Android asks, allow your browser or Files app to **install unknown apps**.
3. If Play Protect warns that the app is unknown, choose **More details → Install anyway**. The app isn't on the Play Store, so Android can't vouch for it.

### Install on the Mac
1. Download the `-mac.zip` and double-click it to unzip.
2. Drag **M’AND.app** into **Applications**.
3. Open it. macOS will say it can't check the app, because it isn't notarised by Apple (that needs a paid developer account).
4. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to M’AND.

   Or, in Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/M’AND.app"
   ```
5. The first time, macOS asks to let M’AND use your Keychain (where its security key is kept). Enter your Mac password and click **Always Allow**.

### Pair
1. Open M’AND on the Mac and click **Pair a Phone**. A QR code appears.
2. In the phone app, tap **Pair with Mac** and scan the code.
3. Click **Allow** on the Mac.

Both devices must be on the same Wi-Fi.

## Features

Every sharing feature starts **off** until you turn it on.

| Feature | Mac | Android |
|---|---|---|
| **Secure pairing:** scan a QR code, then click Allow. Several phones can be paired | ✅ | ✅ |
| **Connection status**, auto-reconnect, forget device | ✅ | ✅ |
| **Files both ways:** drag and drop, Share sheet, progress, resume, SHA-256 check | ✅ | ✅ |
| **Clipboard text:** passwords are never sent | ✅ | ✅ |
| **Phone notifications on the Mac:** you choose the apps | ✅ | ✅ |
| **Battery level and charging** | ✅ | ✅ |
| **Calls:** see who's calling, answer or decline from the Mac (audio stays on the phone) | ✅ | ✅ |
| **Tap to Send** (experimental): hold the phone against the MacBook notch to send what's on screen | ✅ | ✅ |
| **SMS one-time codes** go to the Mac clipboard | ✅ | ✅ |
| **Quick Share receive** (unofficial, off by default) | ✅ | built into Android |
| **Screen mirroring** with the free [scrcpy](https://github.com/Genymobile/scrcpy) (USB) | ✅ | needs USB debugging |

**Honest status:**
- Tested by the author on a Pixel 7a: pairing, files, clipboard, notifications and battery.
- Built and tested automatically, but **not yet tried on a real phone**: calls, Quick Share, Tap to Send, SMS codes and mirroring.
- [docs/TESTING.md](docs/TESTING.md) has every result.

**Tap to Send notes:**
- It reads the MacBook's notch light sensor through an undocumented macOS interface, so a macOS update could break it. It needs a MacBook with a notch and the lid open.
- On the phone, it needs **M’AND Tap to Send** turned on in Accessibility settings. If Android greys it out, open **App info → ⋮ → Allow restricted settings** first.
- It stays paused while banking and UPI apps are open.

## Build it yourself

**Mac** (Command Line Tools are enough; Xcode is optional)
```bash
scripts/create-dev-signing-cert.sh   # once: a free local signing identity
scripts/build-mac-app.sh             # builds dist/M’AND.app
open "dist/M’AND.app"
```

**Android** (JDK 21 and the Android SDK; see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md))
```bash
cd android && ./gradlew :app:assembleRelease
```

**Tests**
```bash
scripts/test-mac.sh                                    # Mac: 81 tests
(cd android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug)
scripts/interop-test.sh                                # Swift server ↔ Kotlin/Java TLS client
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md): how the apps are built and how they talk
- [Security](docs/SECURITY.md) and [threat model](docs/THREAT_MODEL.md)
- [Feature tracker](docs/FEATURE_TRACKER.md): every feature and its real status
- [Testing and verification status](docs/TESTING.md)
- [Development setup](docs/DEVELOPMENT.md)
- [Roadmap](docs/ROADMAP.md)
- [Decisions](docs/TECHNICAL_DECISIONS.md): why things are built this way
- [Protocol specification](protocol/PROTOCOL.md)
- [References](docs/REFERENCES.md) and [third-party notices](THIRD_PARTY_NOTICES.md)

## Licence

[MIT](LICENSE). Parts are adapted from [TapDrop](https://github.com/0x1p0/TapDrop) (MIT) and [NearDrop](https://github.com/grishka/NearDrop) (Unlicense); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
