# Agent kit: install and change log

Drop-in files that make the guide usable by weak local agents. Built against the Rev 4 guide, now Rev 5.

## Install (from the repo root)

```bash
git pull --rebase origin main
unzip -o ~/Downloads/AppleRecorder-agent-kit.zip      # overwrites AGENTS.md and docs/BUILD-GUIDE.md on purpose
git diff --stat                                        # check what changed
make tasks 2>/dev/null || python3 scripts/split-guide.py   # regenerate docs/tasks/ (already included)
git add -A && git commit -m "docs: agent kit (Rev 5 guide, task files, spec tests, scripts)"
git push origin main
```

The `Makefile` does not exist yet (P0.1 creates it). The Rev 5 guide's Makefile template already has `-include mk/agent.mk`, so `make hooks`, `make tasks`, `make step`, `make protect`, `make sdk-dump` work after P0.1.

## What's in the kit

| Path | Purpose |
|---|---|
| `AGENTS.md`, `CLAUDE.md` | 34-line rule sheet the agents read first. `CLAUDE.md` just points at it. Copy to `.cursorrules` or `GEMINI.md` if your agent wants those names |
| `docs/BUILD-GUIDE.md` | Rev 5 (changes below) |
| `docs/tasks/*.md` | One self-contained file per step, generated from the guide, with `VERIFY:` line |
| `docs/tasks/src/P0.3.body.md` | Hand-written body for the stubs + spec-tests step |
| `Packages/*/Tests/...` | 5 complete spec test files extracted from the guide (uncompiled) |
| `scripts/protect-tests.sh` | Fails if a spec test changed since tag `spec-v1` |
| `scripts/run-step.sh` | One fresh agent session per step, verify, retry with the failure log, stop on red |
| `scripts/hooks/pre-commit` | Secrets, protect-tests, realtime check, `swift test` for staged packages |
| `scripts/apple-api.sh`, `scripts/dump-sdk-interfaces.sh` | Look APIs up in the SDK instead of guessing |
| `scripts/split-guide.py`, `mk/agent.mk` | Regenerate tasks, make targets |
| `scripts/verify.sh` | The guide's script plus the protect-tests row |
| `HUMAN-TODO.md` | Everything agents cannot do |

## Order of operations

1. Install the kit (above). `make hooks` after P0.1.
2. P0.0, P0.1, P0.2 (agent is fine).
3. `make sdk-dump` on the M1, commit `docs/reference/sdk/`.
4. **P0.3 by a strong model or you.** Stubs, all remaining spec tests, compile everything. Then `git tag spec-v1 && git push origin main spec-v1`.
5. Agents: `AGENT_CMD='<your agent>' make step STEP=P1`, then P2 … P6, then P8. P7, P9 and P10 stop at `NEEDS HUMAN` points.
6. After editing the guide: `make tasks`, commit the regenerated files.

## Changes to the guide (Rev 5)

1. Revision 5 note at the top.
2. Rules 17-19 in section 21: frozen spec tests, never guess an Apple API, one step per session.
3. Section 22.1 tree lists the new files. Section 22.4 Makefile includes `mk/agent.mk`.
4. Section 31.2 `verify.sh` has a "spec tests untouched" row. Section 31.3 `ci.yml` fetches full history and tags, and runs `protect-tests.sh` first.
5. Section 24.7: added the missing `ProcessingStage` enum. It was referenced everywhere and defined nowhere.
6. Section 25.8: `writeSilence` was a `/* same as above */` comment. Now real code.
7. Section 32: P0.1 exit check no longer says `make test` green, because spec tests exist before the code. Placeholders only for packages with no seeded tests.
8. Section 32: new step P0.3.

## Gaps found but not fixed in the guide (P0.3 resolves them)

- `TranscribeOrchestrator` and `TranscribeError.engineFailed(stage:)` appear only in test prose (26.3).
- `AppModel` members used by views but never declared: `player`, `reveal(_:)`, `retranscribe(_:)`, `requestDelete(_:)`, `acknowledgeConsent()`, `chooseNotesFolder()`, `chooseAudioFolder()`, `confirmDiscard()`, `cancelProcessing()`, `importAudioPanel()`.
- Section 24.1 says every public struct needs an explicit `public init`, but none of the code has them. `Session.init(title:mode:)` is only a comment.
- `.init(url:startNanos:)` passed to an `Optional<TrackInput>` parameter in the Finalizer test may not infer. Use `TrackInput(...)` if the compiler objects.
- Pure-logic tests were checked against the Python reference only. No Swift has been compiled anywhere in this chain.

## Known limits

- CI is red from P0.3 until the implementations land. That is the point.
- `protect-tests.sh` protects files only after the tag exists. Before that it prints SKIP.
- The pre-commit hook runs `swift test` for staged packages. During P0.3 use `SKIP_HOOK_TESTS=1`.
- Task files duplicate section 21 (about 3 KB each). That is intentional.
