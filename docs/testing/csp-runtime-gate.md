# CSP Runtime Gate

## Purpose

This gate protects the AVM PitWall runtime from design drift. Any phase that changes PitWall behavior, PitWall contracts, or PitWall-facing assumptions must satisfy this gate before the phase can exit.

## F1 evidence status

F1 is currently `host-complete; runtime-pending`.

The reviewed minimal real-CSP probe conclusively proved that the corrected F1
manifest, `[WINDOW_...]` section, folder-matching entry file,
`FUNCTION_MAIN = windowMain`, app discovery, window creation, callback
execution, and direct native `ui.text()` drawing all work. Those are no longer
suspected causes of the full-bundle blank window.

The full-bundle root cause was callback ownership and timing: the generated
bundle registered only `script.windowMain(dt)` at the end of the final `app`
module, while the manifest asks CSP to resolve global `windowMain`. Any later
top-level failure also occurred before callback registration. The corrected
bootstrap registers both names before risky module initialization, draws a
direct native shell first, and dispatches to the complete app only after the
bundle is loaded.

Completed host evidence:

- foundation contract fixtures validate with the repository schemas;
- the 21-module bundle graph is explicit, deterministic, and cycle-checked;
- the unique `AVM PitWall F1 Dev` registration uses `[WINDOW_...]`, global
  `windowMain(dt)`, and a compatibility `script.windowMain(dt)` wrapper;
- callback registration occurs in the first module, before later module
  initialization, and the callback's first draw uses direct native CSP calls;
- staged `namespace-ready` through `audio` execution uses bounded recovery,
  once-only logs, and preserves visible output when state, fixtures, renderers,
  storage, or audio fail;
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

### F1 capability correction

The subsequent real-CSP bundle retest reached the callback and rendered the
native shell, then stopped at the old capability gate with only `required CSP
drawing API unavailable`. The old gate incorrectly required all of these
members before any renderer could run: `ui.windowSize`, `ui.drawRectFilled`,
and `ui.drawText`.

The installed `ac_apps` SDK documents those names, but the successful real
probe only established `ui.text()` and `ui.separator()`. The old aggregate
boolean therefore hid which member was absent or unusable in the running CSP
namespace. The adapter now inspects the real namespace defensively, reports
each exact missing name, and separates capabilities into these levels:

- Level 0: mandatory `ui.text`; direct shell, recovery, and bounded diagnostics;
- Level 1: text-first readable Compact Mode, with deterministic size fallbacks;
- Level 2: optional positioned text, cards, lines, shapes, clipping, and input;
- Level 3: audio, storage, and other host enhancements, outside the drawing gate.

Missing Level-2 members now disable only their dependent visual behavior. Card
backgrounds, custom icons, clipping, sparklines, and buttons each have a text
or omission fallback. If `ui.text` is genuinely absent, recovery reports
`Missing mandatory API: ui.text`; it no longer reports only an aggregate
failure. First-entry diagnostics are bounded and once-only, for example:
`AVM F1 capabilities: level=1 enhanced=false simplified=true ...`.

When Level 2 is unavailable, the application renders a usable text-first
Compact Mode labelled `Simplified rendering mode`, including stint/lap/timing,
fuel/range/pit distance, weather/next change, engineer instruction, and Bridge
/ Engineer state. Expanded and Garage remain reachable when their enhanced
capabilities are available.

The duplicate native shell was caused by both the bootstrap callback wrapper
and `app.windowMain()` drawing an initialization canary. Bootstrap is now the
single shell owner; both callback aliases delegate to that shared entrypoint,
which resets a per-frame guard and emits the shell once.

### F1 renderer visibility correction

The latest pre-correction deterministic bundle was deployed to the separate F1 development
target and reached every application stage in real CSP. The window still
showed only the direct native shell (`AVM PitWall`, `F1 runtime active`, and
the initialization line), even though the enhanced renderer logged
`full mode rendered`. That log was only proof that the renderer returned from
Lua without an exception; it was not proof of a visible draw operation.

The corrected adapter now returns `drawn`, `degraded`, `unavailable`, or
`failed` based on the protected underlying CSP call. It validates bounds,
alpha, vectors, colors, and callable members, records skipped-operation
reasons, and never reports a draw when no CSP member was invoked. Callable
userdata and callable tables are accepted in addition to Lua functions. The
installed SDK confirms that `ui.text()` is the safest generic-app baseline,
while `ui.availableSpace()` is preferred for content sizing, followed by
available-space axis methods, `ui.windowSize()`, and finally a conservative
780x380 flow fallback.

Every callback now resets bounded frame-local evidence for native shell draws,
mode text, enhanced primitives, degraded fallback, skipped operations, and
the first skip reason. The first attempt logs one `AVM F1 render evidence:`
record. `full mode rendered` is emitted only when mode text, enhanced output,
or a visible degraded fallback was recorded.

Compact Mode always emits a direct `ui.text()` flow renderer containing the
fixture's stint, lap, timing, fuel, pace, tyres, weather, engineer, and
connection values. Expanded and Garage/Diagnostics have the same text-first
guarantee. Enhanced cards are attempted only after valid size/layout checks;
zero-operation or invalid enhanced rendering immediately leaves the text-first
body visible. The initialization line is emitted only before a mode-specific
body has succeeded and is not repeated after successful mode rendering.

Current correction status remains `host-complete; runtime-pending`: the
original real-CSP result established the invisible-body defect, but this
environment cannot perform the required post-correction CSP screenshot for
Compact, Expanded, and Garage. The package must not be promoted to
runtime-validated until those three mode bodies are visibly confirmed.

Host-side green status must not be interpreted as satisfying those pending
items.

The host gate now covers manifest/entry shape, callback registration timing,
direct-shell ordering, capability-level source contracts, simplified-renderer
labels, independent visual degradation guards, four target-size visibility
matrices, deterministic output, and forced-stage contract hooks. Dynamic
callback, capability-matrix, and forced-failure execution remain pending when
no Lua runtime is installed; the current environment has neither Lupa nor
`lua`/`luac`.

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
