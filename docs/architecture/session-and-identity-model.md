# AVM Race Engineer Session And Identity Model

Status: DRAFT

This document proposes the F0 model for session authority, operator identity,
and driver-host identity across AVM Race Engineer.

Related documents: [Component Boundaries](component-boundaries.md),
[Data Flow](data-flow.md), [Offline And Reconnect Model](offline-and-reconnect-model.md),
[Security Boundaries](../operations/security-boundaries.md),
[Support And Diagnostics](../operations/support-and-diagnostics.md).

## Proposed Identity Domains

- `driver-host identity`: the bridge-side identity representing a specific edge
  machine in a race session.
- `operator identity`: the authenticated human actor using `Engineer Console`.
- `session identity`: the active race or stint context against which telemetry,
  commands, and audit events are correlated.
- `command identity`: the unique instance identifier for a driver-visible
  action, including expiry and acknowledgement state.

## Proposed Identity Relationships

```mermaid
flowchart LR
  Operator["Operator Identity"] --> Session["Race Session"]
  DriverHost["Driver Host Identity"] --> Session
  Session --> Command["Command Identity"]
  Session --> Telemetry["Telemetry Stream Identity"]
  Command --> Ack["Acknowledgement Identity"]
```

## Proposed Authority Rules

- The relay should be the authority for binding operator actions to the active
  race session.
- The relay should validate that a bridge connection is associated with the
  intended driver-host identity before accepting session data as authoritative.
- Command issuance should always be attributable to one operator identity, even
  when multiple browser tabs are active.
- The bridge should correlate acknowledgements to existing command identities
  rather than minting independent driver-visible command state.

## Proposed Session Lifecycle

```mermaid
stateDiagram-v2
  [*] --> absent
  absent --> detecting
  detecting --> active
  detecting --> identity_mismatch
  identity_mismatch --> detecting
  active --> ending
  active --> identity_mismatch
  ending --> closed
  closed --> [*]
```

In `active`, operator and driver-host identities attach with scoped roles and
all telemetry, command, and audit events correlate to the relay-side session
identity. `ending` closes command issuance before retention begins.

## Proposed Identity Risks

| Risk | Why it matters | Proposed control direction |
| --- | --- | --- |
| shared generic edge credentials | weak attribution and revocation | distinct driver-host identity per edge machine |
| unaudited operator actions | no reliable post-incident review | relay-side audit with operator correlation |
| stale browser tab acting on old session | commands could target wrong context | explicit active-session validation before dispatch |
| reconnect under ambiguous host identity | telemetry trust collapse | reject or quarantine until identity is re-established |

## Open F0 Questions

- Whether driver-host identity is long-lived across events or race-weekend
  scoped.
- Whether operators need separate identities for read-only versus command
  issuance roles from day one.
