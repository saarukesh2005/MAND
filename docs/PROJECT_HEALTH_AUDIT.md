# M’AND — Project Health Audit

Audit date: 2026-10-20. Baseline commit: `1392a89` (v0.2.0).

> **This is a snapshot of v0.2.0, kept as a record — it is not current status.**
> Much of what it lists has since been fixed, including Android 17 support with
> `ACCESS_LOCAL_NETWORK` onboarding, first-run onboarding on both apps, multiple phones,
> per-address pairing throttling, the minified release APK and the accessibility pass.
> For where the project actually stands, read `FEATURE_TRACKER.md` and `ROADMAP.md`.

## Baseline results (run 2026-10-20)
| Check | Result |
|---|---|
| `scripts/test-mac.sh` | PASS: 43 tests (22 MandMacKit + 21 MandCore) |
| `./gradlew :core:test` | PASS: 16 tests |
| `./gradlew :app:assembleDebug` / `:app:lintDebug` | PASS / 0 errors, 7 expected warnings |
| `scripts/interop-test.sh` | PASS: 4 tests (last run 2026-10-20) |
| Phone (USB) | Not connected. The founder reports pairing, files, clipboard, notifications and battery working on their phone |

## Module map
- `protocol/` (spec and shared vectors) → `mac/Sources/MandCore` (Swift) and `android/core` (Kotlin). Both are pure logic and tested against the same vectors.
- `mac/Sources/MandMacKit`:
  - `Net`: BridgeServer, TLS, FramedConnection
  - `Identity`, `Trust`: Keychain storage
  - `Files`: FileTransferService
  - `Features`: clipboard, notifier, scrcpy, login item
  - `App`: AppModel, AppSettings
- `mac/Sources/MandMac`: SwiftUI views (thin).
- `android/app`:
  - `net`: BridgeClient, MacSession, discovery
  - `identity`: Keystore
  - `data`: DataStore
  - `files`, `clipboard`, `notify`, `device`, `system`, `service`: feature modules plugged in via `FeatureHandler`
  - `ui`: Compose screens

The boundaries are reasonable: UI → state model → services → protocol core.

## Feature status
| Feature | Implemented | Automated tests | Real hardware |
|---|---|---|---|
| Pairing, reconnect, forget | ✅ | ✅ Mac + interop | ✅ user-reported |
| Files both ways | ✅ | ✅ Mac (9) + vectors | ✅ user-reported |
| Clipboard | ✅ | partial (codec) | ✅ user-reported |
| Notifications | ✅ | partial (codec) | ✅ user-reported |
| Battery | ✅ | partial (codec) | ✅ user-reported |
| Screen mirroring | ✅ launcher | ✅ error mapping only | ❌ not tried |

## Top 10 issues, ranked by severity × user value
1. **Only one phone at a time.** The Mac server keeps a single active session, so a second phone replaces the first.
2. **Reconnect never rests.** Android retries every ≤30 s forever, even with no network. This wastes battery while offline.
3. **Android 17 not supported.** targetSdk 36; the `ACCESS_LOCAL_NETWORK` flow is missing.
4. **Pairing can be griefed per address.** One LAN device can burn the global 10-attempt budget.
5. **No first-run onboarding** on either app. Users land on a bare status screen.
6. **No sleep/wake handling** on the Mac. Stale sessions linger up to 45 s after wake.
7. **Transfer history lives in memory only.** It's lost when the Mac app quits.
8. **Debug-only APK.** 65 MB, not minified.
9. **No UI-level tests.** Android Compose and Mac model state transitions are untested.
10. **Accessibility not audited.** Some icons lack labels; Android touch targets are unchecked.

## Security / privacy
No open critical findings. One critical issue (Swift file-name traversal) was fixed on 2026-10-20 with regression tests. Open items are listed in `SECURITY.md` and `THREAT_MODEL.md`.

## Technical debt and maintenance risk
- **`BridgeClient.kt`** (~500 lines) and **`BridgeServer.swift`** (~490 lines) are the largest files. They can be split once the multi-device work settles.
- **Toolchain workarounds** for building without Xcode (plugin copy, `@State` avoidance) depend on the Command Line Tools layout. They're documented in DECISIONS D7.
- **Dependencies are few:** swift-certificates, AndroidX, zxing-android-embedded, kotlinx-serialization. All are maintained, with permissive licences.
