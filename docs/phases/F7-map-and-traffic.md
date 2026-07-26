# F7: Map and Traffic

## Goal
Add spatial and traffic-awareness workflows for engineers using the expanded telemetry foundation.

## Dependencies
F6.

## Deliverables
Coordinates, team cars, public opponents, gaps, classes, and traffic workflows, plus explicit exclusion of private opponent claims.

## Exclusions
Private opponent claims, setup transfer, and broad strategy workspace features.

## Implementation Sequence
1. Define the minimum valuable map, class, gap, and traffic workflows.
2. Map coordinates, team cars, and public opponents into coherent views.
3. Validate traffic awareness without inventing private opponent data.

## Automated Tests
Component plus E2E coverage for coordinates, team cars, public opponents, gaps, classes, and traffic scenario updates.

## Manual Tests
Operator walkthroughs using realistic traffic scenarios, class changes, and data-sparsity cases.

## CSP Runtime Requirements
Required only if map-derived outcomes affect the driver shell; otherwise document why PitWall is unaffected.

## Security
Ensure spatial views do not imply control actions that have not yet been introduced.

## Exit Criteria
Map and traffic workflows are useful, coherent, grounded in stable telemetry behavior, and free of private-opponent claims.

## Rollback
Limit scope to traffic awareness without advanced mapping overlays if complexity rises too quickly.

## Risks
Overfitting to incomplete telemetry, confusing spatial heuristics, and accidental private-opponent inference.

## Complexity
medium

## Clean-Thread Recommendation
Yes - move engineer command design into a fresh thread so control semantics start from a stable observability base.
