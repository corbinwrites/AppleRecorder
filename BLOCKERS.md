# Blockers

- P4 HostClock: `scripts/apple-api.sh mach_timebase_info` returned no matching API, and `docs/reference/sdk/`, `docs/API-NOTES.md`, and `.build/checkouts/` contain no declaration. `HostClock.nanos(hostTime:)` needs the host-time conversion factor. Do not guess the Apple API; confirm its exact SDK signature and record it in `docs/API-NOTES.md` before implementing this method.
