# F11: Reliability and Security

## Goal
Raise the platform to a supportable hardening level before the closed team alpha.

## Dependencies
F10.

## Deliverables
TLS; authorization roles; secret management; rate limits; backups; retention;
observability; load tests; server and bridge restart recovery; network
interruption handling; soak testing; and rollback evidence.

## Exclusions
Open release, major feature expansion, and unsupported deployment models.

## Implementation Sequence
1. Harden TLS, roles, secrets, rate limits, backups, retention, and observability.
2. Stress the critical E2E paths under load, restart, and network-fault conditions, including soak.
3. Rehearse rollback and incident response with the transferred setup.

## Automated Tests
Release-candidate regression, security-focused integration coverage, load checks, restart checks, network-fault scenarios, backup-restore validation, and three-hour soak automation where possible.

## Manual Tests
Incident drill, rollback rehearsal, restart rehearsal, backup restore check, and support procedure walkthrough.

## CSP Runtime Requirements
Required when hardening changes packaging, trust, or runtime behavior for PitWall.

## Security
This phase is the main hardening gate and must close critical trust-boundary gaps before alpha.

## Exit Criteria
Reliability and security risks across TLS, roles, secrets, rate limits, backups, retention, observability, load, restart, network faults, and soak are reduced to an explicitly accepted alpha posture.

## Rollback
De-scope non-critical hardening extras while preserving mandatory trust and recovery controls.

## Risks
Late identity or deployment surprises, brittle degraded-state handling, and incomplete recovery evidence.

## Complexity
large

## Clean-Thread Recommendation
Yes - use a dedicated alpha-ops thread for F12 so launch-like rehearsal consumes a stable hardened baseline.
