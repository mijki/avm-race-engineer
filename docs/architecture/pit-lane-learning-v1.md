# Automatic Pit Lane Learning V1

Automatic learning is a local, source-evidence-driven capability in AVM
PitWall. `car.isInPitlane` controls the current live state immediately and
`car.isInPit` independently controls box arrival/departure. Calibration affects
predictive distance only; missing calibration never hides current pit state.

The learner preserves the first false-to-true and true-to-false transition
snapshots, applies short configurable debounce/hysteresis, and rejects an
observation after reset, teleport, identity/replay change, or implausible
movement. It never imposes a fixed ten-second delay and does not discard short
legitimate lane visits.

Marker observations are clustered with circular spline distance and secondary
world-position consistency. Records are bounded to 24 accepted and 24 rejected
observations per track/layout. The marker progresses through `UNAVAILABLE`,
`PROVISIONAL`, `LEARNED`, `CONFIRMED`, and `CONFLICTED`; `MANUAL_OVERRIDE` is
stored separately and cannot be overwritten by automatic learning.

The persistence key is `avm_race_engineer_pit_markers_v1`, separate from the
existing V1 presentation settings key. Records use
`pit-marker-record-v1` and bind to a deterministic `track_id::layout_id` key.
Timing summaries distinguish normal stops, drive-throughs, lane visits without
service, reset-suppressed visits, and incomplete visits.
