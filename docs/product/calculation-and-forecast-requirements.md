# Calculation And Forecast Requirements

Status: `Planned`

## Purpose

AVM Race Engineer needs a dedicated race-model and live-calculation foundation
that combines baseline strategy assumptions, accepted strategy revisions, live
measured telemetry, track position, current stint state, representative recent
samples, weather and track conditions, engineer inputs, traffic, and pit
constraints into trustworthy tactical outputs.

This foundation exists to serve both:

- AVM PitWall, which needs compact actionable guidance while driving
- Engineer Console, which needs detailed model state, comparisons, confidence,
  assumptions, and explanations

This document defines product requirements only. It does not authorize
production-code implementation in the current phase.

## Required Output Classes

The product must keep these calculation layers separate:

1. `Measured telemetry`
2. `Derived current state`
3. `Forecast state`
4. `Recommendation state`

They must not collapse into one generic telemetry blob because each layer has a
different freshness, confidence, and actionability profile.

### 1. Measured Telemetry

Direct observations may include:

- fuel level;
- lap, sector, and normalized track position;
- world position where available;
- current lap time and recent lap times;
- tyre temperatures, pressures, and wear;
- ambient and road temperature;
- rain intensity, track wetness, and standing water where available;
- pit state;
- traffic context supported by the active source.

### 2. Derived Current State

Calculated from current and recent measured values:

- fuel use per lap, kilometre, and minute;
- representative rolling pace;
- traffic-adjusted pace where support exists;
- current stint progress by lap, time, and distance;
- fuel delta against accepted plan;
- pace delta against target;
- tyre degradation trend;
- distance and estimated time to pit entry;
- fuel laps remaining;
- current weather and track trend classification.

### 3. Forecast State

Predictions with explicit uncertainty:

- expected fuel at pit entry;
- expected fuel at stint end;
- next-stint fuel requirement;
- earliest, target, and latest safe pit point;
- projected tyre life and pace degradation;
- expected weather impact on pace, tyre, and pit timing;
- projected reserve and race-completion feasibility.

### 4. Recommendation State

Compact tactical outputs may include:

- `ON PLAN`
- `SAVE FUEL`
- `PUSH`
- `TARGET PACE`
- `BOX THIS LAP`
- `BOX IN N LAPS`
- `STAY OUT`
- `EXTEND`
- `SHORTEN STINT`
- `CHANGE TYRES`
- `DOUBLE-STINT TYRES`
- `REPLAN REQUIRED`
- `WAITING FOR VALID DATA`
- `LOW CONFIDENCE`

Recommendations must remain explicitly downstream of measured and forecast
state. They must not masquerade as raw telemetry.

## Baseline, Measured, Forecast, Proposed, And Accepted

The model must preserve these views separately:

- `Baseline`: the original pre-race plan
- `Measured`: current trusted observed state
- `Forecast`: the current model output derived from measured state and one
  identified strategy revision
- `Proposed`: an engineer-proposed revision that is not yet accepted
- `Accepted`: the currently accepted strategy revision

Live calculations must never silently overwrite the baseline plan. Engineer
surfaces must support direct comparison across baseline, measured, forecast,
proposed, and accepted states. Every forecast must identify the strategy
revision it is based on.

## Driver Versus Engineer Presentation

### AVM PitWall

The driver surface must show only compact, immediately useful outputs:

- current stint state;
- fuel state and simple delta framing;
- projected pit-window framing suitable for glance use;
- current weather or track condition;
- next meaningful weather change when confidence and provenance justify it;
- current strategy implication;
- engineer instruction.

The driver surface must not expose dense model charts, sample tables, or
side-by-side scenario matrices while driving.

### Engineer Console

The engineer surface must expose the detailed model:

- baseline versus measured versus forecast versus proposed versus accepted;
- forecast timeline and validity window;
- current assumptions and operating regime;
- sample quality and freshness;
- confidence components and uncertainty ranges;
- explanation and reason-code detail;
- degraded or blocked calculations;
- revision history and operator approval points.

## Confidence And Uncertainty

Every material calculated or forecast value must carry:

- freshness;
- provenance;
- confidence dimensions;
- uncertainty or range framing;
- explanation or reason codes where tactical decisions depend on the value.

The product must not reduce confidence to a single opaque badge in storage or
transport contracts. UI surfaces may collapse the detailed object into a simple
summary, but the underlying model must preserve why confidence is high, medium,
or low.

## Regime Separation

The calculation model must keep incompatible operating regimes separate where
possible, including:

- normal green running;
- traffic-affected running;
- fuel-saving running;
- push running;
- wet running;
- mixed conditions;
- pit in-lap, pit lane, and pit out-lap;
- incomplete or degraded telemetry.

Dry, wet, mixed, caution, and traffic-affected samples must not be blended into
one undifferentiated average.

## Driver-Safe Degraded Behavior

When calculation trust is reduced, the product must degrade explicitly:

- missing or incompatible inputs produce `WAITING FOR VALID DATA`, not invented
  numbers;
- stale calculated values remain stamped stale;
- low-confidence tactical recommendations remain visibly low confidence;
- risky derived recommendations are suppressed when their inputs are stale or
  contradictory.

## Product Boundary Rules

- Driver Bridge is the expected owner of low-latency live calculation and
  driver-status snapshot publication.
- Relay Server may validate, persist, and expand scenario analysis, but browser
  views do not become authoritative by rendering a calculation.
- Engineer Console visualizes and compares model state; it does not own the
  authoritative production calculation path.
- AVM PitWall consumes compact outputs and may retain only minimal safe fallback
  behavior for disconnects.

## Non-Negotiable Rules

- Preserve baseline, measured, forecast, proposed, and accepted state as
  distinct concepts.
- Keep measured, derived, forecast, and recommendation data layers separate.
- Carry provenance, freshness, confidence, and uncertainty with tactical model
  outputs.
- Prefer explicit degraded or unknown states over false precision.
