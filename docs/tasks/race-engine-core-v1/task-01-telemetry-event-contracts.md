# Task 1 — Stabilize Telemetry and Race Event Contracts

Required commit: `Stabilize telemetry and race event contracts`

## Purpose

Define stable, versioned, deterministic contracts for telemetry, immutable events, completed laps, pit observations, calculated values, forecasts, and replay.

Do not implement the full live CSP runtime, pit-learning engine, eligibility engine, stint engine, forecast engine, or new UI.

## Read first

Inspect `AGENTS.md`, repository README files, `apps/driver-lua/src/contracts.lua`, the CSP adapter, `apps/driver-lua/src/live/`, `apps/driver-lua/src/view_model.lua`, host tools, tests, and relevant architecture/contracts/testing documentation.

## Normalized telemetry snapshot V1

Define:

- schema version, snapshot ID, source mode, source and monotonic timestamps, sequence;
- source health: `LIVE`, `PARTIAL`, `STALE`, `OFFLINE`;
- session/car/driver/track/layout identity and deterministic track-layout key;
- session state, elapsed/remaining time, lap limit, race laps, position where reliable;
- speed, fuel, spline position, world position, lap times, official validity;
- `isInPitlane`, `isInPit`, `resetCounter`;
- independent FL/FR/RL/RR tyre records;
- measured weather, temperatures, wind, rain, wetness, grip where verified;
- explicit units, provenance, availability, freshness, and failure reasons.

Unavailable values must remain unavailable, not zero.

## Identity and discontinuity

Define reason codes for initialization, car/track/layout/session changes, restart, replay transition, lap counter decrease, reset, teleport, spline/world jumps, and material refuel.

Separate hard identity boundaries from soft discontinuities. Do not require every boundary to erase all history.

## Immutable race event V1

Event envelope:

- schema version;
- event ID and sequence;
- event type;
- source snapshot ID;
- detection and source/session times;
- identity key;
- confidence and provenance;
- payload;
- suppression/rejection reason where applicable.

Once emitted, an event is immutable.

Define contracts for:

- session start/end/restart, identity/replay changes, reset, teleport;
- lap start/completion/validity/classification/eligibility;
- pit entry candidate/confirmed/rejected, lane entered/exited, box arrival/departure, exit candidate/confirmed/rejected, calibration updated/conflicted;
- refuel and fuel sample acceptance/rejection;
- weather regime change.

## Completed-lap record V1

Include identity, timing, sectors, official validity, invalidation reason, classification, fuel summary, weather regime, compound, pit/reset interaction, and independent eligibility placeholders:

- `useForPace`
- `useForFuel`
- `useForTyres`
- `useForProjection`
- `useForOfficialAverage`
- policy, reasons, manual override

Do not use one global include-invalid-laps Boolean.

Support policy IDs such as `STRICT`, `OPERATIONAL`, and `CUSTOM`.

## Pit contracts

Define a pit-transition observation containing transition type, source snapshot, old/new state, entry/exit classification, spline/world position, reset counter, speed, timestamps, stability duration, movement, confidence, confirmation state, and rejection reasons.

Define marker states:

- `UNAVAILABLE`
- `PROVISIONAL`
- `LEARNED`
- `CONFIRMED`
- `CONFLICTED`
- `MANUAL_OVERRIDE`

Define a versioned persistent track/layout marker record with entry/exit spline and world positions, bounded observations, confidence, source, timestamps, manual override, and pit timing summaries.

## Calculated and forecast envelopes

Calculated value metadata must include value, unit, calculation version, source fields/events, accepted/rejected samples, sample count, regime, policy, freshness, confidence, uncertainty, binding constraint, and unavailable reason.

Forecast metadata must include forecast/model IDs and versions, generation and target times, value/unit, measured and calculated inputs, samples, regime, freshness, confidence, uncertainty, binding constraint, unavailable reason, and supersession.

Do not implement the full engines.

## Deterministic replay

Add host-side fixtures that replay normalized snapshots into deterministic event sequences.

Cover:

1. session start;
2. completed lap;
3. invalidated lap;
4. reset/teleport;
5. pit-lane false→true;
6. pit-box arrival;
7. pit-box departure;
8. pit-lane true→false;
9. start already in pit lane;
10. track/layout change;
11. refuel;
12. weather regime change.

Two replays must serialize byte-identically.

## Versioning and retention

Prefer additive schema evolution. Never silently reinterpret existing fields.

Bound recent events, sample IDs, pit observations, source failures, and diagnostics.

## Tests and gate

Test schemas, units, optional fields, unavailable-versus-zero, deterministic identity, discontinuities, immutable events, completed laps, independent eligibility, pit contracts, calculated/forecast envelopes, bounded retention, all replay fixtures, byte identity, architectural boundaries, deterministic bundle, and V1 protection.

Before commit:

1. run shared validation;
2. validate schemas and fixtures;
3. replay twice;
4. run deterministic build twice;
5. confirm no scope creep;
6. confirm only Task 1 changes.

Create exactly one commit and continue only when the worktree is clean and every gate passed.
