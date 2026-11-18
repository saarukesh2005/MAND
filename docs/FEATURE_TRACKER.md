# Feature tracker

Statuses: **NOT_STARTED · IN_PROGRESS · IMPLEMENTED · TESTED · BLOCKED**.
- **TESTED** means automated tests passed in this repo (evidence column), or a user report on a real device (marked *device: user*).
- Nothing is TESTED on the strength of compiling alone.

Last updated: 2026-11-18.

## 01 Connect
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Nearby-device discovery (Bonjour / NSD) | TESTED | IMPLEMENTED | `dns-sd` check; device: user |
| QR-code pairing with explicit approval | TESTED | TESTED | BridgeServerTests, interop; device: user |
| Manual IP connection (reconnect) | IMPLEMENTED | IMPLEMENTED | |
| Secure authentication (mutual TLS 1.3, pinning) | TESTED | TESTED | BridgeServerTests, interop |
| Device verification (security code) | IMPLEMENTED | IMPLEMENTED | |
| Persistent cryptographic identity | TESTED | IMPLEMENTED | Keychain / Keystore |
| Trusted devices list | TESTED | IMPLEMENTED | |
| Multiple device support | TESTED | n/a | two-phone tests |
| Device renaming | TESTED | n/a | name kept on the Mac only (Devices → Rename…); AppModelTests.rename |
| Device removal (forget) | TESTED | IMPLEMENTED | |
| Automatic reconnection | TESTED | TESTED | ReconnectPolicy tests |
| Connection history (persisted) | NOT_STARTED | NOT_STARTED | in-memory activity log only |
| Network switching recovery | IMPLEMENTED | IMPLEMENTED | network callback, wake handling |
| Connection diagnostics | IN_PROGRESS | IN_PROGRESS | troubleshooting cards; no diagnostics screen |
| Connection quality (latency) | TESTED | n/a | ping round-trip shown as Excellent / Good / Slow; FriendlyTests, AppModelTests |
| Disconnect controls | IMPLEMENTED | IMPLEMENTED | forget / pause |

## 02 Share
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Files both directions, multiple files | TESTED | IMPLEMENTED | FileTransferTests; device: user |
| Folders | TESTED | n/a | Android has no folder picker for sharing |
| Photos, videos, documents, PDFs, ZIP | TESTED | IMPLEMENTED | type-agnostic byte transfer |
| Drag-and-drop | IMPLEMENTED | n/a | |
| Android Share Sheet | n/a | IMPLEMENTED | |
| Share text / URLs | IMPLEMENTED | IMPLEMENTED | `link.v1`: web links shared to M’AND open on the Mac; Mac → phone via notification; other text → clipboard. Vectors + LinkRulesTest; not run on a phone |
| Transfer queue | TESTED | IMPLEMENTED | |
| Progress and speed | IMPLEMENTED | IMPLEMENTED | |
| Remaining time | TESTED | TESTED | `Friendly.secondsRemaining/timeLeft` (same wording both apps) |
| Pause / resume | IN_PROGRESS | IN_PROGRESS | resume after interruption only |
| Retry / cancel | IMPLEMENTED | IMPLEMENTED | |
| Transfer history (persisted) | IMPLEMENTED | NOT_STARTED | Mac JSON, last 100 |
| Duplicate handling, integrity (SHA-256) | TESTED | IMPLEMENTED | |
| Download destination selection | IMPLEMENTED | NOT_STARTED | Android fixed to Downloads/M’AND |
| Streaming (no whole-file loads) | TESTED | IMPLEMENTED | |
| Quick Share receive (unofficial, extra) | TESTED | n/a | 7 end-to-end tests |

## 03 Clipboard
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Both directions, text | IMPLEMENTED | IMPLEMENTED | device: user |
| Manual sync | IMPLEMENTED | IMPLEMENTED | button, tile, share |
| Automatic sync settings | IMPLEMENTED | BLOCKED | Android forbids background clipboard reads (API 29+); manual options offered |
| Clipboard history (opt-in) | NOT_STARTED | NOT_STARTED | |
| Clear history | NOT_STARTED | NOT_STARTED | |
| Sensitive-content detection | IMPLEMENTED | IMPLEMENTED | concealed types / EXTRA_IS_SENSITIVE |
| Per-device permissions | NOT_STARTED | n/a | |

## 04 Notifications
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Forwarding with app, title, text, time | IMPLEMENTED | IMPLEMENTED | device: user |
| App icon | NOT_STARTED | NOT_STARTED | |
| Per-app filters | n/a | IMPLEMENTED | |
| Notification history (persisted) | NOT_STARTED | NOT_STARTED | |
| Do-not-disturb mode | NOT_STARTED | NOT_STARTED | |
| Dismissal sync | IMPLEMENTED | IMPLEMENTED | |
| Reply from the Mac (`notification.reply` / `notification.replied`) | IMPLEMENTED | IMPLEMENTED | shared vectors (7: canReply, reply, replied, and the malformed cases) + round-trips in both languages. The phone fires the app's own `RemoteInput`, so the app sends the message; only notifications M’AND shared can be answered. Not run on a phone |
| Reply outcome shown on the Mac (Sending… / Sent / why it failed) | IMPLEMENTED | n/a | `AppModel.ReplyState`, cleared when the notification is dismissed or removed |
| Privacy settings | IMPLEMENTED | IMPLEMENTED | off by default |

## 05 Device Hub
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Connected devices, names | TESTED | IMPLEMENTED | AppModelTests |
| Manufacturer / model / OS | IMPLEMENTED | IMPLEMENTED | `device.info`; shown on Mac Home; not run on a phone |
| Battery / charging | TESTED | IMPLEMENTED | device: user |
| Connection quality | TESTED | n/a | see Connection quality (latency) |
| Storage | IMPLEMENTED | IMPLEMENTED | `device.info` free/total storage; not run on a phone |
| Last seen | IMPLEMENTED | n/a | |
| Recent activity / transfer activity | IN_PROGRESS | NOT_STARTED | |

## 06 Mirror
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| scrcpy launcher over USB (view-only default) | IMPLEMENTED | n/a | not tried on hardware |
| Live streaming via MediaProjection over Wi-Fi | NOT_STARTED | NOT_STARTED | |
| Resolution / frame rate / full screen / rotation | NOT_STARTED | NOT_STARTED | |

## 07 Control
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Control via scrcpy (opt-in) | IMPLEMENTED | n/a | |
| Tap / scroll / keyboard / navigation via AccessibilityService | IMPLEMENTED | IMPLEMENTED | tap, swipe/scroll, Back/Home/Recents (`control.v1`); keyboard not started |
| Instant disconnect | NOT_STARTED | NOT_STARTED | |

## 07b Find my phone and accessibility (added 2026-11-12, v0.5.0)
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Find my phone (`find.v1`): alarm-volume sound + vibration, Stop on Mac or phone, auto-stop after 60 s | IMPLEMENTED | IMPLEMENTED | vectors + round-trips; AppModelTests.phoneDetails; sound not yet heard on a real phone |
| Usability pass (Mac): big labelled action tiles, plain-language status, on/off switches on Home, link sheet, rename | IMPLEMENTED | n/a | builds; VoiceOver labels/hints on every tile; announcements for status lines |
| Accessibility pass (Android, WCAG 2.2 AA audit) | n/a | IMPLEMENTED | rows are single switch/checkbox controls (TalkBack), AA contrast mint #0F7A55, scrollable onboarding at 200 % font, wrapping button rows, live-region status, labelled text fields, plain wording, "Open settings" on refused permissions, wrong-QR message |

## 07c Connection reliability and built-in mirroring (v0.6.0, 2026-11-12)
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Keychain prompt can no longer break pairing: listener starts at once; unreadable trusted list → phones asked to retry (never told "not paired"); list never overwritten; "Try Again" card | TESTED | n/a | BridgeServerTests.unreadableTrustedList |
| Reconnect at once when the Mac appears on Wi-Fi / network changes / app opened (backoff resets) | n/a | IMPLEMENTED | builds; emulator run below |
| Pair from the phone's camera app (`mand://pair` link, confirm dialog) | n/a | IMPLEMENTED | |
| Get-the-app QR on the Mac's pairing sheet | IMPLEMENTED | n/a | |
| Built-in Wi-Fi screen mirroring (`screen.v1`, MediaProjection → H.264 → AVSampleBufferDisplayLayer), view only | IMPLEMENTED | IMPLEMENTED | H264Tests (4), shared vectors (10); USB/scrcpy kept as Advanced |
| Control the phone from the Mac (`control.v1`): click = tap, drag = swipe, Back/Home/Recents; only while sharing + Accessibility on | IMPLEMENTED | IMPLEMENTED | vectors (7) + round-trips; AppModelTests.controlScale/controlState |

## 08 Tap to Send (from TapDrop, github.com/0x1p0/TapDrop, MIT — added 2026-11-12)
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Read the notch light sensor (private IOHID API, opt-in) | TESTED | n/a | real sensor read on this Mac (lid closed → 0 lux); MandMacKit Tap tests use a fake sensor |
| Room baseline + DIP / RISE triggers | TESTED | n/a | TapTests (synthetic readings) |
| Light-key judge (white seen → black falls, blocks room light) | TESTED | n/a | 10 judge tests: phone, hand, lamp, too far, dark room, timeouts |
| Learned contact level per phone | TESTED | n/a | ContactLearner test |
| `tap.v1` protocol | TESTED | TESTED | shared vectors + round-trips in both languages |
| Round coordination (grab / seen / result, knock = that phone only) | TESTED | IMPLEMENTED | TapCoordinatorTests; Android side compiles and passes lint, not run on a phone |
| Phone: proximity "knock", white/black flash overlay | n/a | IMPLEMENTED | `tap/TapService.kt`: Accessibility overlay (no draw-over-apps permission); not yet run on a phone |
| Phone: send what's on screen (screenshot; original file; circled text) | n/a | IMPLEMENTED (screenshot only) | AccessibilityService.takeScreenshot → file.v1; original-file and circled-text modes not started |
| SMS one-time codes → Mac clipboard (opt-in, RECEIVE_SMS) | IMPLEMENTED | IMPLEMENTED | `Otp.find` TESTED (3 tests); receiver sends via clipboard.v1; not run on a phone |
| Pause in banking/UPI apps (editable list) | n/a | IMPLEMENTED | default list of 10 UPI/bank apps, editable in the Tap card |
| Readiness both ways (`tap.ready`): each side says whether it is on, so the other can ask the person to switch it on instead of failing a round | IMPLEMENTED | IMPLEMENTED | shared vectors (ok + malformed) + round-trips in both languages; `tapMacReady` on the phone, guided setup in the Tap card |
| Guided setup on the phone (try → allow restricted → turn on, each opening the exact screen) | n/a | IMPLEMENTED | `tap/TapSetup.kt` + `ui/TapGuide.kt`; worked out on Android 17 for apps installed from a file; not run on a phone |
| Notch HUD on the Mac: the round's progress shown at the notch itself | IMPLEMENTED | n/a | `Views/NotchHUD.swift`, driven by `onTapPhase` |
| Buzz on the phone for the outcome: one firm buzz when it sent, two short when it didn't | n/a | IMPLEMENTED | `VibrationEffect` heavy/double click; failure reasons worded the same in both apps |
| Settings toggle + status line (Mac) | IMPLEMENTED | n/a | Settings → Tap to Send (off by default), outcome shown in Home; live lux meter not started |
| Real tap on hardware | BLOCKED | BLOCKED | needs the lid open and the Pixel connected |

## Context Engine
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Activity event log (append-only, Lamport-ordered) | TESTED | TESTED | shared context vectors (9 fold, 18 codec) in both languages |
| Context collection from M’AND events | NOT_STARTED | NOT_STARTED | |
| Context graph (nodes, relationships, tags) | NOT_STARTED | NOT_STARTED | |
| Activity detection (explicit signals) | NOT_STARTED | NOT_STARTED | |
| Ask when unsure | NOT_STARTED | NOT_STARTED | |

## Task Capsules
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Create / edit / delete / archive / duplicate | IN_PROGRESS | IN_PROGRESS | model + reducer done and tested; storage and UI next |
| Files, URLs, notes, screenshots, actions | NOT_STARTED | NOT_STARTED | |
| Progress, timeline, device history | NOT_STARTED | NOT_STARTED | |
| Search / pin | NOT_STARTED | NOT_STARTED | |
| Sync between devices | NOT_STARTED | NOT_STARTED | |
| Resume ("Continue … ?") | NOT_STARTED | NOT_STARTED | |
| Export / import | NOT_STARTED | NOT_STARTED | |
| Version history / restore | IN_PROGRESS | IN_PROGRESS | point-in-time fold, diff, restore and undo tested; UI next |

## Personal Brain
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Full-text search (notes, capsules, URLs, documents) | NOT_STARTED | NOT_STARTED | |
| Document indexing (text/PDF) | NOT_STARTED | NOT_STARTED | |
| Knowledge graph / related content | NOT_STARTED | NOT_STARTED | |
| Semantic / natural-language search (local AI) | NOT_STARTED | NOT_STARTED | |
| Source labels (verified / note / inferred / AI) | NOT_STARTED | NOT_STARTED | |
| Search history, deletion, import/export | NOT_STARTED | NOT_STARTED | |

## Time Machine
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Activity timeline | NOT_STARTED | NOT_STARTED | |
| Snapshots / versions / compare | IN_PROGRESS | IN_PROGRESS | reducer-level, tested |
| Restore preview / selective restore / undo | NOT_STARTED | NOT_STARTED | |
| Retention / delete / export history | NOT_STARTED | NOT_STARTED | |

## Anticipate
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Suggestions with confidence and explanation | NOT_STARTED | NOT_STARTED | |
| Dismiss / feedback / quiet mode / frequency | NOT_STARTED | NOT_STARTED | |

## Anywhere
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Where an activity lives / can continue | NOT_STARTED | NOT_STARTED | |
| Versioned sync with conflict resolution | IN_PROGRESS | IN_PROGRESS | conflict detection in the reducer, tested; `context.v1` sync messages next |
| Restore files / notes / URLs / deep links | NOT_STARTED | NOT_STARTED | |

## Delegate
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Objective → plan → approval → execute → verify → report | NOT_STARTED | NOT_STARTED | |
| Tool registry and permission system | NOT_STARTED | NOT_STARTED | |
| History, cancel, retry | NOT_STARTED | NOT_STARTED | |

## Local AI
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Runtime discovery and health (Ollama) | NOT_STARTED | n/a | Ollama not installed yet |
| Model configuration / switching | NOT_STARTED | n/a | |
| Summaries, NL search, planning | NOT_STARTED | n/a | the phone uses the Mac's model over M’AND |
| Works with AI disabled | n/a | n/a | design rule |

## Calls (extra, beyond the brief)
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Ringing banner, answer / decline from Mac | TESTED | IMPLEMENTED | AppModelTests, interop |

## Platform and release
| Feature | Mac | Android | Evidence / notes |
|---|---|---|---|
| Local database with migrations | NOT_STARTED | NOT_STARTED | |
| Release build | IMPLEMENTED | TESTED | `.app` signed; APK `apksigner` verified |
| DMG installer | NOT_STARTED | n/a | |
| Xcode project | BLOCKED | n/a | Xcode not installed; the Swift package opens in Xcode |
| Real Android system test | n/a | TESTED | `scripts/emulator-e2e.sh` on a real Android 17 system (Pixel-sized emulator): install, pair, mutual TLS, all 10 features, mirroring, control. Your own Pixel over real Wi-Fi is still NOT RUN |
| Live Swift ↔ Kotlin interop | TESTED | TESTED | `scripts/interop-test.sh` PASS 2026-11-18, all 10 features negotiated (the macOS 27 hang in the test server is fixed) |
