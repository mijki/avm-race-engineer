# Weather Forecast v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the weather forecast timeline contract used by Driver Bridge, Relay
Server, Engineer Console, and AVM PitWall. The contract keeps measured current
conditions separate from scheduled, estimated, trending, stale, and unknown
future lanes.

## Required Fields

- `schema_version`
- `forecast_id`
- `session_id`
- `track_id`
- `layout_id`
- `generated_at_utc`
- `source_summary`
- `display_bucket_minutes`
- `timeline_status`
- `points`
- `confidence`
- `reason_codes`

## Timeline Rules

- The first intended display cadence is five-minute buckets.
- The first supported sequence is `now`, `+5`, `+10`, `+15`, `+20`, `+25`,
  and `+30` minutes, while the contract remains extensible to longer horizons.
- A five-minute display bucket does not imply a five-minute authoritative source.
- `timeline_status` distinguishes `scheduled`, `estimated`, `trending`,
  `current_only`, `unknown`, and `stale`.
- `authoritative = true` is allowed only when the source actually publishes a
  future schedule.
- `rain_probability_0_to_1` must remain `null` when no real probability exists.
- `interpolated = true` must be set when a bucket was filled by interpolation or
  resampling rather than direct source publication.

## Point Semantics

Each timeline point represents one display bucket and must preserve:

- horizon from generation time
- bucket start and end
- source provenance
- confidence
- uncertainty
- reason codes

## Schema

Authoritative draft schema:
[weather-forecast-v0.schema.json](./weather-forecast-v0.schema.json)
