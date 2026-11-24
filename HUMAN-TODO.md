# HUMAN-TODO

Work agents cannot do. Tick as you go; record macOS version and date for hardware items in `PROGRESS.md`.

## One-time GitHub setup
- [ ] Actions enabled; default branch `main`.
- [ ] Settings → Environments → `release`: required reviewer = you; deployment tags `v*` only.
- [ ] Environment secrets: `MAC_SIGN_P12` (base64 of the .p12), `MAC_SIGN_PASSWORD`, `KC_PASS` (random string). Create them with `scripts/make-release-cert.sh` (guide 20.1). **Back up `release-key.pem` offline.** Losing it forces a new identity and every user re-grants permissions.
- [ ] Commit `release-cert.pem` and `release-cert.sha1` (public). Never the key or `.p12`.
- [ ] Create empty public repo `corbinwrites/homebrew-tap`. Cask goes in `Casks/apple-recorder.rb` (guide 20.3, 20.8).
- [ ] After the first green CI run: branch protection on `main` requiring `ci` (optional, solo repo).

## Before agents start (once)
- [ ] Copy the agent kit into the repo (see `INSTALL.md`), commit, push.
- [ ] `make hooks`
- [ ] Copy legacy spike scripts from `~/Hal9000/projects/local-spikes/Scripts/` into `Spikes/legacy-scripts/` (P0.0).
- [ ] Run `make sdk-dump` on the M1 and commit `docs/reference/sdk/`.
- [ ] P0.1 and P0.2 done (agent or you). **P0.3 by a strong model or you** (needs Xcode, must compile).
- [ ] `git tag spec-v1 && git push origin main spec-v1`. Only you move this tag.

## Hardware steps (M1)
- [ ] P7: `make selftest`. Expect `finalize-synthetic`, `mic-probe` (after you grant Microphone), `capture-tone` all PASS. `capture-tone` with zero buffers: System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only → enable Apple Recorder, relaunch via `open`, rerun.
- [ ] `cpu-60s` < 10% of one core.
- [ ] Discord call, App + Mic, headphones on, 5 min. Both channels mean > -50 dB (guide 33.3 step 3).
- [ ] 60-minute run: no dropped samples, drift ≤ 200 ms (clap at start and end), then transcribe + enhance. Record wall times and peak RAM (Instruments).
- [ ] Room test (Fixture D): Mic only, 3+ speakers, 1-2 m. WER with `small` vs `large-v3-v20240930_626MB`.
- [ ] Acceptance items marked *human* in guide 33.2 (1, 3, 6, 7, 10, 11, 12, 13, 15).

## Release (P10)
- [ ] Push tag `v0.0.1`, then `v0.0.2`. Approve each release in the `release` environment.
- [ ] Second-Mac update test (guide 20.4): grants survive v0.0.1 → v0.0.2 via `brew upgrade` and via manual copy. `codesign -d -r-` shows identifier + certificate hash, never `cdhash`. Ad-hoc negative test is detected and explained.
- [ ] Paste `scripts/print-cask.sh` output into the tap repo.
- [ ] Push `v1.0.0`. Fresh-account install via each path (tap, DMG + Open Anyway, build from source).
