# Build Guide: Native macOS Meeting Recorder & Notes App

Name: **Apple Recorder** (repo and product `AppleRecorder`, bundle ID `io.github.corbinwrites.AppleRecorder`, repo https://github.com/corbinwrites/AppleRecorder). Date: 2026-11-18.

**For the builder:** read Part 2 (§21–§33) first. Part 1 (§1–§20) is the spec Part 2 implements.
Inputs: `web-research-findings.md`, `LOCAL-SPIKES-findings2.md`, Sacred Computer (SRCL) design reference.
Rule: where web and spike disagree, the spike wins. Where a spike claims more than it measured, this guide says so.

**Revision 2:** no paid developer fee (free distribution path), one stereo audio file, Mic-only / App-only modes, native Liquid Glass UX. Sacred Computer is now an editor theme (v1) and optional Terminal chrome preset (v1.1), not the default look. Changed: §1, 3, 5, 6, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19.

**Revision 3:** free distribution rebuilt around one stable self-signed release certificate, based on prior art in GitHub projects (§17.2). Changed: §1, 5, 15, 16, 17, 18, 19, new §20 (signing scripts).

**Revision 4:** name fixed (Apple Recorder). Part 2 added (§21–§33): builder rules, repo scaffold, reference code, tests, work order, GitHub steps. Temp tracks are now 16-bit PCM CAF (§5.3).

**Revision 5:** agent kit. Spec tests are frozen by git tag `spec-v1` (§21 rules 17–19, `scripts/protect-tests.sh`). Per-step task files in `docs/tasks/` are generated from this guide (`make tasks`). New step P0.3 (stubs + spec tests, compiled on a Mac). Apple API lookup helpers (`scripts/apple-api.sh`). Fixed: the `writeSilence` placeholder (§25.8), the missing `ProcessingStage` enum (§24.7), the P0.1 exit check (tests stay red until P0.3 and P1+).

### Completed Milestones
- **P0.0: Get the repo, first push** — Cloned seed repo, legacy spike scripts added, SDK API interfaces dumped.
- **P0.1: Scaffold** — Full repo tree scaffolded with eight packages (`Core`, `Capture`, `Transcribe`, `Enhance`, `Output`, `Theme`, `EditorKit`, `Pipeline`), `project.yml`, `Makefile`, signing and realtime check scripts, and CI/release workflows.
- **P0.2: API verification spike** — `Spikes/ApiCheck` compiled and verified with Core Audio process taps, aggregate devices, `AVAudioEngine`, AAC/PCM files, `Synchronization.Atomic`, `FoundationModels`, and `WhisperKit`. Documented in `docs/API-NOTES.md`.

---

## 1. Decisions locked

| Area | Decision | Basis |
|---|---|---|
| Build vs fork | Build. Read HushScribe, OpenOats, Recap for patterns. Check licenses before copying code. Never copy Hlopya (restrictive license). | W1 |
| Language / UI | Swift 6, SwiftUI shell, AppKit `NSTextView` editor. **Native macOS 26 look (Liquid Glass).** | Rev 2 |
| Capture modes | **App + Mic**, **Mic only** (rooms), **App only** | Rev 2 |
| Per-app capture | Core Audio process taps. ScreenCaptureKit dropped. | L1 |
| Audio file | **One stereo `.m4a`**: L = mic, R = app. Mono for single-source modes. | Rev 2 |
| Transcription | WhisperKit, post-recording. Default `small`. Challenger: `large-v3-v20240930_626MB`. | L3, W3 |
| Notes AI | Apple Foundation Models, on-device, 4,096-token window. Map-reduce. | L4 (`contextSize` = 4096 confirmed) |
| Live preview | Cut from v1. | L5 |
| Output | Plain `.md` + audio in two independent user-chosen folders. No Obsidian dependency. | L6 |
| Workflow | Write notes, record, stop, one click "Transcribe & enhance" | L5 |
| Speaker labels | Me / Them in App + Mic mode only. Mic-only room meetings: unlabeled in v1, diarization targeted v1.1. | W9, Rev 2 |
| Distribution | **Free and open source. No Apple Developer fee.** Stable self-signed release cert (pinned in CI). Homebrew tap + build from source. Revisit only if the §17.5 triggers fire. | Rev 2, §17 |
| Chrome | Liquid Glass, native controls, system accent. Sacred "Terminal" preset is optional, v1.1. | Rev 2, §9 |
| Editor themes | System (default), Sacred, Gruvbox Dark/Light, Dracula, Nord, Tokyo Night, Catppuccin Mocha, Solarized Dark/Light, user JSON | §9 |
| Editor | Obsidian-style markdown: sized headings, live styling, auto-continue lists, clickable tasks | §10 |

---

## 2. Reality check: what the spikes actually proved

Read this before writing code. Several "passes" are weaker than they look.

| Claim | Evidence | Verdict |
|---|---|---|
| L1 "effectively passed" | Tap/aggregate/IOProc all returned `noErr`, valid m4a. **Every Discord capture measured -91.0 dB (digital silence).** Spotify capture proved callbacks, not signal level. | **Not passed.** No audible audio has been captured from any process. |
| "No TCC prompt from CLI" | Web research documents the exact failure mode: denied permission returns `noErr` and delivers zeroed buffers. | The silence is probably a **permission problem**, not a wrong-PID problem. CLI taps inherit the responsible parent app's permission. |
| L3 WhisperKit 0.18.0 | SPM resolved 0.18.0. Web says the project is now `argmax-oss-swift`, latest **v1.1.0** (incremental loading, `promptTokens` fix). | Package URL is stale. Switch and re-run. |
| L3 benchmark | tiny/base/small only, warm runs, no WER, no peak RAM (RSS deltas are noise). | Speed is real. Quality and memory are unmeasured. |
| L4 Foundation Models | `contextSize` = 4096 confirmed on this machine. 24.7 s for ~2.2k chars synthetic. | **Passed.** Real transcripts untested. |
| FM availability | `deviceNotEligible` inside a sandboxed shell, `available` unsandboxed. | **Gate for the sandbox decision (§13).** |
| `com.apple.audio.capture` entitlement | Spike table says "likely required". Web (catap docs) says only `NSAudioCaptureUsageDescription` is needed. | Unknown. Test in a signed `.app` (G1). |

### First thing to do: fix L1

1. Build a minimal signed **`.app`** (not a CLI) with `NSAudioCaptureUsageDescription` and `NSMicrophoneUsageDescription`.
2. Tap a **known audible** source first (YouTube in Safari, Spotify). Run `ffmpeg volumedetect`. Must be well above -91 dB.
3. Check System Settings → Privacy & Security → Screen & System Audio Recording → **System Audio Recording Only** list. Confirm the app is listed and enabled.
4. Only then tap Discord in a live call. Tap the **whole process family** (main + Renderer + GPU + Plugin helpers) via one tap description. Don't pick one PID.
5. Use `kAudioProcessPropertyIsRunningOutput` to decide whether silence is legitimate. Output running + all-zero buffers for >3 s = permission/PID failure, not quiet room.

---

## 3. Scope

### v1 (ship)
- Main window: sessions sidebar, notes editor, floating record capsule, inspector (transcript + player)
- Three capture modes: App + Mic, Mic only, App only
- One stereo `.m4a` (App + Mic) or mono `.m4a` (single source)
- One-click Transcribe & enhance (WhisperKit, then Foundation Models)
- **Import audio**: drop an existing audio file on the window and run the same pipeline
- Markdown + audio written to two configurable folders; re-transcribe from the saved file
- Editor themes, Obsidian-style editor
- Standard Mac plumbing: Settings scene, menu commands, menu bar extra, search, drag and drop, share
- First-run consent sheet, unmissable recording indicators

### v1.1
- Diarization for room / Mic-only meetings (FluidAudio offline pipeline, run after recording)
- Terminal (Sacred) chrome preset
- Hide-markers-on-inactive-lines, heading folding, reading mode (⌘E)
- Parakeet (FluidAudio) as optional transcription backend
- Optional live-draft panel (SpeechAnalyzer), final transcript still from Whisper
- Private Cloud Compute notes model (opt-in, off by default, macOS 27+)
- App Intents (Shortcuts: start/stop recording), Spotlight indexing

### v2
- Wikilink resolution, Obsidian properties rendering

### Never
- Silent cloud fallback of any kind
- Bundled model weights in the repo

---

## 4. Architecture

### 4.1 Targets
- Minimum OS: **macOS 26.0** (Foundation Models, SpeechAnalyzer). Don't use macOS 27-only APIs unless you move CI to the `xcode-27` runner label.
- Apple silicon only (Neural Engine + FM).
- Swift 6 strict concurrency on.

### 4.2 Modules (local Swift packages in one Xcode project)

(Part 2 §22.1 has the exact tree and wins over this sketch.)

```
AppleRecorder/
├─ App/                     SwiftUI app target, scenes, menu bar, commands
├─ Packages/
│  ├─ Core/                 Session model, state machine, settings, logging
│  ├─ Capture/              Process taps, mic, aggregate devices, writers
│  ├─ Transcribe/           WhisperKit wrapper, model manager, VAD, merge
│  ├─ Enhance/              Foundation Models, chunker, token budget, prompts
│  ├─ Output/               Markdown writer, folder access, bookmarks
│  ├─ Theme/                Editor theme tokens, built-in themes, JSON loader, contrast checks
│  ├─ EditorKit/            Markdown editor (TextKit 2), tokenizer, shortcuts
│  └─ TerminalChrome/       Optional Sacred preset (v1.1): Frame, Banner, Button, MenuList, Meter
├─ Resources/Fonts/         Optional: Departure Mono, Geist Mono (+ OFL license files)
├─ Resources/Themes/        *.json
├─ Scripts/                 Spike scripts (list processes, capture, volume check)
└─ docs/                    README assets, LICENSES, CONSENT.md
```

### 4.3 Session state machine

```
idle → armed → recording → stopped → processing → done
                    │          │          │
                    └──────────┴──── failed (recording + notes always preserved)
```

Processing sub-stages (each shown in UI, each resumable):
`loadingModel → transcribing(track, %) → merging → loadingNotesModel → enhancing(chunk n/N) → writing → done`

### 4.4 Persistence
- Source of truth: `~/Library/Application Support/AppleRecorder/Sessions/<uuid>/`
  - `session.json` (metadata, state, settings used)
  - `notes.md` (autosaved every ~2 s and on every state change)
  - `recording/mic.caf`, `recording/app.caf` (temporary crash-safe tracks, deleted only after the final `.m4a` is verified)
  - `transcript.json` (segments with track + start/end)
  - `digests.json` (per-chunk FM output, so a failed run resumes)
- The audio folder holds the **canonical audio** (one `.m4a`). The `.md` in the notes folder is a copy of the session's notes plus results. Deleting the `.md` never destroys the session. Deleting the `.m4a` puts the session in an "audio missing" state: notes and transcript remain, re-transcribe is unavailable until the file is located.
- Plain JSON, no SwiftData. Inspectable, diffable, recoverable.

### 4.5 Concurrency rules
- Audio IOProc runs on a realtime thread: **no allocation, no locks, no Swift concurrency, no logging.** Copy into a preallocated lock-free ring buffer. A writer thread drains it to disk.
- Fix the spike's `UnsafeBufferPointer` lifetime warning before porting capture code.
- Pipeline stages are actors. UI observes `@Observable` view models on `@MainActor`.
- **8 GB rule:** never hold WhisperKit and the FM session working at the same time. Transcribe, unload Whisper, then enhance.

---

## 5. Capture

### 5.0 Modes

| Mode | Sources | File | Transcript labels |
|---|---|---|---|
| **App + Mic** | Process tap(s) + mic | Stereo `.m4a`, **L = mic, R = app** | Me / Them |
| **Mic only** | Mic | Mono `.m4a` | None in v1 |
| **App only** | Process tap(s) | Mono `.m4a` | None |

Room meetings = Mic only. Differences that matter:
- Multiple speakers share one mic, so "Me / Them" doesn't apply. Diarization is the real fix and moves to v1.1.
- Far-field audio is harder for Whisper. Test it (Fixture D, §15). `small` may not be enough; the 626 MB model may earn its RAM here.
- Mic quality is mostly out of your hands, but macOS has a system Mic Mode (Standard / Voice Isolation / Wide Spectrum). Wide Spectrum suits rooms; Voice Isolation will clip distant speakers. Apps can't set it, only show the system picker (`AVCaptureDevice.showSystemUserInterface(.microphoneModes)`, verify). Surface it as a tip when Mic-only is armed.
- Consent matters more here: people in the room never see the app (§14).

### 5.1 Process tap setup
- Enumerate with `kAudioHardwarePropertyProcessObjectList`. Map PID → app via `NSRunningApplication` + `proc_pidpath` (both worked in L1).
- Source picker lists **apps**, not processes. Group helpers by parent bundle (Discord's 4 helpers = one entry). Tap the whole family with one `CATapDescription`.
- Keep tap `muteBehavior` **unmuted** so the user still hears the call.
- **Run the tap in the main app process, not a helper.** TCC attributes a helper's tap to the host app; if the usage string isn't in the host's Info.plist, macOS never prompts (parley #222).
- Aggregate device: private, tap with drift compensation, main sub-device = current default output. Follow Apple's AudioCap sample's dictionary exactly.
- Watch `AudioObjectAddPropertyListenerBlock` on the process list so "Discord appeared" auto-fills the picker (works per L1).

### 5.2 Mic track
- Selectable input device. Separate IOProc or `AVAudioEngine` input; stamp with `mHostTime`.
- Both tracks share the host-time clock. Store each track's first-sample host time in `session.json`.

### 5.3 Writing the file
- While recording, write each source to a **temporary `.caf`** (16-bit PCM, mono, native sample rate, ~5.8 MB/min per source; PCM survives a crash, AAC-in-CAF is unproven) in the session folder. A half-written `.m4a` loses its index and won't open. **Verify crash recovery in L2.**
- On stop, build the final file:
  - **App + Mic:** 2-channel AAC-LC, 48 kHz, ~128 kbps. Ch 0 = mic, ch 1 = app. Pad whichever track started later using its host-time offset. Length = longer track.
  - **Single source:** mono AAC-LC, ~64 kbps.
- **Verify before deleting temp tracks:** decode, check duration matches, check each channel has signal where expected. Never delete first.
- Transcription reads the channels back out of this file (§6). The audio folder copy is the canonical recording.
- **Hard-pan caveat:** external players play the mic only on the left and the call only on the right. Fix it in-app: the player has a **Center** toggle that mixes to both ears. Optional setting "Also export a centered mix" (off by default) for people who share recordings.
- Format observed from the tap: 48 kHz stereo Float32. Resample to 16 kHz mono only inside the transcribe step.

### 5.4 Failure handling (all must surface in UI, never silently)

| Condition | Behavior |
|---|---|
| Zero-buffer detector trips (output running, >3 s all zeros) | Banner: "No audio from Discord. Check System Audio Recording permission." Offer "Open Settings". |
| **Permission lost after an app update** (see §17) | Same detector, plus text: "macOS may have reset permission after the update. Re-enable it." |
| Output device switched mid-call | Rebuild aggregate device, log a gap marker in `session.json`, keep recording |
| Input device switched | Same, plus toast |
| Target app quits | Keep recording mic, banner "Discord closed", offer stop |
| Disk < 1 GB free | Warn before start; stop gracefully at 200 MB |
| Sleep/wake | Pause markers, resume tap, verify buffers non-zero |

### 5.5 Permissions UX
No public API checks System Audio Recording status. Detect by behavior: start a 1 s probe tap on arm, check for non-zero samples while the target is outputting. Show result in the idle capsule: `Source OK` or `No signal`. Mic-only mode needs only Microphone permission, so it keeps working even when the audio-capture grant is stale. Detector rule: exact-zero samples for >3 s after tap start while the target is outputting means permission failure. Add a repair window that lists only what's missing, with one-click "Open Settings" (pattern from parley and call-copilot's 2 s self-test).

---

## 6. Transcription

### 6.1 Setup
- Depend on **argmax-oss-swift ≥ 1.1.0** (WhisperKit). Confirm the LICENSE covers every product you import.
- `audioLoadingMode: .incremental`, `chunkingStrategy: .vad`. Models download at runtime from `argmaxinc/whisperkit-coreml`, stored in Application Support.
- **Stereo file (App + Mic):** split channels. Ch 0 (mic) → "Me", ch 1 (app) → "Them". Transcribe each, merge by timestamp.
- **Mono file (Mic only / App only / imported):** one pass, no speaker labels. Imported stereo files from other tools are mixed to mono.

### 6.2 Model plan (gate before locking default)

| Model | Role | Known |
|---|---|---|
| `small` | Provisional default | 156.6 s for 44:16, 224.1 s for 75:23 (≈17–20×, warm) |
| `large-v3-v20240930_626MB` | Challenger | 1.95% WER (Argmax LibriSpeech), **untested on your M1** |
| `base` | Low-memory fallback | 51–60× |
| `tiny` | Emergency / UI testing only | Mishears names |

Promote the 626 MB variant to default only if: peak RAM (Instruments) leaves headroom beside other apps, and Fixture C WER beats `small` by a meaningful margin. Otherwise `small` stays.

### 6.3 Hallucination defense (in order)
1. VAD pre-filter. Confirm whether WhisperKit exposes more than its energy-based VAD. If not, evaluate a Silero-class pre-pass.
2. Disable previous-text conditioning if loops appear.
3. Post-filter: de-loop repeated n-grams, drop known phantom phrases on near-silent segments.
4. `no_speech_threshold` as a weak last line.
5. Test on Fixture A: aggressive VAD can eat quiet real speech.

### 6.4 Custom vocabulary
- Settings → Vocabulary: a user list (names, theological terms, product names) injected via `promptTokens`.
- Test only on ≥1.1.0 (older versions return empty output with `promptTokens`).
- Measure effect on Fixture C before shipping the feature. Keep prompt short.

### 6.5 Verification
"Re-transcribe" re-runs WhisperKit on the saved audio file with a different model and shows a side-by-side diff. This is the reason audio is kept.

---

## 7. Enhancement (Foundation Models)

### 7.1 Constraints
- 4,096 tokens per session, input + output shared. Read `SystemLanguageModel.default.contextSize` at runtime and scale if larger.
- 60 min ≈ 12,000 transcript tokens. Needs chunking.
- **New `LanguageModelSession` per call.** Never carry history.
- Count with `tokenCount(for:)` before every call.

### 7.2 Token budget per call (4,096 window)

| Slice | Tokens |
|---|---|
| Instructions | ~300 |
| User notes slice | ≤ 500 |
| Transcript chunk | ~1,200 (≈ 6 min of speech) |
| Output reserve | ~800 |
| Safety margin | ~1,300 |

### 7.3 Pipeline
1. **Chunk** transcript at segment boundaries, ~1,200 tokens, 10% overlap.
2. **Map:** per chunk, `@Generable ChunkDigest { topics, decisions, actionItems, questions, keyPoints }`. Persist each digest.
3. **Reduce:** merge digests in groups until one fits. Hierarchical if >8 digests.
4. **Final:** user notes (sliced if >500 tokens) + merged digest → `@Generable MeetingNotes { summary, decisions, actionItems, openQuestions, expandedNotes }`.
5. Compare against **rolling summary** on Fixture B. Keep whichever scores better; don't assume map-reduce wins.

### 7.4 Error handling

| Error | Response |
|---|---|
| `exceededContextWindowSize` | Split input in half, retry |
| `guardrailViolation` / refusal | Retry once with permissive content transformations if the API allows. Else mark chunk "[summary unavailable]", continue, flag in UI. Never drop transcript. |
| Rate limited / concurrent request | Back off, serialize calls |
| `.unavailable(reason)` | Show reason. Offer "Transcript only" note. **No silent switch to a remote model.** |

API shape verified in L4: `session.respond(to:generating:)`, do **not** pass `schema:` to init.

### 7.5 Trust rules for generated text
- Never delete the user's notes. Final doc keeps **My Notes (original)** verbatim below the enhanced section.
- Enhanced sections are labeled generated.
- Action items with names/dates must trace to transcript text. If the model invents an owner, the prompt must say "only use names present in the text".
- Test church/theological content and proper names for refusals (open item from L4).

---

## 8. Output

### 8.1 Folder settings
- **Notes folder** and **Audio folder**: independent, persisted, paths shown in Settings.
- Non-sandboxed build: store paths, handle TCC prompts (iCloud Drive and Documents trigger them).
- Sandboxed build: security-scoped bookmarks, resolve on launch, handle stale/moved/revoked with a clear banner and "Choose folder…".
- Never write partial files: write to temp, then atomic replace.

### 8.2 Naming
`YYYY-MM-DD HHmm Title.md` and `YYYY-MM-DD HHmm Title.m4a`. Timestamp keeps names unique (collision-proof even if the user later opens the folder in Obsidian). Sanitize `/ : \`.

### 8.3 Document template

```md
---
title: Weekly sync
created: 2026-11-18T10:30:00
duration: "00:42:10"
source_app: Discord
capture_mode: app+mic
audio: "../Audio/2026-11-18 1030 Weekly sync.m4a"
transcription_model: whisperkit-small
notes_model: apple-foundation-models
tags: [meeting]
---

# Weekly sync

Recording: [2026-11-18 1030 Weekly sync.m4a](../Audio/2026-11-18%201030%20Weekly%20sync.m4a)

## Summary
...

## Decisions
- ...

## Action items
- [ ] Owner: task

## Open questions
- ...

## Notes
(expanded notes)

## My notes (original)
(verbatim)

## Transcript
**[00:00:12] Me:** ...
**[00:00:19] Them:** ...
```

- Frontmatter: toggle in Settings (default on). Standard YAML, date-time `created`, list `tags`.
- Audio reference: standard relative Markdown link by default. Toggle for `![[file.m4a]]` embed style. Compute the relative path from the notes folder to the audio folder; if impossible (different volumes), fall back to absolute `file://`.
- Enhanced notes on top, transcript at bottom (your stated layout). In Mic-only / App-only mode, transcript lines carry timestamps only, no speaker label.
- If enhancement fails: write transcript + original notes anyway, with a banner line at top.

---

## 9. Design: native Mac first, themes second

### 9.1 Two layers, chosen independently

| Layer | Options | Default |
|---|---|---|
| **Chrome** (window, sidebar, toolbar, controls) | Native Liquid Glass. Terminal (Sacred), v1.1. | Native |
| **Editor theme** (note + transcript surface, syntax colors) | System, Sacred, Gruvbox Dark/Light, Dracula, Nord, Tokyo Night, Catppuccin Mocha, Solarized Dark/Light, user JSON | System |

Sacred Computer and Liquid Glass are opposites. Sacred is square, opaque, flat, no blur, no shadow, one accent. Liquid Glass is rounded, translucent, specular. Mixing them in one window looks broken. So Sacred becomes:
1. an **editor theme in v1** (black canvas, orange `#FF7A00` accent, mono font), and
2. a full **Terminal chrome preset in v1.1** (§9.6).

### 9.2 Native chrome: Liquid Glass rules
Confirmed APIs (SwiftUI, macOS 26+): `glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`, `glassEffectID` for morphing. AppKit: `NSGlassEffectView`.

1. **Build with the Xcode 26 SDK and use standard components.** Sidebar, toolbar, sheets, menus, and `Settings` adopt glass automatically. That is 80% of "looks Mac-y". Don't recreate them.
2. **Glass is the controls layer, not the content.** The editor and transcript surfaces stay opaque (theme canvas). Text on translucent backgrounds is a legibility fight you lose.
3. **Custom glass only for the floating record capsule** and transient toasts.
4. One `GlassEffectContainer` around sibling glass views. Never nest containers. Never put glass on glass.
5. Apply `.glassEffect` **after** layout modifiers (padding, frame), or the shape is wrong.
6. `.interactive()` only on things that are tappable.
7. Primary action = `.glassProminent` with the system accent. Everything else `.glass` or plain.
8. Use system colors, system spacing, SF Symbols. **Red only for recording.**
9. Accessibility is mostly free for system glass (Reduce Transparency, Increase Contrast, Reduce Motion). Test each setting against the custom capsule. Respect the system Clear/Tinted glass preference. Don't override it.
10. Window background: standard. Don't make the editor window translucent.

### 9.3 Mac conventions to adopt

| Area | Do this |
|---|---|
| Window | `NavigationSplitView`: sessions sidebar + editor detail. `.inspector` on the trailing edge for transcript and player. Full-screen, window restoration, state restoration. |
| Toolbar | New session, mode/source menu, share, inspector toggle, search. System items, grouped by the system. |
| Settings | SwiftUI `Settings` scene, tabbed, `Form` with `.formStyle(.grouped)`. |
| Menus | Real menu bar commands for every action, with standard shortcuts. ⌘N new, ⇧⌘R start/stop, ⌘, settings, ⌘F search, ⌘K command palette. |
| Menu bar | `MenuBarExtra` with status and Start/Stop. Dock menu with the same. |
| Lists | Sessions grouped by Today / Yesterday / Earlier. Context menus (Reveal in Finder, Re-transcribe, Delete). Swipe actions. |
| Search | `.searchable` across titles, notes, transcripts. |
| Drag and drop | Drop audio on the window = import. Drag the session out as `.md`. |
| Share | `ShareLink` for the markdown. |
| Empty / error | `ContentUnavailableView`. Blocking issues in sheets. Non-blocking in banners. |
| Sounds | System sounds for start/stop. Off by default if it could leak into the recording (it can: the tap hears system output). |
| Text | Native undo, spell check, Find bar, Services, accessibility text size follows editor setting. |

### 9.4 Editor themes

Tokens every theme defines: `canvas`, `ink`, `mutedInk`, `accent`, `selection`, `codeBg`, `link`, `quote`, `tag`, `strong`, `marker`, `h1`…`h6`, `isDark`.
**System** theme: system colors, follows macOS light/dark, system accent.
Rule: a dark theme sets the window to dark ("Match window to theme", default on). Otherwise a dark editor inside light glass chrome looks wrong.

| Theme | canvas | ink | mutedInk | accent |
|---|---|---|---|---|
| System | system | system | system | system |
| **Sacred** | `#000000` | `#F2F2F2` | `#B8B8B8` | `#FF7A00` |
| Gruvbox Dark | `#282828` | `#EBDBB2` | `#928374` | `#FE8019` |
| Gruvbox Light | `#FBF1C7` | `#3C3836` | `#7C6F64` | `#AF3A03` |
| Dracula | `#282A36` | `#F8F8F2` | `#6272A4` | `#BD93F9` |
| Nord | `#2E3440` | `#D8DEE9` | `#616E88` | `#88C0D0` |
| Tokyo Night | `#1A1B26` | `#C0CAF5` | `#565F89` | `#7AA2F7` |
| Catppuccin Mocha | `#1E1E2E` | `#CDD6F4` | `#6C7086` | `#CBA6F7` |
| Solarized Dark | `#002B36` | `#93A1A1` | `#657B83` | `#CB4B16` |
| Solarized Light | `#FDF6E3` | `#586E75` | `#93A1A1` | `#CB4B16` |

Sacred extras: `codeBg #2A2A2A`, selection = accent @ 35%, `grid #1C1C1C` (Terminal preset only).

**Heading ramps**

| Theme | H1 | H2 | H3 | H4 | H5 | H6 |
|---|---|---|---|---|---|---|
| System / Sacred | ink | ink | ink | ink | mutedInk | mutedInk |
| Gruvbox Dark | `#FB4934` | `#FE8019` | `#FABD2F` | `#B8BB26` | `#83A598` | `#D3869B` |
| Dracula | `#FF79C6` | `#BD93F9` | `#8BE9FD` | `#50FA7B` | `#FFB86C` | `#F1FA8C` |
| Nord | `#88C0D0` | `#81A1C1` | `#8FBCBB` | `#A3BE8C` | `#EBCB8B` | `#B48EAD` |
| Tokyo Night | `#7AA2F7` | `#BB9AF7` | `#7DCFFF` | `#9ECE6A` | `#E0AF68` | `#F7768E` |
| Catppuccin Mocha | `#F38BA8` | `#FAB387` | `#F9E2AF` | `#A6E3A1` | `#89B4FA` | `#CBA6F7` |

Sacred stays single-accent: headings differ by size, not hue. Gruvbox Light and Solarized reuse the ramp with each palette's light-mode variants.

**Contrast warning:** several `mutedInk` values (Dracula, Catppuccin, Tokyo Night, Solarized Light) are the palette's "comment" color and likely fail 4.5:1 as body text. Use them for markers only. The loader checks ink/canvas ≥ 4.5 and accent/canvas ≥ 3, and warns on user themes. The palette hex values are from memory of the published palettes; verify against each project's official repo.

**User themes:** JSON files in `~/Library/Application Support/AppleRecorder/Themes/`.

### 9.5 Typography
- Chrome: system font (SF), system text styles.
- Editor default: **system font, proportional**, like Obsidian. Selectable: New York (serif), SF Mono, plus optional bundled **Geist Mono** and **Departure Mono**.
- Bundled fonts are optional. If you ship them, verify the licenses (both believed SIL OFL) and include the license files. If you don't, there is no font license burden.
- Departure Mono has one weight, so bold needs another face. Geist Mono may lack a true italic; synthesize oblique with a font matrix.
- Sacred editor theme suggests Departure Mono headings + Geist Mono body, but it's a suggestion, not forced.
- Editor font size setting 12–24.

### 9.6 Terminal (Sacred) chrome preset, v1.1
Source: sacred.computer (SRCL, Internet Development Studio): black grid canvas, pale square frames, compact mono, one hot orange accent. Token values come from a third-party measurement of the site, not the repo. **Check the repo's LICENSE.md before copying any component code.** Rebuild in SwiftUI rather than port.

Rules when active: opaque everything, no glass, no corner radius, no shadows. 1 px borders (`#F0F0F0`), labeled frame bars. Orange for the single most important element on screen. Mono type throughout (Departure Mono display, Geist Mono chrome). Black `canvas` with `grid #1C1C1C` lattice, `panel #2A2A2A`, `panelStrong #444444`, `onAccent #000000`. All layout in integer character cells.

Components (`TerminalChrome` package): `SFrame`, `SButton`, `SBanner`, `SMenuList`, `SModal`, `SMeter` (block characters `▁▃▅▇`), `SField` (`>` prompt), `SToast`, `SProgress` (`[██████░░░░] 62%`). Native text editing, pickers and system alerts stay native.

Cost is real: it is a second UI kit. That is why it is v1.1.

---

## 10. Markdown editor (Obsidian behavior)

### 10.1 Approach
`NSTextView` on TextKit 2 wrapped in `NSViewRepresentable`. A markdown tokenizer restyles only the edited paragraph range on each keystroke. Notes are small, so a line-based tokenizer (headings, lists, tasks, fences, inline spans) is enough. Use Apple's `swift-markdown` for the full-document pass on load and paste.

Alternative: `WKWebView` + CodeMirror 6 (what Obsidian itself uses) gets true Live Preview, but adds bundle weight, offline packaging, and a non-native feel. Not recommended for v1.

### 10.2 Feature spec

| Obsidian behavior | v1 | Notes |
|---|---|---|
| Headings H1–H6 sized by level, `#` markers shown muted | ✅ | Scale below |
| Hide `#`/`**` markers on inactive lines | v1.1 | Layout shift is tricky; markers stay visible but muted in v1 |
| Bold, italic, strikethrough, `==highlight==`, inline code | ✅ | |
| Fenced code blocks with `codeBg` | ✅ | |
| Bullet / numbered lists, Enter continues, Tab/⇧Tab indent | ✅ | |
| Tasks `- [ ]` render a clickable box; ⌘Enter toggles | ✅ | |
| Blockquote with left bar | ✅ | |
| `[text](url)`, ⌘-click opens | ✅ | |
| `#tag` styled | ✅ | |
| YAML frontmatter styled muted in a block | ✅ | Properties table is v2 |
| Heading fold arrows in gutter | v1.1 | Needs hidden ranges in TextKit 2 |
| Reading mode toggle (⌘E) | v1.1 | |
| `[[wikilinks]]` styled, not resolved | v1.1 | |
| Callouts, embeds, plugins | No | |

### 10.3 Heading scale
Obsidian's default is roughly 2.0 / 1.6 / 1.37 / 1.25 / 1.12 / 1.12 em, weight 700/600. Verify against its default CSS. With a proportional font, use that scale. A mono face at 2 em overflows fast, so compress for mono:

| Level | Scale | Weight | Space above |
|---|---|---|---|
| H1 | 1.75 em | bold | 1.5 lines |
| H2 | 1.5 em | bold | 1.25 lines |
| H3 | 1.25 em | bold | 1 line |
| H4 | 1.1 em | bold | 0.75 line |
| H5 | 1.0 em | bold, muted marker | 0.5 line |
| H6 | 1.0 em | regular, muted | 0.5 line |

Sizes snap to the cell grid where possible. In the Sacred editor theme, H1/H2 get a bottom hairline in `mutedInk`. That is the one place Sacred and Obsidian visually meet.

### 10.4 Shortcuts
⌘B bold, ⌘I italic, ⌘K link, ⌘Enter toggle task, ⌘] / ⌘[ indent/outdent, ⌥⌘1–6 set heading level, ⌘E reading mode (v1.1).

### 10.5 Reliability
- Autosave every ~2 s to `notes.md`, plus on blur and on state change.
- Undo history survives start/stop recording.
- Paste plain text by default; keep markdown.
- IME / marked-text safe: don't restyle during composition.

---

## 11. Screens and flows

### 11.1 Main window

```
┌──────────────────────────────────────────────────────────────────┐
│ ● ● ●  ◧   Weekly sync                  [App + Mic ▾]  ⤴  ⌕  ⓘ   │  glass toolbar
├────────────┬─────────────────────────────────────┬───────────────┤
│ Today      │ # Weekly sync                       │ TRANSCRIPT    │
│  Weekly…   │ ## Agenda                           │ 0:12 Me  …    │  inspector
│  Disc 1:1  │ - [ ] Q1 scope                      │ 0:19 Them …   │
│ Yesterday  │ - [x] Hiring update                 │               │
│  Planning  │                                     │ ▶ ───●──── 12:03│
│            │   ╭───────────────────────────────╮ │ [Center]      │
│            │   │ ● 00:12:03  ▁▃▅▂ ▁▂▃  ■ Stop  │ │               │
│            │   ╰───────────────────────────────╯ │               │
└────────────┴─────────────────────────────────────┴───────────────┘
```

- Sidebar, toolbar, inspector: system glass.
- Editor: opaque, theme-colored.
- Record capsule: custom glass, floating at the bottom of the editor, centered.
- Inspector hidden by default until a transcript exists (⌥⌘I).

### 11.2 Capsule states

| State | Capsule contents |
|---|---|
| Idle | `● Record` · mode menu (App + Mic / Mic only / App only) · source menu · `Source OK` / `No signal` |
| Recording | Red dot, timer, level meter per source (one for single-source), `■ Stop` |
| Stopped | `Transcribe & Enhance` (prominent) · `Discard` · duration |
| Processing | Expands: stage list + progress, `Cancel`. "Recording and notes are safe." |
| Done | Toast: `Saved` · Reveal · Open · Re-transcribe |
| Failed | Names the failed stage, `Retry from this stage` |

### 11.3 Recording indicators (consent-critical)
- Capsule with red dot and the word **Recording** plus elapsed time. Not color alone.
- Red recording pill in the toolbar, red menu bar icon, Dock badge.
- macOS also shows its own orange mic indicator. Don't try to hide or imitate it.
- Mic-only (room) mode adds one line in the capsule: "Recording the room."

### 11.4 Mic-only specifics
- Single level meter, no Me/Them, mono file.
- Tip row when armed: "Place the Mac centrally. Wide Spectrum mic mode suits rooms." with a button that opens the system picker.
- No dependency on the audio-capture permission.
- Inspector transcript is plain timestamps. Diarization (v1.1) adds "Speaker 1/2/3" labels you can rename.

### 11.5 First run (native sheets, in order)
1. **Consent sheet** (blocking): recording laws vary, all-party consent applies in California and other states, you are the recorder, tell everyone present. Checkbox + `I Understand`. Pattern from OpenOats.
2. Pick notes folder and audio folder.
3. Permissions walkthrough: Microphone, then System Audio Recording, each with a live test (§5.5).
4. Model download: pick transcription model (default `small`), size and progress.
5. Apple Intelligence check. If unavailable: explain, offer transcript-only mode.

### 11.6 Import
Drop an audio file on the window, or File → Import Audio. Creates a session, skips recording, goes straight to the stopped state. Mono and stereo both handled (stereo from this app is channel-split, other stereo files are mixed to mono).

### 11.7 Command palette (⌘K)
Glass panel, Spotlight-style. Commands: Start/Stop, Transcribe & enhance, Re-transcribe, Switch mode, Switch source, Switch theme, Open notes folder, Open audio folder, Settings. Fuzzy match.

### 11.8 Empty and error states

| State | Treatment |
|---|---|
| No sessions | `ContentUnavailableView`: "No sessions. ⌘N to start." |
| No signal | Capsule banner + "Open System Settings" |
| Folder missing/revoked | Banner + "Choose folder…" |
| Model not downloaded | Inline progress, resumable |
| Apple Intelligence off | Reason text, transcript-only option |
| Audio file missing (moved/deleted) | Session shows transcript and notes, player disabled, "Locate file…" |
| Processing failed | Failed stage named, retry from stage. Recording and notes are never lost. |
| Disk low | Warn before, stop gracefully during |

---

## 12. Settings (Settings scene, tabs with SF Symbols)

| Tab | Contents |
|---|---|
| General | Menu bar item, Dock badge, notifications, sounds, temp-file policy |
| Capture | Default mode, default source app, default mic, probe on arm, auto-detect Discord, Mic Mode tip |
| Transcription | WhisperKit model picker (size, status, delete), language, VAD strictness, vocabulary list |
| Notes AI | Model picker (default Apple Foundation Models), availability status, chunk size (advanced), PCC opt-in (v1.1, off) |
| Output | Notes folder, audio folder (separate), filename template, frontmatter toggle, audio link style (relative link / `![[ ]]`), "Also export centered mix" (off) |
| Appearance | Chrome: Native (Terminal in v1.1). Editor theme. Match window to theme. Editor font and size. |
| Legal | Re-show consent, license list, attribution |

Persist all. Transcription model and notes model are independent choices.

---

## 13. Permissions, entitlements, signing

### 13.1 Info.plist
- `NSMicrophoneUsageDescription`
- `NSAudioCaptureUsageDescription` (add by hand, Xcode doesn't list it)

### 13.2 Entitlements

| Build | Entitlements |
|---|---|
| **Non-sandboxed + hardened runtime** (recommended) | `com.apple.security.device.audio-input` |
| Sandboxed (only if FM works there) | `app-sandbox`, `device.audio-input`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client` (model download) |
| Test, don't assume | `com.apple.audio.capture` for taps |

### 13.3 Sandbox gate
L4 saw FM report `deviceNotEligible` when sandboxed. **Test Foundation Models in a signed, sandboxed `.app`.** If it fails, ship non-sandboxed. It removes security-scoped bookmark complexity, and without notarization (§17) the sandbox buys little distribution benefit. Hardened runtime can stay on.

### 13.4 Dev tips
- Stable signing identity during development, or TCC resets after every build.
- On Tahoe/27, only app bundles appear in the permission list. Never test capture from a bare executable.
- Document the exact prompts in order for a fresh account (open L7 item).

---

## 14. Legal, consent, privacy

- README warning: recording laws vary. California Penal Code § 632 requires all-party consent for confidential communications; many other states do too. The person running the app is the recorder. Not legal advice.
- Blocking first-run acknowledgement (§11.5). Persistent in-app recording indicator.
- Room recordings capture people who never see the app. The consent sheet and README say so explicitly: tell everyone present before you press Record.
- Licenses: MIT for the repo. WhisperKit MIT. FluidAudio Apache-2.0, Parakeet model CC-BY-4.0 (needs attribution). Don't commit weights. **Still to check:** Whisper weights license and the converted Core ML model license tags.
- Apple Foundation Models acceptable-use requirements: read the live page, mirror the relevant limits in the README. Copies conflict on regulated domains.
- Privacy statement: audio and transcripts never leave the Mac. Only network use is model download from Hugging Face. Say it in the README and Settings.
- Discord's own terms on recording: not researched. Add a README line telling users to check.

---

## 15. Test plan and acceptance

### 15.1 Fixtures
- **A**: 5-min Discord call, two voices, one on headphones.
- **B**: 60-min meeting-style recording.
- **C**: hand-corrected reference transcript of a 10-min slice. Include theological terms and names.
- **D**: 10-min room recording, 3+ speakers, laptop mic at 1–2 m (Mic-only, far-field accuracy).

### 15.2 Spike closeouts (before feature work)

| Spike | Close by |
|---|---|
| L1 | Audible Discord capture in signed `.app`, no mic bleed, CPU < 10% on M1 |
| L2 | 60-min two-track run, drift ≤ 200 ms, input switch without crash, crash-recovery of `.caf` |
| L3 | WhisperKit ≥ 1.1.0 rerun, WER on C, **peak RAM via Instruments**, VAD on silent stretches, `promptTokens` test, 626 MB variant |
| L4 | Real 60-min transcript, map-reduce vs rolling, theological terms refusal test |
| L7 | Signed-bundle tap test, sandbox + FM test, notarization |

### 15.3 App acceptance (from the spike design findings)
1. Open window, type notes, start and stop a recording.
2. Click Transcribe & enhance. Transcript is produced, notes enhanced, transcript included in the `.md`.
3. Set two different folders, relaunch, both persist and work.
4. Audio lands in the audio folder, `.md` in the notes folder, link resolves across the arrangement.
5. Change transcription and notes models independently. Defaults are WhisperKit `small` and Apple Foundation Models.
6. Move/revoke a folder after relaunch: clear banner, no crash, no data loss.
7. Kill the app mid-recording: relaunch recovers audio and notes.
8. Apple Intelligence off: transcript-only note still produced.
9. Every theme passes the contrast check or warns.
10. Full keyboard operation. VoiceOver reads state changes (recording, stage, done).
11. Mic-only recording works with the audio-capture permission revoked.
12. App + Mic file: ch 0 contains only mic audio, ch 1 only app audio. In-app Center toggle mixes both ears.
13. Drop an existing audio file on the window: imported, transcribed, enhanced, written.
14. Release-signed v0.0.1 → v0.0.2 on a second Mac, same cert: Microphone and System Audio Recording grants survive (§20.4). `codesign -d -r-` shows identifier + certificate hash, never `cdhash`. Negative test: an ad-hoc build installed over it is detected and explained.
15. Glass chrome stays legible with Reduce Transparency and Increase Contrast on.

### 15.4 Performance targets (M1, 8 GB)
- Recording CPU < 10%, no dropped buffers over 60 min
- 60-min transcription < 5 min with `small`
- Enhancement of 60-min transcript < 10 min
- Peak RAM during transcription leaves ≥ 2 GB free (confirm with Instruments)
- Editor stays responsive at 50 KB notes

---

## 16. Build phases and gates

| Gate | Deliverable | Pass condition |
|---|---|---|
| G0 Foundations | Repo, Xcode project, local packages, CI on `macos-26`, LICENSE, signing setup scripts (§20), README skeleton | CI green on empty app |
| G1 Capture | `.app` with a **stable signing identity** that records all three modes to temp `.caf`, builds the stereo/mono `.m4a`, zero-buffer detector, source picker | **Audible capture proven, L1 + L2 pass.** Channel check: mic only on ch 0, app only on ch 1. If not, stop and report. |
| G2 Transcribe | Model manager, channel-split WhisperKit, merge, progress | WER + peak RAM measured on Fixtures C and D |
| G3 Enhance | Chunker, token budget, digests, final notes, error paths | Real-transcript quality accepted |
| G4 Native shell + themes | `NavigationSplitView`, toolbar, glass capsule, inspector, Settings scene, theme package (9 themes) | Every theme reviewed in light and dark macOS, plus Reduce Transparency and Increase Contrast |
| G5 Editor | TextKit 2 markdown editor, shortcuts, autosave | Typing latency + IME check |
| G6 Output + flows | Folders, markdown writer, consent flow, import, search | §15.3 items 1–8 pass |
| G7 Hardening | Permissions walkthrough, permission-loss detection, crash recovery, accessibility, **install test on a second Mac** | §15.3 all pass |
| G8 Release | Zip/DMG, Homebrew tap, source-build script, README, v1.0.0 | Fresh-account install via each install path |

G4 can run in parallel with G2/G3 after G0. These G-labels are product gates; the builder's step IDs (P0.0 … P10) are in §32. v1.1 queue: diarization, Terminal preset, editor polish, Parakeet.

**Implementation order:** Part 2 §32 supersedes this gate order for the builder (software-testable work first, hardware gates flagged `NEEDS HUMAN`). The gates themselves are unchanged.

---

## 17. Release: free path, no Developer ID

### 17.1 The problem
Ad-hoc signing makes the app's identity its binary hash (`cdhash`). Every update is a "new app" to macOS, so the System Audio Recording grant is dropped. Core Audio still returns `noErr` and delivers zeros, which is exactly the L1 symptom (parley #222 documents the same failure).

Apple DTS's answer (forums thread 795739): sign with a stable identity, ideally Apple-issued. Ad-hoc is fine for open source tooling like Homebrew, but causes problems for a Mac app distributed widely. **A self-signed certificate is not Apple-endorsed.** It is a workaround the community has converged on, and it works because TCC keys on the designated requirement, which becomes "bundle ID + certificate hash".

### 17.2 What other open-source projects do (GitHub research)

| Project | Approach | Worth copying |
|---|---|---|
| **AeroSpace** (nikitabobko) | One self-signed cert (`Self-Signed Root`, `Code Signing`) made in Keychain Access, release app signed with it | Proof the pattern ships at scale. Its release notes ("fresh certificate", "renew certificates, change bundle ID") show what a cert change costs users: a re-grant. |
| **CoreEQ** (core-eq #43) | Self-signed "CoreEQ Release", valid to 2046, for the **System Audio Recording** grant. DR = identifier + certificate hash. CI pins the fingerprint and **fails the release if a different cert signs it.** | Closest match to this app's permission. Pin + fail-closed. |
| **Velikiy Moguchiy** (#73) | Public cert committed to the repo; build stops if the `.p12` holds any other cert; explicit DR with leaf hash; forks/PR builds stay ad-hoc | Committed public cert as the pin |
| **Onscreenly** (#54) | 10-year cert; `.p12` exported 3DES + SHA-1 so macOS can import it; script **refuses to overwrite** an existing cert | Cert generation script with a guard |
| **Meeting Manager** (#239) | Self-signed release cert in Actions secrets for Mic, System Audio Recording, Calendars. CI fails if the DR contains `cdhash` or lacks a certificate hash. | The DR assertion |
| **Porter** (#8) | Release/nightly signed in CI, PR builds ad-hoc | Fork PRs must never see the secret |
| **listn** (Whisper capture) | `signing-cert` helper makes a local self-signed cert; first switch from ad-hoc needs one permission reset | Local dev cert helper |
| **Tapmix** (process taps) | Auto-picks an Apple Development identity if present, else documents a self-signed cert | Prefer an existing identity for local builds |
| **parley** (#222), **call-copilot** | Detect the silent-zeros state: exact-zero run after tap start, 2 s capture self-test, one-click repair window. **TCC attributes a helper's tap to the host app.** | Detector design. Keep capture in the main app. |
| **julIDE, FreeTube** taps | Own Homebrew tap, cask `postflight` runs `xattr -dr com.apple.quarantine` and prints a caveat | Distribution pattern |
| NameAlert, patter, switchscribe | Stay ad-hoc, tell users to re-grant after updates | The failure to avoid |

**Caveat:** this is PR and issue text, not field reports. One project (patter) says upgrade permission continuity is "unverified." I found no confirmed report for the audio-capture service on a second machine. The second-Mac test stays the gate.

### 17.3 Design: five layers

**Layer 1. Stable release identity (self-signed)**
- Create **one** certificate, once (§20.1): RSA 2048, 20-year validity, code-signing EKU.
- Private key lives in a GitHub **Environment** secret (`release`, required reviewer, tags only) plus one offline encrypted backup. Losing it forces a new identity, which forces every user to re-grant once.
- Commit the **public** cert and its SHA-1 (`release-cert.pem`, `release-cert.sha1`). CI refuses to sign with anything else.
- Sign nested code inside-out with the same identity, hardened runtime on, no timestamp (§20.2).
- Assert after signing: `codesign -d -r-` shows identifier + certificate hash and **never** `cdhash`.
- Fork and PR builds are ad-hoc. They never see the secret.
- Never change the bundle ID. Install to `/Applications`.
- Cert expiry doesn't matter to TCC matching, but use a long validity anyway so rotation is never forced.

**Layer 2. Local dev identity**
- `make setup-signing` creates a separate local self-signed cert (listn / AeroSpace pattern). If an Apple Development identity exists, prefer it (Tapmix pattern).
- Use a different bundle ID for dev builds (`…AppleRecorder.dev`) so dev and release grants never fight.

**Layer 3. Detection and recovery (in the app)** (§5.4, §5.5)
- Probe on arm, exact-zero-run detector, repair window listing only what's missing, one-click "Open Settings".
- Mic-only mode keeps working with a stale audio-capture grant.
- Capture runs in the **main app process**. If you ever add a helper, the usage string must be in the host's Info.plist or macOS never prompts.

**Layer 4. Distribution**
1. **Own Homebrew tap** with a cask that runs `xattr -dr com.apple.quarantine` in `postflight` and prints a caveat. Homebrew removed `--no-quarantine` in 5.1 and dropped unsigned casks from `homebrew/cask` on 2026-09-01, so only a third-party tap works, and the postflight is how julIDE and FreeTube do it. Homebrew maintainers discourage this, so keep it to your own tap and say so in the README.
2. **GitHub Releases DMG.** Gatekeeper warns; Privacy & Security → **Open Anyway** still works (Eclectic Light tested a quarantined ad-hoc app on Tahoe 26.6.1). Right-click → Open does not.
3. **Build from source.** `make install`. Locally built apps aren't quarantined. Everything must be signed, even ad-hoc; a broken signature is blocked outright.

**Layer 5. Trust**
- SHA-256 in release notes, reproducible build instructions.
- Build provenance is attested in `release.yml` with `actions/attest-build-provenance@v3` (free for public repos). Users verify a download with `gh attestation verify <file> -R corbinwrites/AppleRecorder`.
- Open source is the trust model. A self-signed cert proves "same publisher as last release", not "Apple checked it".

### 17.4 Options compared

| Option | Cost | Grants survive updates? | Notes |
|---|---|---|---|
| Ad-hoc | Free | **No** | Fine for local runs only |
| Ad-hoc with pinned identifier DR | Free | Locally yes (transcript #25) | Any ad-hoc binary with that identifier matches. Reject for releases. |
| Apple Development (free Apple ID) | Free | Yes while the cert lasts | Expires yearly, tied to one person. Expiry = cert change = everyone re-grants. Fits solo local builds only. |
| **Self-signed release cert** | Free | **Yes (community-proven, verify on second Mac)** | Recommended. Pin + fail-closed in CI. |
| Developer ID + notarization | $99/yr | Yes | Removes the Gatekeeper warning too |

### 17.5 Exit path (no lock-in)
Moving to Developer ID later costs one re-grant, the same as a cert rotation. So starting self-signed doesn't trap you. Pay the $99 if any of these happen:
1. The second-Mac update test fails for System Audio Recording.
2. Apple tightens Gatekeeper so quarantined self-signed apps can't be opened via Open Anyway.
3. Gatekeeper friction visibly hurts adoption.
4. The release key leaks and you want a revocable identity.

### 17.6 Updates
No Sparkle in v1. Updates are `brew upgrade` or re-download. Sparkle with EdDSA update signing is a v1.1 option: it doesn't need an Apple account, and an in-place update keeps the same certificate, so grants survive. Verify nested-binary signing rules first.

### 17.7 CI
- GitHub Actions on `macos-26` (free for public repos). Release job runs on tags only, in the `release` environment.
- Steps: import cert into a temporary keychain → sign → assert DR + pin → build DMG + zip → checksums + attestation → upload → bump tap.
- Repo hygiene: LICENSE, CONSENT.md, THIRD-PARTY-LICENSES.md (WhisperKit, models, any bundled fonts), screenshots per theme.

---

## 18. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Tap capture silent due to permission | **High (current evidence)** | §2 fix, zero-buffer detector, probe on arm |
| FM unavailable in sandbox | Medium | §13.3 gate, ship non-sandboxed |
| 8 GB memory pressure | Medium | One model at a time, `small` default, Instruments gate |
| FM guardrail false positives on sermons/names | Medium | Per-chunk fallback, never drop transcript |
| Whisper hallucination on silence | Medium | VAD + post-filters |
| TextKit 2 editor edge cases (IME, undo) | Medium | Line-based restyle, test early (G5) |
| Output-device switch kills tap | Medium | Rebuild listener, gap markers |
| macOS 27 SDK drift vs CI Xcode 26.6 | Low | Min OS 26, no 27-only APIs |
| Font license surprise | Low | Verify OFL, ship license files |
| Sacred component code license | Unknown | Check LICENSE.md, rebuild components rather than copy (v1.1 only) |
| **TCC resets on every update (ad-hoc signing)** | **High until the release cert is in place, then Low** | Stable self-signed release cert pinned in CI (§17.3), permission-loss detection, README steps |
| Release signing key leaked or lost | Low | GitHub Environment secret with required reviewer, tags only, offline backup. Loss or rotation = one re-grant for every user. |
| Gatekeeper friction scares users | Medium | Homebrew tap as primary path, build-from-source script |
| Far-field room audio transcribes poorly | Medium | Fixture D gate, bigger model option, diarization v1.1 |
| Hard-panned stereo annoys external playback | Low | In-app Center toggle, optional centered export |
| Glass hurts legibility if overused | Low | Glass on controls only, opaque editor surface |

---

## 19. Decisions

### Resolved (Rev 2)

| Decision | Answer |
|---|---|
| Developer fee | No. Free path (§17). Pay only if forced. |
| Audio storage | One stereo `.m4a` (L = mic, R = app). Mono for single source. |
| Single-source recording | Yes: Mic only and App only modes. |
| Window style | Native macOS 26 Liquid Glass. Sacred becomes an editor theme (v1) and a Terminal chrome preset (v1.1). |
| App name | Apple Recorder. Product `AppleRecorder.app`. Bundle ID `io.github.corbinwrites.AppleRecorder` (never changes after first release). |
| Repository | https://github.com/corbinwrites/AppleRecorder (`main`, MIT). Homebrew tap: `corbinwrites/homebrew-tap`. |

### Still open (defaults assumed)

| # | Decision | Default |
|---|---|---|
| 1 | Bundle ID confirmation | `io.github.corbinwrites.AppleRecorder`. Cannot change after the first release. |
| 2 | Signing identity for free builds | One self-signed release cert, pinned in CI (§17.3) |
| 3 | When to pay the $99 | Any §17.5 trigger: second-Mac test fails, Apple tightens Gatekeeper, adoption hurt, key leak |
| 4 | Sandbox | Non-sandboxed unless FM works sandboxed (§13.3) |
| 5 | Minimum OS | macOS 26.0 |
| 6 | Default editor font | System proportional |
| 7 | Frontmatter in output | On, toggleable |
| 8 | Audio link style | Relative Markdown link, `![[ ]]` optional |
| 9 | Diarization timing | v1.1, because room meetings need it |

---

## 20. Appendix: signing scripts

Starting points. Test each on a clean Mac.

### 20.1 Create the release certificate (once)

```bash
# scripts/make-release-cert.sh
set -euo pipefail
[ -e release-cert.pem ] && { echo "Refusing to overwrite: a new cert resets every user's permissions."; exit 1; }
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = AppleRecorder Release
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout release-key.pem -out release-cert.pem -days 7300 -config cert.cnf
# 3DES + SHA-1 so macOS `security import` accepts it (OpenSSL 3 defaults break import)
openssl pkcs12 -export -inkey release-key.pem -in release-cert.pem -out release.p12 \
  -name "AppleRecorder Release" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
openssl x509 -in release-cert.pem -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' > release-cert.sha1
base64 -i release.p12 | pbcopy   # paste into the MAC_SIGN_P12 environment secret
echo "Commit release-cert.pem + release-cert.sha1. Never commit release-key.pem or release.p12."
```

### 20.2 Import and sign in CI

```bash
# scripts/sign-release.sh <path/to/AppleRecorder.app>
set -euo pipefail
APP="$1"; KC="$RUNNER_TEMP/sign.keychain-db"; PIN="$(cat release-cert.sha1)"
echo "$MAC_SIGN_P12" | base64 -d > "$RUNNER_TEMP/release.p12"
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$RUNNER_TEMP/release.p12" -k "$KC" -P "$MAC_SIGN_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')

# Pin: refuse any other certificate
IMPORTED="$(openssl pkcs12 -in "$RUNNER_TEMP/release.p12" -passin env:MAC_SIGN_PASSWORD -nokeys -clcerts \
  | openssl x509 -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
[ "$IMPORTED" = "$PIN" ] || { echo "Wrong certificate. Aborting."; exit 1; }

# Inside-out: nested code first, then the app
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" -o -name "*.xpc" \) -print0 \
  | xargs -0 -n1 codesign --force --options runtime --timestamp=none --sign "$PIN" --keychain "$KC"
codesign --force --options runtime --timestamp=none --sign "$PIN" --keychain "$KC" \
  --entitlements App/AppleRecorder.entitlements "$APP"

# Assert identity-based DR, never cdhash
REQ="$(codesign -d -r- "$APP" 2>&1)"; echo "$REQ"
echo "$REQ" | grep -q 'cdhash' && { echo "DR is cdhash-based: not signed with the release cert"; exit 1; }
echo "$REQ" | grep -Eq 'certificate (leaf|root) = H"' || { echo "DR has no certificate hash"; exit 1; }
codesign --verify --deep --strict "$APP"
```

Notes:
- Sign by the SHA-1 hash. An untrusted self-signed cert may not appear in `security find-identity -v`.
- If `codesign --verify` complains about the untrusted root, see Meeting Manager #239 (mark the cert trusted for code signing in that keychain). The DR assertion is the check that matters for TCC.
- Run this job only on tags, in the protected `release` environment.

### 20.3 Homebrew cask (own tap)

```ruby
cask "apple-recorder" do
  version "1.0.0"
  sha256 "<sha256 of the zip>"
  url "https://github.com/corbinwrites/AppleRecorder/releases/download/v#{version}/AppleRecorder-#{version}.zip"
  name "AppleRecorder"
  desc "Local meeting recorder and note taker"
  homepage "https://github.com/corbinwrites/AppleRecorder"
  depends_on macos: ">= :tahoe"
  app "AppleRecorder.app"
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/AppleRecorder.app"]
  end
  caveats "This app is self-signed, not notarized. The cask removes the quarantine flag on install."
end
```

### 20.4 Verify on a second Mac (the gate)
1. Install v0.0.1 (release-signed). Grant Microphone and System Audio Recording. Record a clip, confirm non-silent audio.
2. Install v0.0.2 signed with the **same** cert over it (`brew upgrade` and manual copy, both).
3. Relaunch. Confirm no prompt, audio still non-silent, `codesign -d -r- /Applications/AppleRecorder.app` shows identifier + certificate hash.
4. Negative test: install an ad-hoc build over it. Confirm the app detects silence and explains the permission loss.
5. Record the macOS version and result. Fail on step 3 = trigger 1 in §17.5.

### 20.5 Local dev signing and `make install`

`scripts/setup-local-signing.sh` (run once per Mac via `make setup-signing`; this is the dev identity, **not** the release cert):

```bash
#!/usr/bin/env bash
set -euo pipefail
NAME="AppleRecorder Local Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "'$NAME' already exists"; exit 0; fi
TMP="$(mktemp -d)"; cd "$TMP"
cat > c.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 3650 -config c.cnf
openssl pkcs12 -export -inkey k.pem -in c.pem -out d.p12 -name "$NAME" -passout pass:ar \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import d.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P ar -T /usr/bin/codesign
rm -rf "$TMP"
echo "Created '$NAME'. If codesign asks for keychain access, choose Always Allow."
```

`scripts/sign-local.sh <app>` (used by `make install`; falls back to ad-hoc with a loud warning):

```bash
#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: sign-local.sh path/to/AppleRecorder.app}"
NAME="AppleRecorder Local Dev"
# Sign by SHA-1: an untrusted self-signed cert is hidden by `find-identity -v`.
ID="$(security find-identity -p codesigning | awk -v n="$NAME" 'index($0, n) { print $2; exit }')"
if [ -z "$ID" ]; then
  echo "WARNING: no '$NAME' identity. Signing ad-hoc: permissions reset on every rebuild. Run: make setup-signing" >&2
  ID="-"
fi
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" -o -name "*.xpc" \) -print0 \
  | xargs -0 -n1 codesign --force --options runtime --timestamp=none --sign "$ID"
codesign --force --options runtime --timestamp=none --sign "$ID" --entitlements App/AppleRecorder.entitlements "$APP"
codesign --verify --deep --strict "$APP" && echo "signed with: $ID"
```

Makefile targets (added in §22.4): `make setup-signing` runs the first script; `make install` builds Release with `CODE_SIGNING_ALLOWED=NO`, runs `sign-local.sh`, and copies the app to `/Applications`.

### 20.6 `scripts/verify-signing.sh` (run in CI and by hand)

```bash
#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: verify-signing.sh path/to/AppleRecorder.app}"
PIN="$(cat release-cert.sha1)"
fail() { echo "FAIL: $1"; exit 1; }
codesign --verify --deep --strict "$APP" || fail "signature invalid"
REQ="$(codesign -d -r- "$APP" 2>&1)"; echo "$REQ"
echo "$REQ" | grep -q 'cdhash' && fail "designated requirement is cdhash-based"
echo "$REQ" | grep -Eq 'certificate (leaf|root) = H"' || fail "no certificate hash in requirement"
TMP="$(mktemp -d)"; (cd "$TMP" && codesign -d --extract-certificates "$APP" >/dev/null 2>&1)
GOT="$(openssl x509 -inform DER -in "$TMP/codesign0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
[ "$GOT" = "$PIN" ] || fail "signed with a different certificate ($GOT)"
codesign -dv "$APP" 2>&1 | grep -q 'flags=.*runtime' || fail "hardened runtime is off"
codesign -d --entitlements - "$APP" 2>&1 | grep -q 'com.apple.security.device.audio-input' || fail "audio-input entitlement missing"
for k in NSMicrophoneUsageDescription NSAudioCaptureUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Contents/Info.plist" >/dev/null 2>&1 || fail "$k missing from Info.plist"
done
echo "PASS verify-signing"
```

### 20.7 `.github/workflows/release.yml`

```yaml
name: release
on:
  push:
    tags: ["v*"]
permissions:
  contents: write
  id-token: write
  attestations: write
jobs:
  release:
    runs-on: macos-26
    environment: release
    env:
      APP: build/Build/Products/Release/AppleRecorder.app
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: make test
      - name: Build (unsigned)
        run: |
          xcodegen generate
          xcodebuild -project AppleRecorder.xcodeproj -scheme AppleRecorder -configuration Release \
            -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
      - name: Sign with the pinned release certificate
        env:
          MAC_SIGN_P12: ${{ secrets.MAC_SIGN_P12 }}
          MAC_SIGN_PASSWORD: ${{ secrets.MAC_SIGN_PASSWORD }}
          KC_PASS: ${{ secrets.KC_PASS }}
        run: ./scripts/sign-release.sh "$APP"
      - run: ./scripts/verify-signing.sh "$APP"
      - name: Package
        run: |
          VER="${GITHUB_REF_NAME#v}"
          mkdir -p dist
          ditto -c -k --keepParent "$APP" "dist/AppleRecorder-$VER.zip"
          hdiutil create -volname "Apple Recorder" -srcfolder "$APP" -ov -format UDZO "dist/AppleRecorder-$VER.dmg"
          (cd dist && shasum -a 256 AppleRecorder-* > SHA256SUMS.txt)
      - uses: actions/attest-build-provenance@v3     # v4 is a wrapper over actions/attest; v3 is what GitHub's docs show
        with:
          subject-path: "dist/*"
      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "$GITHUB_REF_NAME" dist/* --title "Apple Recorder $GITHUB_REF_NAME" --generate-notes
```

The entitlements are applied inside `sign-release.sh` (§20.2), which is why the build step disables Xcode's own signing. Pull-request and fork builds never run this workflow.

### 20.8 `scripts/print-cask.sh` (prints the Homebrew cask for the tap repo)

```bash
#!/usr/bin/env bash
set -euo pipefail
V="${1:?version, e.g. 1.0.0}"; ZIP="${2:?path to AppleRecorder-$V.zip}"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
cat <<EOF
cask "apple-recorder" do
  version "$V"
  sha256 "$SHA"
  url "https://github.com/corbinwrites/AppleRecorder/releases/download/v#{version}/AppleRecorder-#{version}.zip"
  name "Apple Recorder"
  desc "Local meeting recorder and note taker"
  homepage "https://github.com/corbinwrites/AppleRecorder"
  depends_on macos: ">= :tahoe"
  app "AppleRecorder.app"
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/AppleRecorder.app"]
  end
  caveats "This app is self-signed, not notarized. The cask removes the quarantine flag on install."
end
EOF
```

A human pastes the output into `Casks/apple-recorder.rb` in `corbinwrites/homebrew-tap` after each release.

---

# PART 2: Implementation spec (for the builder)

Part 1 (§1–§20) says WHAT and WHY. Part 2 says HOW. If they conflict, Part 1 wins: write the conflict in `BLOCKERS.md` and stop.
Reference code below is a **starting point**. **The tests are the contract.** If code and test disagree, fix the code.

---

## 21. Builder rules (read first, obey always)

1. Work in the order of §32. Do not start a phase until the previous phase's exit checks pass.
2. One step = one commit: `P<phase>.<step>: <what>`. Run `make test` before every commit. Never commit a red test.
3. Never weaken, delete, skip, or rewrite a test to make it pass. If a test looks wrong, write why in `BLOCKERS.md` and stop.
4. Use exactly the names, paths, and signatures in this document. No renaming, no reorganizing, no "improvements".
5. Anything marked **[VERIFY]** is an API whose exact shape is unconfirmed. Compile it in the Step 0 spike (§23) first. If it doesn't compile, read Apple's docs, fix it, and record the real signature in `docs/API-NOTES.md`. Still stuck: `BLOCKERS.md`, stop.
6. Dependencies: **only** `argmax-oss-swift` (product `WhisperKit`). Nothing else. No swift-markdown in v1.
7. No network calls except WhisperKit's model download. No analytics, no telemetry.
8. Swift 6 language mode, strict concurrency complete. No `@unchecked Sendable` except where this document shows it. No `!` or `try!` outside tests. No `print` outside `SelfTest/` and `scripts/`; use `Logger`.
9. Realtime audio code lives only in `RealtimeCallback.swift`, follows §25.1, and `scripts/check-realtime.sh` must pass.
10. Never delete user data (notes, audio, transcripts) except on an explicit user action. Temp tracks are deleted only after `Finalizer` verification passes.
11. If a step needs hardware (mic, Discord, permission prompt, Apple Intelligence), do the software part, write the hardware test, and mark the step `NEEDS HUMAN` in `PROGRESS.md`. **Never fake hardware results.**
12. Keep `PROGRESS.md` current: per step, `done` / `blocked` / `NEEDS HUMAN`, plus the last `make test` summary line.
13. Ask no questions. Decide from this document. Undecidable → `BLOCKERS.md`.
14. Identifiers: app display name **Apple Recorder**, product/bundle name `AppleRecorder.app`, repo `AppleRecorder`, bundle ID `io.github.corbinwrites.AppleRecorder`. Never change the bundle ID after the first release (it resets every user's permissions).
15. Git: remote `origin` is `git@github.com:corbinwrites/AppleRecorder.git` (HTTPS: `https://github.com/corbinwrites/AppleRecorder.git`), branch `main`. Never force-push, never rewrite pushed history, never commit secrets (`*.p12`, `release-key.pem`, tokens, `.env`), never put credentials in a remote URL or a file. Push at the end of every phase (§22.6). If a push fails on authentication, keep working locally and record `NEEDS HUMAN: unpushed commits` in `PROGRESS.md`.
16. Never edit `docs/BUILD-GUIDE.md` or `docs/research/*`. They are the spec. A proposed change goes in `BLOCKERS.md` for a human to decide.
17. **Spec tests are frozen.** Every file under `Packages/*/Tests` and `App/UITests` that exists at git tag `spec-v1` may not be modified, renamed, or deleted. `scripts/protect-tests.sh` enforces it (verify, pre-commit, CI). You may add new test files. A test that looks wrong goes in `BLOCKERS.md`; only a human moves the tag.
18. **Never guess an Apple or WhisperKit API.** Run `scripts/apple-api.sh <Symbol>` (greps the SDK interfaces, headers, and SwiftPM checkouts) and read `docs/reference/sdk/`. Record the confirmed signature in `docs/API-NOTES.md`. Not found: `BLOCKERS.md`, stop.
19. **One step per session.** Read `AGENTS.md` and `docs/tasks/<step>.md` only. Task files are generated (`make tasks`); do not edit them. Run `swift test --filter <Suite>` for fast loops. The same failure after 3 attempts: `BLOCKERS.md`, stop.

---

## 22. Repo scaffold

### 22.1 Tree (create exactly this)

```
AppleRecorder/
├─ project.yml                      XcodeGen spec (source of truth for the Xcode project)
├─ Makefile  .gitignore  AGENTS.md  CLAUDE.md  HUMAN-TODO.md
├─ mk/agent.mk                      targets: hooks, tasks, step, protect
├─ PROGRESS.md  BLOCKERS.md  README.md  LICENSE  CONSENT.md  THIRD-PARTY-LICENSES.md
├─ .github/workflows/  ci.yml  release.yml
├─ App/
│  ├─ AppleRecorderApp.swift        @main, scenes, commands, menu bar extra
│  ├─ AppModel.swift                @Observable, @MainActor: owns store, settings, pipeline
│  ├─ Views/                        RootView, SidebarView, EditorPane, RecordCapsule, InspectorView, SettingsView, ConsentSheet
│  ├─ SelfTest/SelfTest.swift       `--selftest <name>` entry points (§31)
│  ├─ Info.plist  (generated)       AppleRecorder.entitlements
├─ Packages/
│  ├─ Core/        Sources/Core, Sources/CoreTestSupport, Tests/CoreTests
│  ├─ Capture/     Sources/Capture, Tests/CaptureTests
│  ├─ Transcribe/  Sources/Transcribe, Tests/TranscribeTests
│  ├─ Enhance/     Sources/Enhance, Tests/EnhanceTests
│  ├─ Output/      Sources/Output, Tests/OutputTests
│  ├─ Theme/       Sources/Theme, Tests/ThemeTests
│  ├─ EditorKit/   Sources/EditorKit, Tests/EditorKitTests
│  └─ Pipeline/    Sources/Pipeline, Tests/PipelineTests          ProcessingCoordinator (§30.1)
├─ Spikes/ApiCheck/                 Step 0 compile-check package (§23)
├─ Spikes/legacy-scripts/           L1/L3 scripts from the local spikes (copied in by a human, §22.6)
├─ scripts/  verify.sh  check-realtime.sh  make-release-cert.sh  sign-release.sh  verify-signing.sh
│            setup-local-signing.sh  sign-local.sh  print-cask.sh
│            protect-tests.sh  run-step.sh  split-guide.py  apple-api.sh  dump-sdk-interfaces.sh  hooks/pre-commit
└─ docs/  BUILD-GUIDE.md  API-NOTES.md  research/{web-research-findings.md, LOCAL-SPIKES-findings2.md}
         tasks/ (generated, plus tasks/src/ hand-written bodies)  reference/ (SDK dumps, validate_logic.py)
```

Dependency rules (enforced by `Package.swift`, no exceptions): `Core` depends on nothing. `Capture`, `Transcribe`, `Enhance`, `Output`, `Theme` depend only on `Core`. `Transcribe` also depends on WhisperKit. `EditorKit` depends on `Core` and `Theme`. `Pipeline` depends on `Core`, `Enhance`, `Output`. The app depends on all.

### 22.2 Package manifest template (`Packages/Core/Package.swift`; copy the shape for the others)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "CoreTestSupport", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core", "CoreTestSupport"]),
    ]
)
```

`Transcribe` adds:

```swift
dependencies: [.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0")],
// target deps:
.product(name: "WhisperKit", package: "argmax-oss-swift"),   // [VERIFY] product name via `swift package describe`
```

Other packages add `.package(path: "../Core")` and `"Core"` to target dependencies; tests also depend on `CoreTestSupport`.

### 22.3 `project.yml` (XcodeGen)

```yaml
name: AppleRecorder
options:
  bundleIdPrefix: io.github.corbinwrites
  deploymentTarget: { macOS: "26.0" }
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    ENABLE_HARDENED_RUNTIME: YES
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"          # CI overrides with the release cert (§20.2)
    PRODUCT_BUNDLE_IDENTIFIER: io.github.corbinwrites.AppleRecorder
packages:
  Core: { path: Packages/Core }
  Capture: { path: Packages/Capture }
  Transcribe: { path: Packages/Transcribe }
  Enhance: { path: Packages/Enhance }
  Output: { path: Packages/Output }
  Theme: { path: Packages/Theme }
  EditorKit: { path: Packages/EditorKit }
  Pipeline: { path: Packages/Pipeline }
targets:
  AppleRecorder:
    type: application
    platform: macOS
    sources: [App]
    dependencies:
      - { package: Core }
      - { package: Capture }
      - { package: Transcribe }
      - { package: Enhance }
      - { package: Output }
      - { package: Theme }
      - { package: EditorKit }
      - { package: Pipeline }
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Apple Recorder
        LSMinimumSystemVersion: "26.0"
        NSMicrophoneUsageDescription: "Apple Recorder records your microphone so it can transcribe your meetings."
        NSAudioCaptureUsageDescription: "Apple Recorder records audio from the app you choose so it can transcribe your meetings."
    entitlements:
      path: App/AppleRecorder.entitlements
      properties:
        com.apple.security.device.audio-input: true
  AppleRecorderUITests:
    type: bundle.ui-testing
    platform: macOS
    sources: [App/UITests]
    dependencies: [{ target: AppleRecorder }]
```

Non-sandboxed (no `app-sandbox` key). See §13.3.

### 22.4 `Makefile` (use real TAB characters)

```make
PKGS = Core Capture Transcribe Enhance Output Theme EditorKit Pipeline
-include mk/agent.mk
.PHONY: gen build test verify selftest setup-signing install
gen:
	xcodegen generate
build: gen
	xcodebuild -project AppleRecorder.xcodeproj -scheme AppleRecorder -configuration Debug -derivedDataPath build build
test:
	@for p in $(PKGS); do echo "== $$p"; (cd Packages/$$p && swift test) || exit 1; done
verify:
	./scripts/verify.sh
selftest: build
	./scripts/verify.sh --selftests
setup-signing:
	./scripts/setup-local-signing.sh
install: gen
	xcodebuild -project AppleRecorder.xcodeproj -scheme AppleRecorder -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
	./scripts/sign-local.sh build/Build/Products/Release/AppleRecorder.app
	rm -rf /Applications/AppleRecorder.app
	cp -R build/Build/Products/Release/AppleRecorder.app /Applications/
```

### 22.5 `PROGRESS.md` format

```
| Step | Status | Evidence |
| P1.1 Core models | done | make test: 14 passed |
| P4.6 Tap hardware | NEEDS HUMAN | selftest capture-tone not run |
```


### 22.6 GitHub repository

**Facts (checked 2026-11-19):** `https://github.com/corbinwrites/AppleRecorder` already exists. Branch `main` has one commit (`Initial commit`) containing only `README.md`:

```
# AppleRecorder
A vibecoded clone of Google Foresight that utilizes Apple Foundational Model or BYO AI
```

Do **not** create a new repo. Build on top of that commit. Keep the tagline as the first line under the README title.

**Remotes:** SSH `git@github.com:corbinwrites/AppleRecorder.git` (preferred), HTTPS `https://github.com/corbinwrites/AppleRecorder.git`.

**First push (P0.0).** Either clone fresh or use the seed repo zip (`AppleRecorder-repo-seed.zip`: a clone with one commit on top holding the docs and repo files):

```bash
git clone git@github.com:corbinwrites/AppleRecorder.git     # or: unzip AppleRecorder-repo-seed.zip && cd AppleRecorder
cd AppleRecorder
git remote -v                                               # origin must be the URL above
git pull --rebase origin main                               # always before pushing
git push -u origin main
```

**Rules**
- Commit often (one step = one commit, §21). Push at the end of every phase and after every step marked `NEEDS HUMAN` is resolved.
- Never `git push --force`. If a push is rejected, `git pull --rebase origin main`, rerun `make test`, push again. If the rebase conflicts, stop and write `BLOCKERS.md`.
- Never commit secrets. `scripts/verify.sh` fails if `*.p12`, `release-key.pem`, or `.env` is tracked. `release-cert.pem` and `release-cert.sha1` (public) **are** committed.
- Commit author: use the person's own git identity. If none is configured, stop and mark `NEEDS HUMAN`; do not invent one.
- Tags: `v0.0.N` for second-Mac update tests, `v1.0.0` for the release. Pushing a `v*` tag triggers `release.yml` (§20, §17.7).

**`.gitignore`**

```
.DS_Store
.build/
build/
DerivedData/
*.xcodeproj
*.xcuserstate
xcuserdata/
.swiftpm/
*.p12
release-key.pem
cert.cnf
.env
*.partial
```

(`*.xcodeproj` is generated by XcodeGen. Do not commit it.)

**GitHub settings (human, once)**
1. Actions enabled. Default branch `main`.
2. Settings → Environments → `release`: required reviewer = repo owner; deployment tags `v*` only.
3. Environment secrets: `MAC_SIGN_P12` (base64 of the `.p12`), `MAC_SIGN_PASSWORD`, `KC_PASS` (any random string). See §20.1, §20.2.
4. After the first green CI run: branch protection on `main` requiring the `ci` check (optional for a solo repo).
5. Create the Homebrew tap repo `corbinwrites/homebrew-tap` (empty, public). The cask lives at `Casks/apple-recorder.rb` (§20.3). Users: `brew install --cask corbinwrites/tap/apple-recorder`.

**README.md must contain (P0.1 writes a first version, P10 finalizes):** the tagline; status badge (`ci`); feature list (three capture modes, one stereo file, local transcription and notes, themes); **privacy statement** (audio and transcripts never leave the Mac; the only network use is the one-time model download from Hugging Face); **recording-consent warning** (§14); install paths (tap, DMG with "Open Anyway", build from source); permissions and the `tccutil reset All io.github.corbinwrites.AppleRecorder` troubleshooting steps (§17.4); license; link to `docs/BUILD-GUIDE.md`.

---

## 23. Step 0: API verification spike (do this before any feature code)

Create `Spikes/ApiCheck` (a Swift package with one executable target). One file per area. Each file must **compile**; hardware calls need not run. Record confirmed signatures in `docs/API-NOTES.md`.

| File | Must compile | Why |
|---|---|---|
| `TapCheck.swift` | `CATapDescription(monoMixdownOfProcesses:)`, `.muteBehavior = .unmuted`, `.isPrivate`, `.uuid`; `AudioHardwareCreateProcessTap`; `AudioHardwareDestroyProcessTap`; read `kAudioTapPropertyFormat`; `kAudioHardwarePropertyTranslatePIDToProcessObject`; `kAudioProcessPropertyIsRunningOutput`; `kAudioProcessPropertyPID`; `kAudioProcessPropertyBundleID` | Per-app capture |
| `AggregateCheck.swift` | `AudioHardwareCreateAggregateDevice` with `kAudioAggregateDevice{Name,UID,MainSubDevice,IsPrivate,TapList,SubDeviceList}Key`, `kAudioSubTapDriftCompensationKey`, `kAudioSubTapUIDKey`; `AudioDeviceCreateIOProcIDWithBlock` (**5-argument Void block**, per L1); `AudioDeviceStart/Stop` | Tap I/O |
| `MicCheck.swift` | `AVAudioEngine` input → mixer (48 kHz mono) → `installTap`; read `AVAudioTime.hostTime` | Mic track |
| `FileCheck.swift` | `AVAudioFile(forWriting:settings:)` for Int16 PCM `.caf` and AAC `.m4a` (2 ch, 48 kHz, 128 kbps); `AVAudioConverter` resample | Writers |
| `AtomicCheck.swift` | `import Synchronization`; `Atomic<Int>`, `.load(ordering:)`, `.store(_:ordering:)`, `.wrappingAdd(_:ordering:)` | Ring buffer |
| `FMCheck.swift` | `SystemLanguageModel.default.availability`, `.contextSize`, `tokenCount(for:)`, `LanguageModelSession(instructions:)`, `respond(to:generating:)` with a `@Generable` struct, `LanguageModelSession.GenerationError` cases | Notes AI |
| `WhisperCheck.swift` | `WhisperKitConfig(model:)`, `WhisperKit(_:)`, `transcribe(audioPath:decodeOptions:)`, `DecodingOptions` (chunking strategy, prompt tokens), result `segments[].start/.end/.text`, incremental audio loading option | Transcription |

Exit check: `cd Spikes/ApiCheck && swift build` succeeds, and `docs/API-NOTES.md` lists every **[VERIFY]** item with its confirmed signature or `NOT AVAILABLE`. If something is `NOT AVAILABLE`, stop and write `BLOCKERS.md`.

---

## 24. Core package

### 24.1 Models (`Packages/Core/Sources/Core/Models.swift`)

Every `public struct` needs an explicit `public init` (Swift does not synthesize public memberwise inits).

```swift
import Foundation

public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    case appAndMic, micOnly, appOnly
    public var hasMic: Bool { self != .appOnly }
    public var hasApp: Bool { self != .micOnly }
    public var channelCount: Int { self == .appAndMic ? 2 : 1 }
    public var labelsSpeakers: Bool { self == .appAndMic }
    public var frontmatterValue: String {
        switch self { case .appAndMic: "app+mic"; case .micOnly: "mic"; case .appOnly: "app" }
    }
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle, armed, recording, stopped, processing, done, failed

    public static let allowed: [SessionState: Set<SessionState>] = [
        .idle:       [.armed, .stopped],        // .stopped directly = imported audio
        .armed:      [.recording, .idle],
        .recording:  [.stopped, .failed],
        .stopped:    [.processing, .idle],      // .idle = discard
        .processing: [.done, .failed],
        .failed:     [.processing, .idle],      // retry or discard
        .done:       [.processing, .idle],      // re-transcribe or discard
    ]
    public func canTransition(to next: SessionState) -> Bool { Self.allowed[self]?.contains(next) ?? false }
}

public enum Speaker: String, Codable, Sendable { case me = "Me", them = "Them" }

public struct TranscriptSegment: Codable, Sendable, Equatable {
    public var start: Double        // seconds from recording start
    public var end: Double
    public var text: String
    public var speaker: Speaker?    // nil unless mode == .appAndMic
}

public struct TrackTiming: Codable, Sendable, Equatable {
    public var firstHostNanos: UInt64   // host time of first sample, in nanoseconds
    public var sampleRate: Double
    public var frames: Int64
    public var tempFileName: String     // e.g. "mic.caf" inside <session>/recording/
}

public struct Gap: Codable, Sendable, Equatable { public var atSeconds: Double; public var reason: String }
public struct FailureInfo: Codable, Sendable, Equatable { public var stage: String; public var message: String }

public struct Session: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var mode: CaptureMode
    public var sourceAppName: String?
    public var sourceBundleID: String?
    public var state: SessionState
    public var durationSeconds: Double?
    public var audioPath: String?        // absolute path of canonical .m4a
    public var notesPath: String?        // absolute path of exported .md
    public var micTrack: TrackTiming?
    public var appTrack: TrackTiming?
    public var gaps: [Gap]
    public var transcriptionModel: String?
    public var notesModel: String?
    public var failure: FailureInfo?
    public var recoveredFromCrash: Bool
    // init(title:mode:) sets: id=UUID(), createdAt=Date(), state=.idle, gaps=[], recoveredFromCrash=false, all optionals nil
}
```

### 24.2 Protocols and plain result types (`Protocols.swift`)

Core never imports FoundationModels or WhisperKit. Real engines live in `Transcribe` / `Enhance`; tests use fakes from `CoreTestSupport`.

```swift
public struct RawSegment: Sendable, Equatable { public var start: Double; public var end: Double; public var text: String }

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioFile: URL, vocabulary: [String],
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment]
}

public protocol TokenCounter: Sendable { func tokens(in text: String) async throws -> Int }

public struct ChunkDigest: Codable, Sendable, Equatable {
    public var topics: [String]; public var decisions: [String]; public var actionItems: [String]
    public var questions: [String]; public var keyPoints: [String]
    public var unavailable: Bool            // true = summary failed for this chunk (placeholder)
    public static let empty = ChunkDigest(topics: [], decisions: [], actionItems: [], questions: [], keyPoints: [], unavailable: false)
}

public struct MeetingNotesResult: Codable, Sendable, Equatable {
    public var summary: String; public var decisions: [String]; public var actionItems: [String]
    public var openQuestions: [String]; public var expandedNotes: String
}

public enum GeneratorError: Error, Sendable, Equatable { case contextExceeded, refused, rateLimited, unavailable(String) }

public protocol NotesGenerator: Sendable {
    func digest(transcriptChunk: String) async throws -> ChunkDigest
    func merge(digests: [ChunkDigest]) async throws -> ChunkDigest
    func finalize(userNotes: String, merged: ChunkDigest) async throws -> MeetingNotesResult
}
```

### 24.3 Settings (`Settings.swift`)

```swift
public enum AudioLinkStyle: String, Codable, Sendable { case markdownLink, wikiEmbed }
public enum ChromeStyle: String, Codable, Sendable { case native, terminal }

public struct AppSettings: Codable, Sendable, Equatable {
    public var notesFolderPath: String? = nil
    public var audioFolderPath: String? = nil
    public var transcriptionModel = "small"
    public var notesModel = "apple-foundation-models"
    public var frontmatter = true
    public var audioLinkStyle: AudioLinkStyle = .markdownLink
    public var exportCenteredMix = false
    public var themeID = "system"
    public var chrome: ChromeStyle = .native
    public var matchWindowToTheme = true
    public var editorFontName: String? = nil      // nil = system
    public var editorFontSize = 15.0
    public var vocabulary: [String] = []
    public var consentAcknowledged = false
    public var defaultMode: CaptureMode = .appAndMic
}
```

Persist as JSON through `SettingsStore` (file: `~/Library/Application Support/AppleRecorder/settings.json`):

```swift
public actor SettingsStore {
    public init(fileURL: URL)
    public func load() -> AppSettings          // defaults when the file is missing or corrupt; never throws or crashes
    public func save(_ s: AppSettings) throws  // atomic write, pretty-printed, sorted keys
}
```

### 24.4 Session store (`SessionStore.swift`)

Layout: `<root>/Sessions/<uuid>/{session.json, notes.md, recording/, transcript.json, digests.json}`.

```swift
public protocol SessionStore: Sendable {
    func create(title: String, mode: CaptureMode) async throws -> Session
    func save(_ s: Session) async throws
    func load(id: UUID) async throws -> Session
    func list() async throws -> [Session]                 // newest createdAt first
    func saveNotes(_ markdown: String, for id: UUID) async throws
    func loadNotes(for id: UUID) async throws -> String
    func delete(id: UUID) async throws                    // explicit user action only
    func recoverInterrupted() async throws -> [Session]   // see test
    func sessionDirectory(for id: UUID) -> URL
}
public actor FileSessionStore: SessionStore {
    public init(root: URL)
    public nonisolated func sessionDirectory(for id: UUID) -> URL      // must be nonisolated to satisfy the protocol
}
```

Rules: JSON uses `.iso8601` dates, `.prettyPrinted` + `.sortedKeys`; every write is atomic (`Data.write(to:options: .atomic)`). `recoverInterrupted()`: for each session whose state is `.recording` or `.armed`: if `recording/` contains any temp track file with size > 0 → state `.stopped`, `recoveredFromCrash = true`; otherwise → state `.failed` with `FailureInfo(stage: "recording", message: "No audio was saved")`. Sessions in `.processing` become `.failed` with stage `"processing"` and message `"Interrupted"`. Never touch `.done`.

### 24.5 Test support (`CoreTestSupport`)

```swift
import Foundation
import Core

public struct CharTokenCounter: TokenCounter {             // deterministic: ceil(chars / perToken)
    public let perToken: Int
    public init(perToken: Int = 4) { self.perToken = perToken }
    public func tokens(in text: String) async throws -> Int { (text.count + perToken - 1) / perToken }
}

public final class FakeNotesGenerator: NotesGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private var _digests: [String] = [], _merges: [[ChunkDigest]] = [], _finals: [(notes: String, merged: ChunkDigest)] = []
    public var onDigest: @Sendable (String) throws -> ChunkDigest = { _ in .empty }
    public var onMerge: @Sendable ([ChunkDigest]) throws -> ChunkDigest = { _ in .empty }
    public var onFinalize: @Sendable (String, ChunkDigest) throws -> MeetingNotesResult = { _, _ in
        MeetingNotesResult(summary: "S", decisions: [], actionItems: [], openQuestions: [], expandedNotes: "") }
    public init() {}
    public var digestInputs: [String] { lock.withLock { _digests } }
    public var mergeInputs: [[ChunkDigest]] { lock.withLock { _merges } }
    public var finalizeInputs: [(notes: String, merged: ChunkDigest)] { lock.withLock { _finals } }
    public func digest(transcriptChunk: String) async throws -> ChunkDigest {
        lock.withLock { _digests.append(transcriptChunk) }          // record first, then run the closure outside the lock
        return try onDigest(transcriptChunk)
    }
    public func merge(digests: [ChunkDigest]) async throws -> ChunkDigest {
        lock.withLock { _merges.append(digests) }
        return try onMerge(digests)
    }
    public func finalize(userNotes: String, merged: ChunkDigest) async throws -> MeetingNotesResult {
        lock.withLock { _finals.append((userNotes, merged)) }
        return try onFinalize(userNotes, merged)
    }
}

public struct FakeTranscriptionEngine: TranscriptionEngine {
    public var result: [RawSegment]; public var error: (any Error)?
    public init(result: [RawSegment] = [], error: (any Error)? = nil) { self.result = result; self.error = error }
    public func transcribe(audioFile: URL, vocabulary: [String], onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment] {
        onProgress(0.5); if let error { throw error }; onProgress(1); return result
    }
}

public func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("ar-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
public func / (lhs: URL, rhs: String) -> URL { lhs.appendingPathComponent(rhs) }       // used by tests: dir/"mic.caf"
```

### 24.6 Core tests (`Tests/CoreTests`, Swift Testing; write all of them)

```swift
import Testing
import Foundation
@testable import Core
import CoreTestSupport

@Suite struct StateMachineTests {
    static let expected: Set<String> = [                       // spelled out independently of the implementation
        "idle>armed", "idle>stopped", "armed>recording", "armed>idle", "recording>stopped",
        "recording>failed", "stopped>processing", "stopped>idle", "processing>done",
        "processing>failed", "failed>processing", "failed>idle", "done>processing", "done>idle",
    ]
    @Test func fullMatrix() {
        for a in SessionState.allCases { for b in SessionState.allCases {
            #expect(a.canTransition(to: b) == Self.expected.contains("\(a.rawValue)>\(b.rawValue)"), "\(a) -> \(b)")
        } }
    }
    @Test func nothingTransitionsToItself() { for s in SessionState.allCases { #expect(!s.canTransition(to: s)) } }
}

@Suite struct CaptureModeTests {
    @Test func properties() {
        #expect(CaptureMode.appAndMic.channelCount == 2)
        #expect(CaptureMode.micOnly.channelCount == 1 && CaptureMode.appOnly.channelCount == 1)
        #expect(CaptureMode.appAndMic.labelsSpeakers && !CaptureMode.micOnly.labelsSpeakers && !CaptureMode.appOnly.labelsSpeakers)
        #expect(CaptureMode.micOnly.hasMic && !CaptureMode.micOnly.hasApp)
        #expect(CaptureMode.appOnly.hasApp && !CaptureMode.appOnly.hasMic)
        #expect(CaptureMode.appAndMic.frontmatterValue == "app+mic")
        #expect(CaptureMode.micOnly.frontmatterValue == "mic" && CaptureMode.appOnly.frontmatterValue == "app")
    }
}

@Suite struct SessionStoreTests {
    private func writeTrack(_ store: FileSessionStore, _ id: UUID, bytes: Int) throws {
        let rec = store.sessionDirectory(for: id).appendingPathComponent("recording", isDirectory: true)
        try FileManager.default.createDirectory(at: rec, withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: rec / "mic.caf")
    }
    @Test func roundTrip() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "Weekly sync", mode: .appAndMic)
        s.sourceAppName = "Discord"; s.state = .stopped; s.durationSeconds = 12.5
        try await store.save(s)
        #expect(try await store.load(id: s.id) == s)
    }
    @Test func listNewestFirst() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var ids: [UUID] = []
        for i in 0..<3 {
            var s = try await store.create(title: "S\(i)", mode: .micOnly)
            s.createdAt = Date(timeIntervalSince1970: 1_000 + Double(i) * 100)
            try await store.save(s); ids.append(s.id)
        }
        #expect(try await store.list().map(\.id) == ids.reversed())
    }
    @Test func notesRoundTripUnicode() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        let s = try await store.create(title: "N", mode: .micOnly)
        let text = "héllo ✓ 日本語\n- [ ] x\n"
        try await store.saveNotes(text, for: s.id)
        #expect(try await store.loadNotes(for: s.id) == text)
    }
    @Test func recoverRecordingWithAudio() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "R", mode: .appAndMic); s.state = .recording; try await store.save(s)
        try writeTrack(store, s.id, bytes: 10)
        let recovered = try await store.recoverInterrupted()
        #expect(recovered.count == 1 && recovered[0].state == .stopped && recovered[0].recoveredFromCrash)
        #expect(try await store.load(id: s.id).state == .stopped)
    }
    @Test func recoverRecordingWithoutAudio() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "R", mode: .micOnly); s.state = .recording; try await store.save(s)
        let r = try await store.recoverInterrupted()
        #expect(r[0].state == .failed && r[0].failure?.stage == "recording" && r[0].failure?.message == "No audio was saved")
    }
    @Test func zeroByteTrackCountsAsNoAudio() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "R", mode: .micOnly); s.state = .armed; try await store.save(s)
        try writeTrack(store, s.id, bytes: 0)
        #expect(try await store.recoverInterrupted()[0].state == .failed)
    }
    @Test func recoverProcessing() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "P", mode: .micOnly); s.state = .processing; try await store.save(s)
        let r = try await store.recoverInterrupted()
        #expect(r[0].state == .failed && r[0].failure?.stage == "processing" && r[0].failure?.message == "Interrupted")
    }
    @Test func doneIsUntouched() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "D", mode: .micOnly); s.state = .done; try await store.save(s)
        #expect(try await store.recoverInterrupted().isEmpty)
        #expect(try await store.load(id: s.id) == s)
    }
    @Test func corruptSessionJSONDoesNotCrashList() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        let good = try await store.create(title: "Good", mode: .micOnly)
        let bad = try await store.create(title: "Bad", mode: .micOnly)
        try Data("{not json".utf8).write(to: store.sessionDirectory(for: bad.id) / "session.json")
        #expect(try await store.list().map(\.id) == [good.id])
    }
}

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = AppSettings()
        #expect(s.transcriptionModel == "small" && s.notesModel == "apple-foundation-models")
        #expect(s.frontmatter && s.audioLinkStyle == .markdownLink && !s.exportCenteredMix && !s.consentAcknowledged)
        #expect(s.themeID == "system" && s.chrome == .native && s.defaultMode == .appAndMic)
    }
    @Test func missingOrCorruptFileYieldsDefaults() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "settings.json"
        #expect(await SettingsStore(fileURL: url).load() == AppSettings())
        try Data("garbage".utf8).write(to: url)
        #expect(await SettingsStore(fileURL: url).load() == AppSettings())
    }
    @Test func roundTrip() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir / "settings.json")
        var s = AppSettings()
        s.notesFolderPath = "/tmp/n"; s.audioFolderPath = "/tmp/a"; s.transcriptionModel = "large-v3-v20240930_626MB"
        s.frontmatter = false; s.audioLinkStyle = .wikiEmbed; s.exportCenteredMix = true; s.themeID = "dracula"
        s.matchWindowToTheme = false; s.editorFontName = "Geist Mono"; s.editorFontSize = 18
        s.vocabulary = ["Soteriology", "Talbot"]; s.consentAcknowledged = true; s.defaultMode = .micOnly
        try await store.save(s)
        #expect(await store.load() == s)
    }
}
```

### 24.7 Small pure helpers (Core): `SessionGrouping`, `Timecode`, `MeterGlyph`, `ProgressBar`

```swift
public struct SessionGroup: Equatable, Sendable { public var title: String; public var sessions: [Session] }
public enum SessionGrouping {
    /// Groups "Today", "Yesterday", "Earlier" (in that order, empty groups omitted). Each group newest first. Future dates count as Today.
    public static func group(_ sessions: [Session], now: Date, calendar: Calendar) -> [SessionGroup]
}
public enum Timecode {
    public static func string(_ seconds: Double) -> String   // "mm:ss", or "h:mm:ss" from 1 h; truncates; negative -> "00:00"
    public static func hms(_ seconds: Double) -> String      // always "HH:MM:SS"
}
public enum MeterGlyph {
    /// db = 20*log10(max(peak, 1e-9)); db > -6 "█", > -12 "▇", > -18 "▆", > -24 "▅", > -36 "▄", > -48 "▃", > -60 "▂", else "▁".
    public static func glyph(forPeak peak: Float) -> Character
}
public enum ProgressBar {
    /// "[██████░░░░] 62%" with `cells` (default 10) cells; filled = floor(fraction * cells); fraction clamped to 0...1; NaN -> 0.
    public static func text(fraction: Double, cells: Int = 10) -> String
}
public enum ProcessingStage: String, Codable, Sendable, CaseIterable {
    case loadingModel, transcribing, merging, loadingNotesModel, enhancing, writing
}
extension ProcessingStage { public var title: String { /* loadingModel "Loading model", transcribing "Transcribing", merging "Merging", loadingNotesModel "Loading notes model", enhancing "Enhancing notes", writing "Writing files" */ } }
```

`ProcessingStage` is defined in `Core` right above (`Pipeline` imports it). Use `Timecode` everywhere: `Chunker.line`, `MarkdownRenderer`, the inspector.

```swift
@Suite struct SessionGroupingTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    static let now = ISO8601DateFormatter().date(from: "2026-11-18T18:30:00Z")!        // 10:30 PST
    func session(_ iso: String) -> Session {
        var s = Session(title: iso, mode: .micOnly); s.createdAt = ISO8601DateFormatter().date(from: iso)!; return s
    }
    @Test func groups() {
        let a = session("2026-11-18T18:00:00Z")      // 10:00 today
        let b = session("2026-11-18T08:00:00Z")      // 00:00 today (boundary)
        let c = session("2026-11-18T07:59:00Z")      // 23:59 yesterday
        let d = session("2026-11-16T20:00:00Z")      // two days ago
        let g = SessionGrouping.group([d, c, b, a], now: Self.now, calendar: Self.cal)
        #expect(g.map(\.title) == ["Today", "Yesterday", "Earlier"])
        #expect(g[0].sessions.map(\.id) == [a.id, b.id])
        #expect(g[1].sessions.map(\.id) == [c.id] && g[2].sessions.map(\.id) == [d.id])
    }
    @Test func emptyGroupsOmitted() {
        let g = SessionGrouping.group([session("2026-11-10T20:00:00Z")], now: Self.now, calendar: Self.cal)
        #expect(g.map(\.title) == ["Earlier"])
        #expect(SessionGrouping.group([], now: Self.now, calendar: Self.cal).isEmpty)
    }
    @Test func futureCountsAsToday() {
        #expect(SessionGrouping.group([session("2026-11-19T20:00:00Z")], now: Self.now, calendar: Self.cal).first?.title == "Today")
    }
}
@Suite struct HelperTests {
    @Test func timecode() {
        let cases: [(Double, String, String)] = [(0, "00:00", "00:00:00"), (12.9, "00:12", "00:00:12"), (59, "00:59", "00:00:59"),
            (60, "01:00", "00:01:00"), (3599, "59:59", "00:59:59"), (3600, "1:00:00", "01:00:00"), (3661, "1:01:01", "01:01:01"), (-5, "00:00", "00:00:00")]
        for (s, a, b) in cases { #expect(Timecode.string(s) == a); #expect(Timecode.hms(s) == b) }
    }
    @Test func meterGlyphs() {
        let cases: [(Float, Character)] = [(1.0, "█"), (0.5, "▇"), (0.25, "▆"), (0.125, "▅"), (0.0625, "▄"), (0.01, "▃"), (0.002, "▂"), (0.0005, "▁"), (0, "▁")]
        for (p, g) in cases { #expect(MeterGlyph.glyph(forPeak: p) == g, "peak \(p)") }
    }
    @Test func progressBar() {
        #expect(ProgressBar.text(fraction: 0) == "[░░░░░░░░░░] 0%")
        #expect(ProgressBar.text(fraction: 0.62) == "[██████░░░░] 62%")
        #expect(ProgressBar.text(fraction: 1) == "[██████████] 100%")
        #expect(ProgressBar.text(fraction: 7) == "[██████████] 100%" && ProgressBar.text(fraction: -1) == "[░░░░░░░░░░] 0%")
        #expect(ProgressBar.text(fraction: .nan) == "[░░░░░░░░░░] 0%")
        #expect(ProgressBar.text(fraction: 0.5, cells: 4) == "[██░░] 50%")
    }
    @Test func stageTitles() { for s in ProcessingStage.allCases { #expect(!s.title.isEmpty) } }
}
```

Fill in nothing else: every test above is complete. Percent in `ProgressBar` = `Int(fraction.clamped * 100)` truncated.

Exit check P1: `cd Packages/Core && swift test` all green, ≥ 35 test cases.

---

## 25. Capture package

### 25.1 Realtime rules (hard)

`RealtimeCallback.swift` is the only file that runs on the Core Audio realtime thread. In that file: **no** logging, allocation, locks, `async`/`await`, `Task`, dispatch, `throw`/`try`, `append`, `Array(`/`String(` construction, `print`. Do not even mention those words in comments (the check script greps the file). It copies samples into a preallocated `RingBuffer` and records the first host time. Nothing else. Peak detection, zero-run detection, downmix, and file I/O happen on the **consumer** side (`TrackWriter`).

```swift
// Packages/Capture/Sources/Capture/RealtimeCallback.swift
import CoreAudio

/// Builds the IO block for the tap's aggregate device. `firstHostTime` points to preallocated storage owned by TapSession.
public func makeTapIOBlock(ring: RingBuffer,
                           firstHostTime: UnsafeMutablePointer<UInt64>) -> AudioDeviceIOBlock {
    return { _, inInputData, inInputTime, _, _ in
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard let buffer = list.first, let raw = buffer.mData else { return }
        if firstHostTime.pointee == 0 { firstHostTime.pointee = inInputTime.pointee.mHostTime }
        let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        _ = ring.write(raw.assumingMemoryBound(to: Float.self), count: samples)
    }
}
```

`scripts/check-realtime.sh`:

```bash
#!/usr/bin/env bash
set -u
F="Packages/Capture/Sources/Capture/RealtimeCallback.swift"
BAD='print\(|NSLog|Logger|os_log|Task[ ]*\{|await |async |DispatchQueue|DispatchSemaphore|NSLock|OSAllocatedUnfairLock|Mutex|\.append\(|Array\(|String\(|malloc|try[ ?!]|throw |fatalError|precondition'
HITS=$(grep -v '^[[:space:]]*//' "$F" | grep -nE "$BAD")
if [ -n "$HITS" ]; then echo "FAIL realtime check:"; echo "$HITS"; exit 1; fi
echo "PASS realtime check"
```

### 25.2 `RingBuffer` (single producer, single consumer, lock-free)

```swift
import Synchronization

public final class RingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    public let capacity: Int
    private let head = Atomic<Int>(0)      // total samples ever written (producer owns)
    private let tail = Atomic<Int>(0)      // total samples ever read (consumer owns)
    private let dropped = Atomic<Int>(0)

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }
    deinit { storage.deallocate() }

    /// Producer. Returns samples written. Anything that doesn't fit is dropped and counted (newest samples are dropped).
    @inline(__always) @discardableResult
    public func write(_ src: UnsafePointer<Float>, count: Int) -> Int {
        let h = head.load(ordering: .relaxed), t = tail.load(ordering: .acquiring)
        let n = min(count, capacity - (h - t))
        if n < count { _ = dropped.wrappingAdd(count - n, ordering: .relaxed) }
        if n > 0 {
            let start = h % capacity, first = min(n, capacity - start)
            (storage + start).update(from: src, count: first)
            if n > first { storage.update(from: src + first, count: n - first) }
            head.store(h + n, ordering: .releasing)
        }
        return n
    }

    /// Consumer. Returns samples read (<= max).
    public func read(into dst: UnsafeMutablePointer<Float>, max: Int) -> Int {
        let t = tail.load(ordering: .relaxed), h = head.load(ordering: .acquiring)
        let n = min(max, h - t)
        if n > 0 {
            let start = t % capacity, first = min(n, capacity - start)
            dst.update(from: storage + start, count: first)
            if n > first { (dst + first).update(from: storage, count: n - first) }
            tail.store(t + n, ordering: .releasing)
        }
        return n
    }
    public var droppedSamples: Int { dropped.load(ordering: .relaxed) }
    public var availableToRead: Int { head.load(ordering: .acquiring) - tail.load(ordering: .relaxed) }
}
```

Tests (`RingBufferTests`):
- `orderPreserved`: write [1…5], read 5 → same values.
- `wraparound`: capacity 8; write 6, read 4, write 6 (fits: 2 + 6 = 8), read all → `[5,6,1,2,3,4,5,6]` pattern (assert exact sequence of what was written).
- `overrunDropsNewestAndCounts`: capacity 4, write 10 samples → returns 4, `droppedSamples == 6`, read returns the first 4.
- `readEmptyReturnsZero`.
- `zeroCountWriteIsNoop`.
- `spscStress`: producer thread writes values `0..<200_000` in random chunk sizes 1…512 into capacity 4096; consumer thread reads concurrently until producer done and buffer empty. Assert: received values strictly increasing; `received.count + droppedSamples == 200_000`. Run 5 times. **Run this test under Thread Sanitizer** (`swift test --sanitize=thread`); it must be clean.
- The stress test uses an explicit completion semaphore to synchronize the consumer's final array writes before assertions.

### 25.3 `ZeroRunDetector` (pure)

```swift
public struct ZeroRunDetector: Sendable {
    public let sampleRate: Double, thresholdSeconds: Double
    private var zeroFrames = 0
    public private(set) var tripped = false
    public init(sampleRate: Double, thresholdSeconds: Double = 3.0) { self.sampleRate = sampleRate; self.thresholdSeconds = thresholdSeconds }

    /// peak = max |sample| of the block. Returns true exactly once per run, the moment the run reaches the threshold.
    public mutating func feed(peak: Float, frames: Int, outputRunning: Bool) -> Bool {
        guard peak == 0, outputRunning else { zeroFrames = 0; tripped = false; return false }
        zeroFrames += frames
        if !tripped, Double(zeroFrames) >= thresholdSeconds * sampleRate { tripped = true; return true }
        return false
    }
}
```

Tests (block = 4,800 frames = 0.1 s at 48 kHz; `feed(peak: 0, frames: 4800, outputRunning: true)` unless stated):
1. 29 blocks → all `false`; the 30th → `true`; the 31st → `false`; `tripped == true`.
2. 100 zero blocks with `outputRunning: false` → never `true`.
3. 20 zero blocks, one block `peak: 0.001`, 20 zero blocks → never `true`.
4. After tripping, one non-zero block → `tripped == false`; then 30 zero blocks → `true` again.
5. 20 zero blocks, 1 block `outputRunning: false`, 20 zero blocks → never `true` (run is reset).
6. `peak: 1e-9` counts as signal (resets the run).
7. `thresholdSeconds: 1` at 44,100 Hz: 9 blocks of 4,410 frames → `false`; the 10th → `true`.

### 25.4 `HostClock` and offsets (pure)

```swift
import Darwin
public enum HostClock {
    nonisolated(unsafe) private static let info: mach_timebase_info_data_t = { var i = mach_timebase_info_data_t(); mach_timebase_info(&i); return i }()
    public static func nanos(hostTime: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        let d = UInt64(denom), n = UInt64(numer)
        return (hostTime / d) * n + (hostTime % d) * n / d            // overflow-safe
    }
    public static func nanos(hostTime: UInt64) -> UInt64 { nanos(hostTime: hostTime, numer: info.numer, denom: info.denom) }
    /// Frames of leading silence for a track that started `trackStartNanos`, relative to the earliest track.
    public static func startOffsetFrames(trackStartNanos: UInt64, referenceNanos: UInt64, sampleRate: Double) -> Int {
        guard trackStartNanos > referenceNanos else { return 0 }
        return Int((Double(trackStartNanos - referenceNanos) / 1e9 * sampleRate).rounded())
    }
}
```

Tests:
- `nanos(hostTime: 3000, numer: 125, denom: 3) == 125_000`; `numer: 1, denom: 1` is identity.
- Overflow: for `hostTime = 10^16`, `numer 125`, `denom 3`: result equals `UInt64((UInt128(10^16) * 125) / 3)` (independent big-int computation).
- Offsets: same time → 0; +500 ms @48 kHz → 24,000; +1 s @44.1 kHz → 44,100; +1 µs @48 kHz → 0 (rounds); +10.5 ms @48 kHz → 504; track earlier than reference → 0.

### 25.5 `ProcessCatalog` (pure grouping; Discord's helpers become one entry)

```swift
public struct AudioProcessInfo: Sendable, Equatable {
    public var objectID: UInt32; public var pid: Int32
    public var bundleID: String?; public var executablePath: String?; public var isRunningOutput: Bool
}
public struct AppEntry: Sendable, Equatable, Identifiable {
    public var id: String; public var displayName: String
    public var objectIDs: [UInt32]; public var isRunningOutput: Bool
}
public enum ProcessCatalog { public static func group(_ procs: [AudioProcessInfo]) -> [AppEntry] }
```

Grouping key, in order: (1) the executable path up to and including its **first** path component ending in `.app` (the outermost bundle; helper apps live inside it); display name = that component without `.app`. (2) else the bundle ID cut at the first `.helper` (case-insensitive); display name = last dot-component. (3) else `pid:<pid>`, display name `Process <pid>`. `objectIDs` ascending; `isRunningOutput` = any member; entries sorted running-first, then by display name case-insensitively.

Tests:
- **Discord fixture (from the L1 spike):** four processes `143` (`com.hnc.Discord.helper.Renderer`, `/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)`), `144` (`com.hnc.Discord`, `/Applications/Discord.app/Contents/MacOS/Discord`), `145` (no bundle ID, path `…/Discord Helper (GPU).app/…`), `146` (`com.hnc.Discord.helper`, `…/Discord Helper.app/…`) → exactly **one** entry named `Discord` with `objectIDs == [143,144,145,146]`.
- Spotify (`/Applications/Spotify.app/Contents/MacOS/Spotify`) + Discord → two entries; the one with `isRunningOutput == true` sorts first.
- No paths, bundle IDs `com.hnc.Discord` and `com.hnc.Discord.helper.GPU` → one entry `Discord`.
- No path, no bundle ID → `Process 4242`.
- Empty input → `[]`. Input order shuffled → identical output.

### 25.6 Tap and mic sessions (hardware; reference code, **[VERIFY]** everything)

```swift
import CoreAudio, AVFoundation

public enum CaptureError: Error, Sendable { case osStatus(String, Int32), noFormat, deviceNotFound }
@inline(__always) func check(_ what: String, _ s: OSStatus) throws { if s != noErr { throw CaptureError.osStatus(what, s) } }

public final class TapSession: @unchecked Sendable {
    public let ring: RingBuffer
    public private(set) var sampleRate: Double = 48_000
    public private(set) var channels = 1
    private var tapID = AudioObjectID(kAudioObjectUnknown), aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let firstHost = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
    private let queue = DispatchQueue(label: "AppleRecorder.tap.io", qos: .userInteractive)
    public var firstHostTime: UInt64 { firstHost.pointee }

    public init(processObjectIDs: [UInt32], ringSeconds: Double = 10) throws {
        firstHost.initialize(to: 0)
        ring = RingBuffer(capacity: Int(48_000 * 2 * ringSeconds))
        let desc = CATapDescription(monoMixdownOfProcesses: processObjectIDs.map { AudioObjectID($0) })
        desc.uuid = UUID(); desc.muteBehavior = .unmuted; desc.isPrivate = true
        try check("CreateProcessTap", AudioHardwareCreateProcessTap(desc, &tapID))

        var fmt = AudioStreamBasicDescription(); var sz = UInt32(MemoryLayout.size(ofValue: fmt))
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check("TapFormat", AudioObjectGetPropertyData(tapID, &addr, 0, nil, &sz, &fmt))
        sampleRate = fmt.mSampleRate; channels = Int(fmt.mChannelsPerFrame)

        let outUID = try defaultOutputDeviceUID()
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppleRecorder Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        try check("CreateAggregate", AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID))
    }
    public func start() throws {
        let block = makeTapIOBlock(ring: ring, firstHostTime: firstHost)
        try check("CreateIOProc", AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue, block))
        try check("DeviceStart", AudioDeviceStart(aggID, procID))
    }
    public func stop() {
        if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }
    deinit { stop(); firstHost.deallocate() }
}
```

`defaultOutputDeviceUID()`: read `kAudioHardwarePropertyDefaultOutputDevice` from `kAudioObjectSystemObject`, then `kAudioDevicePropertyDeviceUID` as `Unmanaged<CFString>?` → `takeRetainedValue() as String`.
`AudioProcessEnumerator.list() -> [AudioProcessInfo]`: read `kAudioHardwarePropertyProcessObjectList`; per object read `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunningOutput`; executable path from `proc_pidpath(pid, …)`.

`MicSession` (reference): `AVAudioEngine`; `engine.connect(engine.inputNode, to: mixer, format: inputFormat)`; `mixer.installTap(onBus: 0, bufferSize: 4096, format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))` → in the block copy `buffer.floatChannelData![0]` into its own `RingBuffer` and store the first `when.hostTime`. Expose `sampleRate = 48_000`, `channels = 1`, `firstHostTime`, `start()`, `stop()`, `ring`. Selected input device: set via `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` on `engine.inputNode.audioUnit` **[VERIFY]**.

### 25.7 `TrackWriter` (consumer side: drains ring, downmixes, detects, writes Int16 mono CAF)

```swift
public final class TrackWriter: @unchecked Sendable {
    public init(ring: RingBuffer, channels: Int, sampleRate: Double, url: URL,
                onBlock: @escaping @Sendable (_ peak: Float, _ frames: Int) -> Void) throws
    public func start()                      // dedicated Thread; poll every 20 ms; max 4,800 frames per read
    public func stopAndFlush() throws -> Int64   // stop thread, drain ring completely, close file, return frames written
    public var droppedSamples: Int { get }
}
```

File settings: Linear PCM, 16-bit integer, mono, `sampleRate` as captured, `.caf`. Downmix = mean of interleaved channels. `peak` = max |sample| of the block **after** downmix, before writing. Allocate the `AVAudioPCMBuffer` once.

Tests (`TrackWriterTests`, no hardware: a test thread plays producer into the ring):
- Write a 2 s 440 Hz sine at 48 kHz in random chunks → `stopAndFlush()` returns `96_000` ± 0; reading the CAF back gives the same samples within Int16 quantization (max abs error ≤ 1/32768 × 2).
- Stereo interleaved input `[L=1.0, R=0.0, …]` → file contains `0.5` (mean).
- `onBlock` receives peak `0` for a silent input and the frames sum equals total frames.
- `stopAndFlush()` called twice → second call returns the same count and does not throw.
- Producer faster than disk (tiny ring) → `droppedSamples > 0` is reported, frames written + dropped == produced.

### 25.8 `Finalizer` (stereo/mono `.m4a` from temp tracks; software-testable)

```swift
public struct TrackInput: Sendable { public var url: URL; public var startNanos: UInt64
    public init(url: URL, startNanos: UInt64) { self.url = url; self.startNanos = startNanos } }
public struct ChannelReport: Sendable, Equatable { public var peak: Float; public var rms: Float; public var isSilent: Bool }
public struct FinalizeReport: Sendable, Equatable {
    public var durationSeconds: Double; public var channels: Int
    public var mic: ChannelReport?; public var app: ChannelReport?     // nil when that source was not recorded
}
public enum FinalizeError: Error, Sendable, Equatable { case noInput, cannotRead(String), verificationFailed(String) }

public enum Finalizer {
    public static let sampleRate = 48_000.0
    /// mic -> channel 0, app -> channel 1 when both exist; otherwise a single mono channel.
    public static func finalize(mic: TrackInput?, app: TrackInput?, to output: URL) throws -> FinalizeReport
}
```

Algorithm (contract):
1. Both nil → `.noInput`.
2. `reference = min(startNanos of present tracks)`; each track's leading silence = `HostClock.startOffsetFrames(…, sampleRate: 48_000)`.
3. Each track is read through a `TrackReader`: streams the CAF in blocks, resamples to 48 kHz mono Float32 with `AVAudioConverter` when the source rate differs, prepends leading silence, zero-pads after EOF. **Never load a whole track into memory.**
4. Output: `AVAudioFile(forWriting: output, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: n, AVEncoderBitRateKey: n == 2 ? 128_000 : 64_000])`; loop in 48,000-frame blocks until every reader is finished; write non-interleaved Float32 buffers; accumulate per-channel peak and sum of squares.
5. Verify: reopen `output`; decoded duration within ±0.15 s of the expected duration; else `.verificationFailed("duration")`. A silent channel is **reported** (`isSilent = peak < 0.001`), never an error.
6. Write to `output.appendingPathExtension("partial")` then rename, so a crash never leaves a half-written `.m4a`.

Test helpers (`Tests/CaptureTests/AudioTestHelpers.swift`; write these exactly):

```swift
import AVFoundation
func writeSine(to url: URL, freq: Double, seconds: Double, sampleRate: Double, amplitude: Float = 0.5) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let n = AVAudioFrameCount(seconds * sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; buf.frameLength = n
    for i in 0..<Int(n) { buf.floatChannelData![0][i] = amplitude * Float(sin(2 * .pi * freq * Double(i) / sampleRate)) }
    try file.write(from: buf)
}
func writeSilence(to url: URL, seconds: Double, sampleRate: Double) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let n = AVAudioFrameCount(seconds * sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; buf.frameLength = n
    for i in 0..<Int(n) { buf.floatChannelData![0][i] = 0 }
    try file.write(from: buf)
}
func readChannels(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
    let f = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try f.read(into: buf)
    let n = Int(buf.frameLength)
    return ((0..<Int(f.processingFormat.channelCount)).map { Array(UnsafeBufferPointer(start: buf.floatChannelData![$0], count: n)) }, f.processingFormat.sampleRate)
}
func goertzelPower(_ x: ArraySlice<Float>, freq: Double, rate: Double) -> Double {
    let k = 2 * cos(2 * .pi * freq / rate); var s1 = 0.0, s2 = 0.0
    for v in x { let s = Double(v) + k * s1 - s2; s2 = s1; s1 = s }
    let n = Double(x.count); return (s1 * s1 + s2 * s2 - k * s1 * s2) / (n * n)
}
func rms(_ x: ArraySlice<Float>) -> Float { sqrt(x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))) }
```

Tests (`FinalizerTests`; these run in CI with no hardware and are the main proof of the stereo-channel requirement):

```swift
@Test func stereoChannelsStayPureAndAligned() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    try writeSine(to: dir/"mic.caf", freq: 440, seconds: 3.0, sampleRate: 48_000)
    try writeSine(to: dir/"app.caf", freq: 880, seconds: 2.0, sampleRate: 44_100)        // different rate: forces resampling
    let r = try Finalizer.finalize(mic: .init(url: dir/"mic.caf", startNanos: 1_000_000_000),
                                   app: .init(url: dir/"app.caf", startNanos: 1_500_000_000),   // app starts 0.5 s later
                                   to: dir/"out.m4a")
    let (ch, rate) = try readChannels(dir/"out.m4a")
    #expect(ch.count == 2 && rate == 48_000)
    #expect(abs(r.durationSeconds - 3.0) < 0.15)
    let mid = 48_000 * 1 ..< 48_000 * 2                                   // 1.0–2.0 s: both present
    #expect(goertzelPower(ch[0][mid], freq: 440, rate: 48_000) > 100 * goertzelPower(ch[0][mid], freq: 880, rate: 48_000))
    #expect(goertzelPower(ch[1][mid], freq: 880, rate: 48_000) > 100 * goertzelPower(ch[1][mid], freq: 440, rate: 48_000))
    #expect(rms(ch[1][0..<(48_000 * 4 / 10)]) < 0.01)                      // app silent for its 0.5 s lead-in (checked 0–0.4 s)
    #expect(rms(ch[0][0..<(48_000 * 4 / 10)]) > 0.1)                       // mic present from the start
    #expect(r.mic?.isSilent == false && r.app?.isSilent == false)
}
```

More tests (write them all):
- `appStartsFirst`: app starts 0.25 s **before** mic → ch0 silent for the first 0.2 s, ch1 loud.
- `micOnlyIsMono`: `app: nil` → 1 channel, 440 Hz, duration ≈ 2.0 s.
- `appOnlyIsMono`: `mic: nil` → 1 channel, 880 Hz.
- `noInputThrows`: both nil → `.noInput`.
- `silentTrackIsReportedNotFatal`: mic = zeros → no throw, `r.mic?.isSilent == true`, `r.app?.isSilent == false`.
- `missingFileThrowsCannotRead`.
- `noPartialFileLeftOnFailure`: after a failing call, no `out.m4a` and no `out.m4a.partial` exist.
- `longTrackStreams`: 75 s sine finalizes correctly (duration ± 0.15 s) — exercises multi-block streaming and converter state across block boundaries (check there are no clicks: max sample-to-sample jump in a 440 Hz × 0.5 amplitude sine ≤ 0.1 at 48 kHz).
- `outputIsAAC`: `AVAudioFile` reports 48,000 Hz; file size for 3 s stereo is between 30 KB and 90 KB.

Exit check P4 (software): `cd Packages/Capture && swift test` green; `swift test --sanitize=thread` green; `scripts/check-realtime.sh` prints PASS.

### 25.9 `CenteredMix` (in-app player's Center toggle and the optional centered export)

```swift
public enum CenteredMix {
    /// Reads any audio file; writes a 48 kHz mono 16-bit WAV (or AAC if `output` ends in .m4a) whose samples are the mean of all channels. Streams in 1 s blocks.
    public static func write(from source: URL, to output: URL) throws
}
```
Test: build a stereo `.m4a` with `Finalizer` (440 Hz mic, 880 Hz app) → `CenteredMix.write` → result has 1 channel, 48,000 Hz, duration within 0.15 s, and **both** 440 Hz and 880 Hz present (each Goertzel power > 20× the power at 1,500 Hz). A mono source passes through unchanged (samples equal within 1e-4). A missing file throws.

---

## 26. Transcribe package

### 26.1 `ChannelExtractor`

```swift
public enum ChannelSelection: Sendable, Equatable { case channel(Int), mixdown }
public enum ChannelExtractor {
    /// Streams `source` (m4a/caf/wav/aiff) to a 16 kHz mono 16-bit WAV in `directory`. Returns its URL.
    public static func extract(_ selection: ChannelSelection, from source: URL, into directory: URL) throws -> URL
}
```
Rules: stereo App+Mic file → `.channel(0)` = Me, `.channel(1)` = Them. Any mono file → `.channel(0)`. Imported stereo from other tools → `.mixdown`. `.channel(n)` with `n >= channelCount` throws. Streams in 1 s blocks; never loads the file whole.

Tests: build a stereo m4a with `Finalizer` from 440 Hz (mic) and 880 Hz (app) → `.channel(0)` WAV is 16,000 Hz mono 16-bit, 440 Hz dominant (Goertzel 100×), duration ± 0.05 s; `.channel(1)` → 880 Hz dominant; `.mixdown` → both present; `.channel(2)` throws; a mono source with `.channel(0)` works.

### 26.2 `TextCleaner`, `VocabularyPrompt`, `TranscriptMerger`, `HallucinationFilter`, `SilenceMap` (all pure)

```swift
public enum TextCleaner {
    /// Removes Whisper special tokens like <|startoftranscript|> and <|0.00|>, collapses whitespace, trims.
    public static func clean(_ s: String) -> String
}
public enum VocabularyPrompt {
    /// "Vocabulary: A, B, C." Dedupe case-insensitively, keep first spelling, drop empties, max 224 characters (stop adding terms before exceeding). nil if no terms.
    public static func make(terms: [String]) -> String?
}
public enum TranscriptMerger {
    public static func merge(me: [RawSegment], them: [RawSegment]) -> [TranscriptSegment]       // labeled
    public static func unlabeled(_ segs: [RawSegment]) -> [TranscriptSegment]                   // speaker == nil
}
public struct HallucinationFilter: Sendable {
    public var maxConsecutiveRepeats = 2
    public var phantomPhrases: Set<String> = ["thank you", "thanks for watching", "thank you for watching",
        "subtitles by the amara.org community", "you", "bye", "please subscribe", "like and subscribe"]
    public init() {}
    /// Normalization for comparison: lowercase, strip everything except letters, digits, spaces; collapse spaces.
    public func apply(_ segs: [RawSegment], isSilent: @Sendable (_ start: Double, _ end: Double) -> Bool) -> [RawSegment]
}
public struct SilenceMap: Sendable {
    public static func build(from wav16kMono: URL, windowSeconds: Double = 0.1, thresholdDBFS: Double = -50) throws -> SilenceMap
    public func isSilent(_ start: Double, _ end: Double) -> Bool       // true if >= 90% of windows in range are below threshold
}
```

Tests (table-driven):
- `TextCleaner`: `"<|startoftranscript|><|0.00|> Hello  world <|2.50|>"` → `"Hello world"`; `"  a\n b "` → `"a b"`; `""` → `""`; text without tokens unchanged.
- `VocabularyPrompt`: `["Soteriology","soteriology","Talbot",""]` → `"Vocabulary: Soteriology, Talbot."`; `[]` → `nil`; 100 long terms → result length ≤ 224 and ends with `"."`.
- `TranscriptMerger.merge`: me `[(5,6,"B"),(0,1,"A")]`, them `[(2,3,"C")]` → order A(Me), C(Them), B(Me); equal start times → Me first; whitespace-only text dropped; text trimmed; newlines in text become spaces.
- `HallucinationFilter`: 5 identical consecutive `"Thank you."` on non-silent audio → keeps 2 (maxConsecutiveRepeats); 30 identical loop `"I'm going to go"` → keeps 2; `"Thank you."` once on a **silent** window → dropped; the same on a **non-silent** window → kept; `"You"` on silent → dropped; `"Yes."` ×2 on non-silent → both kept; non-consecutive repeats are not touched; empty input → empty.
- `SilenceMap`: synthetic WAV = 1 s tone, 1 s silence, 1 s tone → `isSilent(1.1, 1.9) == true`, `isSilent(0.1, 0.9) == false`, `isSilent(0.5, 1.5) == false` (only 50% silent).

### 26.3 `WhisperEngine` adapter (**[VERIFY]** all WhisperKit names)

```swift
import WhisperKit
public actor WhisperEngine: TranscriptionEngine {
    public let modelName: String
    private var kit: WhisperKit?
    public init(modelName: String) { self.modelName = modelName }

    public func transcribe(audioFile: URL, vocabulary: [String],
                           onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment] {
        let kit = try await load()
        var options = DecodingOptions(/* chunkingStrategy: .vad, wordTimestamps: false — names per API-NOTES.md */)
        // vocabulary: encode VocabularyPrompt.make(terms:) with kit.tokenizer and set options.promptTokens (only on WhisperKit >= 1.1.0)
        let results = try await kit.transcribe(audioPath: audioFile.path, decodeOptions: options)
        return results.flatMap(\.segments).compactMap {
            let t = TextCleaner.clean($0.text)
            return t.isEmpty ? nil : RawSegment(start: Double($0.start), end: Double($0.end), text: t)
        }
    }
    public func unload() { kit = nil }        // 8 GB rule: call before enhancement starts
    private func load() async throws -> WhisperKit { /* WhisperKit(WhisperKitConfig(model: modelName)) once; cache in `kit` */ }
}
public enum ModelCatalog {
    public static let all: [(name: String, approxMB: Int)] = [("tiny", 66), ("base", 145), ("small", 480), ("large-v3-v20240930_626MB", 626)]
}
```

Rules: process **one channel file at a time** (me, then them); call `unload()` after the last file; report progress as `(finishedFiles + fraction) / totalFiles`.

Tests:
- Always-run: `TranscribeOrchestrator` (pure orchestration over a `TranscriptionEngine`) with `FakeTranscriptionEngine`: App+Mic → engine called twice (channel 0 then 1), result labeled and merged; mono → called once, unlabeled; engine error → the orchestrator rethrows a `TranscribeError.engineFailed(stage:)` and leaves the temp WAVs removed.
- Integration (gated by env `AR_INTEGRATION=1`; downloads the `tiny` model): generate speech with `say -o speech.aiff "The quarterly budget review is on Friday and Sarah owns the action item."`, convert to CAF via `afconvert`, run `Finalizer` (mic only), transcribe with `tiny`, then assert the lowercased text contains at least 3 of: `quarterly`, `budget`, `friday`, `sarah`, `action`. Never fail the always-run suite because of this one.

---

## 27. Enhance package

### 27.1 Budget and prompts

```swift
public struct TokenBudget: Sendable, Equatable {
    public var window = 4096, instructions = 300, userNotes = 500, output = 800, margin = 1300
    public var chunkTokens: Int { window - instructions - userNotes - output - margin }    // 1196 at defaults
    public func scaled(toWindow w: Int) -> TokenBudget        // multiplies the other four fields by w/window, rounded
}
public enum Prompts {
    public static let digestInstructions = """
    You summarize one segment of a meeting transcript. Use only facts that appear in the text. \
    Do not invent names, dates, numbers, or owners. If a list has no items, return an empty list. \
    Keep every item under 25 words.
    """
    public static let mergeInstructions = """
    You combine several partial meeting summaries into one. Remove duplicates. Keep only items present in the input. \
    Do not invent names, dates, numbers, or owners.
    """
    public static let finalInstructions = """
    You write meeting notes. Combine the person's own notes with the summary of the transcript. \
    Keep the person's wording where possible. Only use names that appear in the input. \
    Action items must say who and what only if the input says so.
    """
    public static func digestPrompt(_ chunk: String) -> String { "Transcript segment:\n\(chunk)" }
}
```

Tests: `chunkTokens == 1196`; `scaled(toWindow: 8192)` has `window == 8192` and `chunkTokens` within 2 of 2,392; each instruction string is ≤ 900 characters (≈ 300 tokens at a conservative 3 chars/token) so it fits `budget.instructions`; each contains the phrase `Do not invent` or `Only use names`.

### 27.2 `Chunker` (pure; the contract is the tests)

```swift
public struct Chunk: Sendable, Equatable { public var text: String; public var firstSegment: Int; public var lastSegment: Int
    public var startSeconds: Double; public var endSeconds: Double }
public enum Chunker {
    /// "[00:12] Me: text"  (mm:ss; hh:mm:ss when >= 1 h). No speaker -> "[00:12] text".
    public static func line(_ s: TranscriptSegment) -> String
    public static func chunk(_ segments: [TranscriptSegment], maxTokens: Int, overlapFraction: Double = 0.1,
                             counter: any TokenCounter) async throws -> [Chunk]
}
```
Algorithm: count each line once; a chunk's cost = sum of its line costs + 1 per newline join. Greedy fill until the next line would exceed `maxTokens`; emit; start the next chunk with the trailing lines of the emitted one whose total cost ≤ `overlapFraction × maxTokens` (drop the overlap if it would leave no room for the next line). A single line costing more than `maxTokens` is split at word boundaries into pieces ≤ `maxTokens`; every piece keeps the segment's index and time range.

Tests (use `CharTokenCounter(perToken: 4)`):
- `line` formatting: `(12s, "Hello", .me)` → `[00:12] Me: Hello`; `(3725s, "x", nil)` → `[1:02:05] x`; speaker `.them` → `Them:`.
- Empty input → `[]`.
- **Budget:** for 300 random segments (seeded RNG, 20–400 chars each) and `maxTokens: 200`, every `counter.tokens(in: chunk.text) <= 200`.
- **Coverage:** every segment index `0..<n` lies in at least one chunk's `firstSegment...lastSegment`; first chunk starts at 0; last chunk ends at `n-1`.
- **Order/progress:** `firstSegment` non-decreasing and strictly greater than the previous chunk's `firstSegment`; `lastSegment` non-decreasing.
- **Overlap:** with `overlapFraction: 0.1` and many short segments, `chunk[k+1].firstSegment <= chunk[k].lastSegment`; with `0`, `chunk[k+1].firstSegment == chunk[k].lastSegment + 1`.
- **Oversize line:** one 5,000-character segment, `maxTokens: 100`, `overlapFraction: 0` → every piece ≤ 100 tokens and the words of all pieces, concatenated in order, equal the original words.
- **Scale:** 720 segments, segment *k* starting at `4k` seconds, each text exactly 50 characters (a line is 62 characters ≈ 16 tokens, plus 1 for the join ≈ 12,200 tokens in total), `maxTokens: 1196` → between 10 and 14 chunks.
- **Determinism:** two runs produce equal arrays.

### 27.3 `NotesPipeline` (pure orchestration over `NotesGenerator`)

```swift
public struct PipelineProgress: Sendable, Equatable { public var stage: String; public var done: Int; public var total: Int }
public struct PipelineResult: Sendable, Equatable { public var notes: MeetingNotesResult?; public var warnings: [String]; public var digests: [ChunkDigest] }
public struct NotesPipeline: Sendable {
    public init(generator: any NotesGenerator, counter: any TokenCounter, budget: TokenBudget = .init(),
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) })
    public func run(segments: [TranscriptSegment], userNotes: String,
                    onProgress: @escaping @Sendable (PipelineProgress) -> Void) async -> PipelineResult
}
```

Behavior (every bullet has a test below):
1. Empty `segments` → no generator calls; `notes == nil`; warning `"No transcript to summarize."`.
2. `Chunker` with `budget.chunkTokens`; map each chunk through `digest`, in order; progress `("enhancing", i, n)`.
3. `GeneratorError.contextExceeded` on a chunk → split the chunk text in half **at a line boundary**, digest each half, `merge` the two (depth limit 3; beyond that → treated as `refused`).
4. `.refused` → that chunk's digest is `unavailable`; warning `"Chunk k (mm:ss–mm:ss): summary unavailable."`; continue.
5. `.rateLimited` → `sleep(1 s)`, retry up to 3 times, then as `.refused`.
6. `.unavailable(reason)` → **stop immediately**; `notes == nil`; warning `"Apple Intelligence unavailable: <reason>"`; no further calls.
7. Reduce: drop `unavailable` digests; while more than one digest remains, group them greedily into batches whose combined text cost ≤ `chunkTokens` (always ≥ 1 digest per batch; if no batch has ≥ 2 digests, merge adjacent pairs to guarantee progress) and `merge` each batch.
8. If every digest is unavailable → `notes == nil`, warning `"No chunk could be summarized."`.
9. User notes: if tokens > `budget.userNotes`, keep leading lines that fit and add warning `"Your notes were longer than the model window; the enhanced notes use the first N lines. Your full notes are kept below."`. `finalize` gets the trimmed text.
10. `finalize` `.contextExceeded` → retry once with empty user notes plus the warning above; `.refused` → `notes == nil` + warning; other errors as 6.
11. `Task.isCancelled` is checked before each generator call; on cancel return `notes == nil`, warning `"Cancelled."`.

Tests with `FakeNotesGenerator` + `CharTokenCounter(perToken: 4)` + `sleep: { _ in }`:
- `happyPath`: 12 chunks → `digest` called 12× in order with the chunk texts; `finalize` called exactly once with a single merged digest; `notes != nil`; `warnings.isEmpty`.
- `contextExceededSplits`: chunk 2 throws once → called next with two strictly shorter inputs whose lines, concatenated, equal chunk 2's lines; `merge` called with 2 digests; `notes != nil`.
- `refusedChunkIsSkipped`: chunk 3 refused → one warning containing `Chunk 3` and its time range; other chunks digested; merged digest excludes the unavailable one; `notes != nil`.
- `unavailableStopsEverything`: first call throws `.unavailable("off")` → exactly 1 generator call; `notes == nil`; warning contains `off`.
- `rateLimitRetries`: throws twice then succeeds → 3 calls for that chunk, no warning; throws 4× → placeholder + warning.
- `longUserNotesAreTrimmed`: 2,000-token notes → `finalize` receives ≤ 500 tokens; warning present; text is a prefix of the original lines.
- `emptyTranscript`: zero calls.
- `reduceBatches`: 40 digests × ~200 tokens → every `merge` call's input fits ≤ `chunkTokens`; final `finalize` receives one digest; `merge` call count ≥ 2.
- `cancellation`: cancel the task after the first `digest` → returns promptly, `notes == nil`, warning `"Cancelled."`, no further calls.
- `finalizeContextExceededRetries`: first `finalize` throws `.contextExceeded` → second call has empty notes; `notes != nil`; warning present.

Exemplar (write the remaining pipeline tests in exactly this style):

```swift
import Testing
@testable import Enhance
import Core
import CoreTestSupport

@Suite struct NotesPipelineTests {
    static func segments(_ n: Int) -> [TranscriptSegment] {
        (0..<n).map { TranscriptSegment(start: Double($0 * 4), end: Double($0 * 4 + 3), text: String(repeating: "x", count: 50), speaker: .me) }
    }
    static func digest(_ s: String) -> ChunkDigest {
        ChunkDigest(topics: ["t"], decisions: [], actionItems: [], questions: [], keyPoints: [String(s.prefix(10))], unavailable: false)
    }
    @Test func happyPath() async {
        let gen = FakeNotesGenerator(); gen.onDigest = { Self.digest($0) }
        let p = NotesPipeline(generator: gen, counter: CharTokenCounter(perToken: 4), sleep: { _ in })
        let r = await p.run(segments: Self.segments(720), userNotes: "my notes", onProgress: { _ in })
        #expect(r.notes != nil && r.warnings.isEmpty)
        #expect((10...14).contains(gen.digestInputs.count))
        #expect(gen.finalizeInputs.count == 1 && gen.finalizeInputs[0].notes == "my notes")
    }
    @Test func refusedChunkIsSkipped() async {
        let gen = FakeNotesGenerator()
        gen.onDigest = { [unowned gen] text in
            if gen.digestInputs.count == 3 { throw GeneratorError.refused }
            return Self.digest(text)
        }
        let p = NotesPipeline(generator: gen, counter: CharTokenCounter(perToken: 4), sleep: { _ in })
        let r = await p.run(segments: Self.segments(720), userNotes: "", onProgress: { _ in })
        #expect(r.warnings.count == 1 && r.warnings[0].contains("Chunk 3"))
        #expect(r.notes != nil)
        #expect(r.digests.filter(\.unavailable).count == 1)
    }
}
```

### 27.4 Foundation Models adapter (**[VERIFY]**)

```swift
import FoundationModels
@Generable struct FMChunkDigest {
    @Guide(description: "Main topics discussed") var topics: [String]
    @Guide(description: "Decisions that were made") var decisions: [String]
    @Guide(description: "Action items, with owner only if stated") var actionItems: [String]
    @Guide(description: "Open questions") var questions: [String]
    @Guide(description: "Other key points") var keyPoints: [String]
}
@Generable struct FMMeetingNotes {
    @Guide(description: "Three to five sentence summary") var summary: String
    var decisions: [String]; var actionItems: [String]; var openQuestions: [String]
    @Guide(description: "Notes that merge the person's own notes with the transcript summary") var expandedNotes: String
}
public struct FoundationNotesGenerator: NotesGenerator {
    public init() {}
    // Every call: a NEW LanguageModelSession(instructions: …). Never reuse a session.
    // let r = try await LanguageModelSession(instructions: Prompts.digestInstructions)
    //     .respond(to: Prompts.digestPrompt(chunk), generating: FMChunkDigest.self)     // do NOT pass `schema:` to init (L4)
    // Map errors: exceededContextWindowSize -> .contextExceeded; guardrailViolation / refusal -> .refused;
    // rateLimited -> .rateLimited; model unavailable -> .unavailable(reason string).
    public static func availability() -> (ok: Bool, reason: String?)       // from SystemLanguageModel.default.availability
}
public struct FMTokenCounter: TokenCounter { /* tokenCount(for:) per API-NOTES; on failure fall back to ceil(chars / 3.0) */ }
```

Tests: always-run → availability mapping function (`reasonString(for:)`) covered with the cases listed in API-NOTES; gated (`AR_INTEGRATION=1`, Apple Intelligence on): the synthetic 5-minute transcript from L4 runs through `NotesPipeline` with the real generator in < 120 s, `notes?.summary` non-empty, `actionItems` contains `Sarah`, and no warnings.

---

## 28. Output package

### 28.1 `FileNaming`, `PathMath`, `YAML`

```swift
public enum FileNaming {
    /// Whitespace runs -> one space; characters in / \ : * ? " < > | and control chars -> "-"; trim spaces and leading dots; max 120 characters; empty -> "Untitled".
    public static func sanitize(_ title: String) -> String
    /// "2026-11-18 1030 Weekly sync"  (local time in `timeZone`, format yyyy-MM-dd HHmm)
    public static func baseName(created: Date, title: String, timeZone: TimeZone = .current) -> String
    /// base, "base 2", "base 3", … first name for which `exists` is false.
    public static func uniqueURL(in dir: URL, baseName: String, ext: String, exists: (URL) -> Bool) -> URL
}
public enum PathMath {
    /// Relative path from directory `dir` to `file`. nil when they share no first path component (e.g. different volumes).
    public static func relativePath(from dir: URL, to file: URL) -> String?
    /// Percent-encodes for a Markdown link target: space -> %20, ( -> %28, ) -> %29, plus everything URL-path encoding requires; keeps "/" and "..".
    public static func encodeLinkTarget(_ path: String) -> String
}
enum YAML {
    /// Plain when safe; otherwise double-quoted with \\ \" \n escaped. Quote if: empty; leading/trailing space; contains ":", " #", '"', or newline;
    /// starts with one of - ? : , [ ] { } # & * ! | > ' % @ `; or equals (case-insensitive) true/false/yes/no/null/~; or parses as a number.
    static func scalar(_ s: String) -> String
}
```

Tests (table-driven, write all rows):

| `sanitize` input | expected |
|---|---|
| `Weekly sync` | `Weekly sync` |
| `Q4: plan/review` | `Q4- plan-review` |
| `  spaced   out  ` | `spaced out` |
| `a\b` | `a-b` |
| `x*y?` | `x-y-` |
| `` (empty), `   `, `...` | `Untitled` |
| `.hidden` | `hidden` |
| 200 × `a` | 120 × `a` |
| `emoji 🎙️ ok` | `emoji 🎙️ ok` |
| `tab\there` | `tab here` |

- `baseName`: `2026-11-18T18:30:00Z`, title `Weekly sync`, `America/Los_Angeles` → `2026-11-18 1030 Weekly sync`.
- `uniqueURL`: `exists` true for the first two → returns `base 3.m4a`.

| `relativePath(from:to:)` | expected |
|---|---|
| `/Users/me/Notes` → `/Users/me/Audio/x.m4a` | `../Audio/x.m4a` |
| `/Users/me/Notes` → `/Users/me/Notes/x.m4a` | `x.m4a` |
| `/Users/me/Notes` → `/Users/me/Notes/Audio/x.m4a` | `Audio/x.m4a` |
| `/Users/me/a/b/c` → `/Users/me/x.m4a` | `../../../x.m4a` |
| `/Users/me/Notes/` → `/Users/me/Audio/x.m4a` (trailing slash) | `../Audio/x.m4a` |
| `/Users/me/Notes` → `/Volumes/Ext/Audio/x.m4a` | `nil` |

- `encodeLinkTarget("../Audio/2026-11-18 1030 Weekly sync.m4a")` → `../Audio/2026-11-18%201030%20Weekly%20sync.m4a`; `a (1).m4a` → `a%20%281%29.m4a`.
- `YAML.scalar`: `Weekly sync` → plain; `Q4: plan` → `"Q4: plan"`; `- item` → quoted; `true` → `"true"`; `123` → `"123"`; empty → `""`; `He said "hi"` → `"He said \"hi\""`; `C #notes` → `"C #notes"`; `C# notes` → plain; `a#b` → plain; `1:1 sync` → `"1:1 sync"`; `trailing ` → quoted; `line1\nline2` → `"line1\nline2"`.

### 28.2 `MarkdownRenderer` (pure; golden tests)

```swift
public enum AudioReference: Sendable, Equatable { case relative(String), absolute(URL) }
public struct RenderOptions: Sendable, Equatable { public var frontmatter = true; public var linkStyle: AudioLinkStyle = .markdownLink }
public struct NoteDocument: Sendable {
    public var title: String; public var created: Date; public var timeZone: TimeZone; public var durationSeconds: Double
    public var sourceApp: String?; public var mode: CaptureMode; public var audio: AudioReference?
    public var transcriptionModel: String; public var notesModel: String?; public var tags: [String]
    public var notes: MeetingNotesResult?; public var enhancementWarning: String?
    public var userNotes: String; public var transcript: [TranscriptSegment]; public var options: RenderOptions
}
public enum MarkdownRenderer { public static func render(_ d: NoteDocument) -> String }
```

Rules (exact): blocks are joined with one blank line (`"\n\n"`); the file ends with exactly one `"\n"`.
Block order: frontmatter (if enabled) → `# <title>` (raw title, not escaped) → warning (`> ⚠️ <warning>`) if present → recording line if `audio != nil` → `## Summary` → `## Decisions` → `## Action items` → `## Open questions` → `## Notes` → `## My notes (original)` → `## Transcript`.
Omit a section when empty (lists with no items; empty strings; `userNotes` that is whitespace-only; empty transcript). If `notes == nil` omit the first five note sections.
Frontmatter keys in order: `title`, `created` (`yyyy-MM-dd'T'HH:mm:ss` in `timeZone`, no zone), `duration` (always quoted `"HH:MM:SS"`), `source_app` (if any), `capture_mode` (`mode.frontmatterValue`), `audio` (if any; relative → quoted path unencoded; absolute → quoted `file://` URL), `transcription_model`, `notes_model` (if any), `tags` (`[a, b]`; empty → `[]`). Values pass through `YAML.scalar` except where stated.
Recording line: `.markdownLink` → `Recording: [<file name>](<encoded target>)`; `.wikiEmbed` → `Recording: ![[<file name>]]`. For `.absolute(url)` the target is `url.absoluteString` (already encoded).
Lists: decisions and open questions `- item`; action items `- [ ] item`.
Transcript lines: `**[HH:MM:SS] Me:** text` or `**[HH:MM:SS]** text` when `speaker == nil`; text trimmed, newlines → spaces; timestamp = `Int(start)` seconds.

Golden test (write exactly this; it is the spec): document with title `Weekly sync`; created `2026-11-18T18:30:00Z` in `America/Los_Angeles`; duration `2530`; source `Discord`; mode `.appAndMic`; audio `.relative("../Audio/2026-11-18 1030 Weekly sync.m4a")`; models `whisperkit-small` / `apple-foundation-models`; tags `["meeting"]`; notes: summary `We agreed on Q1 scope.`, decisions `["Drop advanced search to Q1"]`, actions `["Sarah: talk to revenue"]`, questions `["Who owns the runbook?"]`, expanded `Expanded paragraph.`; userNotes `- [ ] Q1 scope\n- [x] Hiring update`; transcript `(12 s, "Hello everyone.", .me)`, `(19 s, "Hi.", .them)`. Expected output:

````
---
title: Weekly sync
created: 2026-11-18T10:30:00
duration: "00:42:10"
source_app: Discord
capture_mode: app+mic
audio: "../Audio/2026-11-18 1030 Weekly sync.m4a"
transcription_model: whisperkit-small
notes_model: apple-foundation-models
tags: [meeting]
---

# Weekly sync

Recording: [2026-11-18 1030 Weekly sync.m4a](../Audio/2026-11-18%201030%20Weekly%20sync.m4a)

## Summary
We agreed on Q1 scope.

## Decisions
- Drop advanced search to Q1

## Action items
- [ ] Sarah: talk to revenue

## Open questions
- Who owns the runbook?

## Notes
Expanded paragraph.

## My notes (original)
- [ ] Q1 scope
- [x] Hiring update

## Transcript
**[00:00:12] Me:** Hello everyone.
**[00:00:19] Them:** Hi.
````

(The expected string ends with a single newline after the last transcript line.)

More render tests (each asserts the full output string or a precise snippet):
- `frontmatterOff`: output starts with `# Weekly sync`.
- `wikiEmbed`: contains `Recording: ![[2026-11-18 1030 Weekly sync.m4a]]` and no `](`.
- `micOnlyTranscriptHasNoLabels`: lines are `**[00:00:12]** Hello everyone.`; frontmatter has `capture_mode: mic`.
- `enhancementFailed`: `notes == nil`, `enhancementWarning == "Notes enhancement unavailable: Apple Intelligence is not enabled. Your transcript and original notes are below."` → banner directly under the title, then the recording line, then **My notes** and **Transcript**; none of Summary/Decisions/Action items/Open questions/Notes.
- `emptySectionsOmitted`: decisions `[]` → no `## Decisions`.
- `emptyUserNotes`: whitespace-only → no `## My notes (original)`.
- `titleNeedingQuotes`: title `Q4: plan` → frontmatter `title: "Q4: plan"` but heading `# Q4: plan`.
- `absoluteAudio`: `.absolute(URL(fileURLWithPath: "/Volumes/Ext/Audio/a b.m4a"))` → `audio: "file:///Volumes/Ext/Audio/a%20b.m4a"`.
- `noAudio`: no `Recording:` line, no `audio:` key.
- `unicodeAndMultilineTranscript`: `"héllo\n日本語"` → `héllo 日本語`.
- `userNotesVerbatim`: user notes containing `## Heading` and trailing spaces are preserved byte-for-byte.
- `durationFormats`: 59 s → `"00:00:59"`; 3,661 s → `"01:01:01"`.

### 28.3 `AtomicWriter`, `FolderCheck`, `SessionExporter`

```swift
public enum AtomicWriter { public static func write(_ data: Data, to url: URL) throws }   // temp file in same dir, then replace; never creates parent dirs
public enum FolderStatus: Sendable, Equatable { case ok, missing, notADirectory, notWritable }
public enum FolderCheck { public static func status(of url: URL) -> FolderStatus }
public enum SessionExporter {
    /// Writes <notesFolder>/<baseName>.md. Chooses the audio reference: relative when PathMath gives one, else absolute.
    public static func export(document: NoteDocument, baseName: String, audioFile: URL?, notesFolder: URL,
                              settings: AppSettings) throws -> URL
}
```

Tests:
- `AtomicWriter`: creates a file; replaces existing content completely; no `*.tmp*` leftovers in the directory; writing into a missing directory throws and creates nothing.
- `FolderCheck`: temp dir → `.ok`; deleted dir → `.missing`; a file path → `.notADirectory`; `chmod 0o555` dir → `.notWritable` (restore permissions in `defer`).
- `SessionExporter` **link resolves**: two temp folders `Notes/` and `Audio/` under one temp root; audio file at `Audio/2026-11-18 1030 Weekly sync.m4a`; after export, extract the link target from the `.md`, percent-decode it, resolve against `Notes/`, standardize → equals the audio file's path. Repeat with folders on "different volumes" (simulate with `/private/tmp/x` vs a path under `/Volumes/Nonexistent/…` string-only) → the output uses an absolute `file://` link.
- Export twice with the same base name → second file is `… 2.md`; the first file is untouched.

---

## 29. Theme and EditorKit packages

### 29.1 Color math and `Theme` (pure)

```swift
public struct RGB: Equatable, Sendable { public var r, g, b: Double }          // 0...1
public func parseHex(_ s: String) -> RGB?                                       // "#RRGGBB" or "RRGGBB"; nil otherwise (alpha not accepted)
public func hexString(_ c: RGB) -> String                                       // "#RRGGBB" uppercase
public func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB                         // a + (b - a) * t
public func luminance(_ c: RGB) -> Double                                       // WCAG relative luminance (sRGB linearization, 0.03928 threshold)
public func contrastRatio(_ a: RGB, _ b: RGB) -> Double                         // (Lmax + 0.05) / (Lmin + 0.05)

public struct Theme: Codable, Sendable, Equatable, Identifiable {
    public var id: String; public var name: String; public var isDark: Bool
    public var canvas, ink, mutedInk, accent: String                            // "#RRGGBB"
    public var selection, codeBg, link, quote, tag, strong, marker: String
    public var headings: [String]                                               // exactly 6
    public static func make(id: String, name: String, isDark: Bool, canvas: String, ink: String, mutedInk: String,
                            accent: String, headings: [String]) -> Theme
    // defaults in make(): selection = accent with 35% alpha as "#RRGGBBAA" (alpha 0x59); codeBg = mix(canvas, ink, 0.06);
    // link = accent; quote = mutedInk; tag = accent; strong = ink; marker = mutedInk
}
public enum SystemTheme { public static let id = "system" }                      // not a Theme value; the editor uses NSColor system colors
public enum BuiltInThemes { public static let all: [Theme]; public static func theme(id: String) -> Theme? }
public enum ThemeLoader {
    public static func load(from directory: URL) -> (themes: [Theme], warnings: [String])   // *.json; invalid files are skipped with a warning, never a crash
    public static func validate(_ t: Theme) -> [String]                                       // warnings (empty = fine)
}
```

Built-in data (exactly these values; ids in the first column). `headings` are H1…H6.

| id | isDark | canvas | ink | mutedInk | accent | headings |
|---|---|---|---|---|---|---|
| `sacred` | true | `#000000` | `#F2F2F2` | `#B8B8B8` | `#FF7A00` | `#F2F2F2 ×4`, `#B8B8B8 ×2` |
| `gruvbox-dark` | true | `#282828` | `#EBDBB2` | `#928374` | `#FE8019` | `#FB4934 #FE8019 #FABD2F #B8BB26 #83A598 #D3869B` |
| `gruvbox-light` | false | `#FBF1C7` | `#3C3836` | `#7C6F64` | `#AF3A03` | `#9D0006 #AF3A03 #B57614 #79740E #076678 #8F3F71` |
| `dracula` | true | `#282A36` | `#F8F8F2` | `#6272A4` | `#BD93F9` | `#FF79C6 #BD93F9 #8BE9FD #50FA7B #FFB86C #F1FA8C` |
| `nord` | true | `#2E3440` | `#D8DEE9` | `#616E88` | `#88C0D0` | `#88C0D0 #81A1C1 #8FBCBB #A3BE8C #EBCB8B #B48EAD` |
| `tokyo-night` | true | `#1A1B26` | `#C0CAF5` | `#565F89` | `#7AA2F7` | `#7AA2F7 #BB9AF7 #7DCFFF #9ECE6A #E0AF68 #F7768E` |
| `catppuccin-mocha` | true | `#1E1E2E` | `#CDD6F4` | `#6C7086` | `#CBA6F7` | `#F38BA8 #FAB387 #F9E2AF #A6E3A1 #89B4FA #CBA6F7` |
| `solarized-dark` | true | `#002B36` | `#93A1A1` | `#657B83` | `#CB4B16` | `#CB4B16 #B58900 #859900 #268BD2 #6C71C4 #D33682` |
| `solarized-light` | false | `#FDF6E3` | `#586E75` | `#93A1A1` | `#CB4B16` | `#CB4B16 #B58900 #859900 #268BD2 #6C71C4 #D33682` |

`validate` thresholds: `ink/canvas ≥ 4.5`, `accent/canvas ≥ 3.0`, every heading `≥ 2.5`, `mutedInk/canvas ≥ 2.0`, six headings, all hex valid. Heading and muted thresholds are lower because they are large or decorative text.

Tests (`ThemeTests`):
- `luminance(black) == 0`, `luminance(white) == 1`; `contrastRatio(black, white)` within 0.01 of 21; `contrastRatio(x, x) == 1`; `#777777` on white within 0.02 of 4.48.
- `parseHex`: `#FF7A00` → (1, 0.478, 0); `ff7a00` accepted; `#FFF`, `#GG0000`, `#FF7A0080`, `""` → `nil`. `hexString(parseHex(h)!) == h.uppercased()` for all built-in colors (round trip).
- `mix(black, white, 0.5)` → `#808080` (rounded).
- Built-ins: `all.map(\.id)` equals the nine ids in the table order (`system` is handled outside `all`); ids are unique; every theme has 6 headings; **`validate` returns `[]` for every built-in** (these exact values were checked against the thresholds: lowest ink ratio 4.99, lowest accent ratio 3.26, lowest heading ratio 2.97, lowest muted ratio 2.43). If one ever fails, write `BLOCKERS.md`; never loosen the thresholds or edit the colors.
- `Theme.make` defaults: `codeBg` for Sacred is `mix(#000000, #F2F2F2, 0.06)`; `selection` ends with `59`.
- `ThemeLoader`: a temp dir with one valid theme JSON, one malformed file, one theme with 5 headings, one with `canvas: "red"` → returns 1 theme and 3 warnings, no crash. A user theme that fails contrast loads with a warning (not rejected).
- JSON round trip equality for every built-in.

### 29.2 Markdown tokenizer (pure; line-based; the table is the contract)

```swift
public enum MDKind: Equatable, Sendable {
    case heading(Int), headingMarker, bold, italic, boldItalic, strike, highlight, inlineCode, marker
    case codeBlock, fence, listMarker, taskBox(checked: Bool), quoteMarker, quote
    case linkText, linkURL, tag, frontmatter, rule
}
public struct MDSpan: Equatable, Sendable { public var kind: MDKind; public var range: NSRange }   // UTF-16 offsets into the whole text
public enum MarkdownTokenizer { public static func tokenize(_ text: String) -> [MDSpan] }            // sorted by location, then length
```

Rules:
- Process by line (`\n`, `\r\n`). **Frontmatter:** only if the text starts with `---` + newline; ends at the next line that is exactly `---`; one `.frontmatter` span over the block (no trailing newline); nothing else is tokenized inside.
- **Fences:** a line starting with ``` (after optional indent) opens/closes. Fence lines → `.fence` (whole line, no newline); lines between → `.codeBlock` (each line, no newline; empty lines produce no span). An unclosed fence runs to the end. Nothing else is tokenized inside.
- **Heading:** `^#{1,6}` followed by one or more spaces. `.headingMarker` = the hashes plus the spaces; `.heading(n)` = the rest of the line (omitted if empty). Seven or more `#`, or no space after → not a heading.
- **Rule:** a line that is only `---`, `***`, or `___` (3+ chars, optional spaces) and is not line 1 frontmatter → `.rule`.
- **List:** optional indent, then `-`, `*`, `+`, or `digits.` / `digits)`, then a space. `.listMarker` = marker + one space (indent excluded). If followed by `[ ]` / `[x]` / `[X]` + space (or end of line) → `.taskBox(checked:)` over the three bracket characters.
- **Quote:** `>` then optional space → `.quoteMarker` (`>` and the space), `.quote` = remainder.
- **Inline** (not inside code spans, fences, frontmatter): code spans first (`` `x` `` → `.marker` backticks + `.inlineCode`); then `***x***` (`.boldItalic`), `**x**`/`__x__` (`.bold`), `*x*`/`_x_` (`.italic`), `~~x~~` (`.strike`), `==x==` (`.highlight`); each emits `.marker` spans for the delimiters. An opening delimiter must be followed by a non-space and a closing one preceded by a non-space; `_` delimiters must not touch a letter or digit on the outside (so `snake_case_name` is not italic). Links `[text](url)` → `.marker` `[`, `.linkText`, `.marker` `](`, `.linkURL`, `.marker` `)`. Tags: `#` + a letter + `[\w/-]*`, not preceded by a word character or `#`.

Test table (describe each span as `kind:"substring"`; assert the list in order):

| # | input | expected |
|---|---|---|
| 1 | `# Title` | `headingMarker:"# "`, `heading(1):"Title"` |
| 2 | `###### Six` | `headingMarker:"###### "`, `heading(6):"Six"` |
| 3 | `####### Seven` | *(none)* |
| 4 | `#tag` | `tag:"#tag"` |
| 5 | `# ` | `headingMarker:"# "` |
| 6 | `text #tag more` | `tag:"#tag"` |
| 7 | `**bold**` | `marker:"**"`, `bold:"bold"`, `marker:"**"` |
| 8 | `*it*` | `marker:"*"`, `italic:"it"`, `marker:"*"` |
| 9 | `***bi***` | `marker:"***"`, `boldItalic:"bi"`, `marker:"***"` |
| 10 | `~~gone~~` | `marker:"~~"`, `strike:"gone"`, `marker:"~~"` |
| 11 | `==hi==` | `marker:"=="`, `highlight:"hi"`, `marker:"=="` |
| 12 | `` `code` `` | `marker:"`"`, `inlineCode:"code"`, `marker:"`"` |
| 13 | `` `**not bold**` `` | marker, `inlineCode:"**not bold**"`, marker (no `bold`) |
| 14 | `snake_case_name` | *(none)* |
| 15 | `2 * 3 * 4` | *(none)* |
| 16 | `[link](https://x.y)` | `marker:"["`, `linkText:"link"`, `marker:"]("`, `linkURL:"https://x.y"`, `marker:")"` |
| 17 | `- item` | `listMarker:"- "` |
| 18 | `* item` and `+ item` | `listMarker:"* "` / `"+ "` |
| 19 | `1. one` and `10) ten` | `listMarker:"1. "` / `"10) "` |
| 20 | `  - nested` | `listMarker:"- "` (range starts after the indent) |
| 21 | `- [ ] todo` | `listMarker:"- "`, `taskBox(false):"[ ]"` |
| 22 | `- [x] done` and `- [X] done` | `listMarker:"- "`, `taskBox(true):"[x]"` / `"[X]"` |
| 23 | `> quote` | `quoteMarker:"> "`, `quote:"quote"` |
| 24 | `para\n---` | `rule:"---"` |
| 25 | `---\ntitle: x\n---\n# H` | `frontmatter:"---\ntitle: x\n---"`, `headingMarker:"# "`, `heading(1):"H"` |
| 26 | "```swift\nlet x = 1 // # no\n```" | `fence:"```swift"`, `codeBlock:"let x = 1 // # no"`, `fence:"```"` |
| 27 | "```\ncode" | `fence:"```"`, `codeBlock:"code"` |
| 28 | `- **b** item` | `listMarker:"- "`, `marker:"**"`, `bold:"b"`, `marker:"**"` |
| 29 | `# héllo 日本語` | `headingMarker:"# "`, `heading(1):"héllo 日本語"` (ranges are UTF-16) |
| 30 | `**🎙️ x**` | `marker`, `bold:"🎙️ x"`, `marker` |
| 31 | `` (empty) | *(none)* |
| 32 | `# A\r\n- b` | `heading(1):"A"` (no `\r` in the range), `listMarker:"- "` |
| 33 | `a --- b` | *(none)* |
| 34 | `##nospace` | *(none)* (a tag needs a letter right after a single `#`) |

Property tests: for 1,000 seeded random strings (length 0–200, alphabet `#*_~=`[]()>-+ 0123456789abc\n\r\t`` and emoji): tokenizer never crashes; every span range is inside `0...utf16.count` and non-empty; spans are sorted. Performance: a 50 KB document tokenizes in < 100 ms in a release build (soft target 20 ms).

### 29.3 Editing helpers (pure)

```swift
public enum ListAction: Equatable, Sendable { case insert(String), exitList, none }
public enum ListContinuation {
    public static func onEnter(line: String) -> ListAction      // `line` = the current line without its newline
    public static func indent(_ line: String) -> String         // prepend two spaces
    public static func outdent(_ line: String) -> String        // remove up to two leading spaces, or one leading tab
}
public enum TaskToggle { public static func toggle(line: String) -> String }
public enum HeadingScale {
    public static func scale(level: Int, monospaced: Bool) -> Double   // level clamped to 1...6
    public static func isBold(level: Int, monospaced: Bool) -> Bool
}
```

`onEnter` table: `- item` → `.insert("\n- ")`; `* item` → `"\n* "`; `+ item` → `"\n+ "`; `  - nested` → `"\n  - "`; `1. one` → `"\n2. "`; `9. nine` → `"\n10. "`; `3) x` → `"\n4) "`; `- [ ] todo` → `"\n- [ ] "`; `- [x] done` → `"\n- [ ] "`; `> quote` → `"\n> "`; `- ` / `1. ` / `- [ ] ` / `> ` (empty item) → `.exitList`; `-` (no space), `plain`, ``, `    four spaces` → `.none`.
`toggle` table: `- [ ] a` ↔ `- [x] a`; `- [X] a` → `- [ ] a`; `* [ ] a` → `* [x] a`; `1. [ ] a` → `1. [x] a`; `  - [ ] n` → `  - [x] n`; `- a` → `- [ ] a`; `1. a` → `1. [ ] a`; `a` → `- [ ] a`; `` → `- [ ] `.
`indent/outdent`: `indent("- a") == "  - a"`; `outdent("  - a") == "- a"`; `outdent("- a") == "- a"`; `outdent(" - a") == "- a"`; `outdent("\t- a") == "- a"`.
`HeadingScale` proportional: `[2.0, 1.6, 1.37, 1.25, 1.12, 1.12]`; monospaced: `[1.75, 1.5, 1.25, 1.1, 1.0, 1.0]`; `scale(level: 0)` = level 1; `scale(level: 9)` = level 6. `isBold`: proportional → always `true`; monospaced → `level <= 5`.

### 29.4 `MarkdownTextView` (AppKit glue; thin on purpose)

`NSViewRepresentable` around `NSScrollView` + `NSTextView` (TextKit 2). All logic is in the pure helpers above; this file only wires them:
- On every text change (and not while `hasMarkedText()`): tokenize the **whole** document and apply attributes inside `beginEditing()/endEditing()`: reset to base attributes, then per span: `.heading(n)` → font size `base × HeadingScale.scale`, color `theme.headings[n-1]`, bold per `isBold`; `.headingMarker/.marker/.frontmatter/.rule/.fence` → `theme.marker`; `.bold` → bold trait; `.italic` → oblique (font descriptor matrix if the face has no italic); `.boldItalic` → both; `.strike` → strikethrough; `.highlight` → background `theme.selection`; `.inlineCode/.codeBlock` → monospaced font + background `theme.codeBg`; `.quote` → `theme.quote`; `.linkText` → `theme.link` + underline; `.listMarker/.taskBox` → `theme.accent`; `.tag` → `theme.tag`.
- Key handling: Return → `ListContinuation.onEnter`; Tab/Shift-Tab on a list line → `indent/outdent`; ⌘Return → `TaskToggle.toggle`; ⌘B/⌘I wrap the selection in `**`/`*`; ⌘K wraps in `[…](url)`; ⌥⌘1…6 set the heading level.
- **Every edit goes through `shouldChangeText(in:replacementString:)` → `replaceCharacters` → `didChangeText()`** so undo works. Undo history survives record/stop.
- Autosave: debounce 2 s → `SessionStore.saveNotes`; also on window resign-key and on state change.
- System theme: use `NSColor.labelColor`, `.secondaryLabelColor`, `.controlAccentColor`, `.textBackgroundColor`.

UI test (`AppleRecorderUITests`): launch with `--uitest-fresh-store`; click the editor; type `# Hi` Return `- a` Return; assert the editor's accessibility value equals `# Hi\n- a\n- `; type Return again → `# Hi\n- a\n`.

---

## 30. Pipeline coordinator, UI state, app shell

### 30.1 `Pipeline` package: `ProcessingCoordinator`

Depends on `Core`, `Enhance`, `Output`. Everything real is injected, so the 8 GB rule and failure handling are unit-tested.

```swift
// ProcessingStage is defined in Core (§24.7).
public struct ProcessingDependencies: Sendable {
    public var transcribe: @Sendable (_ audio: URL, _ mode: CaptureMode, _ vocabulary: [String],
                                      _ progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment]
    public var unloadTranscriber: @Sendable () async -> Void
    public var enhance: @Sendable (_ segments: [TranscriptSegment], _ userNotes: String,
                                   _ progress: @escaping @Sendable (PipelineProgress) -> Void) async -> PipelineResult
    public var writeMarkdown: @Sendable (_ doc: NoteDocument) async throws -> URL
    public var loadTranscript: @Sendable (_ id: UUID) async -> [TranscriptSegment]?      // transcript.json if present
    public var saveTranscript: @Sendable (_ id: UUID, _ segs: [TranscriptSegment]) async throws -> Void
}
public actor ProcessingCoordinator {
    public init(store: any SessionStore, settings: AppSettings, deps: ProcessingDependencies,
                onStage: @escaping @Sendable (ProcessingStage) -> Void)
    public func run(sessionID: UUID, forceRetranscribe: Bool = false) async throws -> Session
}
```

Contract:
1. Load the session; its state must be `.stopped`, `.failed`, or `.done`, else throw `CoordinatorError.invalidState`. Transition to `.processing` and persist.
2. Emit `loadingModel`, `transcribing`, `merging` in that order, then call `saveTranscript`. **Exception:** when `loadTranscript` returns segments and `forceRetranscribe == false`, emit none of these three stages and do not call `transcribe`.
3. **Before** `loadingNotesModel`: `await deps.unloadTranscriber()`. (8 GB rule.)
4. Emit `loadingNotesModel`, `enhancing`; call `deps.enhance`. A result with `notes == nil` is **not** a failure.
5. Emit `writing`; build the `NoteDocument` (`enhancementWarning` = joined warnings when `notes == nil`, else `nil`); call `writeMarkdown`; set `notesPath`, `transcriptionModel`, `notesModel`, state `.done`, clear `failure`; persist; return.
6. If `transcribe` throws → state `.failed`, `failure.stage == "transcribing"`; if `writeMarkdown` throws → `"writing"`. In both cases the session's notes and audio path are unchanged and persisted.
7. If the task is cancelled → state `.stopped`, rethrow `CancellationError`, write nothing.

Tests (`PipelineTests`, all fakes; record a call log array):
- `happyPathStageOrder`: stages are exactly `[loadingModel, transcribing, merging, loadingNotesModel, enhancing, writing]`; final state `.done`; `notesPath` set.
- `whisperUnloadedBeforeEnhancement`: in the call log, `unloadTranscriber` index < `enhance` index; and `transcribe` index < `unloadTranscriber` index.
- `existingTranscriptSkipsTranscription`: `loadTranscript` returns segments → `transcribe` never called; `forceRetranscribe: true` → called.
- `transcribeFailure`: state `.failed`, `failure.stage == "transcribing"`, `writeMarkdown` never called, `enhance` never called.
- `enhancementUnavailableStillWritesMarkdown`: `PipelineResult(notes: nil, warnings: ["Apple Intelligence unavailable: off"])` → `writeMarkdown` called once with `doc.notes == nil` and `doc.enhancementWarning` containing `off`; transcript and user notes present in the doc; state `.done`.
- `writeFailure`: `.failed`, stage `"writing"`.
- `cancellation`: cancel during `transcribe` → state `.stopped`, no markdown written.
- `invalidStates`: `.recording`, `.armed`, `.idle`, `.processing` sessions → `invalidState`.
- `userNotesPassedVerbatim`: `enhance` receives exactly the stored notes text.
- `macMicOnlyDocumentHasNoSpeakerLabels`: `.micOnly` session → every segment in the doc has `speaker == nil`.

### 30.2 UI state mapping (pure, in `Core`)

```swift
public enum CapsuleState: Equatable, Sendable {
    case idle, armed, recording, stopped, processing(ProcessingStage), done, failed(String)
}
public func capsuleState(session: SessionState, stage: ProcessingStage?, failedStage: String?) -> CapsuleState
```
Tests: `.idle→idle`, `.armed→armed`, `.recording→recording`, `.stopped→stopped`, `.processing`+stage → `processing(stage)`, `.processing` with `nil` stage → `processing(.loadingModel)`, `.done→done`, `.failed`+`"transcribing"` → `failed("transcribing")`, `.failed` with `nil` → `failed("unknown")`.

### 30.3 App entry and scenes (`App/AppleRecorderApp.swift`)

```swift
@main struct AppleRecorderApp: App {
    @State private var model = AppModel()
    init() { SelfTest.runIfRequested() }                       // §31: exits the process when `--selftest` is present
    var body: some Scene {
        WindowGroup("Apple Recorder") {
            RootView().environment(model).frame(minWidth: 760, minHeight: 520)
        }
        .commands { RecorderCommands(model: model) }
        Settings { SettingsView().environment(model) }
        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image(systemName: model.isRecording ? "record.circle.fill" : "waveform")
                .symbolRenderingMode(.palette).foregroundStyle(model.isRecording ? .red : .primary, .primary)
        }
    }
}
struct RecorderCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) { Button("New Session") { model.newSession() }.keyboardShortcut("n") }
        CommandMenu("Recording") {
            Button(model.isRecording ? "Stop Recording" : "Start Recording") { model.toggleRecording() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Transcribe & Enhance") { model.transcribeAndEnhance() }.disabled(!model.canProcess)
            Button("Import Audio…") { model.importAudioPanel() }
        }
    }
}
```

`RootView`: `NavigationSplitView { SidebarView() } detail: { EditorPane().safeAreaInset(edge: .bottom) { RecordCapsule().padding() } }`, `.inspector(isPresented:)`, `.toolbar { … }` (new session, mode/source menu, share via `ShareLink`, inspector toggle), `.searchable`, `.sheet` for the consent sheet when `!settings.consentAcknowledged`, `.onDrop(of: [.audio, .fileURL])` → import. Sidebar: `List` grouped Today / Yesterday / Earlier with context menu (Reveal in Finder, Re-transcribe, Delete — delete asks for confirmation). Empty store → `ContentUnavailableView("No sessions", systemImage: "waveform", description: Text("⌘N to start."))`.

### 30.4 `RecordCapsule` (glass, Liquid Glass rules from §9.2)

```swift
struct RecordCapsule: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 14) { content }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)            // applied AFTER padding
        }
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private var content: some View {
        switch model.capsule {
        case .idle, .armed:
            Button { model.toggleRecording() } label: { Label("Record", systemImage: "record.circle") }.buttonStyle(.plain)
            ModeMenu(); SourceMenu(); SignalBadge()              // "Source OK" / "No signal"
        case .recording:
            Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red)
            TimerText(); LevelMeters()
            Button { model.toggleRecording() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.plain)
        case .stopped:
            Button("Transcribe & Enhance") { model.transcribeAndEnhance() }.buttonStyle(.borderedProminent)
            Button("Discard", role: .destructive) { model.confirmDiscard() }.buttonStyle(.plain)
        case .processing(let stage): StageProgressView(stage: stage, progress: model.progress); Button("Cancel") { model.cancelProcessing() }.buttonStyle(.plain)
        case .done: Label("Saved", systemImage: "checkmark.circle"); Button("Reveal") { model.reveal() }.buttonStyle(.plain)
        case .failed(let stage): Text("Failed at \(stage)"); Button("Retry") { model.transcribeAndEnhance() }.buttonStyle(.borderedProminent)
        }
    }
}
```
Rules: **no glass inside the capsule** (no `.glass` button styles, no nested `glassEffect`); the word "Recording" plus the timer always show while recording (not color alone); the red menu bar icon, toolbar pill, and Dock badge appear while recording; every control has an accessibility label; VoiceOver announces state changes through `AccessibilityNotification.Announcement`.

### 30.5 `AppModel` responsibilities (`@Observable @MainActor`)

Owns: `FileSessionStore`, `SettingsStore`, current `Session`, notes text, `ProcessingCoordinator`, `TapSession`/`MicSession`/`TrackWriter`s, theme. Methods: `newSession()`, `toggleRecording()` (arm → probe → record → stop → `Finalizer` → state `.stopped`), `transcribeAndEnhance()`, `cancelProcessing()`, `importAudio(_:)` (copy to audio folder, state `.stopped`), `confirmDiscard()`, `reveal()`. Rules: record only after `consentAcknowledged`; refuse to start when the audio folder status is not `.ok` (show the banner); autosave notes; on launch call `recoverInterrupted()` and show a banner per recovered session; the `Finalizer` output goes to the audio folder via a temp name then atomic rename; temp tracks are deleted only after `Finalizer` returns without error.

### 30.6 Screens (reference SwiftUI; **uncompiled**, adjust to the SDK; behavior rules are the contract)

`AppModel` shape (fields the views below use; methods per §30.5):

```swift
enum SignalState { case unknown, ok, noSignal }
struct Banner: Identifiable { let id = UUID(); var text: String; var actionTitle: String?; var action: (@MainActor () -> Void)? }

@Observable @MainActor final class AppModel {
    var settings = AppSettings() { didSet { scheduleSettingsSave() } }     // debounce 0.5 s -> SettingsStore.save
    private(set) var sessions: [Session] = []
    var selectedID: UUID?
    var notesText = ""                      // bound to the editor; autosaved every 2 s (§10.5)
    var searchText = ""
    var capsule: CapsuleState = .idle
    var progress = 0.0                      // 0...1 of the current processing stage
    var elapsed: TimeInterval = 0
    var levels: (mic: Float, app: Float) = (0, 0)
    var signal: SignalState = .unknown
    var banners: [Banner] = []
    var mode: CaptureMode = .appAndMic
    var sources: [AppEntry] = []
    var selectedSource: AppEntry.ID?
    var transcript: [TranscriptSegment] = []
    var needsConsent: Bool { !settings.consentAcknowledged }
    var isRecording: Bool { capsule == .recording }
    var canProcess: Bool { capsule == .stopped || capsule == .done }
    var filteredSessions: [Session] { /* title / notes / transcript contains searchText, case-insensitive; all when empty */ }
    var activeTheme: Theme? { BuiltInThemes.theme(id: settings.themeID) }     // nil = System
}
```

```swift
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedID) {
            ForEach(SessionGrouping.group(model.filteredSessions, now: .now, calendar: .current), id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sessions) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).lineLimit(1)
                            Text(s.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(s.id)
                        .contextMenu {
                            Button("Reveal in Finder") { model.reveal(s) }
                            Button("Re-transcribe") { model.retranscribe(s) }.disabled(s.audioPath == nil)
                            Divider()
                            Button("Delete…", role: .destructive) { model.requestDelete(s) }      // always asks for confirmation
                        }
                    }
                }
            }
        }
        .overlay { if model.sessions.isEmpty { ContentUnavailableView("No sessions", systemImage: "waveform", description: Text("⌘N to start.")) } }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }
}

struct EditorPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ForEach(model.banners) { b in
                HStack { Text(b.text); Spacer(); if let t = b.actionTitle { Button(t) { b.action?() } } }
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.quaternary)
            }
            MarkdownTextView(text: $model.notesText, theme: model.activeTheme,
                             fontName: model.settings.editorFontName, fontSize: model.settings.editorFontSize)
        }
    }
}

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            List(Array(model.transcript.enumerated()), id: \.offset) { _, seg in
                Button { model.player.seek(to: seg.start) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Timecode.string(seg.start)).monospacedDigit().foregroundStyle(.secondary)
                        if let s = seg.speaker { Text(s.rawValue).bold() }
                        Text(seg.text)
                    }
                }.buttonStyle(.plain)
            }
            .overlay { if model.transcript.isEmpty { ContentUnavailableView("No transcript yet", systemImage: "text.alignleft") } }
            Divider()
            PlayerBar()
        }
        .inspectorColumnWidth(min: 260, ideal: 320)
    }
}

@Observable @MainActor final class AudioPlayerModel {
    var isPlaying = false, centered = false { didSet { reloadForCenter() } }
    var position: TimeInterval = 0, duration: TimeInterval = 0
    func load(_ url: URL) { /* AVAudioPlayer(contentsOf:); keep the original URL */ }
    func toggle() { /* play / pause */ }
    func seek(to t: TimeInterval) { /* clamp to 0...duration */ }
    private func reloadForCenter() { /* when centered: CenteredMix.write(from: original, to: <session temp dir>/centered.wav) once, then play that file at the same position; when off: reload the original */ }
}
struct PlayerBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var player = model.player
        HStack {
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Slider(value: $player.position, in: 0...max(player.duration, 1)) { editing in if !editing { player.seek(to: player.position) } }
            Toggle("Center", isOn: $player.centered).toggleStyle(.button)
        }.padding(8)
    }
}
```

Capsule parts (plain controls inside the glass capsule; **no glass inside glass**):

```swift
struct ModeMenu: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Picker("Mode", selection: $model.mode) {
            Text("App + Mic").tag(CaptureMode.appAndMic); Text("Mic only").tag(CaptureMode.micOnly); Text("App only").tag(CaptureMode.appOnly)
        }.pickerStyle(.menu).labelsHidden()
    }
}
struct SourceMenu: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Picker("Source", selection: $model.selectedSource) {
            ForEach(model.sources) { Text($0.displayName + ($0.isRunningOutput ? "  ●" : "")).tag(Optional($0.id)) }
        }.pickerStyle(.menu).labelsHidden().disabled(!model.mode.hasApp)
    }
}
struct SignalBadge: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.signal {
        case .ok: Label("Source OK", systemImage: "checkmark.circle")
        case .noSignal: Label("No signal", systemImage: "exclamationmark.triangle")
        case .unknown: Label("Checking…", systemImage: "ellipsis.circle")
        }
    }
}
struct TimerText: View { @Environment(AppModel.self) private var model; var body: some View { Text(Timecode.string(model.elapsed)).monospacedDigit() } }
struct LevelMeters: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            if model.mode.hasMic { Text("Mic \(String(MeterGlyph.glyph(forPeak: model.levels.mic)))") }
            if model.mode.hasApp { Text("App \(String(MeterGlyph.glyph(forPeak: model.levels.app)))") }
        }.font(.system(.body, design: .monospaced)).accessibilityLabel("Input levels")
    }
}
struct StageProgressView: View {
    let stage: ProcessingStage; let progress: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stage.title).font(.headline)
            Text(ProgressBar.text(fraction: progress)).font(.system(.caption, design: .monospaced))
            Text("Recording and notes are safe.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

Consent sheet (blocking; shown whenever `needsConsent`):

```swift
struct ConsentSheet: View {
    @Environment(AppModel.self) private var model
    @State private var agreed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before you record").font(.title2).bold()
            Text("Recording laws vary. California and many other states require every party's consent for confidential conversations. You are the person recording. Tell everyone present before you press Record, including people in the room when you use Mic only.")
            Text("Audio and transcripts stay on this Mac. This is not legal advice.").foregroundStyle(.secondary)
            Toggle("I understand and will get consent where it is required.", isOn: $agreed)
            HStack { Spacer(); Button("I Understand") { model.acknowledgeConsent() }.buttonStyle(.borderedProminent).disabled(!agreed) }
        }
        .padding(24).frame(width: 460).interactiveDismissDisabled()
    }
}
```

Settings (tabs; each tab is a `Form` with `.formStyle(.grouped)`):

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            CaptureTab().tabItem { Label("Capture", systemImage: "waveform") }
            TranscriptionTab().tabItem { Label("Transcription", systemImage: "text.bubble") }
            NotesAITab().tabItem { Label("Notes AI", systemImage: "sparkles") }
            OutputTab().tabItem { Label("Output", systemImage: "folder") }
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintpalette") }
            LegalTab().tabItem { Label("Legal", systemImage: "doc.text") }
        }.frame(width: 540, height: 440)
    }
}
struct OutputTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Folders") {
                LabeledContent("Notes folder") { Text(model.settings.notesFolderPath ?? "Not set").lineLimit(1).truncationMode(.middle); Button("Choose…") { model.chooseNotesFolder() } }
                LabeledContent("Audio folder") { Text(model.settings.audioFolderPath ?? "Not set").lineLimit(1).truncationMode(.middle); Button("Choose…") { model.chooseAudioFolder() } }
            }
            Section("Markdown") {
                Toggle("Include frontmatter", isOn: $model.settings.frontmatter)
                Picker("Audio link style", selection: $model.settings.audioLinkStyle) {
                    Text("Markdown link").tag(AudioLinkStyle.markdownLink); Text("Obsidian embed").tag(AudioLinkStyle.wikiEmbed)
                }
                Toggle("Also export a centered mix", isOn: $model.settings.exportCenteredMix)
            }
        }.formStyle(.grouped)
    }
}
struct TranscriptionTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Model", selection: $model.settings.transcriptionModel) {
                ForEach(ModelCatalog.all, id: \.name) { Text("\($0.name)  (~\($0.approxMB) MB)").tag($0.name) }
            }
            Section("Vocabulary (one term per line)") {
                TextEditor(text: Binding(get: { model.settings.vocabulary.joined(separator: "\n") },
                                         set: { model.settings.vocabulary = $0.split(separator: "\n").map(String.init) }))
                    .frame(height: 100).font(.body.monospaced())
            }
        }.formStyle(.grouped)
    }
}
struct NotesAITab: View {
    var body: some View {
        let a = FoundationNotesGenerator.availability()
        Form {
            LabeledContent("Model", value: "Apple Foundation Models (on device)")
            LabeledContent("Status", value: a.ok ? "Available" : (a.reason ?? "Unavailable"))
            Text("Transcript-only notes are written when the model is unavailable. Nothing is sent to a server.").foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}
struct AppearanceTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Chrome", selection: $model.settings.chrome) { Text("Native (Liquid Glass)").tag(ChromeStyle.native); Text("Terminal (v1.1)").tag(ChromeStyle.terminal) }
                .disabled(true)       // enabled in v1.1
            Picker("Editor theme", selection: $model.settings.themeID) {
                Text("System").tag(SystemTheme.id)
                ForEach(BuiltInThemes.all) { Text($0.name).tag($0.id) }
            }
            Toggle("Match window to theme", isOn: $model.settings.matchWindowToTheme)
            Picker("Editor font", selection: Binding(get: { model.settings.editorFontName ?? "" }, set: { model.settings.editorFontName = $0.isEmpty ? nil : $0 })) {
                Text("System").tag(""); Text("SF Mono").tag("SF Mono"); Text("Geist Mono").tag("Geist Mono"); Text("Departure Mono").tag("Departure Mono")
            }
            Stepper("Font size: \(Int(model.settings.editorFontSize))", value: $model.settings.editorFontSize, in: 12...24)
        }.formStyle(.grouped)
    }
}
```
`GeneralTab`, `CaptureTab`, `LegalTab`: one `Form` each with the controls named in §12 (bind to `AppSettings`; Legal has "Show consent again" → `model.settings.consentAcknowledged = false`, plus a link to `THIRD-PARTY-LICENSES.md`). `FolderPicker` = `NSOpenPanel` (`canChooseDirectories`, no files) in `AppModel.chooseNotesFolder/chooseAudioFolder`; after choosing, run `FolderCheck.status` and show a banner unless `.ok`.

UI acceptance (UI tests, `AppleRecorderUITests`): launch with `--uitest-fresh-store` → the consent sheet appears and **Record is disabled** until "I Understand" is clicked; after consent the sidebar shows "No sessions"; ⌘N creates a session; Settings opens with ⌘, and shows seven tabs; changing the transcription model to `base` persists across a relaunch.

---

## 31. Self-tests, verify script, CI

### 31.1 `--selftest` (App/SelfTest/SelfTest.swift)

`SelfTest.runIfRequested()` reads `--selftest <name>` and `--out <path>` from `CommandLine.arguments`. If absent, it returns immediately. Otherwise it runs the named test on a background task, writes **one JSON object** to `--out`, and calls `exit(0)`. JSON: `{"test": "...", "status": "pass|fail|skipped", "message": "...", "metrics": {…}}`.

Self-tests that need Core Audio permissions **must be launched through LaunchServices** (`open -W -n AppleRecorder.app --args --selftest NAME --out FILE`), otherwise macOS attributes the permission to Terminal and you get the silent-zeros state.

| Name | What it does | Pass criteria | Skip when |
|---|---|---|---|
| `permissions` | Reports mic authorization status, Apple Intelligence availability, folder settings status | Always `pass` (informational; metrics hold the values) | never |
| `finalize-synthetic` | `writeSine` mic 440 Hz and app 880 Hz → `Finalizer` → channel-purity check (Goertzel 100×) inside the shipped app | Purity holds, duration ± 0.15 s | never |
| `mic-probe` | Records 2 s through `MicSession` + `TrackWriter` | ≥ 90,000 frames, not all exact zeros | mic not authorized → `skipped` with "grant Microphone" |
| `capture-tone` | Writes an 8 s 440 Hz WAV, starts `/usr/bin/afplay` on it, finds afplay's audio process, taps it for 3 s through `TapSession` + `TrackWriter` + `ZeroRunDetector` | Peak > 0.05, 440 Hz dominant (Goertzel 50×), detector never tripped, no dropped samples | never. **Zero buffers = `fail`** with message "zero buffers: System Audio Recording permission missing or stale". This is the L1 test. |
| `cpu-60s` | Same as `capture-tone` for 60 s; measures our process CPU time / wall time | < 10 % of one core | never |
| `transcribe-say` | `say` speech → `Finalizer` (mic only) → `WhisperEngine("tiny")` | ≥ 3 of the 5 keywords (§26.3) | `AR_NO_NETWORK=1` |
| `enhance-synthetic` | 5-min synthetic transcript fixture → `NotesPipeline` with `FoundationNotesGenerator` | `notes.summary` non-empty, `Sarah` in action items, no warnings, < 120 s | Apple Intelligence unavailable |
| `all` | Runs the above in order | Every non-skipped test passes | — |

### 31.2 `scripts/verify.sh` (one command, one table)

```bash
#!/usr/bin/env bash
set -u
PKGS="Core Capture Transcribe Enhance Output Theme EditorKit Pipeline"
APP="build/Build/Products/Debug/AppleRecorder.app"
fail=0; printf "%-36s %s\n" "CHECK" "RESULT"
run() { local name="$1"; shift; local log="/tmp/ar_verify_${name//[^A-Za-z0-9]/_}.log"
  if "$@" >"$log" 2>&1; then printf "%-36s PASS\n" "$name"; else printf "%-36s FAIL  (log: %s)\n" "$name" "$log"; fail=1; fi; }
for p in $PKGS; do run "unit: $p" bash -c "cd Packages/$p && swift test"; done
run "tsan: Capture" bash -c "cd Packages/Capture && swift test --sanitize=thread"
run "realtime check" ./scripts/check-realtime.sh
run "spec tests untouched" ./scripts/protect-tests.sh
run "no secrets tracked" bash -c "! git ls-files | grep -E '\.p12\$|release-key\.pem\$|\.env\$'"
run "app build (strict concurrency)" make build
if [ "${1:-}" = "--selftests" ]; then
  for t in permissions finalize-synthetic mic-probe capture-tone transcribe-say enhance-synthetic; do
    out="/tmp/ar-selftest-$t.json"; rm -f "$out"
    open -W -n "$APP" --args --selftest "$t" --out "$out"
    s=$(plutil -extract status raw -o - "$out" 2>/dev/null || echo "missing")
    m=$(plutil -extract message raw -o - "$out" 2>/dev/null || echo "")
    printf "%-36s %s  %s\n" "selftest: $t" "$(echo "$s" | tr a-z A-Z)" "$m"
    [ "$s" = "fail" ] || [ "$s" = "missing" ] && fail=1
  done
fi
exit $fail
```

`skipped` is not a failure but must be listed in `PROGRESS.md` as `NEEDS HUMAN`.

### 31.3 CI (`.github/workflows/ci.yml`)

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # protect-tests.sh needs the spec-v1 tag
          fetch-tags: true
      - run: brew install xcodegen
      - run: ./scripts/protect-tests.sh
      - run: make test
      - run: ./scripts/check-realtime.sh
      - run: make build
      - run: bash -c 'cd Packages/Capture && swift test --sanitize=thread'
```
Hardware and Apple Intelligence self-tests do **not** run in CI. The release workflow is §20.

---

## 32. Work order (the builder follows this exactly)

Each step: do it, run the exit check, commit, update `PROGRESS.md`. **At the end of each phase also `git pull --rebase origin main && git push origin main`** (§22.6). Do not skip ahead.

| Step | Deliverable | Exit check |
|---|---|---|
| **P0.0** | Get the repo (§22.6): clone `git@github.com:corbinwrites/AppleRecorder.git` or unzip the seed repo; `git pull --rebase origin main`; confirm `docs/BUILD-GUIDE.md` and `AGENTS.md` exist; copy the legacy spike scripts from `~/Hal9000/projects/local-spikes/Scripts/` into `Spikes/legacy-scripts/` (**NEEDS HUMAN** if the builder cannot reach that folder); push | `git status` clean; `git log origin/main` shows the seed commit on top of `Initial commit`; push succeeded or is marked `NEEDS HUMAN` |
| **P0.1** | Repo tree (§22.1), eight `Package.swift` files (Core, Capture, Transcribe, Enhance, Output, Theme, EditorKit, Pipeline), `project.yml`, `Makefile`, `scripts/*` (all of §20.1–20.8, §25.1, §31.2), `.github/workflows/ci.yml` (§31.3), first `README.md` (§22.6), a `PlaceholderTests.swift` in each package that has no seeded spec tests (P0.3 deletes the placeholders) | `xcodegen generate` and `make build` succeed; `swift build` succeeds in every package. Tests stay red until P0.3 and P1+ (expected) |
| **P0.2** | API spike (§23) + `docs/API-NOTES.md` | `swift build` in `Spikes/ApiCheck` succeeds; every **[VERIFY]** item is resolved or listed in `BLOCKERS.md` |
| **P0.3** | **Strong model or human on a Mac.** Stubs for every public API in Part 2 (throw `TODO.notImplemented` or `fatalError`), every prose-specified test written into `Packages/*/Tests`, the gaps listed in `docs/tasks/P0.3.md` resolved, placeholders deleted. Then `git tag spec-v1` and push the tag | `swift build --build-tests` succeeds in every package; `swift test` fails only by assertion or TODO, never by compile error; `scripts/protect-tests.sh` prints PASS |
| **P1** | Core package (§24.1–24.7) | `cd Packages/Core && swift test`: ≥ 35 tests green; builds clean with `-warnings-as-errors` |
| **P2** | Output package (§28) | All Output tests green, including the golden file and link-resolution tests |
| **P3** | Theme + EditorKit logic (§29.1–29.3) | All tests green; every built-in theme `validate == []`; tokenizer table (34 rows) and property tests green |
| **P4** | Capture software parts: `RingBuffer`, `ZeroRunDetector`, `HostClock`, `ProcessCatalog`, `TrackWriter`, `Finalizer`, `RealtimeCallback.swift` (§25.1–25.5, 25.7–25.9) | `swift test` green; `swift test --sanitize=thread` green; `scripts/check-realtime.sh` prints PASS |
| **P5** | Transcribe package: extractor, cleaner, vocabulary, merger, filter, silence map, orchestrator, `WhisperEngine`, `ModelCatalog` (§26) | Unit tests green. `AR_INTEGRATION=1 swift test --filter Integration` passes, or mark `NEEDS HUMAN` |
| **P6** | Enhance package (§27) + Pipeline package `ProcessingCoordinator` (§30.1) + `capsuleState` (§30.2) | All tests green; the 8 GB-rule test (`whisperUnloadedBeforeEnhancement`) green |
| **P7** | Hardware capture: `TapSession`, `AudioProcessEnumerator`, `MicSession`, selftests `capture-tone`, `mic-probe`, `cpu-60s` (§25.6, §31) | Build succeeds. **NEEDS HUMAN:** run `make selftest` on the M1; `capture-tone` must be `PASS`. If it prints "zero buffers", follow §2's L1 checklist and report; do not continue to P8 shipping |
| **P8** | App shell (§30.3–30.6), `RecordCapsule`, Settings, consent sheet, menu bar, import, `MarkdownTextView` (§29.4), UI test | `make build` succeeds; `xcodebuild test` UI test green; app launches (`open build/…/AppleRecorder.app`) |
| **P9** | Integration: wire `AppModel` to capture, finalizer, coordinator, exporter; settings persistence; recovery on launch | `./scripts/verify.sh --selftests` shows no `FAIL`; every checkbox in §33.2 that is marked *auto* passes |
| **P10** | Release (§20, §22.6): release scripts and workflow from §20.1–20.8 (`make-release-cert.sh`, `sign-release.sh`, `verify-signing.sh`, `release.yml`, `print-cask.sh`), final `README.md`. **NEEDS HUMAN:** create the GitHub `release` environment and secrets, create the `corbinwrites/homebrew-tap` repo, push tags `v0.0.1` then `v0.0.2` | `verify-signing.sh` passes on a CI-signed build; the second-Mac update test (§20.4) passes; GitHub Release `v1.0.0` exists with zip, DMG, SHA-256 |

`PROGRESS.md` is complete only when every step is `done` or `NEEDS HUMAN` with a reason.

### 32.1 Definition of done (v1)

1. `./scripts/verify.sh` prints PASS for every row.
2. `./scripts/verify.sh --selftests` shows no `FAIL`; any `skipped` is explained in `PROGRESS.md`.
3. §33.2 acceptance checklist: all *auto* items pass; all *human* items signed off in `PROGRESS.md` with the macOS version and date.
4. No `BLOCKERS.md` entries remain open.
5. `grep -rn "print(" Packages App --include=*.swift` finds nothing outside `SelfTest/`.
6. `codesign -d -r- AppleRecorder.app` on the release build shows `identifier` + `certificate`, never `cdhash`.
7. `git status` is clean, every commit is pushed to `origin/main`, and the GitHub Actions `ci` run on the latest commit is green.

---

## 33. Traceability and acceptance

### 33.1 Requirement → test

| Requirement (Part 1) | Test(s) |
|---|---|
| Stereo file: L = mic, R = app (§5.0, §5.3) | `FinalizerTests.stereoChannelsStayPureAndAligned`, `appStartsFirst`; selftest `finalize-synthetic` |
| Mono for single source (§5.0) | `micOnlyIsMono`, `appOnlyIsMono` |
| Tracks aligned by host time (§5.2) | `HostClock` offset tests; `stereoChannelsStayPureAndAligned` (0.5 s lead-in silence) |
| Crash-safe recording (§4.4, §5.3) | `SessionStoreTests.recover*`; `FinalizerTests.noPartialFileLeftOnFailure` |
| Silent-capture detection (§5.4, §5.5) | `ZeroRunDetector` tests 1–7; selftest `capture-tone` |
| Realtime safety (§4.5) | `check-realtime.sh`; `RingBufferTests.spscStress` under TSan |
| App grouping (Discord helpers = one source) (§5.1) | `ProcessCatalogTests` (Discord fixture) |
| Per-channel transcription, Me / Them (§6.1) | `ChannelExtractor` tests; `TranscriptMerger` tests; orchestrator tests |
| Mic-only has no labels (§5.0) | `micOnlyTranscriptHasNoLabels`; `macMicOnlyDocumentHasNoSpeakerLabels` |
| Hallucination defense (§6.3) | `HallucinationFilter` + `SilenceMap` tests |
| Vocabulary prompt (§6.4) | `VocabularyPrompt` tests |
| 4,096-token window, chunking (§7) | `TokenBudget`, `Chunker`, `NotesPipeline` tests; selftest `enhance-synthetic` |
| Error handling table (§7.4) | `contextExceededSplits`, `refusedChunkIsSkipped`, `unavailableStopsEverything`, `rateLimitRetries` |
| Never lose user notes / transcript (§7.5) | `userNotesVerbatim`, `enhancementFailed` render test, `enhancementUnavailableStillWritesMarkdown` |
| One model in RAM at a time (§4.5) | `whisperUnloadedBeforeEnhancement` |
| Two independent folders, links resolve (§8) | `SessionExporter` link-resolution test; `FolderCheck` tests |
| Atomic writes, unique names (§8.1, §8.2) | `AtomicWriter` tests; `FileNaming` tests |
| Markdown template (§8.3) | Golden render test + 12 variants |
| Themes + contrast (§9.4) | `ThemeTests` (all built-ins `validate == []`) |
| Obsidian-style editor (§10) | Tokenizer table (34 rows), property tests, `ListContinuation`, `TaskToggle`, `HeadingScale`, UI test |
| State machine (§4.3) | `StateMachineTests.fullMatrix`; `capsuleState` tests |
| Stage order and resumability (§4.3, §11.2) | `happyPathStageOrder`, `existingTranscriptSkipsTranscription` |
| Settings defaults (§12) | `SettingsTests` |
| Release identity (§17, §20) | `verify-signing.sh`; second-Mac test |
| Centered playback / export (§5.3) | `CenteredMix` tests (§25.9) |
| Sidebar grouping, timecodes, meters (§9.3, §11) | `SessionGroupingTests`, `HelperTests` (§24.7) |
| Consent before recording (§11.5, §14) | UI test: Record disabled until consent (§30.6) |

### 33.2 Acceptance checklist (§15.3), with how each is verified

| # | Item | How |
|---|---|---|
| 1 | Window opens, type notes, start/stop a recording | **human** + UI test for typing |
| 2 | Transcribe & enhance produces transcript, notes, and `.md` with transcript | *auto:* coordinator tests + `transcribe-say` + `enhance-synthetic`; **human:** one real run |
| 3 | Two folders persist across relaunch | *auto:* `SettingsTests.roundTrip`; **human:** relaunch check |
| 4 | Audio in audio folder, `.md` in notes folder, link resolves | *auto:* `SessionExporter` link test |
| 5 | Models selectable independently; defaults `small` and Apple Foundation Models | *auto:* `SettingsTests.defaults` |
| 6 | Moved/revoked folder → banner, no crash, no data loss | *auto:* `FolderCheck` tests; **human:** move a folder and relaunch |
| 7 | Kill app mid-recording → relaunch recovers audio and notes | *auto:* `recoverRecordingWithAudio`; **human:** `kill -9` during a real recording |
| 8 | Apple Intelligence off → transcript-only note | *auto:* `enhancementUnavailableStillWritesMarkdown` |
| 9 | Every theme passes contrast or warns | *auto:* `ThemeTests` |
| 10 | Keyboard operation, VoiceOver announces states | **human** |
| 11 | Mic-only works with audio-capture permission revoked | **human** (revoke in System Settings, record Mic only) |
| 12 | App + Mic file: ch 0 only mic, ch 1 only app; Center toggle works | *auto:* `stereoChannelsStayPureAndAligned`; **human:** real Discord call with headphones on |
| 13 | Drop an audio file → imported, transcribed, enhanced, written | **human** + `transcribe-say` |
| 14 | Release-signed v0.0.1 → v0.0.2 on a second Mac keeps permissions | **human** (§20.4) |
| 15 | Glass chrome legible with Reduce Transparency / Increase Contrast | **human** |

### 33.3 Human hardware protocol (for the person on the M1)

1. `make selftest`. Expect `finalize-synthetic PASS`, `mic-probe PASS` (after granting Microphone), `capture-tone PASS`. If `capture-tone` fails with zero buffers: System Settings → Privacy & Security → Screen & System Audio Recording → **System Audio Recording Only** → enable Apple Recorder (add it with `+` if absent), quit and relaunch via `open`, rerun.
2. `cpu-60s`: record CPU %. Target < 10 %.
3. Discord call: join a voice channel with a friend, record 5 min in App + Mic mode, wear headphones. Check: `ffmpeg -i out.m4a -af "pan=mono|c0=c1,volumedetect" -f null -` (right channel = the call) mean > −50 dB; `-af "pan=mono|c0=c0,volumedetect"` (left channel = your mic) mean > −50 dB. Play the file in the app: speak-only-on-left / friend-only-on-right is expected; the Center toggle mixes both.
4. 60-minute run: record a 60-minute meeting-style session; confirm no dropped-sample warning, drift ≤ 200 ms (clap at start and end, compare in Audacity/ffmpeg), then transcribe and enhance; record wall times and peak RAM (Instruments).
5. Room test: Mic-only, 3+ speakers, laptop 1–2 m away (Fixture D). Record WER with `small` and with `large-v3-v20240930_626MB`.
6. Report results in `PROGRESS.md`.

---

## 34. Verification status (read before trusting the code)

**Checked (2026-11-19).** `docs/reference/validate_logic.py` is a Python reference implementation of the pure logic in this guide, run against the guide's own test tables:

- `ZeroRunDetector` (7 cases), `HostClock` conversion and offset math, `FileNaming.sanitize` (12 rows) and `baseName`, `PathMath.relativePath` (6 rows) and link encoding, `YAML.scalar` (13 rows)
- `ListContinuation.onEnter` (18 rows), `TaskToggle` (10 rows), `indent/outdent`
- The Markdown tokenizer: **all 34 table rows** plus 1,000 random inputs without a crash
- `Chunker`: budget, coverage, ordering, overlap, oversize split, line format, and the 720-segment scale case (12 chunks)
- The full `MarkdownRenderer` golden output, compared **byte for byte** with the expected block in §28.2
- Theme contrast: all nine built-in themes pass the §29.1 thresholds (lowest ink 4.99, accent 3.26, heading 2.97, muted 2.43)

**What that found and fixed:** the `C# notes` YAML row contradicted its own rule; the oversize-line chunker test conflicted with default overlap (it now sets `overlapFraction: 0`); `1:1 sync` needed quoting (the rule now quotes any `:`).

**Not verified:**
- **No Swift has been compiled.** This sandbox has no Swift toolchain. The Python check proves the *tables are consistent and satisfiable*. It does not prove the Swift code compiles or passes. P0.2 and each phase's `swift test` are the real check.
- UTF-16 offsets in the tokenizer (Python used code points), Core Audio calls, WhisperKit and Foundation Models API names, SwiftUI/Liquid Glass modifiers, and every hardware behavior.
- The `Pipeline` and `Finalizer` behaviors are specified precisely but were not executed.

**Use the reference:** if a Swift test table and the Swift output disagree, run `python3 docs/reference/validate_logic.py docs/BUILD-GUIDE.md`. If Python agrees with the table, fix the Swift. If Python disagrees with the table, write `BLOCKERS.md`.
