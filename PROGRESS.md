# Progress

Statuses: pending / done / blocked / NEEDS HUMAN.

| Step | What | Status | Evidence |
|---|---|---|---|
| P0.0 | Get the repo, first push | done | f85ba20 (legacy spike scripts, SDK API dumps) |
| P0.1 | Scaffold: tree, packages, project.yml, Makefile, scripts, CI | done | make gen && swift build (8 pkgs) && make build PASS |
| P0.2 | API verification spike | done | swift build in Spikes/ApiCheck PASS |
| P1 | Core package | done | `Packages/Core: 31 tests passed`; `swift build -Xswiftc -warnings-as-errors` PASS |
| P2 | Output package | done | `Packages/Output: 10 tests passed` (golden Markdown, export links, atomic writes, folder checks) |
| P3 | Theme + EditorKit logic | done | `Theme: 3 tests passed`; `EditorKit: 4 tests passed` (34 tokenizer examples and 1,000 seeded range checks) |
| P4 | Capture software parts | blocked | `swift test` currently stops at an unverified HostClock Apple API; see `BLOCKERS.md` |
| P5 | Transcribe package | pending | |
| P6 | Enhance + Pipeline packages | pending | |
| P7 | Hardware capture + selftests | pending | |
| P8 | App shell | pending | |
| P9 | Integration | pending | |
| P10 | Release | pending | |
