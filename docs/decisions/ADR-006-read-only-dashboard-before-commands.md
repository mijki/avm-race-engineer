# ADR-006: Read-Only Dashboard Before Commands

- Status: Proposed
- Date: 2026-07-26
- Related: [F4](../phases/F4-engineer-web.md), [F5](../phases/F5-end-to-end-vertical-slice.md), [F8](../phases/F8-engineer-commands.md)

## Context

Operator commands are higher risk than telemetry viewing because mistakes directly affect the driver experience. The programme needs live visibility before it adds command issuance.

## Decision

Engineer Console stays read-only through the first dashboard phase. Commands are deferred until the telemetry, relay, and PitWall path is observable and stable enough to support acknowledgement and auditability, then introduced in the narrow F5 vertical slice.

## Consequences

- The first dashboard milestone focuses on observability instead of control risk.
- Command semantics can be designed after operator workflows are better understood.
- Some stakeholder expectations must be managed because the dashboard will intentionally lag command capability.

## Open Questions

- Which operator actions, if any, count as harmless enough to stay in the read-only phase.
