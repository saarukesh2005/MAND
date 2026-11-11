# M’AND — Project audit

Audit date: 2026-11-12. Baseline commit: `4838d0d` (+ the docs commit). Earlier detail: [PROJECT_HEALTH_AUDIT.md](PROJECT_HEALTH_AUDIT.md).

## 1. Which repository is M’AND
The build brief names `github.com/morluto/rea.git` as "the existing repository". **That's not M’AND.**
- **REA** is a third-party reverse-engineering toolkit (MIT, npm package `rea-agents`). It was installed on this Mac on 2026-10-19 as a global Claude Code tool (MCP server + skill). It isn't cloned anywhere, and no M’AND code depends on it.
- **M’AND** is this repository (`ANTI-GRAVITY/Projects/M'AND`), built from scratch since 2026-10-19.

**Decision:** keep REA entirely separate. It stays available as an investigation tool, for example to inspect our own APK or the app's signature, but it isn't part of the product (TECHNICAL_DECISIONS D12).

## 2. Environment (verified 2026-11-12)
| Item | State |
|---|---|
| MacBook Air M4, macOS 26.7.1, 16 GB RAM | ✅ |
| Free disk space | ~50 GB |
| Swift 6.4 (Command Line Tools) | ✅ builds and tests the whole Mac side |
| Xcode | ❌ not installed. The Swift package opens directly in Xcode if it's added later |
| JDK 21, Gradle 9.8.1, Android SDK 36/37, adb | ✅ in `~/.mand-tools` and `~/Library/Android/sdk` |
| Android phone (Pixel 7a) on USB | ❌ not connected at audit time. The founder reports v0.2 working on their phone |
| Local AI runtime (Ollama / llama.cpp) | ❌ not installed |
| Windows PC (i5-12400F, GTX 1650) | Not reachable from this environment |

## 3. Architecture today
- **Languages:** Swift 6 (Mac), Kotlin 2.4 (Android). A shared protocol is specified in `protocol/PROTOCOL.md` with shared test vectors.
- **Mac Swift package (`mac/`):**
  - `MandCore`: protocol and file-name safety
  - `MandMacKit`:
    - networking: `BridgeServer`, TLS
    - identity: Keychain
    - files: `FileTransferService`
    - features: clipboard, notifier, scrcpy, login item
    - app state: `AppModel`, settings, transfer history (JSON)
  - `MandQuickShare` (optional Quick Share receiver)
  - `MandMac`: the SwiftUI app
  - `MandInteropServer`: test only
- **Android Gradle project (`android/`):**
  - `:core`: protocol, file names, reconnect policy (pure Kotlin)
  - `:app`:
    - networking: client, session, discovery
    - identity: Keystore
    - data: DataStore
    - feature modules: files, clipboard, notifications, device, calls, system
    - foreground service and Compose UI
  - `:interop`: test only
- **Persistence:**
  - **Mac:** Keychain (identity, trusted phones), UserDefaults (settings), JSON (transfer history).
  - **Android:** Keystore (identity), DataStore (paired Mac, settings).
  - **No database yet on either side.**
- **Network:** mutual TLS 1.3 with certificate pinning, QR pairing with explicit approval, length-prefixed JSON messages, feature negotiation.

## 4. Baseline tests (run 2026-11-12)
| Suite | Result |
|---|---|
| `scripts/test-mac.sh` | PASS: 59 tests (21 core, 31 bridge/app/files, 7 Quick Share) |
| `./gradlew :core:test :app:testDebugUnitTest` | PASS: 26 tests (17 core + 9 Compose UI on Robolectric) |
| `scripts/interop-test.sh` | PASS: 4 (last run 2026-10-20) |
| Android lint | 0 errors |
| Real device | User-reported working on their phone: pairing, files, clipboard, notifications, battery. Mirroring not tried. No device test since v0.3 |

## 5. What exists vs. the new brief
Feature-by-feature status is in [FEATURE_TRACKER.md](FEATURE_TRACKER.md).

- **Done well:** connectivity, sharing, clipboard (manual), notifications, battery, calls, Quick Share.
- **Missing entirely:** the "continuity" layer that the brief makes the core of the product:
  - Context Engine, Task Capsules, Personal Brain, Time Machine
  - Anticipate, Anywhere, Delegate, local AI
  - Mirroring through MediaProjection, and remote control through Accessibility
- **Gaps in existing modules:**
  - device renaming, connection quality and diagnostics history
  - clipboard history, notification icons, history and do-not-disturb
  - device model/OS/storage in the hub
  - transfer pause and remaining time
  - a database on both platforms

## 6. Risks
1. **Scope.** The brief is several months of engineering, so work proceeds milestone by milestone with the tracker as the record.
2. **No device connected.** Everything that touches the phone (mirroring, control, capsule continuity) can only be automated-tested on the Mac and JVM until a Pixel is plugged in.
3. **No Xcode.** A `.app` and DMG can be built with the Command Line Tools, and the Swift package opens in Xcode. The Xcode UI test runner isn't available.
4. **Platform limits:**
   - **Android blocks:** background clipboard reads, and listening to call audio.
   - **Remote control:** needs the user to enable an Accessibility service, which Android 13+ marks as a "restricted setting" for sideloaded apps.
   - **App state:** apps can't restore arbitrary other apps' state. Only deep links, files and URLs can be restored.
