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
  ac.getSim(), ac.getCar(0), ac.getSession(), and track identity APIs, then
  normalizes canonical field names. It never draws.
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
clearly labelled. RECOVERY represents malformed or unavailable live source
data and never substitutes mock values.

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
