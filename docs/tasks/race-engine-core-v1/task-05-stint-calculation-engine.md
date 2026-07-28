# Task 5 — Implement Stint Calculation Engine

## Required commit

`Implement stint calculation engine`

## Dependencies

Tasks 1–4 must already be committed and validated.

The worktree must be clean before Task 5 begins.

## Purpose

Implement deterministic stint-level calculations using:

- normalized telemetry;
- immutable lap and pit events;
- purpose-specific eligibility decisions;
- explicit configuration and targets.

Task 5 calculates current and historical stint state.

It must not implement future race or pit forecasting, driver recommendations, or a major UI redesign.

## Stint identity and boundaries

Define deterministic stint boundaries.

A new stint may begin because of:

- race/session start;
- leaving the pit lane after a pit visit;
- driver-defined start;
- material refuel associated with a pit cycle;
- tyre compound or set change where detectable and configured;
- explicit restart rules.

Do not treat every reset, invalid lap, or minor discontinuity as a new stint.

Document which events:

- start a new stint;
- end the current stint;
- pause calculation;
- preserve history;
- invalidate only the current incomplete lap.

Assign stable stint IDs and stint-lap numbers.

## Required pace statistics

Maintain separate outputs for:

### Latest completed lap

The most recently completed lap, whether accepted or excluded.

Include:

- lap time;
- official validity;
- classification;
- eligibility result;
- exclusion reason.

### Latest pace-eligible lap

The latest lap accepted for operational pace.

### Official valid average

Arithmetic average of laps accepted for `useForOfficialAverage`.

### Operational stint average

Arithmetic average of laps accepted for `useForPace` under the active policy and compatible regime.

### Representative pace

A robust estimator intended to describe current repeatable pace.

Use an explicit deterministic method, such as:

- median;
- trimmed mean;
- Winsorized mean;
- bounded outlier rejection;
- optional recency weighting.

The selected method must be centralized, versioned, documented, and tested.

Do not label a robust estimator as an arithmetic average.

Use distinct names:

- `OFFICIAL AVG`;
- `STINT AVG`;
- `REP PACE`.

Do not call a statistic `5-LAP AVG` unless it actually uses exactly five accepted laps.

## Pace target comparisons

Support an explicit configured target pace.

Never fabricate a target.

Calculate where available:

- latest accepted versus target;
- operational stint average versus target;
- representative pace versus target;
- latest accepted versus operational stint average;
- latest accepted versus representative pace.

Every delta must identify its reference.

## Required fuel statistics

Maintain separate outputs for:

### Current fuel

Measured live value.

### Latest completed-lap fuel use

Even when excluded for fuel, keep it available for diagnostics with its status.

### Latest fuel-eligible use

Latest lap accepted for `useForFuel`.

### Operational stint fuel average

Arithmetic average over current-stint fuel-eligible laps in the compatible regime.

### Representative fuel use

A robust deterministic estimate for repeatable current consumption.

Do not implement future required-fuel or finish forecasts in Task 5.

### Fuel target comparisons

Support explicit configured target fuel per lap.

Never fabricate it.

Calculate where available:

- latest accepted versus target;
- operational average versus target;
- representative use versus target;
- latest accepted versus operational average;
- latest accepted versus representative use.

## Tyre calculations

Use purpose-eligible tyre samples to calculate current-stint tyre summaries without inventing unsupported physics.

Support where measurements exist:

- current per-wheel temperature;
- current-lap min/max temperature;
- current pressure;
- current wear/life;
- flat-spot state;
- per-wheel trend;
- stint-start versus current change;
- strongest verified tyre-warning input.

Keep unsupported graining/blistering unavailable.

Targets remain explicit configuration.

Do not judge pressure or temperature as good/bad without a configured target or verified rule.

## Stint progress

Calculate:

- current stint ID;
- stint number where determinable;
- current stint lap;
- completed stint laps;
- stint start time;
- elapsed stint time;
- current regime;
- accepted sample counts by purpose;
- latest completed status;
- latest exclusion reasons.

Remaining stint time and remaining stint laps belong to Task 6 forecasts unless they are direct configured limits with no prediction involved.

## Regime separation

Do not combine incompatible operating regimes blindly.

Support separate or tagged statistics for:

- dry;
- wet;
- mixed;
- caution;
- traffic;
- fuel-save;
- push;
- normal operational running.

A regime change must not erase prior samples. It changes which sample set is active.

## Persistence after excluded laps

An excluded or invalid latest lap must not clear:

- official average;
- operational stint average;
- representative pace;
- operational fuel average;
- representative fuel use;
- latest accepted values;
- accepted sample counts;
- confidence;
- freshness.

The latest completed lap remains visible with its exclusion reason.

Only explicit identity or stint boundaries may reset the appropriate state.

## Calculated-value metadata

Use the Task 1 calculated-value envelope.

Every output must carry or expose:

- value;
- unit;
- calculation/model version;
- accepted sample count;
- regime;
- policy;
- freshness;
- confidence;
- unavailable reason;
- bounded accepted/rejected sample references.

## Confidence

Implement deterministic confidence based on explicit factors such as:

- sample count;
- sample freshness;
- regime consistency;
- dispersion;
- missing measurements;
- recent discontinuity.

Do not use generic `LOW CONFIDENCE` without a reason code.

## Determinism

The same events, laps, eligibility decisions, targets, and configuration must produce byte-identical serialized calculation output.

## Tests

Add deterministic tests for at least:

1. stint start;
2. stint end;
3. pit-cycle boundary;
4. refuel boundary;
5. reset that does not start a new stint;
6. stable stint IDs;
7. stint-lap numbering;
8. latest completed lap;
9. latest accepted pace lap;
10. latest accepted fuel lap;
11. official valid average;
12. operational stint average;
13. representative pace estimator;
14. representative estimator outlier handling;
15. pace target deltas;
16. no target means no fabricated delta;
17. latest completed fuel use;
18. latest accepted fuel use;
19. operational fuel average;
20. representative fuel estimator;
21. fuel target deltas;
22. excluded pace lap preserves prior pace statistics;
23. excluded fuel lap preserves prior fuel statistics;
24. the same lap may affect pace and fuel differently;
25. dry/wet regime separation;
26. push/fuel-save regime separation;
27. traffic exclusion from representative pace;
28. sample counts;
29. confidence reasons;
30. per-wheel tyre summaries;
31. unsupported tyre damage remains unavailable;
32. configured versus missing tyre targets;
33. bounded sample references;
34. deterministic replay and serialization;
35. no race/pit forecast engine;
36. no driver recommendation logic;
37. no renderer calculations;
38. no networking;
39. no runtime `require` or `dofile`;
40. deterministic bundle;
41. V1 protection.

## Documentation

Document:

- stint boundaries;
- stint IDs and lap numbering;
- official average;
- operational stint average;
- representative pace;
- fuel statistic equivalents;
- target and delta semantics;
- regime separation;
- excluded-lap persistence;
- tyre calculations;
- confidence;
- traceability;
- what remains for Task 6.

## Task gate

Before committing:

1. Confirm Task 4 is the previous completed task.
2. Run all shared validation.
3. Run stint-boundary tests.
4. Run pace calculation tests.
5. Run fuel calculation tests.
6. Run tyre calculation tests.
7. Run excluded-lap persistence tests.
8. Run deterministic replay twice.
9. Confirm byte-identical calculation output.
10. Run deterministic build twice.
11. Confirm no forecast, recommendation, or UI scope creep.
12. Confirm only Task 5 files changed.

Create exactly one commit:

`Implement stint calculation engine`

After committing:

- confirm the worktree is clean;
- stop for review or continue to Task 6 only under a separate approved orchestration run.
