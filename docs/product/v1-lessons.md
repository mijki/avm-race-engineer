# V1 Lessons

Status: `Planned`

## Why V1 Matters

The previous `avm-pitwall` repository is valuable because it already encoded
real driver and CSP constraints. It should shape this repository's migration
policy, not trap it in the old architecture.

## Lessons To Carry Forward

- The driver surface must stay compact and interruption-aware
- CSP compatibility behavior is a release gate, not a "nice to have"
- Degraded connectivity must become explicit state, not silent failure
- Engineer guidance only works when the command path is visible and trusted

## V1 Migration Policy

1. Treat V1 as the requirements baseline for safety-critical and
   compatibility-critical behavior.
2. Capture inherited behavior with tests or fixtures before intentionally
   changing it.
3. Allow internal architecture to diverge when the new design is cleaner,
   provided the user-visible consequence is documented.
4. Record every deliberate compatibility break before release.
5. Do not claim V1 readiness until telemetry flow, command flow, alerting, and
   degraded-mode handling are verified end to end.

## Acceptable Divergence Areas

- Engineer Console layout and navigation
- Deployment and process topology
- Shared package boundaries
- Setup and transfer experience, if safety improves

## Unacceptable Casual Drift

- Losing critical alerts behind mode suppression
- Renaming stable concepts in a way that breaks shared team language
- Regressing CSP-sensitive behavior without an explicit migration note
