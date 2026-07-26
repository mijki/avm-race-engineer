# Calculation Explanation v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the explanation object attached to calculated race state, forecasts, and
engineer-facing models. The explanation preserves the assumptions, evidence,
reason codes, and uncertainty behind a value or recommendation.

## Required Fields

- `schema_version`
- `explanation_id`
- `subject_type`
- `subject_id`
- `calculation_key`
- `generated_at_utc`
- `summary`
- `primary_reason_codes`
- `confidence_summary`

## Explanation Rules

- `calculation_key` identifies the exact derived or forecast quantity being
  explained, for example `predicted_fuel_at_pit_entry_l`.
- `summary` is the short operator-readable explanation.
- `narrative_steps` are optional machine-readable ordered steps for richer
  engineer views.
- `assumptions` must state whether each assumption is active, stale, or
  invalidated.
- `evidence` must preserve source identifiers and capture times so the operator
  can inspect provenance.
- `uncertainty_summary` must describe uncertainty ranges only when the producer
  can support them honestly.

## Reason Codes

Canonical reason code vocabulary is defined in
[calculation-reason-codes-v0.md](./calculation-reason-codes-v0.md).

## Schema

Authoritative draft schema:
[calculation-explanation-v0.schema.json](./calculation-explanation-v0.schema.json)
