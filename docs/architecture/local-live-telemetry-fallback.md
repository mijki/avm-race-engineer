# Local Live Telemetry Fallback

Status: Proposed F2 implementation boundary

This document describes the temporary local path used by the live-driver
vertical slice. It does not replace the accepted Driver Bridge ownership model.

Flow: CSP native state -> CSP telemetry adapter -> normalized live snapshot ->
identity/lap/stint trackers -> bounded representative samples -> local
non-authoritative calculations -> driver status view model -> Compact,
Expanded, or Garage.

## Ownership

- adapters/csp.lua is the only live-source adapter. It reads documented
  `ac.getSim()`, `ac.getCar(0)`, `ac.getSession(sim.currentSessionIndex)`, and track identity APIs,
  then normalizes canonical field names. It accepts the installed CSP's
  LuaJIT `cdata` callable members, protects every live invocation, and never
  draws.
- session_identity.lua, lap_tracker.lua, stint_tracker.lua, and sample_store.lua
  own deterministic local state transitions and bounded history. They reset on
  identity, replay, session, lap-counter, or refuel discontinuities.
- calculations.lua is pure with respect to CSP and UI. It returns
  value/unit/sample/freshness/confidence/reason objects and uses no storage,
  audio, file, or network calls.
- status_builder.lua is the traceable contract reduction consumed by
  view_model.lua. Renderers do not read raw telemetry or calculate values.

## Source modes

LIVE is the default. MOCK is available only after entering Garage and is
clearly labelled. The live availability states are LIVE (complete core),
PARTIAL (core present with optional gaps), STALE (last valid snapshot retained
after a read failure), and UNAVAILABLE (no usable core snapshot). Recovery
represents malformed or unavailable live source data and never substitutes
mock values.

The adapter keeps a concise, once-only startup probe for `ac`, `getSim`,
`getCar`, `getSession`, the returned `car0`/`sim`/`session` objects, and the
first failure. The first rejected normalized field is also retained once.
These raw diagnostics are exposed only by Garage; race mode receives readable
source labels and safe unavailable values.

## Sample policy

The first slice accepts only complete valid laps with positive fuel burn and no
pit-lane, in-lap, out-lap, identity mismatch, or refuel transition evidence.
The bounded store keeps the latest configured lap, fuel, pace, and weather
samples. Uncertain samples remain excluded instead of being silently promoted
to green running.

## Pit-entry calibration

Calibration is keyed by track and layout and contains track length, normalized
pit-entry spline, optional pit-route distance, source, timestamp, and validity.
The forward-distance calculation wraps across spline 1.0. Garage capture is
stationary-only under the conservative speed threshold. Missing or mismatched
calibration yields Pit entry not calibrated.

## Replacement path

When Driver Bridge and shared race-model packages are available, replace the
input adapter with a versioned Driver Bridge snapshot adapter and keep the
status/view-model and renderer contracts stable. The Lua fallback is not the
authoritative production calculation architecture.
