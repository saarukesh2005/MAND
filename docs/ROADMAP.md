# Roadmap

Status key: ✅ built and verified by automated tests on the Mac · 🟡 built (compiles, lint clean), not yet run on a phone · ⬜ not started

The single remaining gate for every milestone is **testing on the real phone** (see TESTING.md, "Real-phone checklist").

## Milestone 0: environment and project audit ✅
Done 2026-10-19. The Android toolchain was installed on 2026-10-20 (JDK 21, Android SDK command-line tools, platform 36/37, adb), all from verified official downloads.

## Milestone 1: secure connection ✅ Mac / 🟡 Android
QR pairing with Mac approval, mutual TLS 1.3 with pinning, status and last-seen, test messages, 45 s liveness, automatic reconnect with backoff, and forget on either side.
- **Verified:** 13 Mac integration tests, plus the Swift↔Java TLS interop test (pairing, reconnect, wrong pin, unpaired certificate).

## Milestone 2: file transfer ✅ Mac / 🟡 Android
Both directions; multiple files and folders (Mac); Android Share sheet and file picker.
- **Transfer:** progress and speed, cancel, retry (Mac), resume after interruption, SHA-256 verified.
- **Safety:** traversal-safe names, no duplicates, no overwrites (`name (2).ext`), and a choosable download folder on the Mac (default `~/Downloads/M’AND`). Android saves to `Downloads/M’AND`.
- **Verified:** 9 Mac loopback tests (intact transfer, folders and empty files, traversal rejected incl. zero-width and symlink attacks, corruption detected, resume, no duplicates or overwrites, out-of-order rejected) and 25 shared file-name vectors in both languages.

## Milestone 3: clipboard ✅ Mac / 🟡 Android
Off by default on both sides. Text only, with no history kept.
- **Mac:** "Send Clipboard" button and menu-bar item; optional auto-send; items marked concealed by password managers are never sent.
- **Android:** a send button, a Quick Settings tile and the Share sheet (Android blocks background clipboard reads); text marked sensitive is never sent; text from the Mac is applied only when sharing is on.

## Milestone 4: notifications and device info ✅ Mac / 🟡 Android
- **Notifications:** Android NotificationListenerService with a per-app allow-list, off by default. The Mac shows an in-app list and optionally macOS Notification Center; dismissing on the Mac dismisses on the phone.
- **Battery:** level and charging state from Android BatteryManager, shown on the Mac Home screen and in the menu bar. Real values only.

## Milestone 5: screen mirroring ✅ Mac / 🟡 Android
Two routes, and the built-in one is now the default.
- **Built in, over Wi-Fi (0.6.0):** the phone captures its own screen with `MediaProjection` and streams it over `screen.v1`. Nothing to install, no USB, no scrcpy. The phone asks before every session, and it is view-only until "allow control" is switched on, which also needs the Accessibility service (`control.v1`).
- **Advanced, over USB:** the Mac still finds, launches and stops scrcpy (Apache-2.0; user-installed, not bundled) for people who want control over a cable.
- **Not verified:** a real mirroring session end to end (needs the phone).

## Milestone 6: reliability and release 🟡
- **Done:**
  - **Mac:** open at login, a Settings window, a fix for a launch freeze on a privacy prompt, deterministic test runs.
  - **Android:** reconnect after reboot or update, a battery-optimisation prompt.
  - **Android:** targetSdk 37 with `ACCESS_LOCAL_NETWORK` onboarding (minSdk 34).
  - **Accessibility:** a VoiceOver pass on the Mac and a TalkBack / WCAG 2.2 AA pass on Android.
  - **Multiple phones**, and per-address throttling of pairing attempts.
  - **Release tooling:** `scripts/install-android.sh` for the phone, and `scripts/install-mac.sh` — a
    one-line `curl … | bash` install that verifies the download against the release's SHA-256. Because
    `curl` sets no quarantine tag, the Mac app opens without the Privacy & Security detour, so this
    removes most of the need for notarization.
- **Left:**
  - Test everything on the real phone and fix what that finds. This is still the single gate on every 🟡 above.
  - Developer ID notarization (₹8,900/year), if browser downloads should stop warning too.
  - Recheck Google's sideloading verification before it goes global in 2027. M’AND combines an
    AccessibilityService with `RECEIVE_SMS`, which is the pattern that verification looks hardest at.

## Calls and SMS
This table used to say calls and SMS were deliberately not built. Two of those rows shipped since;
see docs/FEATURE_TRACKER.md for the per-feature status and evidence.

| Feature | Status |
|---|---|
| Caller ID / new SMS on the Mac | **Built** (`calls.v1`) — and also works as mirrored notifications (allow your Phone and Messages apps) |
| Answer or decline calls from the Mac | **Built** (`ANSWER_PHONE_CALLS`, `READ_PHONE_STATE`); audio stays on the phone |
| SMS one-time codes → the Mac clipboard | **Built**, opt-in and off by default (`RECEIVE_SMS`, `OtpReceiver` → `clipboard.v1`). Only codes are matched, never whole messages |
| Reading or sending SMS generally | **Not built**, and not planned. Restricted permissions, and far more sensitive than one-time codes |
| RCS messages | Not available to third-party apps |
| Talking or listening to calls on the Mac | **Not possible:** macOS can't act as a phone's hands-free device, and Android doesn't give apps call audio |
