# Engineer Model Snapshot v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the detailed engineer-facing snapshot that keeps baseline, accepted
strategy, measured inputs, derived state, forecast state, recommendation state,
weather, and explanations visible together without collapsing ownership.

## Required Layers

The engineer model snapshot must preserve separately:

- original baseline plan summary
- current accepted strategy summary
- current measured layer
- current derived layer
- current forecast layer
- current recommendation layer
- optional proposed strategy summary
- optional driver-accepted strategy summary

## Required Fields

- `schema_version`
- `snapshot_id`
- `session_id`
- `car_id`
- `driver_id`
- `track_id`
- `layout_id`
- `generated_at_utc`
- `baseline_plan_summary`
- `accepted_strategy_summary`
- `measured_layer`
- `derived_layer`
- `forecast_layer`
- `recommendation_layer`
- `weather_measurement`
- `weather_forecast`
- `confidence_rollup`
- `reason_codes`

## Scope Rules

- This contract is for Engineer Console visibility and audit, not for driver
  publication.
- Rich explanations and alternative scenarios may exist here even when they are
  suppressed from the driver snapshot.
- Full raw telemetry history still remains outside this contract.

## Schema

Authoritative draft schema:
[engineer-model-snapshot-v0.schema.json](./engineer-model-snapshot-v0.schema.json)
