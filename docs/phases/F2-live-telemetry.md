# F2: Live Telemetry Driver Experience

Status: Host-implemented; real CSP validation pending

## Goal

Replace the F1 concept-only race display with a live Assetto Corsa/CSP own-car
and session slice, bounded local driver calculations, and an original,
glanceable AVM PitWall interface.

## Included

- CSP-native normalization for session, identity, car, tyre, and current weather
  state.
- Deterministic session/identity, lap, stint, sample, weather, and pit-entry
  calibration modules.
- Fuel, pace, stint, tyre, current-weather, confidence, and unavailable-state
  calculations.
- Explicit LIVE and Garage-only MOCK source modes, with LIVE/PARTIAL/STALE/
  UNAVAILABLE availability states and no mock substitution during read
  failure.
- Compact, Expanded, and Garage/Diagnostics renderers with no race-mode scroll.
- Deterministic bundle and installer guards, static scans, and host regression
  coverage.

## Explicit exclusions

No Driver Bridge, Relay Server, Engineer Console, database, remote networking,
authoritative forecast engine, or V1 application changes are included.

## Exit evidence

Automated validation covers normalization, identity resets, lap/stint/sample
rules, fuel and pit equations, weather honesty, renderer ownership, no-loader
and no-hardcoded-value scans, deterministic packaging, and installer targeting.
Lua/Lupa is not installed on the validation host, so Lua execution and
interactive CSP rendering remain pending manual gates.

## Real CSP gate

Deploy only to `apps/lua/AVM_PitWall_F1`. Verify the source probe and API
diagnostics, LIVE/PARTIAL source state, dynamic fuel/speed/lap/stint values,
completed-lap sample growth, pit calibration, current weather, tyres, three
modes, the bounded 3+2 Compact card layout, no overlap or clipping, no stale
initialization shell, and no mock substitution. Do not report this gate as
passed without interactive evidence.
