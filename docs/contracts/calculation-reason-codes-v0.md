# Calculation Reason Codes v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the initial canonical reason code vocabulary for race calculations,
forecasts, weather outputs, and reduced driver snapshots.

Machine-readable catalog:
[calculation-reason-codes-v0.json](./calculation-reason-codes-v0.json).

## Usage Rules

- Reason codes are stable machine-facing identifiers.
- Human-readable copy belongs in the UI layer, not in the reason code itself.
- Multiple reason codes may be attached to one value or recommendation.
- Producers should emit the narrowest applicable code set rather than a generic
  catch-all.

## Identity And Compatibility

- `IDENTITY_SESSION_MISMATCH`: input or model state does not match the active
  session.
- `IDENTITY_CAR_MISMATCH`: input belongs to a different car.
- `IDENTITY_DRIVER_MISMATCH`: input belongs to a different driver than the
  active identity expects.
- `IDENTITY_TRACK_MISMATCH`: track or layout identity does not match the active
  model.
- `STRATEGY_REVISION_UNKNOWN`: no accepted strategy revision is available.
- `STRATEGY_REVISION_STALE`: the attached strategy revision is no longer current.

## Telemetry And Sample Quality

- `TELEMETRY_MISSING_REQUIRED_FIELD`: a required upstream field was absent.
- `TELEMETRY_STALE`: source data is older than the allowed freshness window.
- `TELEMETRY_INCOMPLETE`: the source exists but is missing enough fields to
  reduce trust materially.
- `TELEMETRY_SEQUENCE_GAP`: sequence continuity broke and continuity-sensitive
  calculations should downgrade.
- `SAMPLE_SET_TOO_SMALL`: not enough eligible samples exist.
- `SAMPLE_SET_TOO_OLD`: eligible samples are older than the configured window.
- `SAMPLE_SET_INCONSISTENT`: samples disagree beyond tolerance.
- `SAMPLE_SET_OUTLIERS_EXCLUDED`: one or more outliers were excluded.
- `SAMPLE_SET_REGIME_MIXED`: samples from incompatible operating regimes were
  present.

## Operating Regime

- `REGIME_NORMAL_GREEN`
- `REGIME_TRAFFIC_AFFECTED`
- `REGIME_FUEL_SAVING`
- `REGIME_PUSH`
- `REGIME_WET`
- `REGIME_MIXED_CONDITIONS`
- `REGIME_CAUTION_OR_SLOW_ZONE`
- `REGIME_PIT_IN_LAP`
- `REGIME_PIT_LANE`
- `REGIME_PIT_OUT_LAP`
- `REGIME_INCIDENT_OR_DAMAGE`
- `REGIME_INCOMPLETE_TELEMETRY`

These codes may appear as explanatory tags in addition to warning codes.

## Fuel, Stint, And Pit Logic

- `FUEL_MODEL_ESTIMATED`: fuel model exists but is relying on estimated rather
  than stable representative samples.
- `FUEL_MODEL_BLOCKED`: fuel prediction is not trustworthy enough to publish.
- `PIT_ENTRY_POINT_UNKNOWN`: pit-entry location is not available for the active
  track and layout.
- `PIT_ENTRY_WRAPAROUND_APPLIED`: pit-entry wraparound logic was required.
- `PIT_WINDOW_NOT_OPEN`: a recommendation to pit now is blocked by current
  constraints.
- `STINT_END_UNCERTAIN`: stint end is forecast but materially uncertain.
- `TYRE_LIFE_UNCERTAIN`: tyre-life estimate exists but confidence is low.

## Weather And Track Conditions

- `WEATHER_CURRENT_ONLY`: only current measured weather is available.
- `WEATHER_TRANSITION_ONLY`: only current-to-next transition information exists.
- `WEATHER_SCHEDULE_AUTHORITATIVE`: schedule comes from an authoritative source.
- `WEATHER_ESTIMATED_ONLY`: future weather is estimated, not scheduled.
- `WEATHER_TREND_ONLY`: only a short-term trend exists.
- `WEATHER_UNKNOWN_FUTURE`: no future weather claim is justified.
- `WEATHER_SOURCE_CONFLICT`: weather sources disagree materially.
- `WEATHER_SOURCE_STALE`: weather source is stale.
- `WEATHER_CONTROLLER_CHANGED`: controller changed and prior forecast continuity
  is degraded.
- `WEATHER_RESAMPLED_BUCKET`: a timeline bucket was interpolated or resampled.
- `WEATHER_BUCKET_MISSING`: a timeline bucket could not be populated.

## Recommendation And Publication

- `RECOMMENDATION_ON_PLAN`
- `RECOMMENDATION_SAVE_FUEL`
- `RECOMMENDATION_PUSH`
- `RECOMMENDATION_TARGET_PACE`
- `RECOMMENDATION_BOX_THIS_LAP`
- `RECOMMENDATION_BOX_IN_N_LAPS`
- `RECOMMENDATION_STAY_OUT`
- `RECOMMENDATION_EXTEND`
- `RECOMMENDATION_SHORTEN_STINT`
- `RECOMMENDATION_CHANGE_TYRES`
- `RECOMMENDATION_DOUBLE_STINT_TYRES`
- `RECOMMENDATION_REPLAN_REQUIRED`
- `RECOMMENDATION_WAITING_FOR_VALID_DATA`
- `RECOMMENDATION_LOW_CONFIDENCE`

## Confidence Rollup

- `CONFIDENCE_REDUCED_SAMPLE_AGE`
- `CONFIDENCE_REDUCED_SAMPLE_COUNT`
- `CONFIDENCE_REDUCED_SAMPLE_CONSISTENCY`
- `CONFIDENCE_REDUCED_TELEMETRY_COMPLETENESS`
- `CONFIDENCE_REDUCED_IDENTITY_VALIDITY`
- `CONFIDENCE_REDUCED_WEATHER_STABILITY`
- `CONFIDENCE_REDUCED_FORECAST_HORIZON`
- `CONFIDENCE_BLOCKED_INVALID_IDENTITY`
- `CONFIDENCE_BLOCKED_INSUFFICIENT_DATA`

## Change Discipline

- Add new reason codes instead of reusing an existing code for a different
  meaning.
- Do not delete or rename a published code without a compatibility policy
  change.
