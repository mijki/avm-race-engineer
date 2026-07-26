# Driver Status Snapshot v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the compact actionable snapshot for AVM PitWall. It is a reduction of
the full race and weather model for safe in-car display, not a second
authoritative forecast engine.

## Reduction Rules

- Preserve only driver-relevant outputs.
- Keep the source strategy revision and snapshot references for traceability.
- Do not ship full telemetry history, long explanations, or dense forecast
  timelines to the driver race view.
- Weather must remain compact: current condition, next meaningful change, status
  lane, confidence, and strategy implication only.
- The primary instruction must identify whether it came from the engineer,
  forecast engine, or minimal local safe fallback.

## Required Fields

- `schema_version`
- `snapshot_id`
- `session_id`
- `car_id`
- `driver_id`
- `strategy_revision`
- `calculated_race_state_id`
- `forecast_snapshot_id`
- `weather_forecast_id`
- `generated_at_utc`
- `valid_until_utc`
- `connection_state`
- `stint_summary`
- `fuel_summary`
- `pace_summary`
- `pit_summary`
- `weather_summary`
- `primary_instruction`
- `confidence_badge`
- `reason_codes`

## Driver UX Notes

- `weather_summary.label` must be one of `CURRENT`, `SCHEDULED`, `ESTIMATED`,
  `TRENDING`, `UNKNOWN`, or `STALE`.
- A weather ETA may be a range; do not emit false precision.
- Critical instructions must not rely on color alone.

## Schema

Authoritative draft schema:
[driver-status-snapshot-v0.schema.json](./driver-status-snapshot-v0.schema.json)
