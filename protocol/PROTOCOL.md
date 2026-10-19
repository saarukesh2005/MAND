# M’AND Protocol — version 1

This is the single source of truth for how the M’AND Mac app (`MandMac`) and Android app (`MandAndroid`) talk to each other. Both implementations are tested against the shared files in [`vectors/`](vectors/).

## 1. Transport

- **Roles:** the Mac is the **server** (it listens), and the phone is the **client** (it connects).
- **Port:** TCP 47821 by default. If that port is busy, the Mac uses any free port and advertises the real one through Bonjour and the pairing QR code.
- **Discovery:** Bonjour/mDNS service type `_mand._tcp`. The service name is the Mac's display name.
- **Encryption:** TLS 1.3 only, with **mutual authentication**. Both sides present a self-signed P-256 certificate.
- **Trust:** certificate chains are never validated against a CA. Each side accepts the peer only if `SHA-256(peer certificate DER)` equals:
  - a fingerprint it has already paired with, **or**
  - (phone only, during pairing) the Mac fingerprint inside the scanned QR code, **or**
  - (Mac only, while a pairing window is open) any client. That client must then prove it scanned the QR before anything else is accepted (§4).

## 2. Framing

Every message is one **frame**:

```
+----------------------+---------------------------+
| length: UInt32 (BE)  | payload: UTF-8 JSON bytes |
+----------------------+---------------------------+
```

- `length` is the payload size in bytes. It must be between **1** and **1,048,576** (1 MiB).
- A length of 0 is `malformed`. A length over 1 MiB is `too_large`. In both cases the receiver sends `error` and closes the connection.
- Bulk data (files, Milestone 2) will use a separate connection. It never goes in control frames.

## 3. Envelope

```json
{ "v": 1, "type": "text", "id": "5d0c…", "ts": 1760000000000, "body": { "text": "hi" } }
```

| Field | Rule |
|---|---|
| `v` | Integer ≥ 1. The protocol version the sender is speaking. |
| `type` | Non-empty string, at most 64 characters, `[a-z0-9._]`. |
| `id` | Non-empty string, at most 64 characters. Unique per message (UUID recommended). |
| `ts` | Integer, sender's Unix time in milliseconds. For information only, never trusted for security. |
| `body` | JSON object (may be `{}`). |

**Unknown `type` values must be ignored** (logged, not fatal). This lets newer apps add messages without breaking older ones.

### Message types (v1)

| type | direction | body | notes |
|---|---|---|---|
| `hello` | both | `{name, platform, minVersion, maxVersion, app}` | First message each side sends. `platform` is `"mac"` or `"android"`. `name` has at most 64 characters. |
| `pair.request` | phone → Mac | `{proof}` | Only when not yet paired. See §4. |
| `pair.result` | Mac → phone | `{accepted, reason?}` | `reason` is an error code when rejected. |
| `session.ready` | Mac → phone | `{}` | The peer is trusted; normal messages may flow. |
| `ping` | both | `{}` | |
| `pong` | both | `{ref}` | `ref` = the `id` of the ping. |
| `text` | both | `{text}` | Text message, 1–16,384 UTF-8 bytes. |
| `bye` | both | `{reason}` | `reason`: `"unpaired"`, `"shutdown"`. After `"unpaired"` the receiver forgets the sender. |
| `error` | both | `{code, message?}` | See §7. The sender usually closes after it. |

Before `session.ready`, the Mac only accepts `hello` and `pair.request`. Anything else is an error, `not_paired`.

## 4. Pairing

1. The Mac opens a **pairing window** and shows a QR code with an invitation URL:
   ```
   mand://pair?v=1&n=<name>&h=<ip>[,<ip>…]&p=<port>&f=<macFp hex64>&s=<secret b64url>&x=<expiry unix s>
   ```
   - `s` is a fresh random 32-byte secret, base64url-encoded without padding.
   - The window lasts **5 minutes** and allows **3 proof attempts**.
   - The secret is **single-use**: it's destroyed after one successful proof.
2. The phone scans the code and connects to one of the `h` addresses on port `p`. It accepts the TLS connection only if the Mac's certificate fingerprint equals `f`.
3. Both sides send `hello`. The phone then sends `pair.request` with:
   ```
   proof = base64url( HMAC-SHA256( key = secret,
                                   msg = "MAND-PAIR-v1" ‖ phoneFp ‖ macFp ) )
   ```
   - `phoneFp` and `macFp` are the raw 32-byte SHA-256 fingerprints of the certificates **actually used in this TLS session**.
4. The Mac recomputes the proof using the live TLS session's fingerprints and compares in **constant time**. A wrong proof costs an attempt. A secret that's expired, used up or out of attempts is rejected.
5. If the proof is valid, the Mac asks the user **“Allow ‘<name>’ to pair?”**:
   - **Allow:** store `phoneFp` → `pair.result{accepted:true}` → `session.ready`.
   - **Deny:** `pair.result{accepted:false, reason:"pairing_rejected"}` → close.
6. The phone stores `macFp` only after `accepted:true`.

**Why this is safe.** The QR code is shown on your Mac's screen, and only someone who can see it learns `f` and `s`.
- **Pinning `f`** stops anyone from pretending to be the Mac.
- **The proof** binds the secret to both real certificates, so a man-in-the-middle can't reuse it.
- **The approval click** means nothing is trusted silently.

**Typed-code pairing is deliberately not supported.** A short code can be brute-forced offline.

## 5. Version negotiation

Each side sends its `minVersion` and `maxVersion` in `hello`.
- The chosen version is `min(maxA, maxB)`, valid only if it's ≥ `max(minA, minB)`.
- If there's no overlap, send `error{code:"version_unsupported"}` and close.
- Both sides compute the same answer independently.

## 6. Liveness and reconnection

- **Liveness:** each side sends `ping` every **15 s** once the session is ready. A connection with no frame received for **45 s** is considered dead and closed.
- **Reconnection:** the phone reconnects automatically with backoff of 1, 2, 4, 8, 16, then 30 s (capped). The backoff resets after a successful `session.ready`.
- **Reconnect targets, in order:**
  1. The address Bonjour resolves for the paired Mac.
  2. The last address that worked.
  3. A manual IP the user entered.

  Reconnecting never re-pairs. The pinned fingerprints must match.

## 7. Error codes

| code | meaning |
|---|---|
| `malformed` | Frame or JSON didn't follow this spec. |
| `too_large` | Frame length over the limit. |
| `version_unsupported` | No common protocol version. |
| `not_paired` | Peer isn't trusted and no pairing window is open. |
| `pairing_expired` | Pairing window or secret has expired or was already used. |
| `pairing_invalid` | Proof didn't verify. |
| `pairing_too_many_attempts` | Attempt limit reached; the window is closed. |
| `pairing_rejected` | The user clicked “Don't Allow”. |

## 8. Changing the protocol

- **New optional fields or new message types:** keep `v`, and older apps will ignore them.
- **Breaking changes:** raise `maxVersion`, keep supporting the old version for at least one release, and add vectors for both.
