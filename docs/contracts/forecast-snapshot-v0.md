# Forecast Snapshot v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the short-horizon and stint-horizon forecast contract for one active
strategy revision. This contract contains forecast state and recommendation
state only; direct measured telemetry remains in the calculated race state.

## Baseline And Revision Rules

- Every forecast must identify the accepted strategy revision on which it is
  based.
- Live forecasts must not overwrite the baseline strategy revision.
- The producer may compute alternatives elsewhere, but this snapshot represents
  the currently selected forecast lane only.

## Required Fields

- `schema_version`
- `forecast_id`
- `session_id`
- `car_id`
- `driver_id`
- `track_id`
- `layout_id`
- `strategy_id`
- `based_on_strategy_revision`
- `baseline_strategy_revision`
- `stint_id`
- `calculated_race_state_id`
- `calculated_at_utc`
- `model`
- `forecast_window`
- `sample_set`
- `assumption_ids`
- `explanation_ids`
- `forecast_state`
- `recommendation_state`
- `confidence`
- `reason_codes`

## Forecast Scope

The forecast state covers at minimum:

- fuel at pit entry
- fuel at stint end
- next-stint requirement
- fuel to add
- projected race-end fuel
- earliest, optimal, and latest safe pit points
- predicted stint end
- tyre life and pace degradation
- traffic and weather impact summaries
- strategy feasibility

`calculated_race_state_id` supplies the trace to telemetry sources, capture and
monotonic time, sequence, and freshness. The model, sample set, assumption, and
explanation references preserve forecast-specific lineage without copying the
measured layer.

## Schema

Authoritative draft schema:
[forecast-snapshot-v0.schema.json](./forecast-snapshot-v0.schema.json)
