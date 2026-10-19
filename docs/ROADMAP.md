# Roadmap

Status key: ✅ done and verified · 🟡 written, not yet verified · ⬜ not started

## Milestone 0: environment and project audit ✅
Audit done 2026-10-19 (see TESTING.md for the environment snapshot).

## Milestone 1: secure connection MVP 🟡
| Item | Mac | Android |
|---|---|---|
| Protocol v1 + shared test vectors | ✅ | 🟡 (code written; tests not run, no JDK yet) |
| Device identity in secure storage | ✅ Keychain | 🟡 Keystore |
| TLS 1.3 mutual auth + fingerprint pinning | ✅ (localhost tests) | 🟡 |
| QR pairing + explicit approval | ✅ server side (tests) | 🟡 scanner + client |
| Connected status, last seen, history log | ✅ UI built | 🟡 |
| Test message both ways | ✅ server side (tests) | 🟡 |
| Disconnect detection (45 s) and reconnect | ✅ server side | 🟡 backoff, network-change retry |
| Forget device on either side | ✅ (tests) | 🟡 |
| Bonjour advertising / NSD discovery | ✅ advertised (`dns-sd`) | 🟡 |
| Real phone ↔ Mac end-to-end | ⬜ needs Android Studio and the phone | |

**Done when:** every acceptance check in TESTING.md passes on the real phone.

## Milestone 2: file transfer ⬜
Two-way transfers over a separate pinned TLS connection: progress, speed, cancel, resume after interruption, SHA-256 integrity check, safe file names (no path traversal), no overwrites, and a chosen download folder on the Mac. Android side uses the Share sheet and the system file picker (no broad storage permission).

## Milestone 3: clipboard sharing ⬜
Off by default, with a clear toggle. Only user-initiated: Android can't read the clipboard in the background (Android 10+), so phone→Mac uses the Share sheet, a Quick Settings tile or a notification button. The Mac skips items marked as concealed by password managers. No clipboard history is kept.

## Milestone 4: notifications and device info ⬜
- **Notifications:** Android NotificationListenerService with a per-app allow-list, after an explained permission step. Sideloaded apps may first need *Allow restricted settings*. Android 15+ hides one-time-code content from listeners.
- **Device info:** battery level and charging status from BatteryManager, shown on the Mac only when real values arrive.

## Milestone 5: screen mirroring ⬜
Integrate **scrcpy** (Apache-2.0; v5.0.1 ships a macOS arm64 build). It needs USB debugging or wireless debugging. The Mac app will launch and manage it. Remote control gets its own security review.

## Milestone 6: reliability and release ⬜
- **Android 17:** move to targetSdk 37 with `ACCESS_LOCAL_NETWORK` onboarding.
- **Connection:** start on boot/login, and better handling of phone makers that kill background apps.
- **Quality:** accessibility audit, performance, an installer, and user docs.
- **Policy:** recheck Google's sideloading verification policy (global in 2027).

## Calls and SMS (investigated, not scheduled)
| Feature | Verdict |
|---|---|
| Caller ID / new SMS shown on Mac | Feasible, as mirrored notifications (Milestone 4) |
| Decline or answer a call from the Mac | Possible with `ANSWER_PHONE_CALLS` (runtime permission); needs a design review |
| Read and send SMS | Restricted permissions; possible for a sideloaded app but sensitive. Verify on device before promising |
| RCS messages | Not available to third-party apps |
| Talking or listening to calls on the Mac | **Not possible:** macOS can't act as a phone's hands-free device, and Android doesn't give apps call audio |
