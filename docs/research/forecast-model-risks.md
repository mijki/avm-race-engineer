# Forecast Model Risks

Status: RESEARCH - DRAFT

This document captures the risks of adding model-based weather forecasting on
top of CSP weather observations before the source lanes are proven.

Related documents:
[weather forecast architecture](../architecture/weather-forecast-architecture.md),
[weather source selection](../architecture/weather-source-selection.md),
[weather capabilities](weather-capabilities.md).

## Core Risk Table

| Risk | Why it matters | Failure mode | Required mitigation |
| --- | --- | --- | --- |
| Transition hint mistaken for schedule | `upcomingType` plus `transition` is narrower than a timeline | UI claims `RAIN IN 10 MIN` without authoritative timing | Keep a separate `Transition hint` lane and ban ETA wording from it |
| Controller-specific semantics drift | WeatherFX controllers can differ and be swapped | Model learns one controller behavior and misreads another | Capture controller identity and CSP build in every probe |
| Build-specific field behavior | SDK presence does not guarantee identical runtime semantics | Same field behaves differently across CSP builds or modes | Version-stamp every sample and probe result |
| Stale current data drives future claims | Reconnects or local hangs can freeze weather fields | Model projects outdated conditions as live future weather | Enforce freshness ceilings and explicit stale labels |
| Overfitting to track wetness or grip lag | Grip and wetness may lag visible rain start/stop | Forecast timing is anchored to the wrong signal | Probe lag and treat wetness/grip as separate from rainfall onset |
| Authority collision between local and relay views | PitWall, Bridge, and relay might see different local states briefly | Driver and engineer see conflicting forecast language | Driver Bridge remains the low-latency calculation authority; Relay validates identity and is canonical only for the accepted shared distribution view and preserved provenance |
| False certainty from single-source modeling | One local source can miss server-side or controller-side intent | Forecast appears precise while missing authoritative future inputs | Preserve `Unknown` when no schedule source exists |
| Mutation path confusion | Controller setters exist, but readback authority is unproven | Team assumes writable weather implies readable schedule | Keep write surfaces out of read-source selection until proven |

## Practical Guardrails

- Do not add a forecast model until current weather and transition-hint probes
  are complete.
- Do not merge estimated output into the same fields used for direct
  observations.
- Do not display estimated future weather without uncertainty or confidence.
- Do not let forecast output suppress a proven authoritative schedule later.

## Current Recommendation

Model-based forecasting is architecturally possible, but should remain deferred
until AVM has:

- stable current-field probes;
- a clear verdict on transition-hint semantics; and
- a proven answer for where authoritative future schedules would come from, if
  they exist at all.
