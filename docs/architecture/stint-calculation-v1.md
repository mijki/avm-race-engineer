# Stint calculation V1

`tools/stint_calculations.py` calculates current and historical stint state from
completed laps, immutable race events, and purpose-specific eligibility. It is
pure and replayable: inputs are copied, assignments are stable, and the result
is immutable. It does not estimate future race or pit endpoints and does not
issue driver actions.

## Boundaries and identity

The initial stint is `stint:<identity-key>:1`. A material pit-cycle exit,
explicit driver/session boundary, material refuel without a later pit-exit
marker, or configured compound/set change starts the next numbered stint.
Material refuel plus its later pit exit is one pit-cycle boundary. Reset,
teleport, and minor discontinuity evidence do not start a stint; they only
affect lap eligibility. Pause/resume events pause live progress without
deleting history; an incomplete current lap is simply not an accepted sample.
Every assigned completed lap receives a stable
`stint_id`, `stint_number`, and one-based `stint_lap_number`.

## Pace and fuel semantics

`OFFICIAL AVG` is an arithmetic mean of current-stint laps accepted for
`useForOfficialAverage`. `STINT AVG` is an arithmetic mean of current-regime
laps accepted for `useForPace`. `REP PACE` is a separate robust estimator;
V1 uses the versioned median method (`median-v1`). Fuel exposes the equivalent
current, latest-completed, latest-accepted, `STINT AVG`, and representative-use
values in litres per lap. An excluded latest lap stays visible with its reason
and cannot clear earlier accepted statistics.

Configured pace and fuel targets produce signed `measured - target` deltas with
an explicit reference. Missing targets produce no delta and
`TARGET_NOT_CONFIGURED`; no target is inferred from samples.

## Regimes, tyres, and confidence

Dry, wet, mixed, caution, traffic, fuel-save, push, and normal samples remain
tagged. The active regime selects samples without deleting prior regime
history. Traffic is excluded from representative pace by eligibility, while
fuel-save and push samples are usable only in their matching regime.

Tyre output reports measured per-wheel temperature, pressure, wear/life,
flat-spot state, current-lap temperature range, per-wheel trends, and stint
start-to-current changes when available. Graining and blistering remain
explicitly unavailable because no verified measurement is assumed. Tyre target
comparisons are emitted only for configured targets; the engine does not label
measurements good or bad without one.

Every calculated value uses the Task 1 `calculated-value-v1` metadata envelope:
unit, calculation version, bounded accepted/rejected sample references, sample
count, regime, policy, freshness, confidence, uncertainty/reason codes, and an
unavailable reason. Confidence is deterministic from sample count, dispersion,
and freshness.

Task 6 owns remaining stint time/laps as forecasts, required fuel, pit-entry
and pit-cycle forecasts, and any strategy recommendation. Renderer values and
network transport are outside this module.
