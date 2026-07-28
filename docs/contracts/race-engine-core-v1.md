# Race Engine Core V1 Contracts

These contracts define the bounded, deterministic local core shared by the
normalized CSP telemetry path, host replay, and later race calculations. They
are additive to the existing V0 driver-status contracts and do not implement a
forecast or eligibility engine.

## Contract families

- `telemetry-snapshot-v1`: measured telemetry with explicit source health,
  identity, timestamps, sequence, provenance, availability, and failures.
- `race-event-v1`: immutable detected facts with stable ordering and source
  references. Event payloads never replace the source snapshot.
- `completed-lap-v1`: timing, validity, classification, fuel and weather facts
  plus independent `useFor*` eligibility decisions for pace, fuel, tyres,
  projection, and official averages.
- `pit-transition-observation-v1` and `pit-marker-record-v1`: raw transition
  evidence and bounded track/layout calibration records.
- `calculated-value-v1`: derived values with accepted/rejected samples,
  policy, freshness, confidence, uncertainty, and unavailable reasons.
- `forecast-envelope-v1`: explicitly predictive values with model identity,
  measured/calculated inputs, target time, uncertainty, and supersession.

## Stability rules

Missing values remain missing. Units are part of every measured or derived
field's metadata. New fields are additive; an existing field is never silently
reinterpreted. Event IDs and replay ordering are deterministic for the same
normalized snapshot sequence. Recent events, observations, sample IDs, source
failures, and diagnostics are bounded by the owning runtime.

The JSON schema companion is
`race-engine-core-v1.schema.json`. Host replay uses
`tools.race_engine_core.replay_snapshots` and the checked-in fixture catalog
under `tests/fixtures/race_engine_core_v1_replay.json`.
