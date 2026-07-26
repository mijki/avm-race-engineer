# ADR-007: Explicit Command Acknowledgement

- Status: Proposed
- Date: 2026-07-26
- Related: [F8](../phases/F8-engineer-commands.md), [F12](../phases/F12-closed-team-alpha.md), [End-to-End Test Matrix](../testing/end-to-end-test-matrix.md)

## Context

Command paths across Engineer Console, Relay Server, and AVM PitWall are
unreliable unless the system can distinguish sent, received, applied, timed
out, and duplicated actions. Silent command handling is not acceptable for
race operations.

## Decision

All planned engineer-to-driver commands require explicit acknowledgement semantics. The command model must support timeout, retry policy, duplicate suppression, and audit-friendly state transitions before alpha exit.

## Consequences

- Engineer command work can be verified against explicit states.
- Replay and incident analysis become materially easier.
- The command surface will ship slower than a fire-and-forget model, but with lower operational risk.

## Open Questions

- Whether acknowledgement states should be normalized across all command types or allow limited subtype-specific detail.
