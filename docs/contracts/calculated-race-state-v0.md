# Calculated Race State v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the current calculated race-state contract for one session and car. It
captures the direct measured inputs required by the model, the derived current
state, and the active recommendation state without restating full telemetry
history.

## Data Layer Separation

This contract must preserve separate lanes for:

1. measured telemetry summary
2. derived current state
3. references to forecast outputs
4. active recommendation state

It must not collapse those lanes into one undifferentiated payload.

## Required Fields

- `schema_version`
- `state_id`
- `session_id`
- `car_id`
- `driver_id`
- `track_id`
- `layout_id`
- `strategy_id`
- `strategy_revision`
- `baseline_strategy_revision`
- `stint_id`
- `calculated_at_utc`
- `capture_time_utc`
- `capture_time_monotonic_ms`
- `sequence`
- `freshness`
- `model`
- `sample_set`
- `telemetry_refs`
- `assumption_ids`
- `explanation_ids`
- `measured_telemetry_summary`
- `derived_current_state`
- `comparison_to_plan`
- `active_recommendation_state`
- `confidence`
- `reason_codes`

## Scope Rules

- `measured_telemetry_summary` contains only the direct observations needed to
  understand the current model state.
- `derived_current_state` contains calculations based on accepted samples and
  current conditions.
- Future predictions belong in the forecast snapshot, not here, except for the
  reference `forecast_snapshot_id`.
- Recommendation state must identify whether a recommendation is blocked,
  actionable, or waiting for valid data.
- Telemetry, assumption, and explanation references provide the trace from each
  published value to source attribution, model inputs, exclusions,
  uncertainty, and reason codes without duplicating full telemetry history.

## Units

- fuel: litres
- distance: metres
- pace: seconds per lap
- fuel rates: litres per lap, kilometre, or minute
- normalized ratios: `0.0` to `1.0`

## Schema

Authoritative draft schema:
[calculated-race-state-v0.schema.json](./calculated-race-state-v0.schema.json)
