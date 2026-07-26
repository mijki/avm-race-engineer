# ADR-011: Forecast Confidence And Explanations

- Status: Proposed
- Date: 2026-07-26
- Related: [Race Model And Forecast Engine](../architecture/race-model-and-forecast-engine.md), [Calculation Data Flow](../architecture/calculation-data-flow.md), [Observability](../architecture/observability.md)

## Context

Race calculations and weather-aware forecasts will often run with incomplete,
mixed-regime, stale, or recently changing data. A single unqualified number or
generic high/medium/low badge is not enough for operator trust, replay, or
safe driver messaging.

## Decision

Every derived and forecast value should carry structured confidence and
explanation metadata. Confidence should include component-level assessment for
sample quantity, sample age, sample consistency, telemetry completeness,
regime match, weather stability, strategy compatibility, and identity validity.
Explanation output should identify inputs, assumptions, excluded samples,
operating regime, reason codes, and freshness/provenance status.

UI may collapse the structure into simpler badges for at-a-glance display, but
the underlying object must remain available for Engineer Console, relay-side
audit, replay, and debugging.

## Consequences

- The platform can show `LOW_CONFIDENCE`, `WAITING_FOR_VALID_DATA`, or
  `UNKNOWN` honestly instead of hiding weak evidence behind precise numbers.
- Engineers can understand why a forecast moved and whether the sample basis is
  still trustworthy.
- Driver-facing reductions can remain compact while still being grounded in the
  same explanation model.

## Open Questions

- Which confidence thresholds should map to driver-visible reduced labels in
  the first driver shell.
