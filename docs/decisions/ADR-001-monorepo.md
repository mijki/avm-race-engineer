# ADR-001: Monorepo

- Status: Proposed
- Date: 2026-07-26
- Related: [Programme Roadmap](../phases/programme-roadmap.md), [F0](../phases/F0-foundation.md)

## Context

AVM Race Engineer plans four tightly related surfaces: AVM PitWall, Driver Bridge, Relay Server, and Engineer Console. The early programme needs fast coordination between shared contracts, test fixtures, and release gates without pretending the components are a single deployable binary.

## Decision

Keep all planned surfaces in one monorepo during F0-F12. Shared schemas, fixtures, ADRs, and phase gates live beside component code, but runtime boundaries remain explicit and testable.

## Consequences

- Cross-component changes can land atomically when contracts move.
- Testing and release gates can reference one source of truth.
- The repo must resist accidental coupling by keeping component ownership and interfaces explicit.

## Open Questions

- Whether packaging should stay fully repo-local after the closed team alpha.
