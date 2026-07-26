# F8: Engineer Commands

## Goal
Expand engineer-to-driver commands into a full auditable command catalog.

## Dependencies
F7.

## Deliverables
Full command catalog, priority rules, expiry rules, acknowledgement states, audit trail, issue visibility, and offline behavior.

## Exclusions
Strategy workspace, setup transfer, and non-command hardening work.

## Implementation Sequence
1. Define the full catalog with priority and expiry semantics.
2. Implement acknowledgement, duplicate handling, offline behavior, and issue visibility.
3. Validate audit trails and failure-path behavior for the entire catalog.

## Automated Tests
End-to-end command scenarios covering sent, acknowledged, expired, duplicated, wrong-session, offline, and issue-reporting states.

## Manual Tests
Operator and real AC/CSP rehearsals for high-priority, expired, offline, and acknowledgement-heavy command flows.

## CSP Runtime Requirements
Required; command UX must stay within CSP runtime and driver-distraction limits.

## Security
Authorize command origin strictly and record audit-friendly state transitions for every control path.

## Exit Criteria
The command catalog is explicit, prioritized, expiring, acknowledged, auditable, issue-aware, and safe while clients are offline.

## Rollback
Reduce the command set to the smallest high-value subset if semantic breadth adds risk.

## Risks
Command overload, ambiguous priority handling, unsafe retries, and driver-facing failure confusion.

## Complexity
large

## Clean-Thread Recommendation
Yes - begin strategy workspace work in a clean thread once command semantics are stable and replayable.
