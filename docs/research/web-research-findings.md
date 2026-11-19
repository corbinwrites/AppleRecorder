# Web Research Findings: Meeting Notes App

Date: 2026-11-18. Source: web only, no hardware. Where a web finding conflicts with a local spike, the spike wins.
Confidence tags: **[solid]** primary/official source, **[medium]** secondary or single source, **[weak]** unverified or inferred.

## Bottom line

- **Build, don't fork.** Several MIT/Apache Swift projects exist. None found that combines per-app capture, WhisperKit, Apple Foundation Models and Obsidian output with re-verification from saved audio. HushScribe and OpenOats are the closest.
- **Run Core Audio process taps first in L1.** Narrower permission ("System Audio Recording"), per-process, and most of the Swift projects use it. Still test ScreenCaptureKit to compare.
- **Design for a 4,096-token Foundation Models window.** Sources conflict with 8,192. L4 reads `contextSize` on your Mac and settles it.
- **WhisperKit is the default.** MIT, v1.1.0 (Aug 2026) adds low-memory long-file loading and a fix for `promptTokens`. Candidate model: `large-v3-v20240930_626MB`.
- **Cut live preview from v1** unless L5 surprises you.
- **Decide on the $99 Apple Developer fee.** It determines whether you ship signed releases or build-from-source with an "Open Anyway" README section.
- **Dual-track capture (mic vs app) already gives "Me vs Them."** Diarization is only needed for multiple remote speakers. Keep it v2.

## Conflicts to resolve in spikes

| Topic | Conflict | Spike |
|---|---|---|
| Foundation Models context size | Apple docs and WWDC26 Q&A say 4,096; WWDC26 session 241 sample prints 8,192 | L4 |
| Core Audio tap minimum OS | API appears in 14.2 headers; AudioCap sample says 14.4 | L1 |
| SCK audio without Screen Recording permission | Some code claims width/height 0 avoids it; Apple forum answer and SignalCaster docs say permission is needed | L1 |
| Monthly permission re-prompt | Documented for Screen Recording (incl. ScreenCaptureKit). Not found for Core Audio taps | L1 |
| SpeechAnalyzer accuracy | 2.1% WER (LibriSpeech, read speech) vs 14.0% (earnings calls). Different data | L5 |
| SpeechAnalyzer custom vocabulary | Sources disagree on whether it exists and how well it works | L5 |

---

## W1. Prior art

**Found:**

| Project | License | Stack | Notes |
|---|---|---|---|
| **HushScribe** | MIT | Swift 6.3, macOS 26+ | Writes `.md` with frontmatter (type, created, attendees, tags, source_app) to a chosen folder (e.g. Obsidian vault). Parakeet-TDT v3 (default), WhisperKit base/large-v3, or Apple Speech. Summaries via Apple NL or Qwen3 (MLX). **Closest match.** |
| **OpenOats** | MIT | Swift 6.2, macOS 15+, Apple silicon | Local transcription (~600 MB model), Markdown transcripts to any folder. Homebrew cask + DMG + signing/notarization scripts. Notes via OpenRouter (cloud, optional). Forces an in-app recording-obligations acknowledgement. |
| **Recap** | Not retrieved | Swift, WhisperKit, Core Audio taps, Ollama/OpenRouter | README says incomplete, not for daily use. Closest to your capture + WhisperKit stack. Build from source only. |
| **Kleoth** | Apache-2.0 | Swift 6, macOS 14.4+ | Menu bar app + CLI. Whisper (~600 MB). Self-signed builds. Optional ElevenLabs cloud. |
| **Hlopya** | Custom, restricts companies of 1000+ employees | Swift 5.9, Core Audio, FluidAudio (Parakeet v3), Claude API | Signed + notarized. Separate mic/system WAVs plus stereo mix. **Don't borrow code** (non-standard license). |
| **Anarlog** | MIT (outside `enterprise/`) | Local SQLite, Markdown export | Cross-platform; ~9.3k stars. Team now also building a separate product, "char". |
| **Meetily** | Not retrieved | Whisper/Parakeet, macOS + Windows | Large user base; license and stack details not checked. |
| **Talat** | Commercial, one-time fee | FluidAudio + AudioTee | Not open source. AudioTee (its Core Audio tap library) is. |

**Open questions:** Recap, Meetily and Anarlog licenses and exact capture approach weren't verified. HushScribe was read from a GitHub mirror domain; confirm at the real repo before relying on details. Star counts conflicted between sources, so ignore them.

**Recommendation:** Build. Read HushScribe, OpenOats and Recap for capture, export and signing patterns. Check licenses before copying anything.

**Sources:** github.com/maxmaxme/hlopya, github.com/ofcRS/kleoth, github.com/yazinsai/OpenOats, github.com/RecapAI/Recap, openapps.pro/apps/recap, gh.hhj520.top/drcursor/HushScribe (mirror), themenonlab.blog/blog/anarlog-open-source-local-first-granola-alternative, techcrunch.com/2026/03/24/talats-ai-meeting-notes-stay-on-your-machine-not-in-the-cloud, openalternative.co/meetily

---

## W2. Per-app audio capture APIs

**Core Audio process taps [solid for API shape, medium for the rest]**
- `AudioHardwareCreateProcessTap` + `CATapDescription`. Tap lives inside a private aggregate device; you read from an IOProc. Per-app via PID → `AudioObjectID` translation.
- Minimum OS: introduced in 14.2 headers, Apple's sample (AudioCap) targets 14.4. Use 14.4 as the safe floor.
- Permission: TCC service `kTCCServiceAudioCapture`. Add `NSAudioCaptureUsageDescription` to Info.plist by hand (Xcode doesn't list it). Prompt reads "System Audio Recording," narrower than Screen Recording.
- No public API to check or request the permission. AudioCap uses private TCC calls (build-flag to disable).
- **Silent failure:** denied permission returns `noErr` and delivers zeroed buffers. Add a non-zero check to the L1 spike.
- Sandboxed apps need no extra audio-capture entitlement (per the `catap` docs).
- Electron/Discord: audio often plays from helper processes. `callnotes` tapping by app family works, with a global-tap fallback. Tap the whole process family, not one PID.
- Changing the output device mid-call (e.g. AirPods) can silence a running tap.

**ScreenCaptureKit [medium]**
- `SCStream` with `capturesAudio = true`, `SCContentFilter` including/excluding applications gives per-app filtering. Works from macOS 13+ in some projects; Apple forum thread says screen output must be added or it errors (thread is older, may be outdated).
- Permission: "Screen & System Audio Recording." SignalCaster docs say you must grant it even though no video is captured.
- Re-prompt: Sequoia shows a monthly "Allow For One Month" prompt for screen-recording apps, including ScreenCaptureKit apps. Whether Core Audio taps trigger it: **not found.**
- Tahoe 26.1 quirk (Apple forum): plain executables don't appear in the Screen & System Audio Recording list, only app bundles. Build the L1 spike as a `.app`, not a bare CLI.
- Dev tip (forum): permission can reset after every Xcode build unless signing is stable.

**macOS 26/27 changes:** nothing concrete found for either API beyond the Tahoe list-UI quirk. One macOS 27 beta forum report concerns `CGWindowListCopyWindowInfo` returning window owner names without permission. Minor.

**Recommendation:** Test taps first, SCK second. Test with output-device switching and helper processes. Record permission prompts exactly as they appear.

**Sources:** github.com/insidegui/AudioCap, dev.to/nickdelv/2000-buffers-of-nothing-3i8, pypi.org/project/catap/0.5.2, github.com/michaelczesun/callnotes, 9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly, tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts, developer.apple.com/forums/thread/718279, tunetrackersystems.com/documentation/signalcaster/source-appcapture.html, origin-devforums.apple.com (Tahoe plain-executable thread)

---

## W3. WhisperKit and alternatives

**WhisperKit [solid]**
- MIT. Repo has been renamed **argmax-oss-swift**; latest found is **v1.1.0 (Aug 6, 2026)**.
- v1.1.0: incremental file loading (`audioLoadingMode: .incremental`) cuts peak memory 70%+ on 3-hour input, chunked at VAD boundaries (default 120 s chunks). Fixes empty transcription when `promptTokens` is set. Also adds SpeakerKit speaker centroid embeddings.
- API: word timestamps option, `chunkingStrategy: .vad` (energy-based VAD per release notes), temperature fallback, `promptTokens`.
- Models: Hugging Face `argmaxinc/whisperkit-coreml`, downloaded at runtime. Argmax's eval table (LibriSpeech): `large-v3-v20240930_626MB` 1.95% WER at 626 MB; full large-v3 ~3.1 GB; tiny 7.47% WER at 66 MB.
- Device defaults: a fork's copy of Argmax's `config.json` lists the 626 MB large-v3 variant as default for M1-class chips **[weak, verify in the Argmax repo]**.

**Speed on M1 [medium, 2024 data]:** Argmax benchmark logs show M1 running full large-v3 (947 MB) at ~1.85 speed factor and tiny.en at ~55. M2 runs the 626 MB variant at ~8–12. Unit isn't stated (likely × real time). No M1 numbers found for the 626 MB variant. **No peak-RAM figures found for 8 GB.**

**Alternatives [medium]**
- **Parakeet TDT v3 via FluidAudio** (Apache-2.0 SDK; model CC-BY-4.0): fast (README cites ~50× real time), 25 mostly European languages vs Whisper's 99. ~600 MB. Used by HushScribe, Hlopya, Talat.
- **MLX Whisper / whisper.cpp:** viable; no head-to-head numbers retrieved.
- **SpeechAnalyzer:** see W5.

**Hallucination on silence [medium]**
- Cause: Whisper has no built-in VAD and conditions on previous text, so silence can trigger looping or invented phrases.
- Mitigations in order of effect: VAD pre-filter (Silero or similar), turn off previous-text conditioning if loops appear, post-filters (delooping, a list of known hallucination phrases). `no_speech_threshold` is a weak secondary defense.
- A 2025 study reportedly cut WER on non-speech-heavy audio from ~105% to ~6.5% by combining Silero VAD with delooping and a phrase list (secondhand via a blog; check arXiv 2501.11378).
- Not confirmed: whether WhisperKit exposes a Silero-class VAD. It documents an energy-based one.
- Caution: aggressive VAD can drop quiet real speech. Test on fixture A.

**Recommendation:** WhisperKit ≥1.1.0 with `.incremental` loading and `.vad` chunking. Start L3 with the 626 MB large-v3 variant, then small and base as fallbacks. Add Parakeet (FluidAudio) as an optional fourth row if English-only speed matters. Test `promptTokens` only on ≥1.1.0.

**Sources:** github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0, huggingface.co/argmaxinc/whisperkit-coreml, huggingface.co/spaces/argmaxinc/whisperkit-benchmarks (M1/M2 commits), popularai.org/p/whisper-hallucinations-during-silence, arxiv.org/pdf/2501.11378, docs.fluidinference.com, github.com/benbjurstrom/FluidAudio

---

## W4. Foundation Models framework

**Context size [conflict]**
- Apple's "Managing the context window" doc: **4,096 tokens per session**. Input and output share it.
- `SystemLanguageModel.contextSize` and `tokenCount(for:)` arrived in 26.4 and are back-deployed.
- WWDC26 session 241 code sample prints `8192` for `contextSize`. A third-party writeup of the WWDC26 lab Q&A quotes Apple engineers saying the on-device window is still 4,096 in iOS 27 and PCC is 32K. A DEV post repeats 8192.
- Apple's docs list three on-device model versions: 26.0–26.3, 26.4, and 27.0. Behavior can differ by OS.
- **Design to 4,096 as the floor** and read `contextSize` at runtime.

**API [solid/medium]**
- `@Generable` / `@Guide` for guided generation, tool calling, `tokenCount(for:)`.
- Availability states: `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady` (third-party skill docs; confirm in Apple docs).
- Errors: `guardrailViolation`, `exceededContextWindowSize`, rate-limited, unsupported language, concurrent requests.
- Apple's advice for long input: drop used entries, summarize history, split unrelated tasks into separate sessions. Apple open-sourced utilities including a summarize-history modifier.

**Guardrails [medium, from lab Q&A]:** input moderation has a "permissive content transformations" setting. A natural-language refusal is a model response, not a guardrail error. Structured output can throw a separate refusal error. Guardrails reportedly improved in 26.4/27 to cut false positives.

**Rate limits / background [medium]:** on macOS the local model should not be rate-limited while the app is in the foreground. Background use can be rate-limited.

**M1 / 8 GB:** no source found. One third-party Rust crate comment lists M1 as "not eligible"; I think that's wrong but didn't verify. The Setup availability check settles it.

**macOS 27 additions [medium]**
- `fm` CLI preinstalled, Python SDK (`apple_fm_sdk`).
- Private Cloud Compute via `PrivateCloudComputeLanguageModel`: 32K context, no keys or auth, has usage limits.
- Bring-your-own provider via a language-model protocol.
- Apple says apps in the App Store Small Business Program (<2M downloads) get PCC at no API cost. A GitHub-distributed app's status is **unclear**.
- Release/availability status of macOS 27 on your M1 wasn't checked.

**Acceptable use [conflict between copies]:** Apple's current English requirements page bans, among other things, illegal use, privacy/IP infringement, circumventing guardrails, and (in one version) unsupervised high-risk decisions in employment, medical, legal or finance. Older/regional copies also banned "regulated healthcare, legal, financial services" and generating scholarly or academic products. Meeting summarization isn't clearly covered, but **confirm the live page** and mirror the relevant limits in the README.

**PCC offer:** PCC sends transcript text off-device to Apple (private, but not local). If offered, make it opt-in, off by default, and macOS 27+ only. This also raises your minimum OS if it's required.

**Recommendation:** Map-reduce with small chunks and a rolling structured summary, token-counted before each call. Treat PCC as optional v1.1. Include an Apple-Intelligence-off fallback (transcript-only note).

**Sources:** developer.apple.com/documentation/foundationmodels/managing-the-context-window, developer.apple.com/documentation/foundationmodels/systemlanguagemodel, infoq.com/news/2026/03/apple-foundation-models-context, developer-rno.apple.com/cn/videos/play/wwdc2026/241, antongubarenko.substack.com/p/wwdc26-coding-intelligence-machine, developer.apple.com/wwdc26/guides/macos, nonstrict.eu/wwdcindex/wwdc2026/334, developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework

---

## W5. SpeechAnalyzer

**Found [medium]**
- macOS 26+ (Apple silicon for SpeechTranscriber), long-form with no duration cap, on-device only. Models are system assets downloaded per locale via `AssetInventory`, shared across apps, zero bundle size.
- Modules: `SpeechTranscriber`, `DictationTranscriber` (fallback), `SpeechDetector` (VAD). Volatile results give sub-second live partials.
- No diarization.
- Accuracy numbers (all vendor-run or blog-run; none from Apple):
  - get-inscribe (M2 Pro, LibriSpeech): 2.12% WER clean / 4.56% noisy vs Whisper Small 3.74% / 7.95%.
  - IraVoice (M5 Max, 40 speakers): 1.98% vs whisper.cpp small.en 4.28%.
  - Argmax (2025, earnings calls, harder audio): 14.0% WER, between Whisper base (15.2%) and small (12.8%).
- The gap is the dataset: read speech vs real calls. Expect the harder number for Discord audio.
- Custom vocabulary: sources disagree (one says contextual-string biasing exists, one says no, Argmax found it weaker than the old API). Apple's lab had no definitive answer.

**Recommendation:** Cut live preview from v1. If L5 shows it cheap, it fits best as a v1.1 "draft while recording" feature, with Whisper still producing the final transcript.

**Sources:** forasoft.com/blog/article/speech-recognition-with-neural-networks-on-ios-1621, gigazine.net/gsc_news/en/20260714-apple-speech-analyzer-benchmark, dev.to/iravoice/apple-speechanalyzer-vs-whispercpp-a-40-speaker-mac-benchmark-40i4, edenai.co (Yap writeup)

---

## W6. Distribution

**Notarization [solid/medium]**
- Needs the **$99/yr Apple Developer Program**, a Developer ID Application certificate, hardened runtime enabled, and `xcrun notarytool` (`altool` was removed Nov 2023).
- Signed-but-not-notarized builds are blocked the same as unsigned ones.
- Since Sequoia, Control-click → Open no longer bypasses Gatekeeper. Users go to Privacy & Security → "Open Anyway." Locally built apps aren't quarantined, so build-from-source avoids this.
- Free membership for nonprofits and government was claimed in a comment thread **[weak]**.

**Homebrew [medium]:** a developer blog says the main cask repo disables casks that fail Gatekeeper checks as of Sept 1, 2026. Own tap still works. Verify at docs.brew.sh/Deprecating-Disabling-and-Removing.

**How others ship:** Hlopya, signed + notarized release plus build from source. OpenOats: own Homebrew tap, DMG, scripted signing/notarization. Kleoth: self-signed DMG with right-click Open. Recap: build from source only.

**Entitlements / sandbox [medium]**
- Hardened runtime: `com.apple.security.device.audio-input` covers mic and Core Audio input.
- Sandboxed and notarized open examples (Dot, BetterCapture) ship with `app-sandbox`, `device.audio-input`, `network.client`, user-selected file access, and Sparkle.
- Process taps: `NSAudioCaptureUsageDescription`, no extra entitlement.
- Not found: whether a sandboxed app can use ScreenCaptureKit app-audio capture, and which exact entitlements the Obsidian vault write needs beyond user-selected read-write plus a security-scoped bookmark. Left for L7.

**GitHub Actions [solid]**
- `macos-26` (arm64, M1, 3 cores, 7 GB) is GA since Feb 26, 2026. Free and unlimited for public repos. `macos-latest` points to macOS 26.
- Default Xcode on `macos-26` was set to 26.6 in July 2026. An `xcode-27` label exists as public preview.
- `macos-26-xlarge` (M2, 5 cores, 14 GB) is paid, ~$0.102/min per a third-party PR **[weak]**.
- macOS 14 runner images are fully unsupported from Nov 2, 2026.

**Sparkle [medium]:** works with notarized apps, but every nested binary needs the hardened runtime flag. Sandboxed apps use the XPC-service variant. Skip it unless you want in-app updates.

**Recommendation:** Decide on the $99. If yes: notarized DMG built in Actions on `macos-26`, plus your own Homebrew tap. If no: build-from-source README with an Open Anyway section.

**Sources:** flaviocopes.com/apple-developer-free-vs-paid, flaviocopes.com/macos-open-anyway, osnews.com/story/141055, developer.apple.com/forums/thread/768376, developer.apple.com (Configuring the hardened runtime), desktopinsights.com/apps/dot, desktopinsights.com/apps/bettercapture, furbo.org/2019/08/16/catalina-app-notarization-and-sparkle, github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners, docs.github.com (GitHub-hosted runners), github.com/actions/runner-images

---

## W7. Obsidian conventions

**Found [solid, official help]**
- Properties are YAML frontmatter at the top of the file.
- Types: text, list, number, checkbox, date (`2020-08-21`), date & time (`2020-08-21T10:30:00`), tags. A property name has one type vault-wide.
- Internal links inside text or list properties must be quoted.
- Defaults: `tags`, `aliases`, `cssclasses`. Singular forms (`tag`, `alias`, `cssclass`) are deprecated.
- Audio formats: flac, m4a, mp3, ogg, wav, webm, 3gp. Playback depends on device codecs.
- Embed syntax `![[file]]`. Precedent frontmatter from HushScribe: type, created, attendees, tags, source_app.

**Not found:** Obsidian's official rules for embed resolution when names collide, how the attachment-folder setting changes what `![[recording.m4a]]` resolves to, and common meeting-note naming conventions. Left for L6.

**Recommendation:** Use a date & time `created`, list `attendees` and `tags`, and an embed in the body. Keep the m4a name unique (timestamp in filename) so shortest-name resolution can't collide. L6 verifies.

**Sources:** help.obsidian.md/properties, obsidian.md/help/file-formats, gh.hhj520.top/drcursor/HushScribe (mirror)

---

## W8. Licensing and compliance

**Licenses [medium]**
- WhisperKit: MIT (confirm the renamed argmax-oss-swift LICENSE covers SpeakerKit too).
- FluidAudio: Apache-2.0. Parakeet TDT v3 model: CC-BY-4.0. pyannote community-1 models: CC-BY-4.0. These are compatible with an MIT repo, but CC-BY needs attribution. Download models at runtime, don't commit weights.
- Argmax "Pro" SDKs (WhisperKit Pro, SpeakerKit Pro) are commercial. Don't depend on them.
- **Not retrieved:** Whisper weights license and the license tag on the converted Core ML models. Check before writing the README.
- Hlopya is not MIT-compatible to copy from. Anarlog is MIT except `enterprise/`.
- Apple's Foundation Models acceptable-use terms are separate from licensing (see W4).

**Recording consent (not legal advice) [medium]**
- California Penal Code § 632: criminal to intentionally record a **confidential communication** without all parties' consent. § 632.7 covers cellular and cordless calls. Reported penalties: fine up to $2,500 and up to one year (criminal); $5,000 per violation (civil, § 637.2).
- Sources count all-party states differently (11 to 15 depending on how they treat split rules). One list of nine: CA, FL, IL, MD, MA, MT, NH, PA, WA.
- AI notetakers don't change this. The person running the app is the recorder.
- Precedent: OpenOats requires an in-app acknowledgement of obligations before the first recording.
- Not researched: Discord's own terms on recording calls.

**Recommendation:** MIT repo. README warning stating that recording laws vary and all-party consent applies in California and other states. First-run acknowledgement dialog. Visible in-app "recording" indicator.

**Sources:** github.com/yazinsai/OpenOats, docs.fluidinference.com, huggingface.co/1of2/speaker-diarization-coreml, rcfp.org/reporters-recording-guide/california, justia.com/50-state-surveys/recording-phone-calls-and-conversations, jotme.io/blog/two-party-consent-states, scribbl.co/post/do-you-have-to-tell-people-youre-recording

---

## W9. Diarization (v2, low priority)

**Found [medium]**
- **FluidAudio** (Apache-2.0, Swift, Core ML on the Neural Engine): offline pyannote-based pipeline ~15% DER at ~122× real time (M4 Pro, 48 GB). Streaming 26–32% DER. Sortformer single-model option ~32% DER, aimed at 2–4 speakers. Streaming is 10–15% worse than offline per its own docs.
- **SpeakerKit** is in the open-source argmax-oss-swift package (v1.1.0 added speaker centroid embeddings for matching across runs). License and RAM cost not checked. SpeakerKit **Pro** is a separate commercial package; its card reports latency on an M3 8 GB but I wouldn't depend on it.
- pyannote community-1 Core ML port: CC-BY-4.0, ~1% DER from the original, macOS 14+.
- **No 8 GB RAM figures found** for any option.

**Recommendation:** Skip for v1. The two-track recording already labels you vs everyone else. Revisit with FluidAudio's offline pipeline for multi-speaker Discord calls, run after recording, not live.

**Sources:** docs.fluidinference.com/introduction, docs.fluidinference.com/reference/benchmarks, github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0, huggingface.co/1of2/speaker-diarization-coreml, huggingface.co/aoiandroid/speakerkit-pro

---

## Added to the spike list

- L1: add a zero-buffer check, output-device switch mid-call, tap by process family for Discord helpers, and build as `.app` on Tahoe.
- L3: use WhisperKit ≥1.1.0, `.incremental` loading, test `promptTokens`, add Parakeet as an optional row.
- L4: print `contextSize`; design to 4,096 until proven otherwise.
- L6: test embed resolution with colliding names and non-root attachment folders.
- L7: test a sandboxed build with ScreenCaptureKit and process taps separately.
