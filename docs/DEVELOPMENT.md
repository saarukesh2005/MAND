# Development setup

## Mac (works today)

**Needs:** macOS 14+ and Apple Command Line Tools (`xcode-select --install`). Xcode is optional.
**Verified on:** macOS 26.7.1, Apple M4, Swift 6.4 (Command Line Tools).

```bash
scripts/create-dev-signing-cert.sh   # once — creates the "M’AND Local Dev" signing identity
scripts/test-mac.sh                  # run all Mac tests
scripts/build-mac-app.sh             # build dist/M’AND.app (release); add "debug" for a debug build
open "dist/M’AND.app"
```

- **The first build** downloads Apple's `swift-certificates`, `swift-asn1` and `swift-crypto` packages, pinned in `mac/Package.resolved`.
- **On first launch** M’AND creates its identity in your login keychain ("M’AND Device Identity"). macOS may ask about **Local Network** access; choose **Allow** so phones can find the Mac. You can change this later in System Settings → Privacy & Security → Local Network.
- **Quick compile check without packaging:** `cd mac && swift build`.

## Android (needs Android Studio)

1. Install **Android Studio** (free) from <https://developer.android.com/studio>. It includes the Java runtime, the Android SDK and `adb`. Choose the **Standard** setup and skip emulator images; we test on a real phone.
2. In Android Studio choose **Open** and pick the `android/` folder. Let it finish "Gradle sync". It downloads Gradle 9.8.1, and the download is checked against the SHA-256 in `gradle/wrapper/gradle-wrapper.properties`.
3. Generate the command-line Gradle wrapper (`./gradlew`) once. Android Studio doesn't need it, but terminal builds do. Ask Claude Code to do this step: it downloads the Gradle 9.8.1 distribution, checks it against the pinned SHA-256, and runs `gradle wrapper` from it. The project deliberately doesn't contain an unverified wrapper JAR (see DECISIONS.md D11).
4. Build and test:
   ```bash
   ./gradlew :core:test           # shared protocol tests
   ./gradlew :app:assembleDebug   # builds app/build/outputs/apk/debug/app-debug.apk
   ```

### Put it on your phone
1. On the phone, go to Settings → About phone and tap **Build number** 7 times to unlock Developer options.
2. Turn on Settings → System → Developer options → **USB debugging**.
3. Connect the phone by USB and tap **Allow** on the phone.
4. Install the app: `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

## Project rules
- **Protocol:** change `protocol/PROTOCOL.md` and `protocol/vectors/` first, then both implementations. Both test suites must pass.
- **Secrets:** never commit keys, certificates or keystores (`.gitignore` blocks the common types).
- **Mac UI state:** keep it in `AppModel`, built from real events. Don't put placeholder data in UI flows.
