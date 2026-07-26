# F2: Driver Bridge POC

## Goal

Validate a .NET Windows Driver Bridge proof of concept that captures the raw
telemetry and identity required by the later forecast engine, with no server
dependency.

## Dependencies

F1.

## Deliverables

C#/.NET Windows bridge proof of concept; Assetto Corsa shared-memory reader;
session detection; car, driver, track, layout, and session identity capture;
raw telemetry and environmental fields required for later calculations; local
diagnostics; local recording; and bridge fixtures with no server dependency.

## Exclusions

Relay networking, Engineer Console workflows, PitWall command transport, and
production forecast ownership.

## Implementation Sequence

1. Define shared-memory and diagnostics boundaries for the bridge.
2. Prove session handling, identity capture, raw telemetry capture, and local
   recording on Windows.
3. Produce bridge fixtures consumable by the weather-probe and forecast-engine
   phases without introducing a server.

## Automated Tests

Session lifecycle tests, shared-memory parser tests, identity-preservation
tests, raw telemetry fixtures, environmental-field fixtures, diagnostics
tests, and local recording metadata checks.

## Manual Tests

Windows bridge smoke covering start, stop, missing shared-memory data,
diagnostics visibility, and local recording replay.

## CSP Runtime Requirements

Advisory unless bridge payload choices force changes to the driver shell
assumptions.

## Security

Constrain local configuration and keep simulator-facing concerns isolated from
broader system trust.

## Exit Criteria

The bridge captures raw telemetry and identity locally, emits diagnostics,
records locally, and remains server-free while preserving the data needed by
F3A and F3.

## Rollback

Limit the proof of concept to one telemetry slice if wider coverage blocks
downstream work.

## Risks

Shared-memory edge cases, identity drift, telemetry ordering ambiguity, and
bridge logic leaking server assumptions too early.

## Complexity

medium

## Clean-Thread Recommendation

Yes - start the relay and weather-probe phases in dedicated threads so server
and capability concerns are evaluated independently from bridge details.
