# Task 6 — Implement Race and Pit Forecast Engine

## Required commit

`Implement race and pit forecast engine`

## Dependencies

Tasks 1–5 must already be committed and validated.

The worktree must be clean before Task 6 begins.

Where practical, Task 5 calculations should receive a real-CSP sanity check before Task 6 starts.

## Purpose

Implement deterministic race, stint, fuel, and pit forecasts using stable measured telemetry, immutable events, eligibility decisions, stint calculations, learned pit markers, and explicit strategy configuration.

Task 6 produces forecasts and forecast metadata.

It must not redesign the HUD, add networking, or represent forecasts as measured values.

## Forecast principles

Every forecast must:

- identify its model and version;
- identify measured and calculated inputs;
- include sample counts;
- include freshness;
- include confidence;
- include uncertainty where appropriate;
- expose a binding constraint;
- provide a specific unavailable reason;
- avoid unsupported precision;
- remain deterministic for identical inputs.

Do not produce a forecast when required inputs are unavailable or incompatible.

## Stint endpoint forecasts

Calculate where defensible:

- time-limited stint endpoint;
- lap-limited stint endpoint;
- fuel-limited stint endpoint;
- driver-rule-limited endpoint when explicitly configured;
- tyre-rule-limited endpoint only when backed by explicit configuration and trustworthy data;
- planned stint endpoint;
- predicted actual endpoint;
- binding constraint.

Expose:

- remaining stint time;
- remaining stint laps;
- predicted endpoint lap;
- predicted endpoint time;
- limiting factor.

Distinguish direct configured limits from model-based estimates.

## Race/session forecasts

Calculate where defensible:

- estimated race laps remaining;
- estimated race time remaining;
- predicted finish lap for timed races;
- predicted finish session time;
- fuel required to finish;
- expected fuel at finish;
- number of planned stops remaining;
- strategy-plan feasibility.

Do not invent race-control rules.

All endurance rules must come from explicit configuration.

## Fuel forecasts

Use stable Task 5 fuel statistics and explicit targets.

Calculate where defensible:

- estimated laps remaining on current fuel;
- estimated time remaining on current fuel;
- estimated distance remaining;
- required fuel per lap to reach planned pit;
- required fuel per lap to finish;
- expected fuel at planned pit;
- expected fuel at finish;
- margin versus required consumption;
- fuel-save requirement.

Keep separate:

- configured target fuel per lap;
- representative current fuel use;
- required fuel per lap now.

Do not label required fuel as a measured target.

## Pit-entry forecasts

Use Task 3 learned markers and Task 5 pace inputs.

Calculate where defensible:

- forward spline distance to pit entry;
- route distance to pit entry;
- ETA to pit entry;
- expected lap of pit entry;
- predicted fuel at pit entry;
- whether the planned entry point has already been passed;
- pit-entry window state.

Handle spline wraparound correctly.

If the entry marker is unavailable, current live pit-lane state must still work, but predictive entry forecasts remain unavailable with a specific reason.

## Pit-cycle forecasts

Use bounded empirical pit observations where available.

Calculate where defensible:

- expected entry-to-box duration;
- expected box arrival time;
- expected service duration from explicit plan or empirical model;
- expected box departure;
- expected box-to-exit duration;
- expected pit exit;
- expected total pit-lane duration;
- estimated total pit loss;
- expected rejoin lap/time.

Distinguish:

- measured historical pit observations;
- configured planned service;
- forecasted pit-cycle values.

Do not infer future service operations that were not configured.

## Pit confidence

Marker confidence and timing-observation confidence must affect pit forecast confidence.

Examples:

- provisional marker;
- learned marker;
- confirmed marker;
- manual override;
- conflicting marker;
- no recent pit timing;
- drive-through-only evidence;
- normal-stop evidence.

Do not report highly precise pit ETA or pit loss when confidence is low.

## Pace and regime selection

Use the correct Task 5 pace input for the forecast context.

Possible choices include:

- operational stint average;
- representative pace;
- matching dry/wet/fuel-save/push regime;
- explicit strategy target.

Do not combine incompatible regimes.

Document precedence.

## Weather boundary

Current measured weather and measured trends may affect forecasts.

Do not generate authoritative future rain timing without an actual future-weather source.

Allowed:

- current wet/dry regime;
- measured recent trend;
- scenario sensitivity when explicitly labeled.

Not allowed:

- fabricated rain ETA;
- fabricated future condition.

## Uncertainty and precision

Use ranges where the model supports them.

Examples:

- `6.1–6.5 laps`;
- `12:10–12:45`;
- `8.1–8.7 L at entry`.

The Compact view model may later choose a rounded central estimate plus confidence, but the forecast contract must preserve uncertainty.

## Forecast invalidation and supersession

A forecast may become invalid or superseded because of:

- new completed lap;
- regime change;
- pit entry;
- refuel;
- reset or teleport;
- identity change;
- strategy change;
- marker update;
- target change;
- stale source.

Do not mutate old forecast records. Preserve supersession according to the Task 1 contract.

## Recommendations boundary

Task 6 may expose machine-readable forecast states such as:

- on plan;
- fuel margin low;
- pit window open;
- planned entry passed;
- forecast unavailable.

Do not implement final driver-message selection or visual priority. That belongs to Task 7 and later UI work.

## Tests

Add deterministic tests for at least:

1. time-limited stint;
2. lap-limited stint;
3. fuel-limited stint;
4. multiple simultaneous constraints;
5. correct binding constraint;
6. remaining stint time;
7. remaining stint laps;
8. predicted timed-race finish lap;
9. fuel required to planned pit;
10. fuel required to finish;
11. required fuel per lap now;
12. expected fuel at pit;
13. expected fuel at finish;
14. fuel margin;
15. no target does not fabricate target comparison;
16. distance to pit entry;
17. spline wraparound;
18. pit entry already passed;
19. pit marker unavailable;
20. provisional marker confidence;
21. confirmed marker confidence;
22. conflicting marker behavior;
23. manual marker override;
24. entry-to-box estimate;
25. service-duration input;
26. box-to-exit estimate;
27. total pit duration;
28. pit-loss estimate;
29. drive-through evidence not treated as normal-stop service evidence;
30. dry/wet regime selection;
31. fuel-save/push regime selection;
32. stale source invalidates or degrades forecast;
33. reset invalidation;
34. identity-change invalidation;
35. strategy-change supersession;
36. uncertainty and rounding;
37. unavailable reasons;
38. deterministic replay and serialization;
39. no future-weather fabrication;
40. no UI layout changes;
41. no networking;
42. no runtime `require` or `dofile`;
43. deterministic bundle;
44. V1 protection.

## Documentation

Document:

- forecast architecture;
- model precedence;
- stint endpoint forecasts;
- race/session forecasts;
- fuel forecasts;
- pit-entry forecasts;
- pit-cycle forecasts;
- marker and timing confidence;
- regime selection;
- uncertainty;
- supersession;
- weather boundary;
- recommendation boundary;
- unavailable reasons;
- real-CSP validation requirements.

## Task gate

Before committing:

1. Confirm Task 5 is in history and the worktree was clean.
2. Run all shared validation.
3. Run stint forecast tests.
4. Run fuel forecast tests.
5. Run pit-entry tests.
6. Run pit-cycle tests.
7. Run confidence and uncertainty tests.
8. Run invalidation and supersession tests.
9. Run deterministic replay twice.
10. Confirm byte-identical forecast output.
11. Run deterministic build twice.
12. Confirm no future-weather fabrication, networking, or UI scope creep.
13. Confirm only Task 6 files changed.

Create exactly one commit:

`Implement race and pit forecast engine`

After committing:

- confirm the worktree is clean;
- continue to Task 7 only if every Task 6 gate passed.
