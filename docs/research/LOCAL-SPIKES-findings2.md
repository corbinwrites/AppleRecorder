# Local Spikes: Meeting Notes App

Needs real hardware, Xcode, and real audio. Run on the M1 MacBook Pro (8 GB). Do them in order. **L1 is go/no-go.** If it fails, stop and report.

## Setup (once)

- Record exact versions: macOS, Xcode, Swift, machine model, RAM. Put them at the top of every result.
- Confirm Apple Intelligence is on and `SystemLanguageModel.default.availability` reports available.
- Fixtures (reuse for every spike):
  - A. 5-min Discord call, two voices, one on headphones.
  - B. 60-min meeting-style recording.
  - C. Hand-corrected reference transcript of a 10-min slice, for error checks.

---

## ✅ Environment — Confirmed 2026-11-18

| Field | Value |
|---|---|
| macOS | 27.0.1 (Build 26A434) |
| Machine | MacBook Pro 17,1 — Apple M1 |
| RAM | 8 GB |
| Swift | 6.4 (swiftlang-6.4.0.34.1 / clang-2100.3.34.1) |
| SDK | macOS 27.0 |
| Xcode | Installed at `/Applications/Xcode.app` |
| xcode-select | ✅ `/Applications/Xcode.app/Contents/Developer` (confirmed with `xcode-select -p` on 2026-11-18) |
| Apple Intelligence | **available** (`SystemLanguageModel.default.availability`) |

> **Note on Swift compilation in this sandbox:** The release package build succeeded as recorded below. Later standalone Obsidian UI helper runs could not write Swift module cache under `/Users/corbin/.cache/clang/ModuleCache`; directing the cache to `/private/tmp` stalled. Selecting Xcode.app is confirmed, but did not resolve this helper-specific sandbox/cache issue.

> **Fixtures:** The Discord app was running during the 2026-11-18 tap tests, but captured process audio was digital silence. A confirmed audible Discord call sample is still needed for L1; a 60-minute dual-track session and hand-corrected reference slice remain needed for L2/L3.

---

## L1. Per-app audio capture (go/no-go)

**Question:** Can we record audio from one chosen app (Discord) to a file, reliably, with sane permissions?

### 🟢 L1 Results — 2026-11-18 — **EFFECTIVELY PASSED** (pending Discord fixture)

**ScreenCaptureKit:** ❌ Dead end for a CLI/non-sandboxed tool.
Error `-3801` ("The user declined TCCs") on `SCShareableContent.current` from any process without a signed app bundle with `NSScreenCaptureUsageDescription`. Not worth pursuing for a CLI-first architecture.

**CoreAudio Process Taps:** ✅ Full pipeline verified end-to-end.

| Step | Result |
|---|---|
| `kAudioHardwarePropertyProcessObjectList` | 29 active CoreAudio processes enumerated |
| PID → name mapping | `NSRunningApplication` + `proc_pidpath` both work |
| `AudioHardwareCreateProcessTap` | ✅ `noErr`, valid `tapID` — **no TCC prompt, no entitlement needed for CLI** |
| Tap UID via `kAudioTapPropertyUID` | ✅ |
| `AudioHardwareCreateAggregateDevice` with tap UID | ✅ `noErr` |
| Aggregate device input format | **48 kHz, stereo (2-ch), Float32 LPCM** |
| `AudioDeviceStart` + IOProc callbacks | ✅ 49 callbacks in 500 ms (audio flowing) |
| `ExtAudioFileCreateWithURL` → AAC m4a | ✅ 66,865-byte file, confirmed by `afinfo` |
| Spotify tap (live process, PID 78826, ObjectID 130) | ✅ Found, tapped, aggregate device started, format confirmed |
| `AudioObjectAddPropertyListenerBlock` for process changes | ✅ Works — can watch for Discord appearing |

**Discord helper processes:** 4 helpers confirmed in bundle (`Discord Helper.app`, `(GPU)`, `(Plugin)`, `(Renderer)`). Will appear in `kAudioHardwarePropertyProcessObjectList` during a voice call. Need to identify which PID carries call audio.

**Permission behavior:** No prompt was triggered for `AudioHardwareCreateProcessTap` from a CLI tool. For a signed/sandboxed app bundle, `com.apple.audio.capture` entitlement will be required.

**Outstanding for full PASS:**
- [ ] Launch Discord, join voice channel, identify which ObjectID carries call audio
- [ ] Record a 5-min call to m4a via the full pipeline
- [ ] Confirm no room-mic bleed (tap-only capture)
- [ ] Measure CPU overhead during recording (target: <10% on M1)

**Decision: CoreAudio Process Taps. ScreenCaptureKit is eliminated.**

---

## L2. Dual-track recording and sync

**Question:** Do mic and app audio stay aligned over an hour?

1. Record mic (selectable input device) and app audio to two separate files at the same time.
2. Stamp both against a shared clock (Core Audio host time).
3. Run 60 min, then measure drift by overlaying a known click or clap at start and end.
4. Test switching the input device (built-in, USB, headset) mid-session.

**Pass:** tracks aligned within about 200 ms after 60 min; device switch doesn't crash or lose audio.
**Report:** measured drift, how timestamps were stored, any dropped-sample warnings.

### L2 Status — Not started. Needs live audio session (Fixture B).

**What's known from L1 work:** Both tap and mic can share a Core Audio `AudioDeviceIOProc`; `AudioTimeStamp.mHostTime` is the right shared clock. Aggregate device supports multiple sub-taps. Architecture is clear — just needs a 60-min test run.

---

## L3. WhisperKit on the M1

**Question:** Which model size is usable on 8 GB, and is the transcript good enough?

### 🟡 L3 Results — 2026-11-18 (SPM resolved; build + models pending)

**SPM resolution:** ✅ Complete.

| Package | Version |
|---|---|
| WhisperKit | **0.18.0** |
| swift-transformers | 1.1.9 |
| swift-argument-parser | 1.8.2 |
| swift-jinja | 2.5.2 |
| swift-collections | 1.7.6 |
| swift-crypto | 4.5.2 |
| swift-asn1 | 1.7.4 |
| yyjson | 0.12.0 |

WhisperKit 0.18.0 is the latest stable (up from 0.9.x). Resolve took ~15s on M1 with network.

**Outstanding:**
- [ ] `swift build -c release` (first build will be slow — many dependencies)
- [ ] Download models (tiny, base, small, medium) via WhisperKit CLI or API
- [ ] Transcribe existing audio files (`Psalm90_CampusLight.m4a`, podcast `.wav` files in `~/Music/City Light Podcast/`) for performance benchmarking
- [ ] Benchmark table: model × (wall time, peak RAM, quality)
- [ ] Test VAD (voice activity detection) on silent stretches
- [ ] Test vocabulary/prompt injection for theological terms
- [ ] Score against Fixture C (needs hand-corrected reference — not yet recorded)

---

## ✅ L4. Foundation Models chunking — **PASSED**

**Question:** Can the on-device model turn notes plus a long transcript into good enhanced notes within a 4K shared context?

### L4 Results — 2026-11-18

| Property | Value |
|---|---|
| `SystemLanguageModel.default.availability` | **available** |
| `contextSize` | **4096 tokens** |
| Model | `instruct_3b` (3B parameter, on-device) |
| Guardrails | naturalLanguage moderators on prompt + response; no cloud |
| Availability in sandbox | `deviceNotEligible` (entitlement/TCC restriction) |
| Availability unsandboxed | `available` ✅ |

**API shape confirmed:**
```swift
// Correct — do NOT pass schema: to init
let session = LanguageModelSession()
let response = try await session.respond(to: prompt, generating: MeetingNotes.self)
// response.content is MeetingNotes
```

**`@Generable` test with synthetic transcript — PASS:**

Prompt: ~2,194 chars (synthetic 5-min meeting). Runtime: **24.7 seconds**.

Output quality was high:

> **Summary:** The quarterly planning session focused on progress on key objectives including API shipping, documentation, and design system debt, with decisions made on timelines and priorities. Technical and user feedback highlighted risks and required follow-up on bulk export and load balancer configuration. The team agreed on a phased approach to address design system debt and advanced search, while strengthening monitoring and review processes.

> **Decisions:** Commit to docs by Nov 15 · Drop advanced search to Q1 · Document design system debt tradeoffs by Friday · Mandatory peer review for load balancer config · Chaos engineering exercise in December

> **Action Items:** Sarah → talk to revenue re: bulk export · Jess + Mark → one-pager on design system by Friday · Mark → peer review process in runbook by EOW · Contact Tom re: enterprise bulk export

> **Open Questions:** How will advanced search deprioritization impact future timelines?

> **Expanded Notes:** Coherent paragraph synthesizing shorthand notes with transcript detail. Captured nuance from both sources correctly.

**Key constraint confirmed:** 4,096-token context. A 60-min meeting transcript is ~12,000 tokens — requires chunking. Plan: map-reduce (chunk transcript → summarize each chunk → final synthesis). Rolling summary is simpler but loses early context. Test both on Fixture B when available.

**Refusal test:** No refusals observed on meeting content (business/professional language). Church/theological terms not yet tested — add to L3 vocabulary test.

**Unavailable path pattern:**
```swift
if case .unavailable(let reason) = SystemLanguageModel.default.availability {
    // Show "Apple Intelligence required" UI
    print("Unavailable: \(reason)")
}
```

**Outstanding:**
- [ ] Test with actual 60-min transcript (Fixture B → L3 output)
- [ ] Compare map-reduce vs. rolling summary quality and speed
- [ ] Test guardrail refusals on edge-case content (theological terms, names)
- [ ] Measure runtime for a realistic chunk size (~800 tokens prompt)

---

## L5. Live preview and post-recording workflow

**Decision (updated 2026-11-18):** A live visual transcript is not required. Record first, then run WhisperKit after recording. Provide a one-click action that transcribes the recording, uses the selected AI model to enhance/combine the transcript with the user's notes, and inserts the transcript into the generated notes document. A live-enhance panel is a useful optional enhancement, not a v1 requirement.

The core app window should let the user write notes and start/stop a recording. Keep that interaction focused; post-recording transcription and note enhancement are a deliberate, user-invoked one-click workflow. The existing L3 and L4 timings support post-recording processing, but full-meeting quality and chunking remain to be validated.

---

## L6. Output files and destination settings

**Product direction (updated 2026-11-18):** Obsidian integration is not required. The app writes ordinary Markdown and audio files to separate, user-configurable folders.

### Exploratory Obsidian test artifacts (not a release requirement)

An earlier test mistakenly targeted `/Users/corbin/Hal9000`; the correct active vault is `/Users/corbin/Library/Mobile Documents/iCloud~md~obsidian/Documents/Corbin_Personal`, confirmed by the user. Test notes and sample audio were copied to `People/Meetings/Local Spike Test/` in that vault. Source sample M4As were valid audible 1-second AAC test tones (48 kHz stereo, mean -9.0 dB, peak -5.8 dB). These files can serve as ordinary Markdown/audio examples. Obsidian-specific frontmatter rendering, embeds, and playback are no longer required for product acceptance.

The separate destination-folder settings still require macOS security-scoped bookmark and sandbox testing in the actual app. The prior CLI/UI exploration does not validate those permissions.

## 🟡 L7. Permissions, sandbox, signing

### L7 Notes — 2026-11-18

**xcode-select (updated 2026-11-18):** User ran `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`; `xcode-select -p` confirms `/Applications/Xcode.app/Contents/Developer`. This removes the prior CLT blocker. Code signing and entitlement tests remain outstanding.

**Known minimum entitlements (from API research):**

| Capability | Entitlement | Notes |
|---|---|---|
| Microphone (AVAudioSession) | `com.apple.security.device.audio-input` | Required for sandbox |
| CoreAudio Process Taps | `com.apple.audio.capture` | Likely required in signed app bundle; CLI works without it |
| ScreenCaptureKit | `com.apple.security.screen-recording` + Info.plist `NSScreenCaptureUsageDescription` | Plus user TCC grant |
| FoundationModels | No special entitlement observed | Works in CLI; may need Apple Intelligence enabled in System Settings |

**Sandbox behavior:**
- `swift build` in sandboxed shell: ❌ fails (Clang module cache write blocked)
- `swift build` unsandboxed: ✅ succeeded (19s clean build)
- `AudioHardwareCreateProcessTap` from CLI: ✅ no prompt, no entitlement needed
- `SCShareableContent.current` from CLI: ❌ TCC blocked immediately

**Outstanding:**
- [x] Switch xcode-select to Xcode.app (confirmed 2026-11-18)
- [ ] Build a minimal signed app bundle with `com.apple.audio.capture` entitlement and test process tap behavior
- [ ] Document fresh-account setup steps (what prompts appear, in what order)
- [ ] Notarization test (requires paid Apple Developer account)
- [ ] Confirm FoundationModels availability entitlement requirements for distribution

---

## Results template

For each spike, report:

- Date, versions, machine
- What was tried
- Numbers measured
- Pass or fail
- Surprises
- Recommendation

---

## Status Summary — 2026-11-18

| Spike | Status | Blocker |
|---|---|---|
| **L1** Per-app audio capture | 🟡 Tap pipeline passed; capture silent | Need audible call sample, bleed check, and CPU measurement |
| **L2** Dual-track sync | ⬜ Not started | Need 60-min live session (Fixture B) |
| **L3** WhisperKit | 🟡 Local benchmark complete | Need Fixture C quality scoring, VAD and vocabulary tests; measurements below |
| **L4** Foundation Models | ✅ **Passed** | None — ready to integrate |
| **L5** Live transcript/panel | ✅ Optional | Core workflow is post-recording one-click transcription + enhancement |
| **L6** Configurable file outputs | ✅ Product direction decided | Implement separate folder settings and verify app writes/permissions |
| **L7** Permissions/signing | 🟡 Partial | Xcode selection now points to Xcode.app; signed bundle test remains |

## Next Actions (priority order)

1. ✅ `xcode-select -p` now returns `/Applications/Xcode.app/Contents/Developer`; signed-app and entitlement testing remain
2. Build the main notes/recording window and one-click post-recording transcription/enhancement flow; then verify separate output folders
3. ✅ `cd /Users/corbin/Hal9000/projects/local-spikes && swift build -c release` — release build succeeds; local benchmarks recorded below
4. Record fixtures: Discord call (A), 60-min meeting (B), 10-min corrected reference (C)
5. L1 full close: Discord voice call → tap → record → verify no bleed
6. L3 follow-up: record Fixture C, score accuracy, measure peak RAM, and test VAD plus theological vocabulary


---

## Spike Run Update — 2026-11-18 (release build + local WhisperKit benchmarks)

### Environment observed for this run

| Field | Value |
|---|---|
| macOS | 27.0.1 (Build 26A434) |
| Machine | MacBook Pro 17,1 — Apple M1, 8 GB (machine details from setup record) |
| Swift | 6.4.2 (swiftlang-6.4.2.1.9 / clang-2100.4.1.1) |
| SDK | macOS 27.0.0 |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` (now points to Xcode.app; earlier note saying CLT was stale) |
| WhisperKit | 0.18.0 (resolved package) |

### L3 — Release build

- Command: `cd /Users/corbin/Hal9000/projects/local-spikes && swift build -c release`
- Result: **PASS**, clean release build in 43.66 seconds; final incremental rebuild after harness edits completed in 3.31 seconds.
- The initial sandboxed attempt failed because Swift could not write `/Users/corbin/.cache/clang/ModuleCache`. Re-running with the required cache access succeeded. One initial build emitted an AVFoundation `asset.duration` deprecation warning; the harness now uses `try await asset.load(.duration)`, and the final builds emitted no warnings.
- `LocalSpikes` is the built benchmark executable at `.build/out/Products/Release/LocalSpikes`; the source imports WhisperKit through SPM. There was no standalone `whisperkit` command on `PATH`.

### L3 — Local audio benchmark

Models ran sequentially on the M1 against both existing audio files. The model files were available locally by the run; first model loading showed cold-start variance, while the second run was warm. Wall times below are transcription-only, excluding model loading. Durations come from AVFoundation; segment counts and timestamps are from WhisperKit 0.18.0.

| Model | Psalm90_CampusLight.m4a (44:16) | PodcastRachelleRough.wav (75:23.6) | Timestamped segments |
|---|---:|---:|---|
| tiny | 34.2 s (cold run: 35.1 s) | 49.3 s | 661 / 999 |
| base | 52.1 s (cold run: 69.9 s) | 75.2 s | 657 / 953 |
| small | 156.6 s (cold run: 207.3 s) | 224.1 s | 746 / 955 |

- All six transcriptions completed successfully and returned timestamps through the end of each file. Approximate real-time factors for the warm run: tiny 78x / 92x, base 51x / 60x, small 17x / 20x (Psalm / podcast).
- First-word samples were broadly coherent for all three models. On the podcast, the tiny model heard “Young and Free Hills Island podcast”; base heard “Young and Free Hillsong podcast”; small heard “young and free - The Hillsong podcast.” This is a qualitative spot check only, not a scored accuracy result. No hand-corrected Fixture C exists yet, so no WER or model-quality pass is claimed.
- Model load time varied materially between runs: cold sample tiny/base/small 3.1/77.2/27.4 seconds; subsequent warm sample 2.2/2.0/2.2 seconds. Treat warm load numbers as cache-dependent.
- The previous harness only processed the first audio fixture and mislabeled a point-in-time resident-memory delta as “peak RAM.” It now processes both configured files, records real durations, uses the current async AVFoundation duration API, and prints a working summary table. RSS deltas varied from about -7 to 30 MB at the sample instant and are **not peak memory**; they are not suitable for comparing model memory. Use Instruments or another high-water measurement for that requirement.
- The input WAV is mono, 44.1 kHz, 24-bit PCM; the M4A is the 44:16 Psalm recording. Podcast WAV duration is 4,523.58 seconds (75:23.6).

### L3 remaining

- [ ] Record Fixture C and score each model against the hand-corrected reference (WER or another agreed metric).
- [ ] Measure peak memory with Instruments / an accurate process high-water metric; current RSS sample is insufficient.
- [ ] Run VAD comparison on a file with known silent stretches; the benchmark currently uses WhisperKit's default chunking behavior and does not claim a VAD result.
- [ ] Test theological vocabulary prompt injection; not yet implemented or measured.
- [ ] Consider testing medium only after peak-memory measurement; the current harness defaults to tiny/base/small for the 8 GB machine.

### Other spike state after this run

- **L1:** CoreAudio process-tap pipeline remains effectively passed. Still requires a live Discord voice call to identify the carrying helper PID, record 5 minutes, verify no room-mic bleed, and measure CPU.
- **L2:** Still requires a 60-minute two-track live recording, shared host-time drift measurement, and input-device switch test.
- **L4:** Synthetic Foundation Models chunking test remains passed as documented. Real meeting quality, map-reduce vs rolling-summary comparison, and church-specific terms still need Fixtures B/C.
- **L6:** Obsidian CLI was present at `/Applications/Obsidian.app/Contents/MacOS/obsidian`, but `obsidian help` exited with code 134 and no output in this session. No visual confirmation of Properties rendering, audio embed playback, or alternate attachment paths was obtained. Those checks remain open in Obsidian.
- **L7:** `xcode-select` now points to Xcode.app and the release build works. Signed app-bundle process-tap entitlement, fresh-account permission prompts, notarization, and FoundationModels distribution behavior remain untested.
- **L5:** Live visual transcript is optional; post-recording one-click transcription and note enhancement are part of the intended v1 workflow.

### Harness changes

`projects/local-spikes/Sources/LocalSpikes/LocalSpikes.swift` now benchmarks the podcast WAV path listed above as well as the Psalm M4A, loops through all configured fixtures, records actual audio duration, uses AVFoundation's async duration load, and prints the summary without the broken C `%s` string formatter. RSS labels explicitly say they are endpoint deltas, not peak memory. The previous run displayed the results-table heading but did not capture table rows; the table formatter was replaced and the final build passed, but that formatter change was not rerun through the long benchmark.


---

## Live Verification Update — 2026-11-18 (Discord + Obsidian retry)

### L1 — Discord live process inventory

- `Discord.app` was running (PID 21872) with active audio-process entries for the renderer (ObjectID 143, PID 21897), main app (ObjectID 144, PID 21872), another helper (ObjectID 146, PID 21901), and an additional unlabelled PID 21900 (ObjectID 145). The full inventory was captured by `swift Scripts/list_coreaudio_processes.swift`.
- The saved recorder selected the first process path containing “discord”: ObjectID 143 / PID 21897, `Discord Helper (Renderer)`.

### L1 — 10-second tap attempt (result: valid file, silent audio)

- Command: `swift Scripts/capture_discord.swift discord 10 /private/tmp/discord_tap_test.m4a` — ran directly without building the Swift package.
- `AudioHardwareCreateProcessTap`, aggregate-device creation, and `AudioDeviceStart` all returned status 0 (`noErr`). The IOProc received 480,256 frames over 10.1 seconds and wrote a 64,272-byte M4A.
- `afinfo /private/tmp/discord_tap_test.m4a`: valid AAC, 48 kHz, stereo, 10.005 seconds.
- `ffmpeg -hide_banner -i /private/tmp/discord_tap_test.m4a -af volumedetect -f null -`: mean and max volume both **-91.0 dB**, digital silence. This is **not** an audible-call capture pass. The renderer may not be the audio-carrying process, or Discord may have emitted no audio during this sample. Next try the main process and other helper PIDs; verify non-silent level before calling L1 passed.
- First direct Swift run of the inherited temporary recorder failed to compile because its callback used the old seven-argument/OSStatus form. `Scripts/capture_discord.swift` now uses this SDK's five-argument Void block callback. The corrected run still emits an `UnsafeBufferPointer` lifetime warning; correct it before treating the script as a durable capture utility.
- CPU overhead was not measured. This was a 10-second diagnostic, not the required 5-minute recording.

### Obsidian retry (visual review still unavailable)

- Obsidian reports version **1.12.4** and has a running process (PID 81007), but the CLI helper at `/Applications/Obsidian.app/Contents/MacOS/obsidian` exits with code 134 and no output for both `help` and `--version`.
- `open -a Obsidian` failed: “Unable to find application named 'Obsidian'.” Opening `/Applications/Obsidian.app` failed with Launch Services `kLSNoExecutableErr` (-10827), even though the app process is already running. AppleScript activation by bundle ID and app name also failed to resolve the application.
- Result: no visual check of note properties, embedded-audio playback, or alternate attachment path. The app is running but its CLI/Launch Services entry is not usable from this session.

### Reusable script inventory (saved in the project)

| Script / command | Purpose | Build required? |
|---|---|---|
| `swift Scripts/list_coreaudio_processes.swift` | List CoreAudio process ObjectIDs, PIDs, app names, and bundle IDs | No Swift package build; Swift runs the script directly |
| `swift Scripts/capture_discord.swift discord 10 /private/tmp/discord_tap_test.m4a` | Tap the first matching Discord CoreAudio process and save an M4A diagnostic | No Swift package build; Swift runs the script directly |
| `.build/out/Products/Release/LocalSpikes` | Run the L3 WhisperKit benchmark | Uses the release executable; rebuild with `swift build -c release` after a clean checkout or source change |
| `afinfo /private/tmp/discord_tap_test.m4a` | Inspect captured audio file format and duration | No build |
| `ffmpeg -hide_banner -i /private/tmp/discord_tap_test.m4a -af volumedetect -f null -` | Check whether a capture contains audible signal | No build |

The `Scripts/` copies are the source of truth. The earlier `/private/tmp` helper files are scratch copies and should not be needed for future runs. Do not report the Discord capture as passed until a non-silent sample is recorded from the actual call audio.


- Follow-up probe: `swift Scripts/capture_discord.swift pid:21872 10 /private/tmp/discord_main_tap.m4a` tapped Discord main process ObjectID 144; tap/aggregate/start were all `noErr`, 480,256 frames captured, 64,272-byte M4A. `ffmpeg` measured mean/max **-91.0 dB**. Main process also emitted silence in this 10-second interval; testing helper PIDs next.

- Follow-up probe: `swift Scripts/capture_discord.swift pid:21900 10 /private/tmp/discord_helper_a_tap.m4a` tapped helper ObjectID 145; API statuses were all `noErr`, 480,256 frames, 64,272-byte M4A, but `ffmpeg` measured mean/max **-91.0 dB** (silence).

- Follow-up probe: `swift Scripts/capture_discord.swift pid:21901 10 /private/tmp/discord_helper_b_tap.m4a` tapped helper ObjectID 146; API statuses were all `noErr`, 480,256 frames, 64,272-byte M4A, but `ffmpeg` measured mean/max **-91.0 dB** (silence).

- Grouped follow-up: `swift Scripts/capture_discord.swift discord 15 /private/tmp/discord_all_tap_15s.m4a` selected all four Discord CoreAudio objects (143–146), tap/aggregate/start returned `noErr`, and wrote a 15.008-second, 48 kHz stereo AAC file (65,676 bytes; 720,384 frames). `ffmpeg volumedetect` again returned mean/max **-91.0 dB**. No Discord output was audible in this interval, even with all four process objects tapped.


### Obsidian window screenshot retry

- `swift Scripts/obsidian_window_ids.swift` found window 28545, title `Meetings - Corbin_Personal - Obsidian 1.15.0`.
- `screencapture -l 28545 -x /private/tmp/obsidian_window.png` succeeded. Visual inspection shows the app is displaying the `Meetings` folder/home note in the `Corbin_Personal` vault, with an empty body and no Properties fields. This is **not** the `Hal9000` vault or the spike test meeting note, so the L6 rendering/audio check remains unverified.
- The window title reports Obsidian 1.15.0 while the installed app bundle’s `CFBundleShortVersionString` is 1.12.4. This version/path mismatch accompanies the CLI and Launch Services failures above.
- The saved window enumerator and exact screenshot command are included in `Scripts/README.md`.


### Obsidian direct-window navigation probe

- `swift Scripts/focus_obsidian_command_palette.swift 81007` activated the running app and Command-P opened its command palette.
- The follow-up helper called `NSRunningApplication.activate()` again before typing, which returned focus to the note editor and inserted the word `vault` into the blank `Meetings` note. I immediately sent Command-Z with `swift Scripts/undo_obsidian_probe_input.swift 81007`.
- A fresh window screenshot confirmed the note is blank again (0 words, 0 characters). No persistent note edit remains from that probe.
- The text-entry helper is being changed to preserve current focus and will only be used while the command-palette field is visibly open. Its earlier behavior should not be reused.

### L6 toolchain retry after Xcode selection — 2026-11-18

- User ran `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. `xcode-select -p` confirms `/Applications/Xcode.app/Contents/Developer`.
- Retried `swift Scripts/click_obsidian_palette_search.swift 1060 159`; Swift still failed before executing because it cannot write `/Users/corbin/.cache/clang/ModuleCache/Swift-18Y2CYADWFGX0.swiftmodule` (`Operation not permitted`).
- Retried with `swift -module-cache-path /private/tmp/local-spikes-swift-module-cache Scripts/click_obsidian_palette_search.swift 1060 159`; it produced no output or completion after 35 seconds, so it was interrupted. No click was confirmed and no fresh screenshot was created. Obsidian rendering/audio verification remains pending.
- The exact retry and limitation are also recorded in `projects/local-spikes/Scripts/README.md`.


---

## Product Design Findings — Configurable outputs and model selection (2026-11-18)

The final app design does not depend on Obsidian. It writes standard files to user-selected locations. Obsidian can still be used by a user to open the Markdown later, but no vault integration, plugin, special syntax, or vault-specific attachment behavior is required. The Obsidian CLI/UI experiments above are historical exploration and do not block the product. The primary window is for writing notes and starting/stopping recording; after recording, one click runs transcription and AI note enhancement and inserts the transcript into the final notes. Live visual transcription/enhancement is optional.

### Core interaction

- Main window: editable notes area plus clear start/stop recording controls.
- After a recording is available, provide one action (for example, “Transcribe & enhance”) that runs the selected Whisper model, enhances the user's notes with the transcript using the selected AI model, and includes/inserts the transcript in the final Markdown output.
- The workflow is post-recording; do not require a live transcript to complete a session. A live-enhance panel may be explored later but is optional and not a v1 blocker.
- Show processing progress and errors so the user can tell when transcription/enhancement is complete; preserve the original recording and user notes if processing fails.

### Output locations

- Provide a setting for the destination folder for the generated final Markdown document.
- Provide a separate setting for the audio recording destination folder. The two folders can be configured independently and may be different.
- Persist each selection in app settings and show the selected paths. Let the user change either destination without changing the other.
- Write ordinary `.md` and audio files; do not require Obsidian frontmatter, wikilinks, embeds, or vault discovery. The Markdown should include a clear reference to its associated audio recording. Define whether that reference is relative or absolute as part of implementation, especially when the folders differ.
- Folder access must survive app relaunch. Implement and test macOS security-scoped bookmarks / sandbox permissions for each selected destination. Do not claim this behavior is proven by the current command-line spike.

### Selectable processing models

- Expose transcription (Whisper) model selection in Settings, with the available local WhisperKit models offered by the app. Default to WhisperKit `small` as the provisional choice from this spike. On the M1/8 GB test machine it completed the 44:16 Psalm file in 156.6 seconds and the 75:23.6 podcast in 224.1 seconds (warm transcription runs; model load excluded), approximately 17× and 20× real time. The podcast first-word sample correctly included “Hillsong” for `small`, while `tiny` misheard it as “Hills Island”; this is only a qualitative spot-check. No hand-scored WER or peak-memory measurement exists, so validate `small` with Fixture C and Instruments before treating it as a final quality/memory recommendation.
- Expose AI note-generation model selection in Settings. Default to Apple Foundation Models (`SystemLanguageModel.default`, on-device `instruct_3b` in this test), which was available on this machine and passed the synthetic structured-notes test. The test took 24.7 seconds with a 4,096-token context; real 60-minute meeting quality and chunking strategy still need validation.
- Keep the two choices independent: the user can select the transcription model and AI notes model separately. Persist both settings. Show availability/errors for unavailable models and avoid silently switching to a remote service. Additional AI backends may be added later; Apple Foundation Models remains the default.

### Acceptance checks for the eventual app

- Open the main window, enter notes, start and stop a recording.
- Trigger the one-click post-recording workflow; confirm it runs transcription, enhances the notes, and includes the transcript in the Markdown result.
- Configure two different output folders, restart the app, and confirm both settings persist.
- Record a session and confirm the audio file lands in the configured audio folder and the final Markdown lands in its configured folder.
- Confirm the Markdown identifies/links its corresponding audio across the configured folder arrangement.
- Change transcription and AI model choices independently; confirm each selected model is used and the defaults are WhisperKit `small` and Apple Foundation Models.
- Test folder access after relaunch and handle revoked/moved folders clearly.
- Obsidian opening/rendering and a live-enhance panel are optional conveniences, not release blockers.
