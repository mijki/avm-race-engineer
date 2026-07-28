# Race and Pit Forecast Engine V1

`tools/forecast_engine.py` is the deterministic host-side forecast layer for
the Race Engine Core V1 slice. It consumes the immutable calculation result
from `tools/stint_calculations.py`, the current normalized snapshot, learned
pit diagnostics, and explicit strategy/session configuration.

The dependency direction remains:

`normalized snapshot → immutable events → eligibility → stint calculations → forecasts → driver view model`

The engine has no runtime API access, presentation logic, or transport code.

## Model precedence

Pace uses the current-regime representative pace first, then the operational
stint average, then the latest accepted pace. Fuel uses the representative
current-regime fuel use first, then the operational stint average, then the
latest accepted use. An explicit target is retained as a comparison reference;
it is not silently promoted to a measured consumption model.

Direct configured stint, driver, tyre, race, and pit limits are kept separate
from model-based estimates. The predicted actual stint endpoint is the earliest
defensible endpoint, and its `binding_constraint` names the limiting input.

## Forecast families

- Stint forecasts expose time-, lap-, fuel-, driver-rule-, tyre-rule-, and
  planned endpoints, plus remaining time/laps and a predicted actual endpoint.
- Race forecasts expose remaining laps/time, timed-race finish estimates,
  fuel required to finish, expected finish fuel, margin, and configured stop
  feasibility.
- Fuel forecasts keep current fuel, model burn, required fuel per lap, planned
  pit/finish requirements, expected fuel at pit/finish, and fuel-save margin in
  separate records.
- Pit-entry forecasts use forward circular spline distance. The current live
  pit-lane and pit-box state remains available when no marker is calibrated;
  only predictive entry fields become unavailable.
- Pit-cycle forecasts distinguish measured normal-stop timing, explicit planned
  service duration, and forecast values. Drive-through-only evidence never
  becomes normal-stop service timing.

Every record uses the `forecast-envelope-v1` metadata shape and additionally
contains a bounded sample count and `source_layer: forecast`. Missing inputs
produce a reason such as `PIT_ENTRY_NOT_CALIBRATED`,
`NO_RECENT_PIT_TIMING`, or `RACE_FUEL_REQUIREMENT_UNAVAILABLE` rather than a
numeric placeholder. When the selected sample is stale, the model remains
visible only with degraded confidence and `STALE_SOURCE` provenance.

## Confidence, uncertainty, and weather

Marker state and timing evidence affect pit confidence: provisional markers are
low confidence, learned markers are medium, confirmed or manual markers are
high, and conflicting or missing markers are unavailable for prediction.
Forecast ranges are preserved when the calculation metadata supplies an
observed sample range; otherwise the record explicitly says that a range is
unavailable. The engine uses current measured weather regime only. Future rain
timing or future track conditions are unavailable unless an explicit future
weather source is supplied.

## Invalidation and recommendations

Forecast records are immutable. A new lap, pit transition, reset, identity
change, marker update, strategy revision, or target change is reported through
reason codes and a `supersedes` reference when a prior forecast is supplied.
The engine emits machine-readable states such as `ON_PLAN`, `FUEL_MARGIN_LOW`,
`PIT_WINDOW_OPEN`, `PLANNED_ENTRY_PASSED`, and `FORECAST_UNAVAILABLE`; final
driver-message selection remains a later view-model concern.

Task 5 already owns stable stint identity and ordinal. The forward-compatible
empty-stint transition added with Task 6 mints the next stint ID immediately
after a boundary observed after the last completed lap, retaining the previous
stint and exposing zero completed post-boundary laps. This allows a driver
surface to show `STINT 2 · LAP 0`, followed by `STINT 2 · LAP 1` after the first
completed post-pit lap, without deriving an ordinal from display text.

Real-CSP validation remains a separate gate. These tests validate deterministic
replay and host-side contracts; they do not claim that a simulator session was
run.
