# Forecast Engine

Status: `Proposed`

`packages/forecast-engine` is the planned shared .NET package for live sample
selection, current-state derivation, short-horizon forecast generation, and
explanation output.

It is the reusable production-owned calculation library. Driver Bridge is the
planned authoritative low-latency host for live operation. Relay Server may
reuse the same package for validation, replay, and longer-horizon recalculation
without redefining the race math.

## Planned Responsibilities

- Manage representative sample windows for fuel, pace, tyre, and weather-aware
  modelling.
- Classify samples by operating regime and reject incompatible or stale inputs.
- Produce derived current state from measured telemetry and accepted strategy
  revision inputs.
- Produce short-horizon and stint-level forecast outputs with explicit
  uncertainty and freshness.
- Emit explanation records and structured confidence assessments for every
  derived and forecast calculation.
- Reduce detailed model state into bounded driver-facing snapshot data without
  making AVM PitWall run the full engine.

## Required Operating Regimes

- normal green running
- traffic-affected running
- fuel-saving running
- push running
- wet running
- mixed conditions
- caution or slow-zone running
- pit in-lap
- pit lane
- pit out-lap
- incident or damaged running
- incomplete telemetry

The engine must not blindly average across regimes. It should either maintain
separate rolling models or degrade confidence when the available sample set is
too mixed to support a clean estimate.

## Calculation Capabilities

- sample collection and retention
- sample eligibility and outlier rejection
- rolling fuel models in litres per lap, litre per kilometre, and litres per
  minute
- rolling pace models and target-pace deltas
- pit-entry projection using track position, pit-entry reference, and
  wraparound rules
- stint-end and next-stint fuel projection
- tyre-life and degradation projection
- weather-impact integration and regime crossover handling
- confidence scoring, uncertainty range generation, and degraded-state fallback
- explanation output with assumptions, reason codes, and model version

## Inputs

- measured telemetry from Driver Bridge normalized into canonical units
- accepted strategy revision and immutable baseline plan references
- session, car, driver, track, layout, and pit-entry identity
- current weather and track-condition observations
- optional authoritative future weather schedule where available
- operator-entered assumptions such as reserve target, pit-loss assumptions, or
  tyre crossover thresholds

## Outputs

- derived current state
- forecast snapshot
- driver status snapshot reduction
- engineer-facing model explanation set
- confidence object with component scores and explicit causes for degradation

## Confidence Model Requirements

Each output should carry structured confidence dimensions rather than only one
collapsed label. The package should score and explain at least:

- sample quantity
- sample age
- sample consistency
- telemetry completeness
- regime match
- weather stability
- strategy compatibility
- identity validity

UI layers may collapse those dimensions to high/medium/low for at-a-glance
presentation, but the underlying object must remain available to Engineer
Console and to audit/replay tools.

## Boundary Rules

- `forecast-engine` should depend on `race-domain` for units, identities,
  invariants, and reason codes.
- Runtime ownership stays outside the package. No sockets, no SignalR, no CSP
  APIs, and no browser concerns belong here.
- The package should not own scenario ranking across multiple alternative plans
  beyond the minimum comparison needed to explain one active forecast.
- Any recomputation by Relay Server must preserve the same input revision and
  model-version references rather than silently replacing the bridge result.

## Out Of Scope

- Raw telemetry capture.
- Authoritative strategy acceptance workflow.
- Browser charting or driver UI rendering.
- Team-level scenario search across many alternative plans.
