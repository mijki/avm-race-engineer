# Task 7 — Expose Stable Driver Status View Model

## Required commit

`Expose stable driver status view model`

## Dependencies

Tasks 1–6 must already be committed and validated.

The worktree must be clean before Task 7 begins.

## Purpose

Expose a stable driver-facing view model built from:

- normalized telemetry;
- immutable events;
- lap eligibility;
- stint calculations;
- race and pit forecasts;
- explicit targets and configuration.

Task 7 defines semantics, formatting, priority, availability, and mode allocation.

It must not calculate race values inside the renderer and must not perform a full visual redesign or dynamic-asset pass.

## View-model ownership

The view model may:

- select values;
- select status labels;
- select semantic severity;
- format units and times;
- suppress unavailable comparison rows;
- choose Compact, Expanded, and Garage field allocation;
- provide traceability and reason codes;
- provide stable IDs for rendered cells.

The view model must not:

- call raw CSP APIs;
- reclassify laps;
- calculate averages;
- calculate forecasts;
- infer pit markers;
- fabricate targets;
- fabricate unsupported telemetry.

## Common field contract

Each driver-facing field should expose:

- stable field ID;
- label;
- raw value where appropriate;
- formatted value;
- unit;
- availability;
- semantic state;
- severity;
- confidence;
- freshness;
- source layer;
- comparison reference;
- unavailable reason;
- supporting detail;
- trace ID or calculation/forecast ID.

Semantic state must be independent from presentation color.

## Time formatting

Complete lap times:

- use `m:ss.mmm`;
- use `h:mm:ss.mmm` when required;
- do not show full lap times as raw seconds.

Examples:

- `78.010 s` → `1:18.010`
- `522.322 s` → `8:42.322`

Deltas:

- `+2.322 s`;
- `−0.452 s`;
- support minute-scale deltas where required.

Every delta must identify its reference.

Do not expose generic unlabeled `DELTA`.

## Pace view model

Keep separate:

- configured target pace;
- latest completed lap;
- latest pace-eligible lap;
- official valid average;
- operational stint average;
- representative pace;
- latest accepted versus target;
- operational average versus target;
- representative pace versus target;
- latest accepted versus average;
- sample counts;
- latest exclusion reason;
- confidence;
- freshness.

### Compact allocation

When a target exists, provide a concise structure capable of rendering:

- `TARGET 8:40.000`
- `LAST 8:41.870 +1.870`
- `STINT AVG 8:42.322 +2.322`

Both visible deltas should default to versus target.

When no target exists, provide:

- latest accepted;
- operational stint average;
- latest versus average where useful;
- at most one concise `Target not set` state.

Do not repeat `Not configured` across multiple cells.

### Expanded allocation

May include:

- representative pace;
- official average;
- last versus average;
- average versus target;
- valid and included sample counts;
- latest completed excluded lap;
- exclusion reason;
- confidence and freshness.

## Fuel view model

Keep separate:

- current fuel;
- configured target fuel/lap;
- required fuel/lap now;
- latest completed-lap use;
- latest fuel-eligible use;
- operational stint average;
- representative fuel use;
- range in laps;
- range in time;
- predicted fuel at pit;
- predicted fuel at finish;
- target and required deltas;
- confidence;
- freshness.

### Compact allocation

Prioritize:

- current fuel;
- range;
- latest accepted use;
- stint average;
- required fuel/lap now when available;
- target only when configured;
- predicted fuel at pit only when calibrated and forecastable.

Do not repeat missing-target or calibration text.

### Expanded allocation

May include:

- configured target;
- required now;
- representative use;
- latest versus target;
- average versus target;
- expected fuel at pit/finish;
- margins;
- sample counts;
- confidence;
- unavailable reasons.

## Stint/session strip model

Expose an always-available top-priority structure for later rendering.

Include where defensible:

- stint number;
- current stint lap;
- completed stint laps;
- current race lap;
- race lap limit;
- stint elapsed time;
- predicted remaining stint time;
- predicted remaining stint laps;
- session remaining time or laps;
- position where reliable;
- binding stint constraint;
- concise strategy state.

Do not fabricate unavailable values.

The renderer must be able to omit unavailable fields without meaningless placeholders.

## Tyre view model

Expose four independent wheel cells: `FL`, `FR`, `RL`, `RR`.

Per wheel, expose where available:

- compound;
- current temperature;
- current-lap minimum and maximum;
- pressure;
- pressure delta only when a target exists;
- wear/life;
- flat spotting;
- strongest verified state;
- availability.

Unsupported graining/blistering remain unavailable.

When targets are absent:

- keep measured data visible;
- hide target-dependent rows;
- expose at most one card-level `Targets not set` state;
- do not repeat `Not configured` four times.

## Weather view model

Expose:

- readable current condition;
- measured provenance;
- air temperature;
- road temperature;
- wind speed;
- wind cardinal direction;
- track wetness/state;
- grip with explicit meaning and unit;
- measured trend where defensible;
- future forecast availability.

Do not expose raw enum strings such as `CURRENT 100`.

Do not fabricate future weather.

Prepare stable IDs for later dynamic compass and weather-icon rendering, but do not build the asset system in Task 7.

## Pit view model

Keep separate:

- current live pit-lane state;
- current pit-box state;
- learned marker state;
- marker confidence;
- distance to entry;
- ETA to entry;
- expected fuel at entry;
- active pit call;
- pit-window state;
- expected pit cycle;
- calibration/learning status;
- manual override state.

Missing calibration affects only predictive pit fields.

Compact behavior:

- an active pit call may become prominent;
- calibrated inactive state may show concise distance/forecast;
- uncalibrated state appears once, concisely;
- do not repeat `Pit entry not calibrated`.

## TEL / BRG / ENG trust model

Expose independent status models.

### TEL

- `LIVE`
- `PARTIAL`
- `STALE`
- `OFFLINE`

### BRG

- `CONNECTED`
- `DEGRADED`
- `DISCONNECTED`
- `NOT USED`

### ENG

- `CONNECTED`
- `DEGRADED`
- `LOST`
- `NOT ASSIGNED`

Current local-only expected behavior:

- TEL = LIVE or PARTIAL;
- BRG = NOT USED;
- ENG = NOT ASSIGNED.

`NOT USED` and `NOT ASSIGNED` are neutral, not red failures.

Expose shape/icon semantics in addition to color semantics for later rendering.

## Engineer message boundary

Reuse the structured message contract where present.

The Engineer area carries actionable or contextual messages, not generic source health.

Examples:

- no active instruction;
- latest lap excluded, prior estimates preserved;
- continue current pace;
- save fuel;
- pit window open;
- box this lap;
- critical vehicle or race-control alert only when verified.

Source health belongs to TEL/BRG/ENG.

Missing pit calibration belongs to Pit status unless directly relevant to an active instruction.

Do not add real Bridge or Engineer networking.

## Mode allocation

### Compact

Only immediate driver decisions:

- Engineer/action state;
- stint/session strip;
- fuel;
- pace;
- tyres;
- weather;
- pit;
- TEL/BRG/ENG.

Suppress diagnostic detail and repeated configuration warnings.

### Expanded

Add:

- complete comparisons;
- estimator differences;
- sample counts;
- confidence;
- freshness;
- exclusion details;
- forecast uncertainty;
- full tyre and weather provenance;
- detailed pit forecasts;
- Engineer history.

### Garage

Add:

- raw normalized telemetry;
- event and lap records;
- eligibility decisions and overrides;
- calculation traces;
- forecast traces;
- target configuration;
- pit observations and marker state;
- source diagnostics;
- renderer geometry diagnostics where already supported.

## Priority and semantic status

Provide centralized priority and semantic states for later rendering.

Suggested priority:

1. critical Engineer or verified race-control/vehicle alert;
2. stint/session progress;
3. fuel feasibility;
4. pace versus plan;
5. tyre warning;
6. weather/track change;
7. pit state;
8. source health.

Suggested semantic states:

- neutral;
- informational;
- good;
- caution;
- critical;
- unavailable.

Do not choose actual colors in calculation modules.

## Backward compatibility

Preserve current renderer compatibility where practical.

When a field is renamed or split:

- provide explicit migration or compatibility;
- update tests;
- document old versus new semantics;
- do not silently reuse an old field name with a different meaning.

Minimal renderer updates are allowed only to keep the app functional.

A full shell/layout/asset redesign is later work.

## Tests

Add deterministic tests for at least:

1. common field metadata;
2. unavailable reason propagation;
3. lap-time formatting;
4. delta formatting;
5. no generic unlabeled delta;
6. pace target/last/stint-average semantics;
7. no pace target suppresses target rows;
8. latest completed excluded lap remains diagnostic;
9. fuel current/latest/average/required semantics;
10. no fuel target suppresses target rows;
11. stint/session strip allocation;
12. missing forecast fields degrade cleanly;
13. four independent tyre cells;
14. no repeated tyre `Not configured`;
15. unsupported tyre damage remains unavailable;
16. readable weather condition;
17. wind cardinal formatting;
18. no fabricated future weather;
19. live pit state without calibration;
20. predictive pit fields require calibration;
21. no repeated pit calibration warning;
22. TEL states;
23. BRG neutral `NOT USED`;
24. ENG neutral `NOT ASSIGNED`;
25. Engineer/source-health separation;
26. Compact allocation;
27. Expanded allocation;
28. Garage allocation;
29. priority ordering;
30. semantic states independent from color;
31. backward compatibility where required;
32. no raw CSP access;
33. no calculations or forecasts in renderer;
34. no networking;
35. no runtime `require` or `dofile`;
36. deterministic bundle;
37. V1 protection.

## Documentation

Document:

- common field contract;
- formatting conventions;
- pace semantics;
- fuel semantics;
- stint strip;
- tyre target suppression;
- weather semantics;
- pit semantics;
- TEL/BRG/ENG;
- Engineer separation;
- mode allocation;
- priority;
- compatibility;
- what remains for later HUD shell and dynamic-visual tasks.

## Task gate

Before committing:

1. Confirm Task 6 is the previous completed task.
2. Run all shared validation.
3. Run formatting tests.
4. Run pace/fuel semantic tests.
5. Run stint-strip tests.
6. Run tyre/weather/pit tests.
7. Run trust and Engineer-separation tests.
8. Run mode-allocation tests.
9. Run deterministic replay twice.
10. Run deterministic build twice.
11. Confirm no raw telemetry, calculation, forecast, networking, or major visual scope creep.
12. Confirm only Task 7 files changed.

Create exactly one commit:

`Expose stable driver status view model`

After committing:

- confirm the worktree is clean;
- run final combined Tasks 4–7 validation;
- return a task-by-task report;
- stop;
- do not begin the HUD visual redesign.
