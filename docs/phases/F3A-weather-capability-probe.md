# F3A: Weather Capability Probe

## Goal

Prove the real CSP and controller weather capabilities, provenance limits, and
local Lua-to-Bridge IPC options before the production forecast engine claims
support for live weather forecasting behavior.

## Dependencies

F2.

## Deliverables

Weather-source capability evidence; controller-behavior evidence; upcoming
condition and transition availability verdicts; authoritative future-schedule
availability verdict; local IPC candidate comparison; dry, wet, transition,
online-server, reconnect, and replay probe captures; and a documented provider
boundary with explicit unknowns.

## Exclusions

Production forecast-engine implementation, final relay fan-out, Engineer
Console authoring, and any claim that future weather is always available.

## Implementation Sequence

1. Inspect the installed CSP SDK and controller-facing runtime surfaces for
   current weather, transition, and schedule evidence.
2. Probe static dry, static wet, dynamic transition, online-server, reconnect,
   and replay scenarios to confirm what is actually exposed.
3. Compare bounded Lua-to-Bridge IPC candidates and document what proof is
   still required before choosing one for implementation.

## Automated Tests

Capability-matrix fixture validation, probe-record normalization checks,
provider-provenance fixture checks, and timeline contract snapshot checks for
current-only, transition-only, authoritative-schedule, estimated, unknown, and
stale states.

## Manual Tests

Real AC/CSP probe sessions covering static dry, static wet, dynamic weather
change, online server, reconnect, replay, and active-controller changes.

## CSP Runtime Requirements

Required; this phase exists to replace assumptions with runtime evidence.

## Security

Keep probe surfaces read-only, bounded, and explicit about any local IPC trust
boundary.

## Exit Criteria

The repository contains enough evidence to say which weather fields are current
measurements, which controller transition hints are available, whether any
authoritative future schedule exists, and which local IPC options remain viable
without overstating capability.

## Rollback

If future-schedule access is unsupported, lock the next phase to current
conditions plus bounded estimated trends rather than fabricating authoritative
forecast behavior.

## Risks

Controller-specific behavior, misleading SDK examples, replay/live divergence,
and unsupported interop assumptions.

## Complexity

medium

## Clean-Thread Recommendation

Yes - keep the live forecast-engine implementation in the next phase isolated
until probe evidence stabilizes.
