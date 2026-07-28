# Automatic Pit Lane Learning V1

Automatic learning is a local, source-evidence-driven capability in AVM
PitWall. `car.isInPitlane` controls the current live state immediately and
`car.isInPit` independently controls box arrival/departure. Calibration affects
predictive distance only; missing calibration never hides current pit state.

The learner preserves the pit-entry and pit-exit snapshots, applies short
configurable debounce/hysteresis, and rejects an observation after reset,
teleport, identity/replay change, or implausible movement. It never imposes a
fixed ten-second delay and does not discard short legitimate lane visits.

Each completed visit is classified at pit exit as exactly one of
`DRIVE_THROUGH`, `STOP_GO`, `SERVICE_STOP`, or `UNKNOWN_STOP`. Entering the
lane starts a visit record but never starts a stint. A box arrival and dwell
without service evidence is `STOP_GO`; dwell duration alone is not service
proof. Service evidence may be a measurable fuel increase, verified tyre
replacement/reset, measurable repair completion, confirmed planned service or
driver change, or explicit manual new-stint confirmation. Only
`SERVICE_STOP` can advance the stint ordinal. Live lane and box state remain
independent driver-facing telemetry.

Marker observations are clustered with circular spline distance and secondary
world-position consistency. Records are bounded to 24 accepted and 24 rejected
observations per track/layout. The marker progresses through `UNAVAILABLE`,
`PROVISIONAL`, `LEARNED`, `CONFIRMED`, and `CONFLICTED`; `MANUAL_OVERRIDE` is
stored separately and cannot be overwritten by automatic learning.

The persistence key is `avm_race_engineer_pit_markers_v1`, separate from the
existing V1 presentation settings key. Records use
`pit-marker-record-v1` and bind to a deterministic `track_id::layout_id` key.
Timing summaries preserve the explicit visit classification and the bounded
entry/exit snapshots, including ambiguous or reset-suppressed visits as
`UNKNOWN_STOP`.
