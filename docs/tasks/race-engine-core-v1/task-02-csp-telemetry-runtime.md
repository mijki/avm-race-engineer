# Task 2 — Harden Live CSP Telemetry Runtime

Required commit: `Harden live CSP telemetry runtime`

Dependency: Task 1 committed, validated, clean worktree.

## Purpose

Implement Task 1 snapshot, source-health, identity, and discontinuity contracts against live CSP.

Do not implement automatic marker learning, complete eligibility, complete calculations, complete forecasts, or major UI changes.

## CSP mapping

Inspect the installed SDK and verify fields before use.

Normalize:

- `ac.getCar(0)`;
- `car.isInPitlane`;
- `car.isInPit`;
- `car.splinePosition`;
- `car.position`;
- `car.resetCounter`;
- speed, fuel, lap counters/times, validity, tyres;
- `ac.getSim()` session values, track length, track/layout identity, replay, position where reliable;
- measured weather, air/road temperatures, wind, wetness, grip where verified.

Document source, normalized name, type, unit, optionality, and fallback for every field.

## Safe readers

Handle primitives, callable cdata/userdata, vectors, missing fields, and CSP-version differences.

Do not invoke unknown userdata blindly. Read failures must become explicit unavailable values with reason codes, never zero.

## Source health

Implement:

- `LIVE`: core fields available and fresh;
- `PARTIAL`: core works, optional fields degraded;
- `STALE`: last usable snapshot exceeded freshness threshold;
- `OFFLINE`: no usable current core snapshot.

Centralize core/optional fields, thresholds, transition reasons, recovery, and anti-flapping.

## Snapshot history

Implement monotonic sequence numbers, IDs, timestamps, age, and a bounded recent-snapshot ring buffer.

The buffer must preserve original pit-boundary evidence long enough for Task 3 candidate confirmation.

## Identity and discontinuity

Detect and classify initialization, car/track/layout/session changes, restart, replay, lap decrease, resetCounter change, teleport, spline/world jumps, and material refuel.

Produce stable immutable evidence for later consumers. Do not reset every subsystem indiscriminately.

## Pit source telemetry

Expose independently:

- `isInPitlane`;
- `isInPit`;
- spline/world positions;
- reset counter;
- speed;
- identity;
- timestamps.

These are source facts. Do not learn markers yet.

Current pit state must follow CSP immediately without a long artificial delay.

## Reset/teleport evidence

Expose enough evidence to reject false future calibration after reset-to-pits, teleport, app start in pits, session/car/track reload, or replay jump.

Current live state may be `IN PIT LANE` while marker learning is suppressed.

## Diagnostics

Provide bounded diagnostics for source health, freshness, missing optional fields, failures, identity, reset counter, latest discontinuity, pit states, recent snapshot count, and adapter failure reason.

Do not expose raw CSP objects to Compact UI.

## Tests and gate

Cover optional/core failure, partial/stale/offline/recovery, anti-flapping, sequencing, units, unavailable values, callable values, vectors, deterministic identity, resets, teleports, refuel, start-in-pit, independent pit states, bounded history, architecture boundaries, deterministic bundle, and V1 protection.

Before commit:

1. confirm Task 1 is previous;
2. run shared validation;
3. run telemetry/source-health/identity/reset tests;
4. replay deterministically;
5. run deterministic build twice;
6. confirm no marker learning or UI redesign;
7. confirm only Task 2 changes.

Create exactly one commit and continue only when clean and fully passing.
