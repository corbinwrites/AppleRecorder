# Local Spikes Scripts

Run commands from `projects/local-spikes`. Standalone `swift Scripts/*.swift` helpers use the Swift interpreter, so they do not need the SwiftPM/WhisperKit package build. They still compile the individual script at launch. `LocalSpikes` is the SwiftPM benchmark executable and requires `swift build -c release` after a clean checkout or source edit.

## L1: CoreAudio process tap

List current audio process objects (ObjectIDs/PIDs change between launches):

```sh
swift Scripts/list_coreaudio_processes.swift
```

Capture all CoreAudio process objects whose executable path contains `discord` (target, seconds, output path):

```sh
swift Scripts/capture_discord.swift discord 10 /private/tmp/discord_tap_test.m4a
```

Isolate one PID if needed:

```sh
swift Scripts/capture_discord.swift pid:21872 10 /private/tmp/discord_main_tap.m4a
```

The tap captures app output only, not the room microphone. A successful tap and non-empty file do not prove audio was captured. Inspect the file and signal:

```sh
afinfo /private/tmp/discord_tap_test.m4a
ffmpeg -hide_banner -i /private/tmp/discord_tap_test.m4a -af volumedetect -f null -
```

Check `mean_volume` and `max_volume`; -91 dB in these tests means digital silence.

## L6: Obsidian window inspection/navigation

The installed CLI helper aborts in this environment. Find the running Obsidian window and capture only that window:

```sh
swift Scripts/obsidian_window_ids.swift
screencapture -l <window-id> -x /private/tmp/obsidian_window.png
```

`Scripts/search_obsidian_commands.swift <pid> <query>` activates Obsidian, opens Command-P, and filters the command palette in one invocation. `Scripts/focus_obsidian_command_palette.swift <pid>` opens the palette. `Scripts/press_obsidian_return.swift` sends Return to the currently focused control.

The following UI helpers are experimental and should only be used after a screenshot confirms the target/focus: `type_obsidian_palette.swift` types into whichever field is focused; `click_obsidian_palette_search.swift <x> <y>` and `click_obsidian_vault_switcher.swift <pid>` click screen coordinates; `press_obsidian_escape.swift <pid>` activates the app and sends Escape. `undo_obsidian_probe_input.swift <pid>` sends Command-Z and is only appropriate when the last edit is a known probe insertion. A previous probe typed `vault` into the blank Meetings note; Command-Z removed it, and a fresh screenshot verified 0 words/0 characters.

## L3: WhisperKit benchmark

```sh
swift build -c release
./.build/out/Products/Release/LocalSpikes
```

`Sources/LocalSpikes/LocalSpikes.swift` benchmarks tiny/base/small against the Psalm M4A and podcast WAV paths. The built product is under `.build/` and is not a source artifact.

## Recorded results (2026-11-18)

- Discord Renderer PID 21897, main PID 21872, helper PIDs 21900/21901: individual 10-second taps all returned `noErr` and wrote valid M4A files, but each measured -91 dB.
- A 15-second tap across all four Discord CoreAudio objects measured -91 dB.
- The full 300-second grouped tap `/private/tmp/discord_all_tap_5m.m4a` captured 14,400,000 frames in 300.3 seconds, produced a valid 300-second 48 kHz stereo AAC file, and measured mean/max -91 dB. The tap/file pipeline ran; Discord call audio was not captured. CPU overhead and room-mic bleed are still untested.
- Obsidian 1.12.4 bundle CLI aborted (134), while the running window reported 1.15.0. The user confirmed `/Users/corbin/Library/Mobile Documents/iCloud~md~obsidian/Documents/Corbin_Personal` is the correct vault; the chooser shows `Corbin_Personal` as ACTIVE. Both spike notes and the sample audio copies are in `People/Meetings/Local Spike Test/` in that vault. Latest screenshot still has the vault chooser open; note rendering and playback remain unverified. A coordinate-click retry was blocked by a Swift module-cache permission error and then stalled with a `/private/tmp` cache, so it was interrupted.

See `~/Downloads/LOCAL-SPIKES.md` for the dated full log, command outputs, limitations, and status changes. Temporary audio/screenshots are under `/private/tmp`; reusable Swift source is in this directory.


## L6 current vault and test artifact location

Correct active vault (confirmed by the user): `/Users/corbin/Library/Mobile Documents/iCloud~md~obsidian/Documents/Corbin_Personal`. The Markdown notes and sample audio copies were placed in `People/Meetings/Local Spike Test/` inside that vault. `Corbin_Personal` was visibly marked ACTIVE in the latest window capture. Rendering, attachment resolution, and playback have not yet been visually confirmed. See `~/Downloads/LOCAL-SPIKES.md` for the event log and earlier failed navigation attempts.

### Toolchain retry after Xcode selection (2026-11-18)

The user ran `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`; `xcode-select -p` now reports `/Applications/Xcode.app/Contents/Developer`. Re-running `swift Scripts/click_obsidian_palette_search.swift 1060 159` still fails because Swift cannot write its default module cache under `/Users/corbin/.cache/clang/ModuleCache` (sandbox `Operation not permitted`). Retrying with `swift -module-cache-path /private/tmp/local-spikes-swift-module-cache ...` did not finish within 35 seconds and was interrupted. No UI click was confirmed and no new screenshot was produced. The earlier copied test files remain in the correct vault; rendering/playback are still pending.

## Product direction update (2026-11-18)

The final product does not require Obsidian. It should write a standard Markdown document and the audio recording into independently configurable folders, with each folder selection persisted in settings. The Markdown should identify its corresponding audio file. Model settings are independent: provisional transcription default is WhisperKit `small` based on the spike's qualitative check and 17–20× real-time M1 transcription speed; AI notes default is on-device Apple Foundation Models. See `~/Downloads/LOCAL-SPIKES.md` for measurements, caveats, and implementation acceptance checks. Obsidian UI helpers remain documented for reproducing the historical integration experiment, not as product prerequisites.

Core interaction decision: the app's main window is for writing notes and starting/stopping a recording. Afterward, one click runs Whisper transcription, enhances the notes with the selected AI model, and inserts the transcript into the final Markdown. Live visual transcript/live-enhance UI is optional; users do not need it to complete the workflow. See `~/Downloads/LOCAL-SPIKES.md` for the full design and acceptance checks.
