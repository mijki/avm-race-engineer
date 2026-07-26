# Race Model And Forecast Engine

Status: DRAFT

This document extends the F0 architecture foundation with the planned race
model, live calculation engine, and weather-aware forecast foundation for AVM
Race Engineer.

Related documents: [System Context](system-context.md),
[Component Boundaries](component-boundaries.md),
[Data Flow](data-flow.md),
[Calculation Data Flow](calculation-data-flow.md),
[Session And Identity Model](session-and-identity-model.md),
[Offline And Reconnect Model](offline-and-reconnect-model.md),
[Strategy Revision v0](../contracts/strategy-revision-v0.md),
[ADR-008](../decisions/ADR-008-live-calculation-ownership.md),
[ADR-009](../decisions/ADR-009-weather-source-provenance.md),
[ADR-010](../decisions/ADR-010-five-minute-weather-timeline.md), and
[ADR-011](../decisions/ADR-011-forecast-confidence-and-explanations.md).

## Purpose

AVM Race Engineer needs a dedicated subsystem that continuously combines:

- immutable baseline strategy assumptions
- current accepted strategy revision
- measured telemetry
- current track position and stint state
- representative recent samples
- weather and track-condition evidence
- engineer-entered assumptions
- pit constraints and traffic context

The subsystem must continuously produce:

- current derived race state
- short-horizon forecasts
- pit-entry and stint forecasts
- next-stint requirements
- strategy recommendations
- confidence, uncertainty, and explanation output

## Architectural Principles

- Keep measured, derived, forecast, and recommendation data in separate layers.
- Keep baseline, accepted, proposed, and forecast state separate.
- Make provenance explicit for every weather and forecast claim.
- Keep authoritative live calculations out of browser and Lua runtimes.
- Share calculation rules through reusable .NET packages rather than
  reimplementing them per surface.
- Prefer degraded or unknown output over false precision.

## Four Calculation Layers

| Layer | What it contains | Examples | Key rule |
| --- | --- | --- | --- |
| measured telemetry | direct observations | fuel level, lap, normalized position, weather sample, pit state | never relabel as forecast |
| derived current state | current state computed from valid measurements and rolling history | rolling fuel burn, current stint progress, distance to pit entry, weather trend | always name sample basis |
| forecast state | predicted future outcomes | fuel at pit entry, predicted stint end, tyre crossover estimate, next-stint fuel | always include uncertainty |
| recommendation state | bounded action output | `ON_PLAN`, `SAVE_FUEL`, `BOX_IN_N_LAPS`, `LOW_CONFIDENCE` | never hide confidence or stale inputs |

The system must not collapse these layers into one generic telemetry object.
Engineer-facing views may show them together, but storage and contracts should
keep them distinct.

## Baseline, Revision, And Forecast Separation

The model must preserve all of the following as distinct records:

- `baseline_plan`: original pre-race strategy intent
- `accepted_revision`: currently accepted strategy revision
- `live_measured_state`: current direct observations
- `derived_current_state`: current rolling interpretation of live data
- `current_forecast`: predictions based on one identified strategy revision
- `proposed_revision`: engineer-generated alternative not yet accepted
- `driver_accepted_revision`: a revision explicitly accepted into active use

Rules:

- Live calculations must never overwrite the baseline plan.
- Every forecast must identify the `strategy_id` and `strategy_revision` it was
  based on.
- A proposed revision remains separate from the accepted revision until an
  explicit acceptance event occurs.
- Driver-facing output should identify whether advice is based on the accepted
  revision or on a pending replan.

## Package Boundaries

### `packages/race-domain`

- Canonical units and immutable model primitives.
- Session, car, driver, track, layout, strategy, stint, and pit-entry
  identity.
- Validation rules, reason codes, freshness, confidence dimensions, and
  explanation primitives.

### `packages/forecast-engine`

- Sample collection, regime classification, rolling models, pit-entry
  projection, fuel and stint forecasts, weather integration, and confidence
  generation.
- Pure reusable calculation logic used by Driver Bridge and optionally by Relay
  Server.

### `packages/strategy-simulation`

- Alternative-plan comparison, scenario analysis, sensitivity analysis, and
  feasibility/risk comparison.
- Not required for the first driver-client shell.

## Runtime Ownership

| Surface | Planned ownership |
| --- | --- |
| Driver Bridge | authoritative low-latency live calculation host, representative-sample management, derived current state, short-horizon forecast, compact driver snapshot publication, offline continuity |
| Relay Server | receives measured and calculated state, validates identity and compatibility, may recompute using the same packages, runs longer-horizon and alternative-plan calculations, records revisions and explanations |
| Engineer Console | visualizes model output, assumptions, confidence, and scenarios; may request recalculation or simulation; does not own authoritative production calculations |
| AVM PitWall | consumes compact driver status snapshots; may keep only a minimal safe fallback for disconnect/stale handling; does not host the full forecast engine |

Authoritative low-latency race-state calculation belongs in Driver Bridge so
offline driver operation continues when relay connectivity drops. Relay Server
may recompute for validation and scenario analysis, but browser code must not
become the production source of truth.

## Canonical Inputs

The live engine should operate on canonical normalized inputs that include at
least:

- session, car, driver, track, and layout identity
- accepted strategy revision and baseline-plan references
- current lap and lap timing state
- normalized track position and track length
- current fuel estimate
- speed and pace samples
- pit-entry reference and pit-lane state
- tyre condition and wear where available
- measured weather and track-condition samples
- traffic and caution-state classification
- operator assumptions such as reserve policy or intended tyre choice

## Fuel And Pit-Entry Calculation Design

The formulas below are conceptual. They describe the expected inputs and
relationships, not locked implementation detail.

| Output | Conceptual design | Required inputs |
| --- | --- | --- |
| current fuel | latest valid measured fuel, possibly smoothed only if the source is noisy | measured fuel, capture time, source validity |
| valid rolling fuel use per lap | robust rolling median/trimmed mean of eligible lap-level samples for the active regime | current and prior fuel deltas, lap completions, regime labels, sample eligibility |
| valid rolling fuel use per kilometre | eligible fuel delta divided by valid covered distance, aggregated over compatible samples | fuel deltas, distance deltas, regime labels |
| fuel use per minute | eligible fuel delta divided by elapsed active time, especially useful in pit lane or caution cases | fuel deltas, elapsed time, pit/caution classification |
| fuel laps remaining | current fuel divided by selected fuel-per-lap model with reserve excluded or shown separately | current fuel, active burn model, reserve policy |
| physical distance remaining | remaining race or stint target distance from current position to target endpoint | current lap, normalized position, track length, target endpoint |
| distance to pit entry | wrapped forward distance from current normalized position to the configured pit-entry point for the active track and layout | normalized position, track length, pit-entry point, route data, layout identity |
| estimated time to pit entry | distance to pit entry divided by representative pace for the current regime, with degraded logic when pace is invalid | distance to pit entry, representative pace, regime |
| predicted fuel at pit entry | current fuel minus projected consumption over distance/time to pit entry, plus uncertainty range | current fuel, distance/time to pit entry, active fuel model, uncertainty |
| predicted fuel at stint end | current fuel minus projected consumption to the planned or inferred stint endpoint | current fuel, target stint endpoint, fuel model, uncertainty |
| expected consumption for next stint | projected distance or laps for the next stint times the chosen regime-specific burn model with weather/traffic adjustments | planned next-stint length, fuel model, weather and traffic assumptions |
| required departure fuel | next-stint expected consumption plus reserve plus start-out-lap and pit-lane allowances | next-stint consumption, reserve policy, pit assumptions |
| required reserve | explicit reserve policy expressed in litres or equivalent modelable rule | strategy assumptions, weather/caution margins |
| fuel to add at next stop | required departure fuel minus predicted fuel at stop arrival, bounded by zero and tank capacity | required departure fuel, predicted arrival fuel, tank capacity |
| projected race-end fuel | current fuel minus projected total remaining consumption under the active accepted revision | current fuel, remaining race distance/time, active forecast |
| fuel delta versus baseline plan | projected or measured fuel minus the baseline-plan reference at the same race point | baseline-plan curve, current state or forecast |
| required saving per lap | fuel deficit divided by remaining green-flag-equivalent laps, adjusted for feasible saving regime | deficit, remaining laps, feasible regime |
| available excess fuel | projected race-end fuel minus required reserve | projected race-end fuel, reserve policy |
| tank-capacity feasibility | departure-fuel requirement compared against tank capacity and refuel constraints | required departure fuel, tank capacity, refuelling rules |
| refuelling-time estimate | fuel to add multiplied by pit-system refuel rate plus fixed stop constraints where relevant | fuel to add, refuel rate, stop assumptions |

### Distance To Pit Entry Rules

Distance-to-pit-entry logic must account for:

- current normalized track position
- active track length
- configured or detected pit-entry reference point
- wraparound at lap end
- whether pit entry has already been passed this lap
- pit-entry route differences where available
- session, track, and layout identity

If the pit-entry reference or route is unknown, the engine should degrade
confidence and avoid pretending that the distance is exact.

## Stint Calculation Design

| Output | Conceptual design | Required inputs |
| --- | --- | --- |
| current stint number | infer from accepted revision plus observed pit-exit history | accepted revision, pit history, lap history |
| current stint identity | stable ID minted when the active stint begins and preserved through snapshots | session, car, strategy revision, stint start event |
| stint progress by lap | laps completed in current stint divided by planned or predicted stint laps | stint start lap, current lap, stint target |
| stint progress by time | elapsed stint time divided by planned or predicted stint duration | stint start time, current time, target duration |
| stint progress by distance | distance since stint start divided by planned or predicted stint distance | stint-start position, current distance, target distance |
| planned stint end | endpoint from accepted strategy revision | accepted revision |
| predicted stint end | updated endpoint from live fuel, pace, tyre, and weather models | accepted revision, current state, forecast models |
| earliest safe pit point | earliest point that preserves reserve and pit-entry reachability | current fuel, reserve, pit-entry model |
| optimal pit point | best current recommendation balancing fuel, pace, tyre, traffic, and weather assumptions | all current models and assumptions |
| latest safe pit point | latest point before reserve, tyre, or feasibility constraints fail | current fuel, degradation, weather, reserve |
| remaining stint duration | predicted stint end time minus current time | predicted stint end, current time |
| remaining stint distance | predicted stint endpoint minus current position | predicted stint end, current position |
| target pace | plan-derived or regime-adjusted target pace for the active stint | accepted revision, weather/traffic assumptions |
| pace delta | measured representative pace minus target pace | rolling pace, target pace |
| rolling pace trend | direction and magnitude of pace change across eligible samples | pace sample set |
| tyre-life estimate | projected remaining useful tyre window from wear, thermal, and pace trends | tyre data, weather, pace trend |
| degradation estimate | trend model over compatible samples by regime | tyre, pace, weather, traffic samples |
| current reserve | projected remaining reserve if pitting now or finishing current target | current fuel, reserve policy, target point |
| projected reserve | reserve at planned or predicted stint end | projected end fuel, reserve policy |
| confidence | structured score from data quality, regime fit, and identity validity | sample set, telemetry completeness, identity |

## Weather Integration

The race model should distinguish weather evidence classes explicitly:

- measured current weather
- measured current track condition
- controller-provided current-to-next transition
- authoritative server/controller schedule
- AVM-derived recent trend
- AVM-estimated future conditions
- unknown future conditions

Rules:

- Do not present a derived trend as an authoritative forecast.
- Do not infer rain probability from rain intensity alone.
- Do not claim five-minute buckets are authoritative unless the source itself
  is authoritative at that horizon.
- Weather effects must influence sample eligibility, fuel and pace modelling,
  tyre-life projection, and forecast confidence.

## Structured Confidence And Explanation Model

Every derived or forecast value should carry:

- `session_id`
- `car_id`
- `driver_id`
- `track_id`
- `layout_id`
- `strategy_id`
- `strategy_revision`
- `stint_id`
- telemetry source
- capture time
- monotonic time
- calculation time
- sequence
- sample set reference
- operating regime
- assumptions
- model version
- freshness
- structured confidence
- uncertainty range
- reason codes

The confidence object should include component scores or explicit verdicts for:

- sample quantity
- sample age
- sample consistency
- telemetry completeness
- regime match
- weather stability
- strategy compatibility
- identity validity

The explanation object should name:

- which inputs were used
- which assumptions were applied
- which samples were excluded and why
- which regime the output was based on
- why confidence was reduced
- whether the value is measured, derived, forecast, estimated, scheduled,
  trending, unknown, stale, or degraded

## Degraded-State Rules

- If telemetry is incomplete, keep the last valid compatible model only while
  freshness policy allows it, then degrade confidence.
- If weather future data is absent, display `UNKNOWN` rather than inventing a
  forecast.
- If strategy or identity mismatches exist, reject the output from the active
  tactical path.
- If compatible representative samples do not exist, emit `WAITING_FOR_VALID_DATA`
  or `LOW_CONFIDENCE` instead of overfitting one noisy sample.

## Not In Scope For This Document

- Exact wire contract field names.
- Exact persistence schema.
- Exact refuelling rules per series.
- Exact CSP local IPC mechanism.
