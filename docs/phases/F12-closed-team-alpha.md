# F12: Closed Team Alpha

## Goal
Validate the platform in a supervised, reversible closed team alpha with real racing workflows and no public release.

## Dependencies
F11.

## Deliverables
Closed team alpha runbook covering real team practice, qualifying, endurance, multiple drivers, remote engineer participation, driver swaps, support flow, and alpha exit report.

## Exclusions
Public release, large-scale onboarding, and net-new feature scope beyond alpha blockers.

## Implementation Sequence
1. Define the real-team alpha cohort, support envelope, and success thresholds.
2. Run supervised practice, qualifying, endurance, multi-driver, remote engineer, and driver-swap sessions with rollback readiness preserved.
3. Capture incidents, usability gaps, and deferred risks without turning alpha into a public release.

## Automated Tests
Final end-to-end suite, critical-path release-candidate checks, support-path checks, and rollback validation.

## Manual Tests
Supervised alpha sessions across practice, qualifying, endurance, multi-driver, remote engineer, and driver-swap flows, plus support drills and forensic review.

## CSP Runtime Requirements
Required; supported CSP baselines and rollback behavior must be validated on the alpha package.

## Security
Operate with least privilege, monitored access, and explicit incident escalation during alpha.

## Exit Criteria
The closed team alpha is supportable, evidence-backed, reversible, and explicitly non-public.

## Rollback
Use the pre-approved rollback path immediately if alpha incident rates exceed the support envelope.

## Risks
Real-user variance, support overload, unobserved regressions, and pressure to treat alpha as public release.

## Complexity
large

## Clean-Thread Recommendation
Yes - start the post-alpha planning cycle in a new thread so alpha evidence remains a stable historical record.
