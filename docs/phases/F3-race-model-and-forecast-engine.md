# F3: Race Model and Forecast Engine

## Goal

Implement the initial race model, live calculation engine, and weather-aware
forecast baseline using the raw telemetry path from F2 and the capability
evidence from F3A.

## Dependencies

F2 and F3A.

## Deliverables

Shared race-domain contracts and units; forecast-engine baseline; Bridge-owned
derived current state and short-horizon forecast outputs; Driver Status
Snapshot reduction; Engineer Model Snapshot detail shaping; forecast confidence
and explanation structures; replay fixtures; and deterministic contract
fixtures for calculated and weather-aware forecast states.

## Exclusions

Final relay-side scenario tooling, Engineer Console editing, broad strategy
workspace authoring, opponent private telemetry assumptions, and any claim that
the browser owns authoritative calculations.

## Implementation Sequence

1. Formalize the race-domain boundary, canonical units, identity lineage, and
   calculated and forecast contract ownership.
2. Implement Bridge-owned current-state, fuel, pit-entry, stint, confidence,
   and weather-integration logic using explicit regime and provenance handling.
3. Prove the baseline engine with deterministic calculations, replay fixtures,
   contract validation, and degraded-state scenarios before Relay work expands
   distribution.

## Automated Tests

Unit, property, replay, and contract coverage for fuel and pit-entry
calculations, stint forecasts, confidence degradation, regime separation,
weather integration, duplicate sequence handling, reconnect handling, baseline
versus live preservation, driver snapshot reduction, and engineer detail
expansion.

## Manual Tests

Windows bridge and replay walkthrough covering session start, session change,
missing telemetry, stale telemetry, dry-to-wet transition, wet-to-dry
transition, wrong-identity rejection, and degraded weather-source behavior.

## CSP Runtime Requirements

Required for live weather-source and telemetry-capture assumptions; replay-only
evidence is insufficient for final sign-off.

## Security

Keep production calculation ownership in reusable domain libraries and avoid
spreading authority across Bridge, Relay, Console, and PitWall simultaneously.

## Exit Criteria

The Bridge can produce traceable calculated race state and forecast snapshots
with explicit confidence, uncertainty, and weather provenance, and the outputs
are stable enough for Relay distribution and read-only console rendering.

## Rollback

Reduce the baseline to current-state, fuel, pit-entry, and conservative
short-horizon forecast outputs if broader stint or weather modeling blocks the
phase.

## Risks

Unit ambiguity, regime contamination, false forecast precision, and ownership
drift between Bridge and Relay.

## Complexity

large

## Clean-Thread Recommendation

Yes - begin relay distribution work in a separate thread once the forecast
contracts and Bridge ownership stop changing daily.
