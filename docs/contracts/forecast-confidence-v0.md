# Forecast Confidence v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the structured confidence object used by calculated race state,
forecast, driver snapshot, engineer snapshot, and weather contracts. The object
must preserve why the system trusts or distrusts a result instead of collapsing
everything into a single label only.

## Required Fields

- `schema_version`
- `confidence_id`
- `subject_type`
- `subject_id`
- `calculated_at_utc`
- `overall_band`
- `overall_score`
- `freshness_state`
- `components`
- `reason_codes`

## Confidence Dimensions

The initial confidence dimensions are:

- `sample_quantity`
- `sample_age`
- `sample_consistency`
- `telemetry_completeness`
- `regime_match`
- `weather_stability`
- `strategy_compatibility`
- `identity_validity`
- `forecast_horizon`
- `source_health`

Every dimension records:

- a normalized score from `0.0` to `1.0`
- a weight used by the producer
- a status that supports UI warnings
- a short rationale

## Banding Rules

- `overall_score` is the machine-friendly scalar.
- `overall_band` is the UI-friendly collapsed label.
- Producers must not emit `high` when `identity_validity` or
  `telemetry_completeness` is failing.
- Consumers may downgrade a displayed band if freshness is stale, but must not
  silently upgrade the producer band.

## Reason Codes

`reason_codes` capture named causes for reduced or blocked confidence. Canonical
reason code vocabulary is defined in
[calculation-reason-codes-v0.md](./calculation-reason-codes-v0.md).

## Schema

Authoritative draft schema:
[forecast-confidence-v0.schema.json](./forecast-confidence-v0.schema.json)
