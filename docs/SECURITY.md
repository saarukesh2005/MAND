# Security

M’AND treats security as a feature. This page explains what protects you, what permissions are used and why, and what's still missing. Passing tests doesn't by itself make the app secure; see "Known risks".

## Threat model (Milestone 1)
- **Protected against:** other people and devices on the same Wi-Fi network. They can see traffic, connect to the Mac's port, impersonate either device, or replay old messages.
- **Not protected against:** someone who controls your unlocked Mac or phone, or who can see the Mac's screen while the pairing QR code is shown.

## How it works
| Protection | How |
|---|---|
| Encryption | TLS 1.3 only, on every connection |
| Device identity | Each device generates a P-256 key: Mac login Keychain / Android Keystore (non-exportable). Keys are never in source, Git or backups |
| Who is trusted | Only certificates whose SHA-256 fingerprint was paired. No certificate authorities, no "trust anyone on Wi-Fi" |
| Pairing | QR code carries the Mac's fingerprint and a single-use 256-bit secret (5 min, 10 attempts). The phone proves it saw the QR with `HMAC(secret, phoneFp‖macFp)` bound to the live TLS certificates. Then **you must click Allow** on the Mac |
| Unpaired devices | Rejected during the TLS handshake (no pairing window), or after a failed proof. Nothing but `hello`/`pair.request` is accepted before pairing completes |
| Input validation | Frame size ≤ 4 KiB until paired, ≤ 1 MiB after; QR addresses must be numeric IPs; phone names are stripped of control/direction-override characters before display; strict JSON schema; byte-length limits; illegal types rejected. Any violation sends `error` and closes the connection |
| Forget | Either side can unpair; the session stops being trusted immediately, the other side is told, and the pairing is deleted |
| Flood limits | At most 16 unfinished connections (4 per address); unfinished handshakes are dropped after 15 s; an unanswered approval after 2 min |
| Logs | Activity log records events only (connected, paired, errors), **never message contents** |
| Backups | Android pairing data is excluded from cloud backup and device transfer |

## Permissions and why
**Mac**
- **Local Network** (asked by macOS): needed to advertise M’AND with Bonjour so the phone can find it. If you deny it, the phone can still connect by IP address.
- **Keychain:** stores the Mac's identity and the list of paired phones.

**Android**
| Permission | Why |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Local-network connection to the Mac (no internet servers) |
| `CHANGE_NETWORK_STATE`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` | Keep the link alive in the background (Android 14+ rules) |
| `POST_NOTIFICATIONS` | The required "M’AND connected" status notification (asked with an explanation) |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Opens the system dialog; you decide |
| `CAMERA` (from the scanner library) | Only while scanning the pairing QR code |

Not requested: SMS, contacts, call log, storage, location, accessibility, notification access. Later milestones will explain each new permission before asking.

## Known risks and remaining work
1. **The Android side hasn't been compiled or tested yet.** Its security behaviour is unverified until it is.
2. **Local Network denial:** if denied, discovery fails but connecting by IP works. The UI explains this, but hasn't been tested on a real denial.
3. **Shoulder-surfing during pairing:** anyone who photographs the QR code within its 5-minute window could try to pair. They would still need you to click **Allow**, so only approve phones you recognise and check the security code.
4. **Pre-pairing connections:** while a pairing window is open, the Mac accepts TLS from any client. That client can only send `hello` and `pair.request` (≤ 4 KiB frames) and is dropped after 15 s, so this is a small attack surface during those 5 minutes.
5. **Pairing nuisance:** a device on the LAN can use up the 10 proof attempts and close the pairing window. You would have to show a new QR code. It can't pair or read anything. Per-address throttling is future work.
6. **One phone at a time:** if two paired phones connect, the newer connection replaces the older one, so they may take turns. Multi-phone support is future work.
7. **A failed Keychain save** when forgetting a device is shown as a warning. The device is cut off immediately, but it could be trusted again after a restart. Retry Forget if you see the warning.
8. **Development signing:** the Mac app is signed with a local self-signed identity. That's fine for personal use, but it isn't notarized.
9. **No independent security audit** has been done.

## Review history
- 2026-10-19: an AI security review of the Mac and Android code found no critical issues. One high-severity bug (pairing was cancelled if Allow took more than about a second) and several medium-severity hardening items were fixed the same day, with regression tests.

## Reporting
This is a personal project. Record issues in `docs/TESTING.md` under "Known bugs".
