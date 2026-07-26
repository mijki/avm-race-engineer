# Product Scope

Status: `Planned`

## F0 Scope

The F0 scope for this repository is to define the first release shape of AVM
Race Engineer tightly enough that implementation can proceed contract-first and
UX-first.

The F0.1 amendment extends that foundation with a dedicated race-model,
live-calculation, strategy-forecasting, and weather-forecast requirements
package without broadening the repository into production implementation.

## In Scope For F0 Definition

- Stable terminology and product boundaries
- Driver-facing interaction model for AVM PitWall
- Engineer Console information architecture centered on live operation
- Alert semantics across driver, engineer, and backend surfaces
- Setup, pairing, and handoff expectations for safe race-day operation
- Shared-contract and strategy-package boundaries
- Race-model, calculation, and weather-forecast product requirements
- Compact driver guidance versus detailed engineer model visibility
- Explicit provenance and degraded-state rules for calculated and weather
  outputs
- V1 migration policy and parity expectations

## Out Of Scope For F0 Definition

- Detailed implementation plans for every subsystem
- Production forecast-engine implementation or scenario simulation
- Production deployment topology decisions
- Advanced automation beyond trusted telemetry, commands, and alerts
- Recreating every V1 screen or internal structure one-for-one

## Release Framing

The first release from this repository should be considered credible only when
the team can demonstrate:

- End-to-end telemetry flow
- End-to-end engineer command flow with acknowledgement handling
- Driver-safe alerting behavior in all three driver modes
- A repeatable setup and transfer workflow with explicit readiness checks
- Documented handling of V1 compatibility-sensitive behavior

## Dependency On V1 Lessons

F0 scope is intentionally constrained by V1 behavior that already proved useful
or safety-critical. Those lessons and the migration policy are tracked in
[v1-lessons.md](v1-lessons.md).
