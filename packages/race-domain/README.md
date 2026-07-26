# Race Domain

Status: `Proposed`

`packages/race-domain` is the planned shared .NET package for immutable race
model types, typed units, validation rules, and explanation primitives used by
the live calculation and forecasting stack.

It is the vocabulary layer, not a runtime host. Driver Bridge, Relay Server,
and offline tools may all consume it. AVM PitWall and Engineer Console should
consume contracts derived from it rather than reimplementing race math in Lua
or browser code.

## Planned Responsibilities

- Define canonical typed units for fuel, distance, pace, time, temperature,
  wetness, water, and wind.
- Define stable identities for session, car, driver, track, layout, strategy,
  strategy revision, stint, and pit-entry reference.
- Define race-length, lap-progress, distance-progress, fuel, pace, tyre,
  weather-regime, and track-condition-regime value models.
- Define immutable baseline-plan, accepted-revision, proposed-revision, and
  forecast-input models, plus typed calculation inputs and outputs.
- Define the four calculation layers as distinct model families:
  measured telemetry, derived current state, forecast state, and recommendation
  state.
- Define shared validation rules, freshness metadata, confidence dimensions,
  uncertainty ranges, and calculation reason codes.
- Define contract-facing reduction types such as driver-safe recommendation
  summaries and engineer-detailed explanation records.

## Canonical Units

| Quantity | Canonical unit | Notes |
| --- | --- | --- |
| fuel volume | litres | Stored as volume, not inferred "laps" |
| distance | metres | Canonical geometry and position distance |
| distance summary | kilometres | Explicitly converted from metres for fuel-per-kilometre models and display |
| track length | metres | Bound to `track_id` and `layout_id` |
| duration | seconds | Continuous forecast, pit-loss, and refuelling calculations |
| event and monotonic time | milliseconds | Capture ordering, freshness, and precise elapsed-time evidence |
| pace / lap time | milliseconds | Keep raw lap timing exact |
| fuel burn by lap | litres per lap | Regime-specific model output |
| fuel burn by distance | litres per kilometre | Useful across partial laps |
| fuel burn by time | litres per minute | Useful in pit lane and caution cases |
| speed | metres per second | UI may render km/h separately |
| temperature | degrees Celsius | Ambient, road, tyre, brake where applicable |
| rain intensity | 0-1 normalized | Intensity is not probability |
| track wetness | 0-1 normalized | Direct or derived source must be stated |
| standing water | 0-1 normalized | Direct or derived source must be stated |
| humidity | 0-1 normalized | `1.0` represents 100 percent relative humidity |
| atmospheric pressure | pascals | Preserve the documented source unit; UI may convert |
| wind speed | metres per second | Direction remains degrees |
| wind direction | degrees | Normalized to the documented 0–360 convention |

## Core Model Groups

- `identity`: session, driver-host, driver, car, team, track, layout.
- `planning`: baseline plan, accepted strategy revision, proposed strategy
  revision, stint plan, pit window, reserve policy.
- `telemetry`: measured values with capture time, monotonic time, source,
  freshness, and sequence.
- `derived-state`: rolling current-state outputs backed by sample sets.
- `forecast`: short-horizon, stint, pit-entry, and next-stint predictions with
  uncertainty.
- `recommendation`: bounded action outputs such as `ON_PLAN`, `SAVE_FUEL`,
  `BOX_THIS_LAP`, and `LOW_CONFIDENCE`.
- `explanations`: reason codes, confidence dimensions, assumption records,
  stale/degraded markers, and compatibility failures.

## Boundary Rules

- `race-domain` should stay pure and deterministic. No network, file, clock,
  UI, or simulator SDK side effects belong here.
- The package should not own sample storage policy, rolling-window policy, or
  runtime event orchestration. Those belong in `forecast-engine`.
- The package should not own multi-scenario ranking or plan comparison. That
  belongs in `strategy-simulation`.
- Strategy revisions must remain explicit. Live measured state and forecasts
  must never overwrite the original baseline plan.

## Required Invariants

- No field with ambiguous units.
- No forecast without strategy identity and revision reference.
- No active-state reuse across incompatible session, track, layout, or car
  identities.
- No recommendation without provenance to the measured/derived/forecast inputs
  that produced it.
- No confidence label without structured component detail behind it.

## Planned Consumers

- Driver Bridge for authoritative low-latency calculation inputs and outputs.
- Relay Server for validation, replay, optional recomputation, persistence, and
  scenario evaluation.
- Contract packages for schema generation and fixture alignment.
- Offline replay and test harnesses for deterministic verification.

## Out Of Scope

- Assetto Corsa shared-memory reading.
- CSP Lua interop or local IPC.
- SignalR, HTTP, browser state, or UI rendering.
- Database persistence and audit storage.
