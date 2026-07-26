# F4: Relay Server

## Goal

Stand up the planned ASP.NET Core and SignalR relay server for authenticated
live-session fan-out of raw, calculated, and forecast state.

## Dependencies

F3.

## Deliverables

ASP.NET Core service; SignalR transport; authentication foundation; session
rooms; health endpoints; Docker Compose deployment; downstream contracts;
compatibility and identity validation for bridge-calculated state; and
weather-provenance-preserving distribution, with no Engineer Console editing.

## Exclusions

Engineer Console editing, rich strategy tools, scenario authoring, and command
catalog authoring.

## Implementation Sequence

1. Define authenticated session rooms and relay health boundaries.
2. Connect bridge ingress for raw, calculated, and forecast state to SignalR
   fan-out and downstream subscriptions.
3. Prove Docker Compose, compatibility validation, and health behavior without
   introducing engineer-side editing features.

## Automated Tests

Auth token checks, session-room tests, health endpoint tests, bridge-to-relay
integration, compatibility-validation tests, provenance-preservation tests,
and reconnect-path scenarios.

## Manual Tests

Relay smoke covering authenticated connect, room membership, health visibility,
forecast delivery, and compose startup.

## CSP Runtime Requirements

Advisory unless relay contract changes affect the driver shell payload shape.

## Security

Apply deny-by-default thinking to client presence and session access from the
outset.

## Exit Criteria

The relay authenticates clients, manages session rooms, exposes health,
preserves forecast lineage and weather provenance, and supports the first
read-only Engineer Console phase.

## Rollback

Narrow relay scope to a single-session model if multiplexing creates avoidable
risk.

## Risks

Auth drift, room-identity bugs, compose complexity, and premature console
feature bleed.

## Complexity

large

## Clean-Thread Recommendation

Yes - begin Engineer Console work in a separate thread once relay contracts
stop changing daily.
