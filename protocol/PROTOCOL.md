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
| `v` | Integer ≥ 1 (a JSON integer: `1.0`, `"1"` and `true` are malformed). The protocol version the sender is speaking. |
| `type` | Non-empty string, at most 64 bytes, `[a-z0-9._]`. |
| `id` | Non-empty string, at most 64 bytes. Unique per message (UUID recommended). |
| `ts` | Integer, sender's Unix time in milliseconds. For information only, never trusted for security. |
| `body` | JSON object (may be `{}`). |

**String limits are measured in UTF-8 bytes**, so both apps count them the same way: `name` ≤ 128, `app` ≤ 32, `proof` ≤ 128, `ref` ≤ 64, `reason`/`code` ≤ 64, error `message` ≤ 512, `text` 1–16,384. Strings must not be empty.

**Unknown `type` values must be ignored** (logged, not fatal). This lets newer apps add messages without breaking older ones.

### Message types (v1)

| type | direction | body | notes |
|---|---|---|---|
| `hello` | both | `{name, platform, minVersion, maxVersion, app, features?}` | First message each side sends. `platform` is `"mac"` or `"android"`. |
| `pair.request` | phone → Mac | `{proof}` | Only when not yet paired. See §4. |
| `pair.result` | Mac → phone | `{accepted, reason?}` | `reason` is an error code when rejected. |
| `session.ready` | Mac → phone | `{}` | The peer is trusted; normal messages may flow. |
| `ping` | both | `{}` | |
| `pong` | both | `{ref}` | `ref` = the `id` of the ping. |
| `text` | both | `{text}` | Text message, 1–16,384 UTF-8 bytes. |
| `bye` | both | `{reason}` | `reason`: `"unpaired"`, `"shutdown"`. After `"unpaired"` the receiver forgets the sender. |
| `error` | both | `{code, message?}` | See §7. The sender usually closes after it. |

Before `session.ready`, the Mac only accepts `hello` and `pair.request`. Anything else is an error, `not_paired`.

## 3a. Feature messages (added for Milestones 2–4)

These are new message types under protocol version 1. Older apps ignore them, as required by §3. Each side lists the features it supports in an optional `hello.features` array: up to 32 strings, each at most 32 bytes, using `[a-z0-9._]`. A side only sends feature messages that the peer advertised. Feature messages are only valid after `session.ready`.

| feature | messages |
|---|---|
| `file.v1` | `file.offer`, `file.accept`, `file.reject`, `file.chunk`, `file.ack`, `file.done`, `file.result`, `file.cancel` |
| `clipboard.v1` | `clipboard.text` |
| `device.v1` | `device.status` |
| `notifications.v1` | `notification.posted`, `notification.removed`, `notification.dismiss` |
| `calls.v1` | `call.state`, `call.action` |
| `tap.v1` | `tap.grab`, `tap.light`, `tap.seen`, `tap.result`, `tap.knock`, `tap.decline` |
| `find.v1` | `find.ring`, `find.stop`, `find.state` |
| `link.v1` | `link.open` |

`device.v1` also carries `device.info` (added in 0.5; older Macs ignore it as an unknown type).

### File transfer (`file.v1`)

`tid` is the transfer ID: 1–64 bytes of `[A-Za-z0-9_-]`, chosen by the sender.

| type | direction | body |
|---|---|---|
| `file.offer` | sender → receiver | `{tid, name, size, sha256}` |
| `file.accept` | receiver → sender | `{tid, offset}` |
| `file.reject` | receiver → sender | `{tid, reason}` |
| `file.chunk` | sender → receiver | `{tid, offset, data}` |
| `file.ack` | receiver → sender | `{tid, received}` |
| `file.done` | sender → receiver | `{tid}` |
| `file.result` | receiver → sender | `{tid, ok, reason?}` |
| `file.cancel` | either | `{tid, reason}` |

Field rules:
- **`name`:** a relative path of 1–1024 bytes, using `/` between folders. The receiver **always** cleans it with the safe-file-name rules below and never trusts it as a path.
- **`size`:** a byte count from 0 to 2^40.
- **`sha256`:** 64 lowercase hex characters.
- **`offset`:** where to start, from 0 to `size`. The receiver uses it to resume a partially received file.
- **`data`:** base64url without padding, decoding to 1–196,608 bytes (192 KiB).
- **`reject` reasons:** `already_exists` (an identical file is already there), `too_large`, `no_space`, `invalid_name`, `busy`, `disabled`.

How a transfer runs:
1. **Sending:** chunks must arrive in order, with `offset` equal to the bytes received so far. The sender keeps at most **8 chunks** un-acknowledged.
2. **Checking:** after `file.done`, the receiver checks the size and SHA-256. If they match, it moves the file into place under a **new, non-clashing name** (`name (2).ext`) and replies `file.result{ok:true}`. Otherwise it deletes the data and replies `ok:false, reason:"integrity"`.
3. **Interruptions:** if the connection drops, the receiver keeps the partial data, keyed by `sha256` and `size`. The sender offers the file again after reconnecting, and the receiver answers with the resume `offset`.

**Safe file names.** Both apps implement this identically and test it against `vectors.fileNames`:
1. Split the path on `/` and `\`.
2. For each component:
   - remove every code point in Unicode categories Cc and Cf (control, format and direction-override characters);
   - replace `:` with `_`;
   - trim ASCII spaces from both ends;
   - drop the component if it's now empty or `.`;
   - if it's `..`, **reject the whole name** (path traversal);
   - if it starts with `.`, replace that first `.` with `_`;
   - if it's longer than 255 UTF-8 bytes, keep the extension (the text after the last `.`, if that is at position > 0 and ≤ 16 bytes long) and cut the rest down, by whole code points, until it fits.
3. The result must have 1–32 components; otherwise reject the name.
4. **Unique names:** `stem.ext` becomes `stem (2).ext`, `stem (3).ext`, and so on. A name without an extension becomes `name (2)`.

### Clipboard (`clipboard.v1`)
`clipboard.text {text}` carries 1–262,144 UTF-8 bytes and is sent **only after a deliberate user action**, or after the user turns on an explicit auto-send option on the Mac. The receiver applies it only if the user enabled clipboard sharing there. Apps must not send content that the source marks as sensitive or concealed.

### Device status (`device.v1`)
`device.status {battery, charging}`: battery is an integer from 0 to 100; charging is a boolean. The phone sends it when connected and whenever either value changes.

### Phone details (`device.info`, part of `device.v1`)

`device.info {model, os, storageFree, storageTotal}`, phone → Mac, sent on connect:
- **`model`:** 1–128 bytes, for example "Pixel 7a".
- **`os`:** 1–64 bytes, for example "Android 16".
- **Storage fields:** integers from 0 to 2^50 bytes.

### Find my phone (`find.v1`)

| type | direction | body |
|---|---|---|
| `find.ring` | Mac → phone | `{}`: play a loud sound (alarm volume, so it's heard on silent) and vibrate |
| `find.stop` | Mac → phone | `{}`: stop |
| `find.state` | phone → Mac | `{ringing}`: boolean, sent when the sound starts and stops |

The phone stops by itself after 60 seconds, or when the user presses Stop on the phone.

### Links (`link.v1`)

`link.open {url, title?}`, either direction, sent only after a deliberate user action (Share → M’AND, or "Open Link on Phone").

- **`url`:** 1–2,048 bytes. It must start with `http://` or `https://` (any case) and have a non-empty host. Control characters and spaces are not allowed.
- **Everything else is rejected as `malformed`.** This includes `file:`, `javascript:`, `intent:` and custom app schemes, so a paired device can only ever open web pages.
- **`title`:** optional, at most 256 bytes.

**Receivers:**
- **Mac:** opens the link in the default browser, or puts it on the clipboard (a setting).
- **Phone:** shows a notification that opens the link when tapped. Android doesn't allow opening pages from the background.

### Tap to Send (`tap.v1`)
Touch the phone to the MacBook's notch to send what's on its screen. Adapted from TapDrop's light key (MIT, github.com/0x1p0/TapDrop): the Mac's ambient light sensor must see the phone's own screen turn white and then black, on cue.

| type | direction | body |
|---|---|---|
| `tap.knock` | phone → Mac | `{}`: the phone's proximity sensor says it was just put against something |
| `tap.grab` | Mac → phone | `{round, dark}`: start a light key (`round` ≥ 1; `dark` = the room is dark) |
| `tap.decline` | phone → Mac | `{round, why}`: not now (e.g. `paused-app`, `locked`, `off`) |
| `tap.light` | phone → Mac | `{round, on}`: the screen is now full-brightness white (`on: true`) or black (`on: false`) |
| `tap.seen` | Mac → phone | `{round}`: the notch saw the white; turn black now |
| `tap.result` | Mac → phone | `{round, ok, why?}`: `ok` → send the screen's content over `file.v1` / `clipboard.v1`; otherwise `why` (≤64 bytes) |

Rules:
- One round at a time.
- A phone sends nothing for a round unless it got `tap.result{ok:true}` for it.
- The Mac judges the light: white − black ≥ 45 % of this phone's learned contact level, and in a lit room the black phone must block the room light.

### Calls (`calls.v1`)
| type | direction | body |
|---|---|---|
| `call.state` | phone → Mac | `{state, caller?}`: `state` is `ringing`, `active` or `idle`; `caller` (≤128 bytes) is a display name or number when known |
| `call.action` | Mac → phone | `{action}`: `answer` or `decline` (declining an active call hangs it up) |

The phone sends `call.state` on every change of phone state, and only if the user turned on calls on the Mac. The call audio always stays on the phone.

### Notifications (`notifications.v1`)
| type | direction | body |
|---|---|---|
| `notification.posted` | phone → Mac | `{key, app, appName, title?, text?, time}` |
| `notification.removed` | phone → Mac | `{key}` |
| `notification.dismiss` | Mac → phone | `{key}` |

Limits:
- `key` and `app`: at most 256 bytes.
- `appName`: at most 128 bytes.
- `title`: at most 512 bytes.
- `text`: at most 4,096 bytes. Senders truncate.
- `time`: Unix milliseconds.

The phone only sends notifications from apps the user allowed.

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
