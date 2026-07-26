# Strategy Simulation

Status: `Proposed`

`packages/strategy-simulation` is the planned shared .NET package for
alternative-plan evaluation and scenario comparison built on top of
`race-domain` and `forecast-engine`.

It is a scenario-analysis package, not the authoritative low-latency live
calculation engine. The first driver-client shell does not require it.

## Planned Responsibilities

- Compare Plan A/B/C and accepted-versus-proposed strategy revisions.
- Simulate alternative stint lengths, pit windows, tyre choices, and fuel-add
  choices.
- Evaluate weather, traffic, and caution scenarios against the same race-domain
  inputs.
- Produce comparative outputs such as projected race time, projected reserve,
  projected pit loss, feasibility, and risk.
- Support sensitivity analysis around uncertain assumptions such as fuel burn,
  crossover timing, or weather transition timing.

## Planned Inputs

- immutable baseline plan
- accepted strategy revision
- proposed alternative strategy revisions
- current measured state and derived current state
- forecast-engine regime models and uncertainty ranges
- weather scenarios with explicit provenance and confidence
- configurable pit-loss and reserve assumptions

## Planned Outputs

- scenario result summaries
- alternative pit-window comparisons
- feasibility and tank-capacity checks
- risk-ranked recommendation support for Engineer Console
- explanation deltas showing why one scenario outperforms another

## Boundary Rules

- `strategy-simulation` should reuse `race-domain` identities, units, and
  revision semantics.
- It should consume `forecast-engine` state and models instead of re-creating a
  separate live-calculation implementation.
- It should remain deterministic for the same inputs so replay and operator
  audit can reconstruct scenario results.
- It should not become the owner of driver-facing bounded status snapshots.

## Out Of Scope

- Raw telemetry ingestion.
- Driver Bridge connectivity or buffering.
- Browser-managed ad hoc calculation logic.
- CSP Lua runtime execution.
