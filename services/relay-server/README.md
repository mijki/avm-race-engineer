# Relay Server

Status: `Planned`

Relay Server is the on-prem transport and session coordination service for AVM
Race Engineer.

## Responsibilities

- Authenticate driver and engineer connections and enforce team/session rooms.
- Receive, validate, and fan out versioned live telemetry.
- Route engineer commands to exactly one intended driver, preserving expiry,
  idempotency, acknowledgement, and audit lifecycle.
- Maintain bounded replay buffers and persist session, strategy revision,
  command, setup-metadata, and approved-file records.
- Expose health endpoints and structured operational logs without secrets.

## Proposed technology

- ASP.NET Core 10 on .NET 10 LTS.
- [ASP.NET Core SignalR](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction?view=aspnetcore-10.0)
  as the first real-time transport candidate; WebSockets are preferred with
  supported fallback transports.
- PostgreSQL, pinned to a supported major/current minor when F3 begins; the
  project follows the upstream
  [five-year major-version policy](https://www.postgresql.org/support/versioning/).
- Linux-compatible containers and Docker Compose for the on-prem topology.

## Interfaces

- Receives telemetry and command traffic from Driver Bridge
- Serves Engineer Console session data and command routing
- Enforces contracts defined in shared packages

## Out Of Scope

- Rich strategy modeling that belongs in shared domain packages
- In-car rendering logic
- Standalone deployment orchestration
- Direct installation into Assetto Corsa or silent strategy/setup application
