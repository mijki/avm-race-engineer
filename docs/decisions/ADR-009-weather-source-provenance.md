# ADR-009: Weather Source Provenance

- Status: Proposed
- Date: 2026-07-26
- Related: [Telemetry Capability Matrix](../research/telemetry-capability-matrix.md), [Weather capability findings](../research/weather-capabilities.md), [Race Model And Forecast Engine](../architecture/race-model-and-forecast-engine.md)

## Context

Weather data may come from multiple evidence classes with different authority:
measured current conditions, controller transition hints, server/controller
future schedules, AVM-derived trends, and AVM-estimated forecasts. Treating all
of them as the same kind of forecast would mislead both the driver and the
engineer.

## Decision

Preserve weather provenance as a first-class part of the model. Distinguish at
least:

- measured current weather
- measured current track condition
- controller-provided current-to-next transition
- authoritative server/controller schedule
- AVM-derived trend
- AVM-estimated future condition
- unknown future condition

UI and contract layers may collapse these to labels such as `CURRENT`,
`SCHEDULED`, `ESTIMATED`, `TRENDING`, `UNKNOWN`, and `STALE`, but they must not
promote a trend into a schedule or fabricate future certainty from current
measurements alone.

## Consequences

- Forecast consumers can tell whether a weather claim is measured, scheduled,
  estimated, stale, or unsupported.
- Confidence and explanation output can degrade honestly when future weather is
  not authoritatively available.
- Driver-facing weather alerts can remain short without becoming misleading.

## Open Questions

- Which exact CSP/controller combinations can provide enough evidence to count
  as authoritative schedule sources in practice.
