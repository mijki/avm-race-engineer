# AVM Race Engineer Retention And Backups

Status: DRAFT

This document proposes the F0 retention, export, and backup posture for AVM
Race Engineer session and audit data.

Related documents: [Observability](../architecture/observability.md),
[Session And Identity Model](../architecture/session-and-identity-model.md),
[On-Prem Deployment](on-prem-deployment.md).

## Proposed Retention Principles

- Retention should be configurable per race weekend or operational period rather
  than assumed infinite.
- Audit records should remain attributable and more durable than transient edge
  logs.
- Driver-host local storage should be treated as a convenience buffer, not the
  primary long-term source of truth.
- Exported diagnostic packages should minimize unnecessary sensitive data while
  remaining useful for incident review.

## Proposed Data Classes

| Data class | Proposed retention posture |
| --- | --- |
| relay audit trail | durable, attributable, prioritized for incident review |
| relay session summaries | retained long enough for race analysis and support |
| live telemetry detail | configurable by event/race weekend needs |
| bridge local buffers | short-lived and aggressively cleaned up |
| exported diagnostics | time-bounded and access-controlled |

## Proposed Backup Priorities

1. Preserve relay-side audit and session metadata first.
2. Preserve enough recent session state to support post-incident reconstruction.
3. Avoid backup strategies that silently encourage operators to rely on the
   driver host as the only surviving record.

## Proposed Recovery Considerations

- Restored historical data should remain distinguishable from current live
  session state.
- Backup restore should not reopen expired command instances as actionable
  commands.
- Operator-visible recovery messaging should state when durable history is
  partially unavailable.

## Open F0 Questions

- How much high-resolution telemetry must survive beyond the current race
  weekend.
- Whether audit exports need a separate retention policy from internal stored
  audit data.
