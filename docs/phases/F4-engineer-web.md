# F4: Engineer Console

## Goal
Deliver the first read-only Engineer Console backed by relay data.

## Dependencies
F3.

## Deliverables
Read-only Engineer Console with driver online state, car, track, session, speed, RPM, gear, fuel, lap, basic charts, and stale UX.

## Exclusions
Engineer editing, driver commands, setup transfer, and strategy authoring.

## Implementation Sequence
1. Define the minimum useful read-only Engineer Console fields and charts.
2. Map live, stale, and disconnected states for every visible panel.
3. Validate that the console stays read-only until the command phase.

## Automated Tests
View-model tests for driver online, car, track, session, speed, RPM, gear, fuel, lap, basic charts, and stale-state rendering plus relay subscription integration.

## Manual Tests
Operator walkthrough of the read-only console covering happy path, stale UX, and disconnect states.

## CSP Runtime Requirements
Advisory unless web payload choices force changes to the driver shell display model.

## Security
Keep operator visibility separate from control authority and minimize data exposure in the read-only console.

## Exit Criteria
An operator can observe live session state in the Engineer Console with no editing or command surface.

## Rollback
Trim the dashboard to fewer views if reliability suffers under wider scope.

## Risks
Noisy telemetry, ambiguous stale states, and accidental command creep.

## Complexity
medium

## Clean-Thread Recommendation
Yes - use a fresh thread for the first vertical slice so cross-stack validation is isolated from console iteration noise.
