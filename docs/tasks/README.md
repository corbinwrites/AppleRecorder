# Task files

Generated from `docs/BUILD-GUIDE.md` by `scripts/split-guide.py` (`make tasks`). Do not edit. One session = one file.

| Step | Verify | Notes |
|---|---|---|
| P0.0 | `git status --short && git log --oneline -3` |  |
| P0.1 | `make gen && for p in Core Capture Transcribe Enhance Output Theme EditorKit Pipeline; do (cd Packages/$p && swift build) || exit 1; done && make build` |  |
| P0.2 | `(cd Spikes/ApiCheck && swift build)` | Hardware calls need not run; they must compile. |
| P0.3 | `for p in Core Capture Transcribe Enhance Output Theme EditorKit Pipeline; do (cd Packages/$p && swift build --build-tests) || exit 1; done && ./scripts/protect-tests.sh` | Strong model or human with Xcode. Do not give this step to a weak local agent. |
| P1 | `(cd Packages/Core && swift test)` |  |
| P2 | `(cd Packages/Output && swift test)` |  |
| P3 | `(cd Packages/Theme && swift test) && (cd Packages/EditorKit && swift test)` | Do 29.1-29.3 only. 29.4 (the AppKit view) is P8. |
| P4 | `(cd Packages/Capture && swift test) && (cd Packages/Capture && swift test --sanitize=thread) && ./scripts/check-realtime.sh` | Software parts only. TapSession and MicSession are P7. |
| P5 | `(cd Packages/Transcribe && swift test)` | Integration test needs AR_INTEGRATION=1 and the network; mark NEEDS HUMAN if you cannot run it. |
| P6 | `(cd Packages/Enhance && swift test) && (cd Packages/Pipeline && swift test)` | Real Foundation Models tests need Apple Intelligence; mark NEEDS HUMAN. |
| P7 | `make build` | NEEDS HUMAN: capture-tone must be run on the M1 via `make selftest`. Never fake it. |
| P8 | `make build` | UI tests need a GUI session. |
| P9 | `./scripts/verify.sh` | Hardware self-tests are NEEDS HUMAN. |
| P10 | `./scripts/verify-signing.sh build/Build/Products/Release/AppleRecorder.app` | NEEDS HUMAN: GitHub environment and secrets, tap repo, v0.0.1 / v0.0.2 tags, second-Mac test. |
