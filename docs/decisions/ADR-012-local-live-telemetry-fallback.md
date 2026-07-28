# ADR-012: Proposed Local Live Telemetry Fallback

Status: Proposed

## Context

The live-driver vertical slice needs real own-car/session values before Driver
Bridge and the shared race-model packages exist. The PitWall still must not
become the final authoritative calculation owner.

## Decision

Add a narrow CSP-native adapter and a bounded, explicitly non-authoritative Lua
calculation path behind the existing driver-status reduction boundary. Keep
identity, lap, stint, sample, weather, track calibration, calculation, and UI
responsibilities in separate modules. Use LIVE by default, MOCK only from
Garage diagnostics, and RECOVERY for source failures without mock substitution.

## Rejected alternatives

- Copy the V1 application wholesale: rejected because this repository treats V1
  as a compatibility reference and the vertical slice needs a new data boundary.
- Put raw telemetry calls in renderers: rejected because it prevents traceable,
  testable calculations and risks per-frame work in UI code.
- Treat mock fixtures as a live fallback: rejected because it would mislead a
  driver when the CSP source is unavailable.

## Consequences

This slice provides useful live driver feedback and host-testable equations,
but its local calculations must be replaced or validated by Driver Bridge
before production authority is assigned. Real CSP evidence remains a separate
runtime gate from host tests.
