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

## D14. compileSdk 37, targetSdk 36 — 2026-10-20
**Why:** current AndroidX Compose libraries require compiling against API 37. Compiling against newer APIs doesn't change runtime behaviour; the target stays 36 (see D9).

## D15. Android build output outside the project folder
**Why:** Gradle's test runner couldn't load test classes from a path containing an apostrophe (`M'AND`). When the path contains one, build output goes to `~/.mand-build/`. Renaming the project folder would also fix this; we chose not to touch your folder.

## D16. Android toolchain without Android Studio
**Why:** you allowed me to do the setup. The JDK, SDK command-line tools and Gradle were downloaded from official sources, checksum-verified, and installed into your home folder only. It's about 2 GB instead of 10+ GB. Android Studio can be added later and reuses the SDK.

## D17. Feature negotiation through `hello.features`
**Why:** new features are added without bumping the protocol version. Each side only uses features the other announced, and older apps ignore unknown messages.

## D18. File transfer over the main connection, one transfer at a time
**Why:** it reuses the already-pinned TLS session, so there's no second port or certificate exchange.
- An 8-chunk window keeps the link responsive for pings.
- Partial files are keyed by SHA-256 and size, so an interrupted transfer resumes even after reconnecting.

**Revisit if:** speed on large files disappoints in real-phone tests.

## D19. Partial downloads in Application Support, not Downloads
**Why:** touching a privacy-protected folder at launch made macOS show a prompt that froze startup. Partial files now live in `~/Library/Application Support/M’AND/Partial`, and only finished files move to the chosen folder.

## D20. scrcpy is found, not bundled
**Why:** bundling it means redistributing scrcpy and its adb, with licence and update duties. You install it once; M’AND finds it in Homebrew or Applications, or wherever you choose. Mirroring is view-only unless you opt into control.

## D21. Swift↔Java interop test
**Why:** the riskiest unknown was whether Apple's TLS and Java's TLS agree on mutual P-256 certificate authentication. A test-only Swift server and a Kotlin JSSE client prove it on the Mac before a phone is involved.

## D22. The continuity layer is one append-only event log — 2026-11-12
Context Engine, Task Capsules, Time Machine, Anywhere sync and Anticipate all need the same thing: **a trustworthy history of what happened, on which device, in what order.** So everything is built on a single local **context log** of immutable events (`capsule.created`, `item.added`, `note.edited`, `action.completed`, …). Current state is a deterministic *fold* of the log.
- **Time Machine** = fold up to any moment, and diff two moments. **Restore and undo append new events**; history is never rewritten, so nothing is silently overwritten.
- **Sync (Anywhere)** = exchange missing events, tracked by a per-device version vector. Events are idempotent; order is by (Lamport clock, device id).
- **Conflicts:** scalar fields are last-writer-wins by that order; collections are add/remove sets where the latest event per item wins. This is a small op-based CRDT, just enough for capsules. Concurrent edits that both change the same field within one sync gap are recorded as a **conflict** the UI can show, never silently dropped.
- **Shared reducer:** the fold is implemented in Swift (`MandContext`) and Kotlin (`:core`) and checked against shared vectors (`protocol/vectors/context-v1.json`), exactly like the network protocol.

**Why not a full CRDT library:** capsules are small, mostly single-writer documents. A ~300-line reducer that both languages share and test identically is easier to verify than a dependency.

## D23. Local databases
- **Mac:** SQLite through the system `SQLite3` module, with no new dependency. Built-in FTS5 handles Personal Brain search; WAL mode; migrations via `PRAGMA user_version`.
- **Android:** Room 2.8 (KSP) with FTS4 (Room's supported full-text index) and versioned migrations.
- **Same logical model:** both store the same events; derived tables are rebuildable caches.

## D24. Personal Brain without AI first
- Full-text search (FTS5/FTS4) over capsule titles, notes, URLs, file names and **indexed document text** (plain text, Markdown and PDF via PDFKit on Mac).
- **Relationships** are explicit (an item in a capsule, a tag) or **inferred** (shared tag, same web domain, same file); inferred ones are labelled as such.
- **Semantic search and summaries** are added only when a local model is available (D25), always labelled "AI-generated".

## D25. Local AI = Ollama on the Mac, optional
- **Runtime:** M’AND talks to Ollama's local HTTP API (`127.0.0.1:11434`) when it is installed. It discovers models, health-checks them, and lets the user pick one.
- **Phone:** the phone asks the Mac over the existing encrypted link. It never runs large models itself, and nothing goes to the internet.
- **Without AI:** every feature works without AI; AI only adds summaries, grouping suggestions, natural-language search and Delegate planning.
- **Hardware:** the GTX 1650 PC isn't assumed.

## D26. Delegate runs a fixed tool registry, never a shell
The agent can only call registered tools (create capsule, add items, group links, find unfinished work, move files into a folder, summarise). Each tool declares whether it reads or **changes** data; changing tools require explicit approval of the exact plan, and every run is recorded with its real outcome. There is no arbitrary shell or network tool.

## D27. Screen mirroring over Wi-Fi uses MediaProjection + H.264
For the "Mirror" module the phone captures its screen with MediaProjection (system consent dialog every session), encodes it with the hardware H.264 encoder, and streams it inside the existing pinned TLS link. The Mac decodes it with VideoToolbox. scrcpy over USB stays as the alternative. Remote control uses an Accessibility service the user enables explicitly; it is off by default.

## Open decisions
- **Real-phone test:** everything in TESTING.md's checklist.
- **Distribution:** personal sideloading for now. Google's developer verification for sideloaded apps rolls out globally in 2027; recheck the free "limited distribution" option before then.
- **Android 17 target:** design the `ACCESS_LOCAL_NETWORK` onboarding (Milestone 6).
