# Release checklist

M’AND 0.3.0 is ready for **personal use** on your own devices. It is **not** ready for public distribution; see "Before sharing with others".

## Every release
- [ ] **Versions bumped:** Mac `AppInfo.version` + `scripts/build-mac-app.sh`; Android `versionCode`/`versionName` + `BridgeClient.APP_VERSION`
- [ ] `scripts/test-mac.sh`: all Mac tests pass
- [ ] `cd android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug`: pass, 0 lint errors
- [ ] `scripts/interop-test.sh`: pass
- [ ] `./gradlew :app:assembleRelease`: R8-minified APK builds
- [ ] `apksigner verify --print-certs`: the certificate SHA-256 matches the installed app (`0290691e…`), otherwise the update won't install
- [ ] `scripts/build-mac-app.sh`: app is signed by "M’AND Local Dev" (`codesign -dv`)
- [ ] **Upgrade test:** install over the previous version on the phone; pairing, settings and history are kept
- [ ] **Real-phone checklist:** run the relevant rows in TESTING.md and record the results
- [ ] **Protocol:** changes are documented in `protocol/PROTOCOL.md` with shared vectors; older apps still work (unknown messages ignored)
- [ ] **Docs:** README, TESTING and ROADMAP match reality
- [ ] **Hygiene:** no secrets, keys or keystores in git (`git ls-files | grep -iE "key|jks|p12|pem"`)

## Release configuration review (done for 0.3.0)
- **Android release build:**
  - `isMinifyEnabled` and `isShrinkResources` are on; the APK is 2.7 MB.
  - No debug-only code paths; `Log` calls contain no user content.
  - `android:allowBackup="false"`, and extraction rules exclude all data.
- **Android manifest:**
  - Every permission is justified in SECURITY.md.
  - Exported components: the launcher, the Share target (content:// only), and the system-bound tile and listener.
- **Mac app:**
  - The test-only `MandInteropServer` target is never packaged; only `MandMac` goes into the .app.

## Before sharing with others (not done)
- [ ] **Android:**
  - Create a dedicated release keystore and back it up; store its password outside git.
  - Switching keys requires users to uninstall once.
  - Publish on Google Play ($25 one-time) or use Google's developer verification for sideloading (global from 2027).
- [ ] **Mac:**
  - Apple Developer ID ($99/year), hardened runtime, notarization and stapling.
  - A DMG installer.
- [ ] **Quick Share:**
  - Decide whether to ship the unofficial feature publicly.
  - Keep it off by default and clearly labelled.
- [ ] **Audit:** an independent security review of the pairing, transfer and Quick Share code.
- [ ] **Legal:** a privacy policy (for a store listing) and THIRD_PARTY_NOTICES in the About box.
- [ ] **Accessibility:** a full VoiceOver and TalkBack pass.
