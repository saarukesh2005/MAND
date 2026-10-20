# Testing and verification status

Nothing below says "verified" unless it was actually run. Last updated: 2026-10-20.

## Status report

| Area | Implemented | Built | Automated tests | Real hardware | Notes |
|---|---|---|---|---|---|
| Protocol core, Swift (`MandCore`) | ✅ | ✅ | ✅ 21 tests, 7 suites | n/a | Includes all shared vectors |
| Protocol core, Kotlin (`:core`) | ✅ | ✅ | ✅ 16 test methods | n/a | Same shared vectors |
| Mac TLS server + pairing | ✅ | ✅ | ✅ 13 tests | Mac only | Real TLS 1.3 on localhost |
| Mac file transfer | ✅ | ✅ | ✅ 7 tests | Mac only | Two real transfer engines wired back to back |
| Swift ↔ Java/Kotlin TLS interop | ✅ | ✅ | ✅ 4 tests | Mac only | Same TLS stack family as Android, but not the Android app itself |
| Mac app (UI, clipboard, notifications, mirroring launcher, settings) | ✅ | ✅ | ⬜ no UI tests | ✅ launches, listens on 47821, TLS 1.3 | |
| Android app | ✅ | ✅ APK builds | lint: 0 errors | ⬜ | **Not yet run on any phone or emulator** |
| Phone ↔ Mac end-to-end | — | — | — | ⬜ | **Not yet verified** |

## How to run
```bash
scripts/test-mac.sh                       # 41 Mac tests
(cd android && ./gradlew :core:test)      # Kotlin core
scripts/interop-test.sh                   # Swift server ↔ Kotlin client
(cd android && ./gradlew :app:lintDebug)  # Android lint
```

## What the automated tests cover

**Shared vectors** (`protocol/vectors/protocol-v1.json`, run by both Swift and Kotlin):

| Group | Cases | What they check |
|---|---|---|
| Framing | 7 | Single and back-to-back frames, partial frames, zero length, over-limit length |
| Envelopes | 65 | Every message type, including file/clipboard/device/notification messages. Malformed messages, wrong types, byte-length limits (exactly at the limit is accepted, one over is rejected) |
| Version negotiation | 4 | Match, overlap, no overlap |
| Pairing proof | 2 | A known-good HMAC; the same proof with fingerprints swapped is rejected |
| QR invitations | 11 | A valid code; wrong scheme, short fingerprint, bad secret/port/hosts/version; DNS names and bad IPv4 rejected |
| Safe file names | 19 | Traversal (`..`), absolute and Windows paths, hidden names, control and direction-override characters, Unicode, long names, depth limit |
| Unique names | 5 | `a (2).txt`, `a (3).txt`, names without extensions, `.tar.gz` |

**Mac integration tests** (real Network.framework TLS 1.3 on 127.0.0.1, throwaway keychain):
- **Pairing:**
  - pair with approval, then text both ways
  - approval clicked 3 seconds later still works
  - user declines
  - wrong proof
  - proof made for another certificate
- **Refusals:**
  - an unpaired phone with no pairing window
  - the phone refuses a Mac with the wrong certificate
  - text before pairing
  - frames over 4 KiB before pairing
  - more than 4 half-open connections from one address
- **After pairing:** reconnect without re-pairing; a forgotten phone is told, cut off and refused next time
- **Phone names:** cleaned before they're displayed

**Mac file-transfer tests** (two real `FileTransferService`s connected back to back):
- a 1 MB file arrives intact
- folders with nested files and empty files
- a traversal name is rejected, and nothing is written outside the folder
- corrupted data is caught by SHA-256 and not saved
- a 3 MB transfer cut at about 1 MB resumes from the partial file
- an identical file isn't duplicated
- a different file with the same name is saved as `notes (2).txt`, and the original is untouched
- out-of-order chunks cancel the transfer

**Interop** (`scripts/interop-test.sh`): a Kotlin client using Java TLS 1.3 with a P-256 client certificate against the real Swift server.
- **Passes when it should:** pairs (HMAC proof), exchanges text, clipboard and battery messages, reconnects without re-pairing.
- **Fails when it should:** a wrong pinned fingerprint fails the handshake; an unpaired certificate is refused.

## Manual checks on this Mac
- **2026-10-19:**
  - **App:** builds, signed by "M’AND Local Dev" (`dev.mand.mac`).
  - **Network:** listens on 47821, offers TLS 1.3, refuses clients without certificates (alert 116), and is advertised via Bonjour.
- **2026-10-20:**
  - **Launch-freeze fix:** the app now listens immediately after launch. It was blocked by a Downloads privacy prompt before.
  - **Keychain:** no test keys are left in the login keychain.

## Real-phone checklist — not yet run
1. **Install:** run `scripts/install-android.sh`, and note the phone model and Android version.
2. **Pair:** scan the QR code and confirm the security codes match; click Allow. Both apps show Connected, and the Mac shows the battery level.
3. **Test message:** send one each way.
4. **Files, Mac → phone:** drag a photo and a folder onto Files. Each appears in Downloads/M’AND on the phone.
5. **Files, phone → Mac:** in Gallery choose Share → **Send to Mac** with several photos. They appear in ~/Downloads/M’AND.
6. **Resume:** start a large file (over 500 MB), turn Wi-Fi off halfway, then on again. The transfer continues and the file opens.
7. **Clipboard:**
   - Turn it on in both apps; copy on the Mac → Send Clipboard → paste on the phone.
   - Copy on the phone → Quick Settings tile → paste on the Mac.
   - Copy a password from a password manager: it's not sent.
8. **Notifications:**
   - Grant access and allow one app (e.g. Messages); send yourself a message, and it appears on the Mac.
   - Dismiss it on the Mac: it's gone from the phone.
   - A notification from an app you didn't allow doesn't appear.
9. **Reconnect:**
   - Turn the phone's Wi-Fi off: within 45 s the Mac shows not connected. Turn it on: it reconnects by itself.
   - Restart the phone: it reconnects without opening the app.
   - Quit and reopen the Mac app: it reconnects.
   - Lock the phone for 10 minutes: it stays connected, or reconnects promptly.
10. **Mirroring:** install scrcpy and connect by USB → Start. The phone screen appears, view-only. Turn on control and confirm taps work.
11. **Forget:** forget on the Mac; the phone shows "removed" and can't reconnect. Pair again, then forget on the phone; the Mac removes it.
12. **Expired code:** wait 5 minutes and scan the QR code; you get a clear "expired" message.

## Known bugs / limitations
- **The Android app has never run.** Expect a round of fixes during the checklist.
- **One phone at a time:** a second paired phone replaces the first.
- **Downloads prompt:** macOS asks for Downloads access the first time a file arrives (expected, but untested).
- **No UI tests yet:** there are no automated UI tests for either app.
