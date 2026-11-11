# Development setup

## What's installed on this Mac (2026-10-20)
| Tool | Where | How |
|---|---|---|
| Swift 6.4 + Swift Testing | Apple Command Line Tools | already present |
| JDK 21 (Eclipse Temurin 21.0.12.1, arm64) | `~/.mand-tools/jdk-21.0.12.1+1` | official Adoptium download, SHA-256 verified |
| Gradle 9.8.1 | `~/.mand-tools/gradle-9.8.1` (only used to create the wrapper) | services.gradle.org, SHA-256 verified |
| Android SDK: command-line tools, platform-tools (adb), platforms 36 and 37, build-tools 36 | `~/Library/Android/sdk` | Google's official zip, SHA-1 verified; then `sdkmanager` |

Nothing was installed system-wide and no Homebrew was needed. Android Studio is **optional**: if you install it later, it finds the same SDK. To remove the tools, delete `~/.mand-tools`, `~/.mand-build` and `~/Library/Android/sdk`.

## Mac app
```bash
scripts/create-dev-signing-cert.sh   # once — the "M’AND Local Dev" signing identity
scripts/test-mac.sh                  # all Mac tests
scripts/build-mac-app.sh             # dist/M’AND.app (add "debug" for a debug build)
open "dist/M’AND.app"
```
- **First launch:** M’AND creates its identity in your login keychain. If macOS asks about **Local Network**, choose **Allow**.
- **First file from the phone:** macOS asks once whether M’AND may use your **Downloads** folder (the default save location). Choose **Allow**, or pick another folder in Settings.
- **Why `test-mac.sh` and not `swift test`:** with only the Command Line Tools, Apple's test-macro plugin can't find its own libraries. The script keeps a private copy in `~/.mand-tools/swift-plugins` and loads it explicitly (TECHNICAL_DECISIONS.md D7).

## Android app
```bash
export JAVA_HOME=~/.mand-tools/jdk-21.0.12.1+1/Contents/Home   # scripts do this for you
cd android
./gradlew :core:test           # protocol core + shared vectors
./gradlew :app:assembleDebug   # the APK
./gradlew :app:lintDebug       # Android lint
```
- **Build output** goes to `~/.mand-build/`, not `android/*/build`. Gradle's test runner can't load classes from a folder whose path contains an apostrophe, and this project lives in `M'AND` (TECHNICAL_DECISIONS.md D15). The APK is at `~/.mand-build/_app/outputs/apk/debug/app-debug.apk`.
- **`android/local.properties`** points to the SDK. It's machine-specific and ignored by git.

### Put it on your phone
1. On the phone, go to Settings → About phone and tap **Build number** 7 times.
2. Turn on Settings → System → Developer options → **USB debugging**.
3. Plug the phone into the Mac with a USB cable. Unlock it and tap **Allow** for USB debugging.
4. Run `scripts/install-android.sh`. It builds, installs and opens M’AND, and prints the phone model and Android version.

### First run on the phone
1. Open M’AND on the Mac → **Pair a Phone**. On the phone tap **Pair with Mac**, scan the code, then click **Allow** on the Mac.
2. Allow **notifications** (for the status notification) and **unrestricted battery** when M’AND asks.
3. **Optional features:**
   - **Clipboard sharing:** turn it on in both apps.
   - **Notifications on the Mac:**
     1. Turn the switch on.
     2. Tap **Open Notification access** and allow M’AND. If Android says it's a restricted setting, go to App info → ⋮ → **Allow restricted settings** first.
     3. Tap **Choose apps** and pick the apps to share.
   - **Quick Settings tile:** pull down Quick Settings → edit → add **Clipboard to Mac**.

## Tests across both languages
```bash
scripts/interop-test.sh
```
This starts a test-only Swift server (`MandInteropServer`, never shipped) with a throwaway keychain. It then runs a Kotlin client that uses Java's TLS stack, the same one Android uses, against it with throwaway certificates.

## Project rules
- **Protocol:** change `protocol/PROTOCOL.md` and `protocol/vectors/` first, then both implementations. All test suites must pass.
- **Secrets:** never commit keys, certificates or keystores (`.gitignore` blocks the common types).
- **UI:** show only real state. Don't put placeholder data in user-facing flows.
- **Privacy prompts:** never touch privacy-protected folders (Downloads, Documents, Desktop) at launch. macOS would show an access prompt and block the app.
