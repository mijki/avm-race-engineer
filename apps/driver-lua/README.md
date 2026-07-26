# AVM PitWall

Status: `Planned`

AVM PitWall is the compact in-car CSP Lua client. It is the driver-facing AVM
surface and therefore carries the strictest safety constraints.

## Responsibilities

- Render Compact Race, Expanded Race, and Garage/Diagnostics modes.
- Present bounded stint, fuel, pace, tyre, weather, traffic, connection, and
  engineer-instruction state.
- Collect only CSP-specific supplemental data justified by an evidence record.
- Acknowledge or reject commands, repeat the latest message, report predefined
  issues, and accept an approved setup download only while safely in the garage.
- Keep a useful limited local view when the Driver Bridge or Relay Server is
  unavailable.

## Proposed implementation boundary

- CSP Lua app maintained as small development modules.
- Deterministic build-time bundling into one generated CSP-compatible entry
  file; the shipped path uses neither runtime `require` nor `dofile`.
- CSP calls isolated behind an adapter; fuel, pace, stint, pit, and trend
  calculations remain pure domain logic.
- The generated bundle is validated, never hand-edited, and must pass a real
  Assetto Corsa/CSP gate before a driver-client phase closes.

## Must Preserve From V1

- Driver-first interaction density
- CSP-compatible integration behavior
- Safe fallback behavior during communication loss

## Out Of Scope

- Long-form strategy analysis
- Complex setup configuration during active driving
- Server-side telemetry storage or orchestration
- High-volume telemetry transport, authentication, file transfer, profile
  administration, and server reconnection orchestration

See [docs/ux/driver-client-ux.md](../../docs/ux/driver-client-ux.md) and
[docs/architecture/lua-source-and-build-architecture.md](../../docs/architecture/lua-source-and-build-architecture.md).
