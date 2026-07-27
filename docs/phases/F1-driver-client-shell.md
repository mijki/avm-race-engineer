# F1: Driver Client Shell

Status: `Host-complete; runtime-pending`

## Goal

Deliver a polished AVM PitWall shell inside the CSP Lua runtime without any
live networking or production calculation ownership.

## Dependencies

F0.1.

## Deliverables

Polished CSP shell; Compact Race Mode, Expanded Race Mode, and
Garage/Diagnostics Mode; deterministic mock telemetry, calculated race state,
forecast, and weather snapshots; sound handling; mock acknowledgement UX;
build-time bundling; render fallback; and real CSP validation evidence.

## Exclusions

Live networking, relay connectivity, real engineer commands, shared-memory
bridge work, and any production forecast engine.

## Implementation Sequence

1. Define the shell UX and the Compact Race, Expanded Race, and
   Garage/Diagnostics mode boundaries.
2. Validate deterministic mock telemetry, calculated-state, forecast,
   weather, alert, sound, and acknowledgement states with bundled assets only.
3. Prove build-time bundling, render fallback, and real CSP runtime behavior
   without networking or live Bridge dependencies.

## Automated Tests

Bundle parser, bundle order, forbidden API scan, local module checks, mock
telemetry fixtures, mock calculated-race-state fixtures, mock current stint
forecast fixtures, mock fuel-delta fixtures, mock predicted-fuel-at-pit-entry
fixtures, mock next-stint-requirement fixtures, mock forecast-confidence
fixtures, mock current-weather fixtures, mock five-minute weather timeline
fixtures, scheduled weather fixtures, estimated weather fixtures, unknown
weather fixtures, stale weather fixtures, weather alert fixtures, tyre
crossover fixtures, mock acknowledgement fixtures, and render fallback host
checks.

### Delivered host evidence

The F1 implementation now provides:

- `apps/driver-lua/src/` source modules with an explicit 21-module dependency
  graph and one generated runtime bundle;
- deterministic contract fixtures under `apps/driver-lua/fixtures/contracts/`
  plus the required 18-scenario catalog;
- code-defined vector-like icons and four generated, bounded WAV tones with an
  asset ownership manifest;
- pure view-model reduction, formatting, bounded alert dedupe/repeat/
  acknowledgement/expiry state, and visible malformed-data fallback;
- Compact Race, Expanded Race, and Garage/Diagnostics compositions, with no
  scrolling child UI in either race mode;
- dependency-free host validation, deterministic byte comparison, forbidden
  loader/network scanning, local-count inspection, and an optional callback
  smoke when Lupa is installed;
- a dry-run-first installer that only targets `apps/lua/AVM_PitWall_F1` and
  preserves the V1 `apps/lua/AVM_PitWall` directory.

The exact scenario IDs are recorded in
`apps/driver-lua/fixtures/f1-scenario-catalog.json`. `MALFORMED_SNAPSHOT` is an
intentional invalid Lua envelope and is not expected to validate against the
foundation schemas; all contract-shaped JSON fixtures are validated by the F1
host suite.

## Manual Tests

Real Assetto Corsa and CSP shell validation covering mode switching, sound,
fallback rendering, weather-alert messaging, and unavailable-state behavior.

## CSP Runtime Requirements

Required; this phase establishes the supported shell assumptions and package
discipline.

Current status: the generated package passes the host-side bundle, contract,
asset, installer, and deterministic-build checks. The local environment does
not provide a Lua parser, Lupa, or an interactive Assetto Corsa/CSP session, so
callback execution, visible in-game render smoke, and mode/audio interaction
remain pending. This is deliberately not counted as CSP validation passed.

The reviewed minimal real-CSP probe proved app discovery, corrected manifest
shape, window creation, `FUNCTION_MAIN = windowMain` resolution, callback
execution, and direct native drawing. It did not prove the full bundle: the
generated bundle's original callback was registered only by the final `app`
module as `script.windowMain(dt)`, while the manifest requested global
`windowMain`, so the full app opened with a blank client region.

The correction registers both callback shapes in `bootstrap.lua`, before any
later module can fail. The shared callback draws `AVM PitWall`, `F1 runtime
active`, and an initialization line with direct `ui.text()` calls before
dispatching to the application entry. Full initialization then runs through
the stable `namespace-ready`, `capabilities`, `storage`, `app-state`,
`default-fixture`, `view-model`, `layout`, `selected-mode`, `alerts`, `footer`,
and `audio` stages. Each stage is bounded; failures retain a direct-native
recovery panel and produce one bounded log entry. Missing storage, assets, and
audio remain degraded inputs rather than callback blockers.

The real-CSP full-bundle retest remains required. This phase is not marked
runtime-validated until the corrected package renders all three modes in CSP.

### Follow-up capability correction

The next real-CSP retest proved app discovery, callback ownership, generated
bundle execution, the direct native shell, and staged recovery. It then
rejected the old capability superset with `required CSP drawing API
unavailable`. That gate had classified `ui.windowSize`, `ui.drawRectFilled`,
and `ui.drawText` as mandatory even though the successful native probe only
proved `ui.text` and `ui.separator`. Because the old code exposed one boolean,
it could not identify the exact unavailable member. The corrected adapter now
reports exact `ui.<name>` entries from the live namespace and treats only
`ui.text` as mandatory for the emergency and text-first paths.

The capability levels are Level 0 mandatory text/recovery, Level 1 readable
text-first Compact Mode, Level 2 optional enhanced cards/positioned text/lines/
shapes/clipping/input, and Level 3 optional audio/storage/host features.
Missing visual members degrade independently: cards lose backgrounds,
clipping falls back to ordinary text, icons fall back to labels, sparklines
are omitted when line drawing is missing, and unavailable buttons remain
non-interactive without blocking rendering. A Level-1 runtime displays
`Simplified rendering mode` plus stint/lap/timing, fuel/range/pit distance,
weather/next change, engineer instruction, and Bridge/Engineer state.

The duplicate initialization shell was traced to bootstrap drawing the direct
shell and `app.windowMain()` drawing `native.draw_canary()` again in the same
callback. Bootstrap now owns the shell, both callback aliases share one
guarded entrypoint, and one per-frame guard prevents a recovery path from
re-emitting it.

### Renderer visibility correction

The pre-correction follow-up real-CSP retest reached namespace, capability, state, fixture,
view-model, layout, selected-mode, alert, footer, and audio stages. The
visible result was still only the direct native shell, despite a
`full mode rendered` log. The exact defect was silent success in the enhanced
path: a protected call returning without a Lua exception was treated as
visible output, while positioned drawing depended on CSP callable members and
constructed `vec2`/`rgbm` values that had not been validated. Absolute layout
draws could therefore return successfully without proving an on-window draw.

The adapter correction uses callable-member detection for functions,
userdata, and callable tables; validates vectors, positive bounds, finite
coordinates, colors, and alpha; and returns explicit `drawn`, `degraded`,
`unavailable`, or `failed` statuses. It records skipped operations and the
first reason rather than silently claiming success. The real SDK's
`ui.availableSpace()` is now the preferred content-size source, with axis,
window-size, and conservative fallback paths. Invalid or off-screen layout
selects flow rendering.

The guaranteed base renderer is direct `ui.text()` flow output. Compact shows
mode, stint/lap, time, fuel, pace, tyres, weather, engineer, and connection
fixture values; Expanded and Garage/Diagnostics emit mode-specific text before
any optional decoration. Frame-local evidence tracks native, mode-text,
enhanced, degraded, skipped, and first-skip counts. `full mode rendered` now
requires non-zero mode evidence, and enhanced zero-operation attempts retain
the visible text-first body. The initialization line is suppressed after a
successful mode body, so it cannot remain as a stale final state.

Host tests cover the accounting contract, no-op adapter behavior, callable
member handling, text-only values, size/layout fallback, zero-operation
enhanced fallback, initialization lifecycle, all three mode renderers,
deterministic bundling, and F1 scope scans. The supplied real-CSP result is
recorded as the pre-correction baseline; post-correction Compact, Expanded,
and Garage screenshot validation remains pending and is required before this
phase can be marked CSP-validated.

This follow-up has host-side static and deterministic coverage for capability
levels, exact diagnostics, text-only rendering labels, independent optional
degradation, callback alias delegation, and single-shell ownership. The real
CSP status remains runtime-pending until the corrected package is manually
verified in the installed simulator; host tests are not treated as CSP proof.

## Security

Keep the shell non-privileged and avoid implicit control capabilities.

## Exit Criteria

The host portion of the shell is polished, networking-free, deterministic, and
ready to accept later relay-backed calculated and weather payloads without
redesign. The phase cannot be promoted to fully CSP-valid until the manual gate
in [CSP Runtime Gate](../testing/csp-runtime-gate.md) is completed.

## Rollback

Reduce to Compact mode plus fallback rendering if the full three-mode shell
threatens runtime safety.

## Risks

CSP incompatibility, package sprawl, and over-designing weather or
acknowledgement UX before real transport exists.

## Complexity

medium

## Clean-Thread Recommendation

Yes - move bridge work into a new thread once the client shell constraints are
fixed.
