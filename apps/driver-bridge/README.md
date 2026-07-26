# Driver Bridge

Status: `Planned`

Driver Bridge is the Windows-side collector and communication process that
connects the local simulator environment to the broader AVM system.

## Responsibilities

- Read standard Assetto Corsa shared memory independently of AVM PitWall.
- Normalize units and attach source, UTC and monotonic capture time, sequence,
  session, car, and driver identity.
- Record sessions locally so a Relay Server outage does not destroy the
  driver's evidence.
- Maintain authenticated relay connectivity and a bounded local link to AVM
  PitWall.
- Receive engineer commands, reject wrong-session/wrong-car/expired duplicates,
  and forward valid driver-facing state.
- Stage setup downloads, verify metadata and checksum, back up the destination,
  and copy an accepted setup only after garage consent.
- Handle Assetto Corsa start, stop, restart, and reconnect while exposing local
  diagnostics.

## Proposed technology

- C# on [.NET 10 LTS](https://learn.microsoft.com/en-us/dotnet/core/releases-and-support)
  (`net10.0-windows`) using the .NET Generic Host for the long-running process.
- A background process is sufficient for F2; an optional Windows tray shell is
  a later usability decision and must not own telemetry or command logic.
- The Lua-to-bridge IPC transport remains an F2 proof decision; see
  [local IPC options](../../docs/research/local-ipc-options.md).

## Interfaces

- Consumes shared telemetry contracts from
  [packages/telemetry-contracts/README.md](../../packages/telemetry-contracts/README.md)
- Consumes shared command contracts from
  [packages/command-contracts/README.md](../../packages/command-contracts/README.md)
- Connects upstream to
  [services/relay-server/README.md](../../services/relay-server/README.md)

## Out Of Scope

- Multi-user strategy collaboration
- Persistent race-control dashboards
- Shared business logic that belongs in cross-repo packages
- Server authentication policy, team authorization, browser state, and
  arbitrary setup editing
