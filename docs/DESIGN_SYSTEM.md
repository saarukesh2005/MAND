# M’AND design system

*Your phone. Your Mac. One ecosystem.* Calm, premium and practical. Every visible element shows real state or performs a real action.

The source of truth in code:
- **Mac:** `mac/Sources/MandMac/Views/Theme.swift` (tokens) and `Components.swift`
- **Android:** `android/app/src/main/kotlin/dev/mand/android/ui/Theme.kt` (`MandTheme`, `Space`, `MandCard`)

## Colour
| Token | Light | Dark | Use |
|---|---|---|---|
| Accent (mint) | `#2E9E73` (Android `#2FA878`) | `#5CD69E` | Connected state, primary buttons, progress |
| Caution | `#CC7819` | `#FFA84D` | Warnings, failed transfers |
| Critical | `#C4452F` | `#FF8A73` | Destructive actions, low battery, permission problems |
| Surface | white | `#1C1F24` | Cards |
| Raised surface | `#F5F7FA` | `#262A30` | Tiles, chips, banners |
| Background | system window (Mac) / `#F7F8FA` | `#111317` | App background |
| Hairline | primary at 8% | primary at 8% | Card borders |

**Rules:**
- **One accent only.** No gradients, glows or decorative 3-D.
- **Status colour is never the only signal.** Every state also has words, such as a chip ("CONNECTED") or a label.
- **Android uses fixed colours** (dynamic colour off), so M’AND looks the same on every phone and matches the Mac.

## Typography
| Role | Mac | Android |
|---|---|---|
| Hero (device name) | SF 26 semibold | `headlineMedium` semibold |
| Title | `title3` semibold | `titleLarge` semibold |
| Section | `headline` | `titleMedium` semibold |
| Body | `body` | `bodyMedium` / `bodyLarge` |
| Caption / status chip | `caption` semibold, uppercase | `labelSmall` semibold, uppercase |
| Numerals (battery) | SF Rounded, monospaced digits | — |

Text uses system fonts and scales with the user's text size: Dynamic Type on Mac, font scale on Android.

## Spacing and shape
- **Spacing:** a 4-pt grid of `4 · 8 · 12 · 16 · 24 · 32`. That's `Theme.Space.xs…xxl` on the Mac and `Space.XS…XL` on Android.
- **Radii:** 8 (small), 12 (tiles), 18 (cards).
- **Depth:** cards use one hairline and a very soft shadow on Mac, tonal elevation 1 on Android. No stacked shadows.
- **Touch targets:** at least 48 dp on Android (Material defaults). Mac controls use `.large` size for primary actions.

## Components
| Component | Purpose | Mac | Android |
|---|---|---|---|
| **Status hero** | "Is my phone connected, and what do I do now?" Avatar, status chip, device name, one-line explanation, and at most one fixing action | `PhoneHero` | `StatusHero` |
| **Device avatar** | Phone glyph in a soft circle; mint ring when connected | `DeviceAvatar` | (in `StatusHero`) |
| **Battery ring** | Circular gauge with %; bolt when charging; grey with "last known" when older than 10 min; red at ≤15% when not charging | `BatteryRing` | — |
| **Device switcher** | Chips to choose which phone actions go to (only shown with 2+ phones) | `DeviceSwitcher` | — |
| **Call banner** | Ringing call, with Answer / Decline; states that audio stays on the phone | `CallBanner` | — |
| **Card** | Section container with optional title/subtitle | `Card` | `MandCard` |
| **Feature tile** | Feature plus real status (Ready / Connect your phone / Off / Not set up) | `FeatureTile` | Feature cards |
| **Transfer row** | Direction, name, phone, progress, speed (only when measured), state, and a contextual action | `TransferRow` | `TransferRow` |
| **Permission card** | Explains *why* before asking; one action | `TroubleshootingCard` / onboarding | `SetupCard`, permission states |
| **Empty state** | Icon, one sentence and the next step | `ContentUnavailableView` | Card with steps |

## States every screen handles
Loading/starting, connected, not paired, waiting/looking, resting (many failures), offline, permission needed, paused, error (with a recovery action), and empty. Placeholder data and fake progress are not allowed. Speed is shown only once real samples exist.

## Motion
- **Animate only state changes:** connection appearing, the onboarding page, phone list changes. Use about 0.3 s "smooth" curves.
- **Reduce Motion:** `stateAnimation(_:)` on Mac honours it; Compose defaults honour system animation scales.
- **Indefinite motion:** only the busy spinner while looking or pairing, and the pulse on a ringing-call icon.

## Icons
SF Symbols on Mac and Material Icons (outlined) on Android, at matching meanings: phone, laptop, bell, clipboard, battery, phone-call, radio waves for Quick Share. Decorative icons are hidden from screen readers; meaning is always in text.

## Platform-specific decisions
- **Mac:** a sidebar (Home, Files, Notifications, Screen Mirroring, Devices, Activity), a menu-bar extra for glanceable status and quick actions, a standard Settings window (⌘,), and sheets for pairing, approval, onboarding and Quick Share consent.
- **Android:** a single scrolling home with sections, first-launch onboarding, permissions asked only when a feature is switched on, and the Share sheet plus a Quick Settings tile for actions from other apps.

## Accessibility checklist
- Every icon-only control has a label; headings are marked (`.isHeader` / `heading()`).
- The battery ring and status chip expose a full spoken description.
- Colour contrast follows system label colours. The accent is used on large/bold text or with a label beside it.
- **Not yet done:** a full VoiceOver/TalkBack walkthrough on real devices (see TESTING.md).
