# Task 4 — Implement Purpose-Specific Lap Eligibility

## Required commit

`Implement purpose-specific lap eligibility`

## Dependencies

Tasks 1–3 must already be committed and validated.

The worktree must be clean before Task 4 begins.

Read and follow:

- `README.md`
- `AGENTS.md`
- `docs/tasks/race-engine-core-v1/README.md`
- `docs/tasks/race-engine-core-v1/shared-execution-rules.md`
- the Task 1–3 specifications and resulting contracts;
- all relevant lap, sample, stint, telemetry, pit, and test modules.

## Purpose

Implement a deterministic eligibility engine that decides whether each immutable completed-lap record may be used for each purpose.

Do not use a single global valid/invalid decision as the internal model.

A lap can be:

- excluded from pace;
- included for fuel;
- included for tyre analysis;
- excluded from projection;
- excluded from the official average.

Task 4 decides eligibility only. It must not implement stint averages, race forecasts, or a UI redesign.

## Core output

For every completed lap, assign independently:

- `useForPace`;
- `useForFuel`;
- `useForTyres`;
- `useForProjection`;
- `useForOfficialAverage`.

Each decision must include:

- decision value;
- policy ID;
- deterministic reason codes;
- source evidence;
- confidence;
- manual-override state;
- decision version.

Emit or persist the corresponding immutable eligibility event according to the Task 1 contract.

Do not mutate the original completed-lap event or raw measured summary.

## Separate validity concepts

Distinguish at minimum:

### Official validity

The simulator or race-control validity state.

This controls eligibility for `useForOfficialAverage`.

### Operational representativeness

Whether the lap remains physically representative for a specific engineering purpose.

A track-limit-invalid lap might still be usable for fuel and tyres while being excluded from official average and possibly pace.

### Completeness

Whether the lap has enough measured data to support a purpose.

### Regime compatibility

Whether the lap belongs to the same operational regime as the estimator that would consume it.

Examples:

- dry;
- wet;
- mixed;
- caution;
- traffic;
- fuel-save;
- push;
- pit cycle.

### Manual override

An explicit user decision for one purpose or multiple purposes.

Manual override must be auditable, reversible, and must not rewrite the original classification.

## Policies

Implement centralized, versioned policies.

At minimum:

### STRICT

Typical intent:

- official valid completed laps only;
- excludes pit, in-lap, out-lap, reset, incident, incomplete, and incompatible-regime laps;
- no automatic inclusion of officially invalid laps.

### OPERATIONAL

Typical intent:

- may include an officially invalid lap for fuel or tyres when distance, continuity, and measurements remain representative;
- may include a track-limit-invalid lap for pace only when the configured operational rule explicitly allows it and no shortcut or material time gain is detected;
- excludes pit, reset, teleport, incident, incomplete, and materially incompatible laps.

### CUSTOM

Purpose-specific configuration built from explicit policy options.

Do not encode one `includeInvalidLaps` Boolean as the core policy.

A convenience UI toggle may later map to a policy, but the engine must retain independent purpose decisions.

## Required evidence and classifications

Consume the immutable completed-lap record and relevant immutable events.

Support evidence such as:

- official validity;
- invalidation reason;
- lap completeness;
- pit entry or exit interaction;
- pit-box interaction;
- reset or teleport interaction;
- refuel interaction;
- lap-time plausibility;
- distance or spline continuity;
- fuel measurement completeness;
- tyre measurement completeness;
- weather regime;
- caution or race-control regime where verified;
- traffic classification when available;
- push/fuel-save classification when explicitly assigned;
- manual compromised-lap marking from existing AVM behavior;
- manual eligibility override.

Do not fabricate evidence that CSP does not provide.

Unknown evidence must remain unknown and should lead to a conservative, documented decision where necessary.

## Baseline decision matrix

Implement an explicit centralized matrix or equivalent ruleset. Exact decisions must remain configurable and tested.

### Normal, complete, officially valid lap

- pace: yes;
- fuel: yes;
- tyres: yes when measurements are complete;
- projection: yes;
- official average: yes.

### Track-limit invalid without shortcut, pit, reset, incident, or regime change

- official average: no;
- fuel: usually yes when fuel measurement is complete;
- tyres: usually yes;
- pace: policy-dependent;
- projection: policy-dependent.

### Shortcut-assisted or implausibly fast invalid lap

- pace: no;
- projection: no;
- official average: no;
- fuel: conservative or no when distance/fuel representativeness is doubtful;
- tyres: yes only when measurement completeness is adequate.

### Traffic-affected lap

- official average: based on official validity;
- pace: usually no under operational representative pace;
- fuel: usually yes;
- tyres: yes;
- projection: usually no for representative pace projection.

### Fuel-save lap

- pace: separate regime or excluded from normal-pace estimator;
- fuel: yes in fuel-save regime;
- tyres: yes;
- projection: only for matching strategy regime;
- official average: based on official validity.

### Push lap

- pace: yes in push regime;
- fuel: yes in push regime;
- tyres: yes;
- projection: only for matching regime;
- official average: based on official validity.

### Wet or mixed lap

- pace, fuel, and projection: only for matching weather regime;
- tyres: yes when measurements are complete;
- official average: based on official validity.

### Pit, in-lap, out-lap, or pit-box lap

- pace: no for normal-stint pace;
- fuel: no for normal fuel-per-lap average unless a later dedicated pit-cycle model consumes it;
- tyres: may be retained for diagnostics;
- projection: no for normal on-track projection;
- official average: no.

### Reset, teleport, incident, incomplete, or severe-discontinuity lap

- pace: no;
- fuel: no unless explicitly recovered with complete trustworthy measurements;
- tyres: diagnostics only;
- projection: no;
- official average: no.

## Latest completed versus latest accepted

Preserve separate references for:

- latest completed lap;
- latest accepted pace lap;
- latest accepted fuel lap;
- latest accepted tyre lap;
- latest accepted projection lap;
- latest official-average lap.

An excluded latest lap must not erase or replace the previous latest accepted lap for another purpose.

## Manual overrides

Support:

- per-purpose include;
- per-purpose exclude;
- restore automatic decision;
- readable override reason;
- timestamp or sequence;
- source;
- audit trail.

Manual overrides must:

- be bounded;
- be reversible;
- survive normal recalculation;
- reset only on appropriate identity/stint boundaries;
- never mutate the original measured lap record.

## Configuration and versioning

Centralize:

- policy ID;
- policy version;
- per-purpose rules;
- invalid-lap behavior;
- regime matching;
- outlier/shortcut thresholds if used;
- manual-override precedence.

Do not hide material policy changes behind the same version.

## Determinism and replay

The same ordered completed-lap records, events, configuration, and overrides must produce byte-identical eligibility decisions and serialized output.

## Tests

Add deterministic tests for at least:

1. normal valid lap;
2. officially invalid but operationally representative lap;
3. track-limit invalid lap under STRICT;
4. track-limit invalid lap under OPERATIONAL;
5. shortcut-assisted lap;
6. implausibly fast lap;
7. traffic-affected lap;
8. fuel-save lap;
9. push lap;
10. dry lap;
11. wet lap;
12. mixed-regime lap;
13. caution lap;
14. pit lap;
15. in-lap;
16. out-lap;
17. pit-box interaction;
18. reset interaction;
19. teleport interaction;
20. incident lap;
21. incomplete lap;
22. missing fuel measurements;
23. missing tyre measurements;
24. independent per-purpose decisions;
25. official average follows official validity;
26. latest completed remains distinct from latest accepted;
27. an excluded lap does not erase previous accepted pointers;
28. manual include override;
29. manual exclude override;
30. restore automatic decision;
31. policy change recalculates deterministically;
32. bounded override history;
33. deterministic replay and serialization;
34. no stint averages implemented;
35. no forecasts implemented;
36. no renderer calculations;
37. no networking;
38. no runtime `require` or `dofile`;
39. deterministic bundle;
40. V1 protection.

## Documentation

Document:

- official validity versus operational representativeness;
- independent purpose decisions;
- baseline policy matrix;
- STRICT, OPERATIONAL, and CUSTOM;
- regime compatibility;
- latest completed versus latest accepted;
- manual overrides;
- reason codes;
- versioning;
- deterministic replay;
- known limitations where evidence is unavailable.

## Task gate

Before committing:

1. Confirm Tasks 1–3 are in history and the worktree was clean.
2. Run all shared validation.
3. Run eligibility policy tests.
4. Run manual-override tests.
5. Run deterministic replay twice.
6. Confirm byte-identical eligibility output.
7. Run deterministic build twice.
8. Confirm no stint, forecast, or major UI scope creep.
9. Confirm only Task 4 files changed.

Create exactly one commit:

`Implement purpose-specific lap eligibility`

After committing:

- confirm the worktree is clean;
- continue to Task 5 only if every Task 4 gate passed.
