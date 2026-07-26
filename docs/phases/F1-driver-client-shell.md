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

- `apps/driver-lua/src/` source modules with an explicit 20-module dependency
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
