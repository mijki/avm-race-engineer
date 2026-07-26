# F9: Strategy Workspace

## Goal
Layer strategy workflows on top of live and replay-ready session context with explicit operator consent.

## Dependencies
F8.

## Deliverables
Strategy workspace with Plan A, Plan B, and Plan C; revision handling; operator consent points; and replay-aware validation scenarios.

## Exclusions
Setup transfer, alpha hardening, and public release scope.

## Implementation Sequence
1. Define Plan A, Plan B, and Plan C structures and their revision flow.
2. Bind strategies to live or replay context with explicit operator consent.
3. Validate revision handling and operator decision points.

## Automated Tests
Scenario and E2E coverage for Plan A/B/C state transitions, revisions, consent, and replay/live parity.

## Manual Tests
Strategy drills with representative race situations, revision changes, and operator-consent edge cases.

## CSP Runtime Requirements
Required only when workspace outcomes surface to PitWall; otherwise document non-impact.

## Security
Separate advisory workflows from privileged actions and preserve action audit trails around consent.

## Exit Criteria
The workspace supports Plan A/B/C, revisions, and explicit consent without state drift or hidden automation.

## Rollback
Keep only the highest-value workflows if broad strategy scope harms reliability.

## Risks
Workflow sprawl, replay/live divergence, and unsafe assumptions about operator intent.

## Complexity
medium

## Clean-Thread Recommendation
Yes - shift setup transfer into a separate thread so packaging and handoff concerns are not diluted by workflow iteration.
