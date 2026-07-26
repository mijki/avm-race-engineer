# F5: End-to-End Vertical Slice

## Goal
Validate the first full bridge-relay-console-PitWall slice including the first command path.

## Dependencies
F4.

## Deliverables
Vertical-slice scenario, BOX BOX command, client alert and sound, driver acknowledgement, engineer-visible acknowledgement, server disconnect safety, and reconnect idempotency evidence.

## Exclusions
Broad command catalog, strategy workspace, and setup transfer.

## Implementation Sequence
1. Connect the smallest live telemetry path end to end.
2. Deliver BOX BOX through Relay Server into PitWall with alert, sound, and driver acknowledgement.
3. Prove Engineer Console acknowledgement visibility, server disconnect safety, and reconnect idempotency.

## Automated Tests
End-to-end coverage for telemetry flow, BOX BOX dispatch, sound-trigger fixtures, acknowledgement propagation, disconnect safety, duplicate prevention on reconnect, and PitWall live-status updates.

## Manual Tests
Operator plus real AC/CSP rehearsal of BOX BOX, acknowledgement, disconnect, and reconnect behavior.

## CSP Runtime Requirements
Required; the phase is not complete until the slice passes the runtime gate.

## Security
Keep the command slice narrowly scoped, authenticated, and auditable while the broader command catalog is still deferred.

## Exit Criteria
The first end-to-end slice is repeatable, observable, command-capable for BOX BOX, and CSP-valid under reconnect stress.

## Rollback
Reduce the slice to telemetry plus acknowledgement visibility if BOX BOX sound or reconnect safety proves unstable.

## Risks
Cross-stack mismatch, duplicate command effects, hidden latency, and PitWall runtime regressions.

## Complexity
large

## Clean-Thread Recommendation
Yes - open telemetry expansion in a new thread so the validated slice remains a stable baseline.
