# F2: Driver Bridge POC

## Goal
Validate a .NET Windows Driver Bridge proof of concept with no server dependency.

## Dependencies
F1.

## Deliverables
C#/.NET Windows bridge proof of concept; Assetto Corsa shared-memory reader;
session detection; basic telemetry; local diagnostics; local recording; and
bridge fixtures with no server dependency.

## Exclusions
Relay networking, Engineer Console workflows, and PitWall command transport.

## Implementation Sequence
1. Define shared-memory and diagnostics boundaries for the bridge.
2. Prove session handling, basic telemetry capture, and local recording on Windows.
3. Produce bridge fixtures consumable by the relay phase without introducing a server.

## Automated Tests
Session lifecycle tests, shared-memory parser tests, basic telemetry fixtures, diagnostics tests, and local recording metadata checks.

## Manual Tests
Windows bridge smoke covering start, stop, missing shared-memory data, diagnostics visibility, and local recording replay.

## CSP Runtime Requirements
Advisory unless bridge payload choices force changes to the driver shell assumptions.

## Security
Constrain local configuration and keep simulator-facing concerns isolated from broader system trust.

## Exit Criteria
The bridge captures basic telemetry locally, emits diagnostics, records locally, and remains server-free.

## Rollback
Limit the proof of concept to one telemetry slice if wider coverage blocks downstream work.

## Risks
Shared-memory edge cases, telemetry ordering ambiguity, and bridge logic leaking server assumptions too early.

## Complexity
medium

## Clean-Thread Recommendation
Yes - start the relay phase in a dedicated thread so server concerns are evaluated independently from bridge details.
