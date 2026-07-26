# ADR-002: Small Driver Client

- Status: Proposed
- Date: 2026-07-26
- Related: [F1](../phases/F1-driver-client-shell.md), [F5](../phases/F5-end-to-end-vertical-slice.md), [CSP Runtime Gate](../testing/csp-runtime-gate.md)

## Context

PitWall runs in CSP Lua, the most constrained runtime in the planned stack. If the programme starts with a feature-heavy driver client, CSP limits will be discovered too late and the rest of the system may overfit to capabilities the in-car surface cannot support.

## Decision

The first PitWall milestone is intentionally small: driver-visible shell, status display, and the minimum interaction needed to validate runtime viability. Rich workflows stay off the client until the relay and web path are stable.

## Consequences

- CSP validation happens earlier and with lower risk.
- The in-car surface stays legible and lightweight.
- More advanced driver interaction must justify its runtime cost explicitly.

## Open Questions

- Which fallback states should be mandatory in the first shell beyond disconnected and stale-data handling.
