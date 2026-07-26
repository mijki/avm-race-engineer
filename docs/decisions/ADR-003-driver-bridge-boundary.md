# ADR-003: Driver Bridge Boundary

- Status: Proposed
- Date: 2026-07-26
- Related: [F2](../phases/F2-driver-bridge-poc.md), [F3](../phases/F3-relay-server.md)

## Context

Telemetry capture needs Windows-side access and local session awareness that the other surfaces do not share. Without a hard boundary, simulator integration details will leak into relay and web logic.

## Decision

Treat Driver Bridge as the sole planned Windows-side telemetry collector and
uplink boundary. It owns local capture, lightweight buffering, and relay
handoff. Relay Server, Engineer Console, and AVM PitWall consume bridge
contracts rather than simulator-specific APIs.

## Consequences

- Simulator-specific changes stay localized.
- Bridge fixtures become the stable source for relay and E2E tests.
- Local failure handling can evolve without rewriting downstream components.

## Open Questions

- How much local buffering should remain in scope before persistence arrives later in the roadmap.
