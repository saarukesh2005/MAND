# Decisions

Each entry records what was decided, why, and what would make us revisit it.

## D1. Build both apps ourselves (not KDE Connect) — 2026-10-19
**Why:** KDE Connect already does much of this, but using it would lock the Android side to its design and naming. Our own apps give full control of security, design and the M’AND brand.
**Cost:** more work on the Android side. **Revisit if:** time to a usable product matters more than control.

## D2. Mac is the server, phone is the client
**Why:**
- The Mac is always on.
- Accepting incoming connections on macOS needs no Local Network permission (only Bonjour advertising does).
- Android restricts background work, so the phone keeps one outgoing connection alive from a foreground service.

## D3. TLS 1.3 with mutual certificate pinning
**Why:**
- It's a standard, audited protocol, built into both platforms.
- There's no need for a certificate authority or any internet service.
- Each device creates its own key, which never leaves its secure storage (Mac Keychain, Android Keystore).

## D4. QR + one-time secret + approval click; no typed codes
**Why:**
- **The QR code** delivers the Mac's fingerprint, which stops anyone impersonating the Mac, and a 256-bit secret, which proves the phone saw the screen.
- **The proof** is bound to both real certificates, which stops a man-in-the-middle.
- **The click** means nothing is trusted silently.

**Rejected alternatives:**
- A 6-digit comparison code made from fingerprints: an attacker can generate keys until the codes match.
- A typed pairing code: a short code can be guessed offline.

**Kept for reconnecting only:** manual IP entry. Pinning still protects it.

## D5. Shared protocol vectors
**Why:** two languages implement the same protocol. One shared file of test cases stops them drifting apart, and both test suites must pass it.

## D6. String limits in UTF-8 bytes
**Why:** Swift and Kotlin count "characters" differently. Bytes are unambiguous.

## D7. Mac app built with SwiftPM and Command Line Tools (Xcode optional)
**Why:** it saves a 10+ GB Xcode install. Three workarounds were needed:
1. **`@State`:** with the macOS 27 SDK, SwiftUI's `@State` is a compiler macro whose plugin ships only with Xcode. App-wide UI state lives in plain `@Observable` objects owned by the `App`.
2. **Tests:** the Command Line Tools' Swift Testing macro plugin can't find its helper libraries. `scripts/test-mac.sh` sets `DYLD_LIBRARY_PATH` and calls the toolchain's `swift` directly, because `/usr/bin/swift` is SIP-protected and drops that variable.
3. **Packaging:** there are no asset catalogs (they need Xcode's `actool`). The icon is drawn by `scripts/make-icon.swift` and packed with `iconutil`.

**Revisit if:** Xcode gets installed. Everything still works with Xcode too.

## D8. Stable self-signed code-signing identity
**Why:** ad-hoc signatures change on every build, so macOS would keep re-asking for Keychain and Local Network access (Apple TN3179). `scripts/create-dev-signing-cert.sh` creates a free "M’AND Local Dev" identity in the login keychain.
**Not suitable for distribution to others.** That needs an Apple Developer ID ($99 a year) and notarization.

## D9. Android minSdk 34, targetSdk 36
**Why:**
- **minSdk 34:** the founder's phone runs Android 14+, so the newer APIs are available (e.g. NSD `registerServiceInfoCallback`).
- **targetSdk 36:** targeting 37 (Android 17) activates the new `ACCESS_LOCAL_NETWORK` runtime permission. We'll move to 37 in Milestone 6 together with proper onboarding for it.

## D10. Foreground service type `connectedDevice`
**Why:**
- It's meant for a persistent link to a paired external device.
- `dataSync` is time-limited (6 h per day) for apps targeting Android 15+.

## D11. Keys never in source or Git
**Why:** every device generates its own identity at first launch. `.gitignore` blocks key and certificate files.
- The signing-certificate script writes temporary files only to a temp folder and deletes them.
- The Gradle wrapper JAR that didn't match Gradle's published checksum was rejected. A verified wrapper will be generated locally once Java is installed.

## D12. REA not used for Milestone 1
**Why:** REA is a reverse-engineering toolkit and can't build apps. **Later use, only on our own builds:**
- inspect the APK's permissions and manifest
- run ADB helpers for real-device QA
- check the Mac app's signature

## D13. Mac `@Observable` UI state instead of `@State` in views
See D7. Screen-local state (selected section, message draft, the device being forgotten) lives in `UIState`.

## Open decisions
- **Distribution:** personal sideloading for now. Google's developer verification for sideloaded apps rolls out globally in 2027; recheck the free "limited distribution" option before then.
- **Android 17 target:** design the `ACCESS_LOCAL_NETWORK` onboarding (Milestone 6).
