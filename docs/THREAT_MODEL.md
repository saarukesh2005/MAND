# Threat model

Scope: M’AND 0.3.0, the Mac app and Android app, on a home or office Wi-Fi network. This is a living document. It's an engineering self-assessment, **not** a professional audit.

## Assets
1. **Device identity keys:** Mac Keychain; Android Keystore, non-exportable.
2. **Trust list:** which phones the Mac accepts (Keychain), and which Mac the phone accepts (DataStore).
3. **User content in transit:** files, clipboard text, notification contents, caller names, test messages.
4. **The user's files on disk:** the download folder and everything outside it.
5. **Phone control:** answering or ending calls, and dismissing notifications.
6. **Availability:** the connection staying up; the UI not being flooded.

## Trust boundaries
- **LAN ↔ Mac TLS port (47821):** reachable by every device on the network.
- **LAN ↔ Quick Share port** (random; only while Quick Share is on, advertised to everyone on the network).
- **Paired phone ↔ Mac session:** authenticated, but the peer could be compromised.
- **Other Android apps ↔ M’AND:**
  - the Share sheet activity (exported)
  - the notification listener and Quick Settings tile (system-bound)
- **USB/ADB ↔ phone** (screen mirroring, only when the user enables USB debugging).

## Attackers and mitigations
| # | Attacker / scenario | Mitigations | Residual risk |
|---|---|---|---|
| T1 | **Eavesdropper on Wi-Fi** | TLS 1.3 on every M’AND connection; Quick Share uses UKEY2 + AES-256-CBC + HMAC-SHA256 | Metadata visible: that two devices talk, packet sizes and timing |
| T2 | **Impersonates the Mac** to a paired phone | Phone pins the Mac's SHA-256 certificate fingerprint (from the QR code); TLS fails otherwise (interop test) | None known |
| T3 | **Impersonates a phone** to the Mac | Mac requires a client certificate and pins its fingerprint; unknown phones only reach `hello`/`pair.request` while a pairing window is open | — |
| T4 | **Pairs itself** without the user | Needs the QR secret (256-bit, single use, 5 min) **and** the user clicking Allow; the proof is bound to both live certificates | Someone who photographs the QR and is approved by mistake. The Allow dialog shows the phone's security code to compare |
| T5 | **Pairing spam** / brute force | 10 attempts per window; 3 wrong proofs per address → 60 s cooldown; caps of 16 pending connections and 4 per address; 15 s handshake timeout | Spoofed source addresses can still close a pairing window (nuisance only) |
| T6 | **Malformed protocol messages** | Strict JSON schema; byte limits; 4 KiB frames before pairing, 1 MiB after; unknown types ignored; violations close the connection. 70+ shared vectors in two languages | — |
| T7 | **Malicious file names** (traversal, symlinks, zero-width tricks) | Shared `SafeFileName` rules on Unicode scalars; `realpath` containment check at write time; unique names, never overwrite; partial files kept outside the visible folder | Regression tests cover the known attacks |
| T8 | **Disk/memory exhaustion by a paired peer** | Free-space reservation across in-flight transfers; ≤4 concurrent incoming; chunk ≤192 KiB, 8-chunk window; partials cleaned after 7 days | A malicious *paired* phone can fill the disk up to the safety margin. Pair only your own phones |
| T9 | **Quick Share sender** (anyone on the Wi-Fi while it's on) | Off by default; every transfer needs Accept with a PIN shown; nothing is written before consent; names sanitised; limits of 500 files, 1 TiB per file, free space, 8 connections, 8×5 MiB buffers; links never auto-opened (http/https only, shown with a button); no crash on bad crypto | Consent prompts can be spammed while it's on (turn it off). The unofficial protocol may change |
| T10 | **A paired Mac acts on calls** | Calls on Mac is opt-in, off by default, with runtime Phone permissions; only `answer`/`decline`; `answer` only acts while ringing | A compromised paired Mac could end an active call |
| T11 | **Another Android app abuses M’AND** | Share sheet accepts only `content://` URIs (no `file://` into M’AND's private files); the listener and tile are protected by system bind permissions; other components aren't exported | A malicious app can still *offer* content to the Share sheet. M’AND sends only what the user explicitly shared |
| T12 | **Clipboard leaks** | Off by default; Mac skips concealed/transient pasteboard types; Android honours `EXTRA_IS_SENSITIVE`; phone→Mac sends need a deliberate action; no history; never logged | Content the source app doesn't mark as sensitive is sent if the user sends it |
| T13 | **Notification content leaks** | Off by default; per-app allow-list; Android 15+ redacts one-time codes; never logged; cleared on disconnect | Allowed apps' content is visible on the Mac screen |
| T14 | **Stolen or unlocked device** | Keys are in OS secure storage; Android pairing data is excluded from backups | Anyone using the unlocked device can use M’AND (OS-level protection is assumed) |
| T15 | **Screen-mirroring control** | View-only by default; control is an explicit setting; requires USB debugging, which the user enables | USB debugging itself is powerful. Turn it off when not mirroring |
| T16 | **Supply chain** | Few dependencies, all maintained and permissively licensed; versions pinned (`Package.resolved`, version catalog); toolchain downloads verified by checksum | No automated vulnerability scanning yet |

## Known gaps (tracked in SECURITY.md)
- No professional security audit.
- Quick Share consent prompts aren't rate-limited.
- A compromised paired phone or Mac is trusted until forgotten.
- Debug-key signing is used for personal distribution (see RELEASE_CHECKLIST.md).
