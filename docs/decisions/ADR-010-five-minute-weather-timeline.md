# ADR-010: Five-Minute Weather Timeline

- Status: Proposed
- Date: 2026-07-26
- Related: [Race Model And Forecast Engine](../architecture/race-model-and-forecast-engine.md), [Calculation Data Flow](../architecture/calculation-data-flow.md), [Weather capability findings](../research/weather-capabilities.md)

## Context

Both AVM PitWall and Engineer Console need a stable first forecast cadence for
weather-aware strategy communication. Raw sources will vary in cadence and
authority, and some will only provide current conditions or a transition hint.

## Decision

Use a five-minute bucket timeline as the first planned display cadence for
future weather presentation: `now`, `+5`, `+10`, `+15`, `+20`, `+25`, and
`+30` minutes. The timeline is a presentation and contract cadence, not a claim
that all sources natively publish exact five-minute data. Each bucket must
preserve provenance, confidence, uncertainty, generated time, and whether the
value is authoritative or interpolated.

## Consequences

- Driver and engineer surfaces can share one initial timeline shape.
- Transition-only and low-detail sources can still be represented honestly
  through interpolated or unknown buckets.
- The system must explicitly model missing buckets, stale buckets, and horizon
  confidence degradation.
- Teams must not interpret every five-minute point as authoritative schedule
  truth.

## Open Questions

- How far beyond 30 minutes the first endurance-oriented timeline should extend
  once real source capability is measured.
