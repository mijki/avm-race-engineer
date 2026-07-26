# Testing Strategy

## Purpose

This document defines the planned quality model for AVM Race Engineer across F0-F12. It is a forward-looking gate plan and does not claim that the listed suites already exist.

## Layer Split

- Host-tested: static analysis, packaging, parsers, unit tests, contract fixtures, and deterministic host-side smoke checks.
- Contract: payload schemas, acknowledgement states, telemetry fixtures, UI state fixtures, and compatibility snapshots.
- Integration: bridge-relay, relay-console, relay-PitWall, persistence, and setup-transfer seams.
- CSP: real Lua bundle checks plus actual Assetto Corsa and CSP runtime validation where client phases require it.
- On-prem: compose or deployment-shape rehearsals, health probes, restart drills, and setup-transfer checks.
- Alpha: supervised real-team rehearsal gates spanning live telemetry, commands, support, and rollback.
- Released: post-alpha release gate placeholder only; public release is explicitly out of scope through F12.

## Driver Lua

- Host-tested: module-level unit checks for rendering helpers, mode selection, sound mapping, acknowledgement state transitions, fallback-state selection, and deterministic bundle order.
- Contract: shell payload fixtures, mock telemetry fixtures, mock alert fixtures, command and acknowledgement fixtures, malformed payload fixtures, unavailable-data fixtures.
- Integration: relay-to-client payload compatibility and idempotent reconnect expectations once networking exists.
- CSP: bundle parser check, generated bundle local symbol count, forbidden API scan, callback smoke, render smoke, unavailable-state smoke, malformed-data smoke, command smoke, acknowledgement smoke.
- On-prem: packaged client install and version check as part of setup transfer.
- Alpha: real CSP validation during practice, qualifying, and endurance sessions.
- Released: reserved for future public-release certification and not active in F0-F12.

## Bridge

- Host-tested: binary/shared-memory mapping, unit conversions, session
  lifecycle, Assetto Corsa start/stop/restart, diagnostics, local recording,
  buffering, reconnect, command delivery, setup staging, and filesystem safety.
- Contract: telemetry envelope fixtures, diagnostics fixtures, local recording metadata fixtures.
- Integration: bridge-to-relay happy path, reconnect path, wrong-session rejection, restart handoff, and offline catch-up where later phases require it.
- CSP: not a substitute for client validation and never counted as equivalent to real client tests.
- On-prem: Windows host setup rehearsal and local service restart checks.
- Alpha: long-run bridge stability under real team usage.
- Released: reserved only as a future post-alpha certification lane.

## Relay

- Host-tested: authentication, authorization, team/session isolation, telemetry
  routing, command idempotency and acknowledgement lifecycle, replay buffers,
  persistence adapters, rate limits, retention jobs, backup hooks, and health
  endpoints.
- Contract: SignalR payloads, auth tokens, room membership states, command acknowledgement states, expiry rules, and audit events.
- Integration: bridge-to-relay, relay-to-console, relay-to-client, server restart recovery, network interruption handling, duplicate suppression, expired command handling, wrong-session handling.
- CSP: relay tests never replace client runtime validation.
- On-prem: Docker Compose or equivalent host-shape rehearsals, health probes, restart, backup, and restore drills.
- Alpha: soak tests, multi-driver sessions, remote engineer sessions, and supervised incident drills.
- Released: future production release gate only.

## Engineer Console

- Host-tested: component and chart-rendering tests for driver online state, car,
  track, session, speed, RPM, gear, fuel, lap, traffic, map, connection loss,
  command creation, acknowledgement updates, setup consent, stale UX, and
  accessibility.
- Contract: dashboard payload fixtures, command catalog fixtures, acknowledgement fixtures, strategy revision fixtures, and consent state fixtures.
- Integration: console-to-relay subscriptions, browser end-to-end workflows,
  reconnect idempotency, stale-state behavior, command issuance, audit history,
  and offline fallback messaging.
- CSP: console validation never replaces real client runtime checks.
- On-prem: local browser plus relay deployment rehearsal with role-based access.
- Alpha: real operator workflows with remote engineer participation.
- Released: future public-release gate only.

## End to End

- Host-tested: reusable scenario harnesses and deterministic fixture orchestration.
- Contract: session, command, setup, strategy, and alpha runbook fixtures.
- Integration: simulated-driver and recorded-telemetry paths, live telemetry,
  read-only dashboard, BOX BOX command, acknowledgement, duplicate/expired/
  wrong-session commands, setup transfer, server restart, network interruption,
  multiple team drivers, three-hour soak, and backup/restore flows.
- CSP: real CSP client participation is mandatory in every client phase from F1 onward; host tests are not equivalent.
- On-prem: full stack deployment, restart, and network interruption rehearsals.
- Alpha: practice, qualifying, endurance, driver swap, multi-driver, and remote engineer flows.
- Released: reserved for a later programme beyond F12.

## Gate Principles

- Prefer the cheapest layer that can catch the defect class, but do not let host-side tests masquerade as CSP runtime proof.
- Add lower-layer coverage whenever an upper-layer failure reveals a missing guard.
- Treat fixtures as versioned assets tied to ADR and phase gates.
- Promote a phase only when its automated and manual checks are repeatable in the environment the phase targets.

## Related Documents

- [CSP Runtime Gate](./csp-runtime-gate.md)
- [End-to-End Test Matrix](./end-to-end-test-matrix.md)
- [Programme Roadmap](../phases/programme-roadmap.md)
