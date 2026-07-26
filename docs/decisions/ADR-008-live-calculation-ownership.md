# ADR-008: Live Calculation Ownership

- Status: Proposed
- Date: 2026-07-26
- Related: [Driver Bridge](../../apps/driver-bridge/README.md), [Engineer Console](../../apps/engineer-web/README.md), [Race Model And Forecast Engine](../architecture/race-model-and-forecast-engine.md), [Calculation Data Flow](../architecture/calculation-data-flow.md)

## Context

The race model needs low-latency live calculations, representative-sample
handling, forecast generation, and bounded driver-facing output. Those
calculations must continue to work during relay outages, but the same logic
also needs replay, validation, and scenario reuse on the server side.

## Decision

Treat Driver Bridge as the planned authoritative host for live low-latency race
calculation. Put the reusable calculation rules in shared .NET packages so
Relay Server can validate and optionally recompute using the same domain logic.
Engineer Console remains a visualization and operator-input surface, not the
authoritative production calculation host. AVM PitWall consumes a compact
snapshot and keeps only minimal safety fallback behavior.

## Consequences

- Live tactical calculation can continue on the driver host during relay loss.
- Browser code does not become the hidden source of truth for race state.
- Relay-side replay and scenario analysis can reuse the same production-owned
  calculation packages without copying logic.
- Calculation package boundaries must stay pure and explicit so runtime hosts
  can share them safely.

## Open Questions

- How much relay-side recomputation should run continuously versus on demand in
  the first server phase.
