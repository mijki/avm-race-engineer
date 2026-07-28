# Driver Status View Model V1

`tools/driver_status.py` is the stable reduction layer between the calculation
and forecast engines and the later AVM PitWall renderer. It owns field
selection, metadata, formatting, semantic state, priority, and Compact,
Expanded, and Garage allocation. It does not read runtime APIs or calculate
race values.

## Common field contract

Every field has a stable `field_id`, label, raw value, formatted value, unit,
availability, semantic state, severity, confidence, freshness, source layer,
comparison reference, unavailable reason, supporting detail, and trace ID.
Semantic state is one of `neutral`, `informational`, `good`, `caution`,
`critical`, or `unavailable`; it is intentionally independent from a renderer's
color choice. `NOT USED` Bridge and `NOT ASSIGNED` Engineer trust states are
neutral and use hollow shape semantics.

## Formatting and semantics

Complete lap times are formatted as `m:ss.mmm` or `h:mm:ss.mmm`. Signed deltas
include their reference in both field ID and label, for example `LAST VS
TARGET` and `STINT AVG VS TARGET`; an unlabeled generic delta is not emitted.
Pace keeps target, latest completed, latest pace-eligible, official average,
operational average, representative pace, sample counts, and exclusion
diagnostics separate. Fuel likewise keeps current, latest, average, required
rate, range, expected pit fuel, and expected finish fuel separate.

The stint strip is engine-owned. `current_stint_number` comes from the stint
calculation state and `current_stint_lap` is the zero-based number of completed
laps in the active stint. The view model therefore exposes a diagnostic-safe
label such as `STINT 2 · LAP 0`, then `STINT 2 · LAP 1`; it never parses that
label to recover a stint number.

## Tyres, weather, and pit

Tyres always have independent `FL`, `FR`, `RL`, and `RR` cells. Measured
temperature, pressure, wear, and flat-spot state remain visible without
targets; target-dependent pressure deltas and one card-level target warning
appear only when targets exist. Unsupported graining and blistering remain
explicitly unavailable.

Weather uses readable current condition, measured temperatures, wind speed and
cardinal direction, track state, and measured provenance. Future weather is
unavailable unless an explicit future source exists; the view model never
turns a trend into a rain ETA.

Pit fields keep live lane/box state independent from predictive marker,
distance, ETA, expected fuel, window, and cycle fields. Missing marker
calibration suppresses predictive fields and appears once in Compact. Learned,
confirmed, conflicting, and manual marker states retain their provenance.

## Trust, Engineer, and modes

TEL exposes `LIVE`, `PARTIAL`, `STALE`, or `OFFLINE`; BRG exposes its own
connected/degraded/disconnected/`NOT USED` state; ENG exposes its own
connected/degraded/lost/`NOT ASSIGNED` state. Engineer messages stay separate
from source health. The centralized priority order begins with Engineer/action
state, stint progress, fuel feasibility, pace, tyres, weather, pit, and trust.

Compact exposes only immediate driver decisions and the high-value field
allocation. Expanded adds comparison, confidence, freshness, sample, and
exclusion detail. Garage retains the full stable field set and diagnostics for
traceability. The `legacy` reduction keeps the existing snapshot names where
their semantics remain compatible; renamed or split values are exposed under
new IDs rather than silently changing an old meaning.

Later HUD shell, renderer geometry, dynamic compass, and weather-asset work are
outside this task. Real simulator validation is also separate from deterministic
host-side tests.
