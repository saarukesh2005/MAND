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

## Milestone 5: screen mirroring ✅ Mac (launcher) / needs scrcpy + USB
The Mac app finds, launches and stops scrcpy (Apache-2.0; user-installed, not bundled). It's view-only by default; "allow control" is an explicit opt-in, and errors are explained in plain English.
- **Not verified:** a real mirroring session (needs scrcpy and the phone).

## Milestone 6: reliability and release 🟡
- **Done:**
  - **Mac:** open at login, a Settings window, a fix for a launch freeze on a privacy prompt, deterministic test runs.
  - **Android:** reconnect after reboot or update, a battery-optimisation prompt.
  - **Release tooling:** an install script.
- **Left:**
  - Test everything on the real phone and fix what that finds.
  - Move to targetSdk 37 with `ACCESS_LOCAL_NETWORK` onboarding.
  - An accessibility pass with VoiceOver and TalkBack.
  - Multi-phone support, and per-address throttling of pairing attempts.
  - Developer ID notarization, if you ever share the Mac app.
  - Recheck Google's sideloading verification before it goes global in 2027.

## Calls and SMS (investigated, deliberately not built)
| Feature | Verdict |
|---|---|
| Caller ID / new SMS on the Mac | Works today, as mirrored notifications (allow your Phone and Messages apps) |
| Answer or decline calls from the Mac | Possible with `ANSWER_PHONE_CALLS`; needs its own design and security review |
| Read and send SMS | Restricted permissions; sensitive. Not built |
| RCS messages | Not available to third-party apps |
| Talking or listening to calls on the Mac | **Not possible:** macOS can't act as a phone's hands-free device, and Android doesn't give apps call audio |
