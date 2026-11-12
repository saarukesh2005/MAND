# Master implementation plan

This file and [FEATURE_TRACKER.md](FEATURE_TRACKER.md) are the record of progress. Each phase ends with its tests run, the tracker updated and a commit. To resume in a new session, read both files and continue from the first phase that isn't ✅.

| # | Phase | Status | Deliverables |
|---|---|---|---|
| 1 | Audit and architecture | ✅ 2026-11-12 | PROJECT_AUDIT, FEATURE_TRACKER, this plan, D22–D27 |
| 2 | Context foundation | 🟡 reducer + vectors done (both languages); stores next | Shared event model + reducer (Swift `MandContext`, Kotlin `:core`), shared vectors; Mac SQLite store with FTS5; Android Room store |
| 3 | Task Capsules + Time Machine | 🟡 diff/restore/undo logic done | Capsule CRUD/archive/pin/duplicate, items (files/URLs/notes/screenshots/actions), progress; timeline, point-in-time view, diff, restore preview, undo, retention, export/import |
| 4 | Anywhere (sync) | ⏳ | `context.v1` protocol: vector exchange, event batches, live push; conflict surfacing; "Continue on this device"; per-device state |
| 5 | Personal Brain | ⏳ | FTS search across capsules, notes, URLs, files, indexed documents; graph of explicit + inferred links with source labels; search history; delete/export |
| 6 | Anticipate | ⏳ | Rule-based suggestions with confidence + explanation; dismiss/feedback/quiet mode/frequency |
| 7 | Local AI | ⏳ | Ollama client, discovery, health, model choice; summaries, NL search, grouping; phone → Mac AI over the link |
| 8 | Delegate | ⏳ | Tool registry, planner (rules + optional AI), approval UI, executor, verification, history, cancel/retry |
| 9 | Module gaps | ⏳ | Device rename, model/OS/storage, latency, persisted connection history; clipboard history (opt-in); notification icons/history/DND; transfer remaining time; Android destination choice; share text/URL |
| 10 | Mirror + Control | ⏳ | MediaProjection → H.264 → TLS → VideoToolbox; settings; Accessibility-based control with explicit consent |
| 11 | UI completion | ⏳ | Mac sections: Context, Capsules, Brain, Time Machine, Anticipate, Anywhere, Delegate; matching Android screens; menu bar additions |
| 12 | Security, performance, integration tests | ⏳ | Review of new code; interop tests for `context.v1`; recovery-after-restart tests |
| 13 | Release | ⏳ | `release/android` (debug + release APK), `release/macos` (.app + DMG); INSTALLATION, TROUBLESHOOTING, CHANGELOG and the module docs |

| 2a | Tap to Send (TapDrop-style) | 🟡 Mac done and tested; Android next | `tap.v1`, notch sensor, light-key judge, coordinator; phone overlay, knock, content capture, OTP, banking pause |

Phases 2–8 are the core of the product and come before the module gaps and mirroring.

**Real-device steps** (mirroring, control, continuity between phone and Mac) need the Pixel 7a connected and are marked BLOCKED until then, never "TESTED".
