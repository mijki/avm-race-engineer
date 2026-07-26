# Forecast Engine Test Strategy

## Purpose

This document defines the planned verification model for the shared race-domain,
forecast-engine, and strategy-facing calculation contracts introduced by the
race and weather forecast foundation amendment. It is forward-looking and does
not claim that the listed suites already exist.

## Quality Objectives

- Preserve the four data layers as distinct structures: measured telemetry,
  derived current state, forecast state, and recommendation state.
- Preserve the original baseline plan, current accepted strategy revision, live
  measured state, current forecast, proposed revision, and accepted revision as
  separately traceable records.
- Keep every calculation attributable to identity, strategy revision, sample
  set, operating regime, model version, confidence inputs, and explanation
  reason codes.
- Keep Driver Status Snapshot reduction intentionally compact while Engineer
  Model Snapshot expansion remains explainable and auditable.

## Test Levels

| Level | Primary Purpose | Typical Artifacts |
| --- | --- | --- |
| Unit | Deterministic formulas, unit conversions, eligibility rules, and reason-code branching | pure calculation tests, unit wrappers, operating-regime rules |
| Property | Invariants that should hold across many inputs | monotonic fuel depletion, confidence bounds, wraparound calculations |
| Replay | Recorded telemetry and weather timelines replayed through the engine | bridge recordings, deterministic scenario fixtures |
| Contract | Schema and fixture compatibility for calculated and forecast payloads | JSON fixtures, schema validation, snapshot goldens |
| Integration | Bridge, relay, and console seams using the shared contracts | bridge-to-relay, relay-to-console, relay-to-PitWall |
| CSP Runtime | Validation that live data collection assumptions match real AC/CSP behavior | probe sessions, current-field captures, degraded-source checks |
| On-Prem | Deployment-shape rehearsals under restart and reconnect conditions | relay restart drills, local service restart, host clocks |
| Closed-Team Alpha | Supervised live-team rehearsal under race-like conditions | practice, qualifying, endurance, and reconnect drills |

## Coverage Matrix

| Coverage Area | What Must Hold | Minimum Levels |
| --- | --- | --- |
| Dimensional units | No ambiguity across litres, metres, kilometres, seconds, milliseconds, litres per lap, litres per kilometre, litres per minute, metres per second, and degrees Celsius | unit, property, contract |
| Identity and ownership | session, car, driver, track, layout, strategy, and stint identity survive every calculation and projection | unit, contract, integration |
| Baseline versus live preservation | baseline plan is never silently overwritten by live calculations or proposed revisions | unit, replay, contract |
| Fuel and pit-entry calculations | distance-to-pit-entry, time-to-pit-entry, predicted fuel at pit entry, required reserve, fuel to add, and race-end projections remain explainable | unit, property, replay |
| Stint calculations | current stint, pit windows, projected reserve, tyre life, and target-pace deltas remain tied to the active revision and regime | unit, replay, integration |
| Sample selection | incompatible regimes are not merged into one average and outliers are either excluded or explicitly down-weighted | unit, property, replay |
| Weather integration | dry, wet, mixed, and transition conditions alter sample eligibility, pace, fuel, tyre, and confidence paths intentionally | unit, replay, CSP runtime |
| Confidence and explanation | confidence dimensions degrade for sample count, age, completeness, regime mismatch, identity mismatch, and weather instability | unit, property, contract |
| Snapshot shaping | Driver Status Snapshot stays compact while Engineer Model Snapshot preserves detailed assumptions, uncertainty, and reasons | contract, integration |
| Sequence and reconnect safety | duplicate sequences, reconnects, and session changes do not corrupt active model state | replay, integration, on-prem |

## Scenario Catalogue

| Scenario | Expectation | Primary Levels |
| --- | --- | --- |
| Deterministic calculations | fixed fixtures always produce the same derived and forecast values | unit, replay, contract |
| Missing telemetry | outputs degrade to waiting or low-confidence states with explicit reasons | unit, replay, integration |
| Stale telemetry | freshness penalties reduce confidence and can suppress recommendations | unit, replay, integration |
| Session change | prior session state is discarded or archived without contaminating the new model | unit, replay, integration |
| Strategy revision change | forecast lineage flips to the accepted revision without losing baseline comparison | unit, replay, contract |
| Wrong-car data | foreign-car records are rejected before they affect samples or forecasts | unit, integration |
| Wrong-track data | mismatched track or layout identity invalidates pit-entry and pace assumptions | unit, integration |
| Pit-entry wraparound | distance-to-pit-entry handles lap wrap correctly | unit, property |
| Pit-entry already passed | next legal pit-entry point is projected instead of returning a negative distance | unit, property |
| Too few samples | recommendation layer falls back to waiting or low-confidence instead of false precision | unit, replay |
| Outliers | spikes from incidents, pit lane, or corrupted samples do not distort rolling models silently | unit, property, replay |
| Incompatible regimes | dry, wet, caution, push, save, traffic, pit, and damaged running remain separated | unit, replay |
| Dry-to-wet transition | pace, fuel, tyre, and confidence paths adapt as sources move into mixed conditions | replay, contract, CSP runtime |
| Wet-to-dry transition | crossover and drying assumptions degrade gracefully as the track improves | replay, contract, CSP runtime |
| Confidence degradation | horizon, source age, and volatility reduce confidence in structured, explainable ways | unit, property, replay |
| Forecast horizon | short-horizon and stint-horizon outputs use the correct degradation rules | unit, replay |
| Duplicate sequence | repeated telemetry or forecast sequence numbers do not duplicate state transitions | unit, integration |
| Reconnect | bridge and relay restarts preserve lineage without inventing continuity | replay, integration, on-prem |
| Explanation reason codes | recommendation and degraded states emit stable reason codes | unit, contract |
| Driver snapshot reduction | driver payload keeps only compact actionable outputs and provenance-safe summaries | contract, integration |
| Engineer detail expansion | engineer payload exposes assumptions, samples, ranges, and reason codes without duplicating ownership ambiguously | contract, integration |

## Phase Expectations

| Phase | Forecast and Testing Requirement |
| --- | --- |
| F1 | Deterministic mock fixtures must cover calculated race state, current stint forecast, fuel delta, predicted fuel at pit entry, next-stint requirement, forecast confidence, current weather, five-minute weather timeline, scheduled weather, estimated weather, unknown weather, stale weather, weather alert, and tyre crossover indication. |
| F2 | Raw telemetry and identity capture must be rich enough to feed the forecast engine later, even though F2 does not yet implement the production engine. |
| F3A | Capability probes must prove or reject weather-source and IPC assumptions before the live engine claims support for those paths. |
| F3 | Unit, property, replay, and contract suites become mandatory for the initial live calculation engine. |
| F4 | Relay integration must preserve calculated-state ownership, provenance, confidence, and revision lineage. |
| F5 | Read-only Engineer Console validation must confirm detailed forecast and weather states render correctly, including empty, stale, degraded, and unknown conditions. |
| F6 | The first end-to-end slice must prove compact driver reduction and engineer-detail expansion against the same upstream calculations. |

## Related Documents

- [Weather Forecast Test Matrix](./weather-forecast-test-matrix.md)
- [F3A: Weather Capability Probe](../phases/F3A-weather-capability-probe.md)
- [F3: Race Model and Forecast Engine](../phases/F3-race-model-and-forecast-engine.md)
