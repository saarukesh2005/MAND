# Testing and verification status

Nothing below says "verified" unless it was actually run. Last updated: 2026-10-19.

## Status report

| Area | Implemented | Built | Automated tests | Real hardware | Notes |
|---|---|---|---|---|---|
| Protocol core (Swift `MandCore`) | ✅ | ✅ | ✅ pass | n/a | 19 tests in 6 suites, plus 59 shared vector cases |
| Mac TLS server + pairing (`MandMacKit`) | ✅ | ✅ | ✅ pass | Mac only | 13 tests (real TLS on localhost) |
| Mac app UI + app bundle | ✅ | ✅ | ⬜ none yet | ✅ launches | Listens on 47821, TLS 1.3, Bonjour advertised |
| Protocol core (Kotlin `:core`) | ✅ | ⬜ | ⬜ not run | n/a | Needs a JDK (Android Studio) |
| Android app | ✅ | ⬜ | ⬜ | ⬜ | Needs Android Studio + phone |
| Phone ↔ Mac end-to-end | — | — | — | ⬜ | **Not yet verified** |

## How to run

```bash
scripts/test-mac.sh                       # all Mac tests
cd android && ./gradlew :core:test        # Kotlin protocol tests (after setup)
```

## What the automated tests cover

**Shared vectors** (`protocol/vectors/protocol-v1.json`, used by both Swift and Kotlin):
- **Framing:** single and back-to-back frames, partial frames, zero length, over-limit length.
- **Envelopes:** every message type; unknown types ignored; extra fields ignored. Rejected as malformed:
  - not JSON, or a JSON array
  - missing or empty `type`, or `type` with illegal characters
  - version `0`, `"1"`, `1.0` or `true`
  - bad `id`, or `body` that isn't an object
  - hello/text/pong/pair.result missing required fields
  - wrong types
  - byte-length limits (exactly at the limit is accepted; one over is rejected)
- **Version negotiation:** match, overlap, no overlap.
- **Pairing proof:** a known-good HMAC vector, and the same proof with fingerprints swapped is rejected.
- **QR invitation:** a valid code (including a curly apostrophe in the name). Rejected: wrong scheme, short fingerprint, missing or short secret, bad port, no hosts, unsupported version.

**Swift behaviour tests:**
- framing across many reads; payload limits
- every message round-trips
- strict integer parsing
- **pairing window:** single use, 5-minute expiry, 3-attempt limit, proof bound to the phone certificate
- secret randomness; backoff schedule; 45 s liveness rule; UTF-8-safe truncation

**Mac integration tests** (real Network.framework TLS 1.3 on 127.0.0.1, throwaway keychain):

| Scenario | Result |
|---|---|
| Pair with approval, then text both ways | ✅ |
| Unpaired phone with no pairing window is refused | ✅ |
| Wrong proof is rejected, nothing stored | ✅ |
| Proof made for another certificate (man-in-the-middle) is rejected | ✅ |
| User clicks "Don't Allow": rejected, nothing stored | ✅ |
| Phone refuses a Mac whose certificate doesn't match the QR code | ✅ |
| Paired phone reconnects without pairing again | ✅ |
| Forgotten phone is told, disconnected and refused next time | ✅ |
| `text` before pairing completes closes the connection | ✅ |
| Pairing still works when Allow is clicked 3 s later (regression for a review finding) | ✅ |
| Frame over 4 KiB before pairing → `too_large` and closed | ✅ |
| More than 4 half-open connections from one address are refused | ✅ |
| Phone names are cleaned of control/direction-override characters | ✅ |

Not yet automated: the 45-second timeout against a real stalled peer (the rule itself is unit-tested), and a mismatched protocol version over a live connection (negotiation is unit-tested).

## Manual checks done on this Mac (2026-10-19)
- `dist/M’AND.app` builds and is signed by "M’AND Local Dev" with bundle ID `dev.mand.mac`.
- The app launches and listens on TCP 47821.
- `openssl s_client -tls1_3` sees TLSv1.3 with the Mac's self-signed certificate.
- A client **without** a certificate is refused during the handshake (TLS alert 116, "certificate required").
- `dns-sd -B _mand._tcp` shows "SAARUKESH’s MacBook Air".
- No test keys are left in the login keychain. (An early test run leaked 9 test keys into it; they were removed and the code fixed so tests only use a temporary keychain.)

## Real-phone acceptance checklist (Milestone 1) — not yet run
1. Install the APK; open M’AND; tap **Pair with Mac**; scan the QR code.
2. The Mac asks "Allow …?" and the phone's security code matches; click **Allow**. Both show "Connected".
3. Send a test message each way.
4. Turn the phone's Wi-Fi off: within 45 s the Mac shows "not connected". Turn it on: it reconnects by itself.
5. Quit and reopen the Mac app: the phone reconnects without re-pairing.
6. Put the Mac to sleep and wake it: the phone reconnects.
7. Lock the phone for 10 minutes: still connected (or reconnects promptly).
8. **Forget** on the Mac: the phone shows "removed" and can't reconnect. Pair again, then **Forget** on the phone: the Mac removes it.
9. Scan an expired QR code (wait 5 min): the phone shows a clear "expired" message.
10. Deny Local Network on the Mac (System Settings): the Mac stays reachable by IP. Note what happens to discovery.

## Known bugs / limitations
- The Android build hasn't been compiled yet; expect a round of fixes once Android Studio is installed.
- The Mac app has no automated UI tests yet.
- Mac notifications for incoming test messages aren't implemented; messages appear in the window.
- Only one phone can be connected at a time (see SECURITY.md).
