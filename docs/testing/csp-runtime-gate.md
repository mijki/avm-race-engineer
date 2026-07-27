# CSP Runtime Gate

## Purpose

This gate protects the AVM PitWall runtime from design drift. Any phase that changes PitWall behavior, PitWall contracts, or PitWall-facing assumptions must satisfy this gate before the phase can exit.

## F1 evidence status

F1 is currently `host-complete; runtime-pending`.

The corrective pass confirmed two source-level causes of the original blank
window: the F1 manifest reused the V1 registration name and used
`[WINDOW_MAIN]`, and the bundle exported `_G.windowMain` instead of the CSP app
callback table. Installed CSP app examples and the SDK define the canonical
shape as `script.windowMain(dt)` and use the folder-matching entry file
`AVM_PitWall_F1.lua`. A manual manifest correction made discovery and window
creation work, but the client remained blank, so callback execution is still
not inferred from log absence.

Completed host evidence:

- foundation contract fixtures validate with the repository schemas;
- the 21-module bundle graph is explicit, deterministic, and cycle-checked;
- the unique `AVM PitWall F1 Dev` registration uses `[WINDOW_...]` and the
  canonical `script.windowMain(dt)` callback;
- the first callback operation is a direct native CSP canary, followed by
  narrow staged initialization and a direct native bounded recovery panel;
- generated bundle parsing/inspection, forbidden loader/network scan, and
  local-symbol pressure checks pass;
- deterministic package bytes and the release allowlist pass;
- temporary installer apply/rollback behavior preserves unrelated files and
  the V1 target;
- malformed, unavailable, stale, unknown-weather, alert, acknowledgement, and
  all required mock scenario IDs are represented by the F1 fixture/catalog
  checks.

Pending runtime evidence:

- actual callback execution in the installed CSP Lua runtime;
- visible render smoke at compact, expanded, garage, and fallback states;
- real mode interaction, ACK/repeat behavior, sound playback, stale/offline
  messaging, and resize checks.

Host-side green status must not be interpreted as satisfying those pending
items.

The host gate now covers manifest/entry shape, four target-size visibility
matrices, deterministic output, and forced-stage contract hooks. Dynamic
callback and forced-failure execution remain pending when no Lua runtime is
installed; the current environment has neither Lupa nor `lua`/`luac`.

## Gate Criteria

- Supported CSP baseline version is documented for the phase.
- Module-level unit checks cover client logic touched by the phase.
- The generated bundle passes a parser check.
- The generated bundle passes a local symbol-count or size-budget check.
- The generated bundle passes a forbidden-pattern scan, including no runtime `require` or `dofile`.
- Actual callback smoke runs against the bundled client.
- Actual render smoke validates real visible output.
- Unavailable-data handling is validated.
- Malformed-data handling is validated.
- Command handling is validated for client phases that surface commands.
- Acknowledgement handling is validated for client phases that surface acknowledgements.
- Host-side tests are recorded, but they are never accepted as equivalent to real AC/CSP validation.

## Failure Conditions

- A planned feature depends on browser-only, server-only, or unrestricted OS capabilities inside PitWall.
- A command or telemetry change reaches PitWall without explicit compatibility handling.
- Manual validation requires undocumented simulator setup or one-off operator knowledge.
- A client phase ships with host-side green tests but no real Assetto Corsa and CSP validation.

## Required Evidence

- Updated phase document referencing the PitWall impact.
- Matching host-tested, contract, and integration additions where applicable.
- Real Assetto Corsa and CSP validation notes for every client phase.
- Manual validation checklist for CSP-specific behavior.

## F1 manual checklist

After reviewing the default dry-run output, build the package and deploy only
to the separate development target `apps/lua/AVM_PitWall_F1`. Record the
package `bundle_sha256` from `build-manifest.json` and the CSP version in the
phase note. In an actual session, verify:

1. the app opens with `AVM PitWall` visible and never presents a blank window;
2. Compact Race renders the fixed fuel/pace/tyres/pit/weather hierarchy at the
   narrow target size and keeps the critical message plus `ACK` visible;
3. Expanded Race renders timing, message, fuel, pace, tyres, pit, weather, and
   health cards without scrolling or clipped critical copy;
4. Garage/Diagnostics can select each catalog scenario, test critical and ACK
   tones, and show source/contract/audio status without changing live state;
5. `MALFORMED_SNAPSHOT`, `WAITING_FOR_VALID_DATA`, `UNKNOWN_FUTURE_WEATHER`,
   `STALE_WEATHER`, `BRIDGE_OFFLINE`, and `ENGINEER_OFFLINE` remain visibly
   labeled and never become false zeroes;
6. `BOX_THIS_LAP` displays the critical icon/copy and acknowledgement control;
   ACK is idempotent, and repeat behavior is bounded;
7. window resize across the documented compact and expanded targets preserves
   the message and weather warning; and
8. the installed V1 `apps/lua/AVM_PitWall` remains unchanged.

The checklist is not complete until an operator records the actual simulator
and CSP result. A host-only run must leave the F1 status runtime-pending.

## Phase Applicability

| Phase | Applies | Notes |
| --- | --- | --- |
| F0 | advisory | defines the gate |
| F1 | required | client shell phase requires real CSP proof |
| F2-F4 | advisory unless PitWall-facing contracts change | bridge, relay, and console phases still record compatibility impact |
| F5-F12 | required | client-participating phases need real AC/CSP validation |

## Related Documents

- [Testing Strategy](./testing-strategy.md)
- [End-to-End Test Matrix](./end-to-end-test-matrix.md)
- [ADR-002: Small Driver Client](../decisions/ADR-002-small-driver-client.md)
