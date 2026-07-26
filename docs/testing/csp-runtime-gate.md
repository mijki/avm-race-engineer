# CSP Runtime Gate

## Purpose

This gate protects the AVM PitWall runtime from design drift. Any phase that changes PitWall behavior, PitWall contracts, or PitWall-facing assumptions must satisfy this gate before the phase can exit.

## Gate Criteria

- Supported CSP baseline version is documented for the phase.
- Module-level unit checks cover client logic touched by the phase.
- The generated bundle passes a parser check.
- The generated bundle passes a local symbol-count or size-budget check.
- The generated bundle passes a forbidden-pattern scan, including no runtime `require` or `dofile`.
- Actual callback smoke runs against the bundled client.
- Actual render smoke validates real visible output.
- Unavailable-data handling is validated.
- Malformed-data handling is validated.
- Command handling is validated for client phases that surface commands.
- Acknowledgement handling is validated for client phases that surface acknowledgements.
- Host-side tests are recorded, but they are never accepted as equivalent to real AC/CSP validation.

## Failure Conditions

- A planned feature depends on browser-only, server-only, or unrestricted OS capabilities inside PitWall.
- A command or telemetry change reaches PitWall without explicit compatibility handling.
- Manual validation requires undocumented simulator setup or one-off operator knowledge.
- A client phase ships with host-side green tests but no real Assetto Corsa and CSP validation.

## Required Evidence

- Updated phase document referencing the PitWall impact.
- Matching host-tested, contract, and integration additions where applicable.
- Real Assetto Corsa and CSP validation notes for every client phase.
- Manual validation checklist for CSP-specific behavior.

## Phase Applicability

| Phase | Applies | Notes |
| --- | --- | --- |
| F0 | advisory | defines the gate |
| F1 | required | client shell phase requires real CSP proof |
| F2-F4 | advisory unless PitWall-facing contracts change | bridge, relay, and console phases still record compatibility impact |
| F5-F12 | required | client-participating phases need real AC/CSP validation |

## Related Documents

- [Testing Strategy](./testing-strategy.md)
- [End-to-End Test Matrix](./end-to-end-test-matrix.md)
- [ADR-002: Small Driver Client](../decisions/ADR-002-small-driver-client.md)
