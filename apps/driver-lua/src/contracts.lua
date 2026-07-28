local namespace = _G.AVM_PITWALL_F1
local contracts = {}

local function is_table(value)
  return type(value) == "table"
end

local function has_fields(value, fields)
  if not is_table(value) then
    return false
  end
  for index = 1, #fields do
    if value[fields[index]] == nil then
      return false
    end
  end
  return true
end

function contracts.is_driver_status(snapshot)
  if not has_fields(snapshot, {
    "schema_version", "snapshot_id", "session_id", "car_id", "generated_at_utc",
    "connection_state", "stint_summary", "fuel_summary", "pace_summary", "pit_summary",
    "weather_summary", "primary_instruction", "confidence_badge", "reason_codes"
  }) then
    return false
  end
  if type(snapshot.schema_version) ~= "string" or snapshot.schema_version == "" then
    return false
  end
  if not has_fields(snapshot.stint_summary, { "current_stint_number", "stint_progress_ratio" }) then
    return false
  end
  if not has_fields(snapshot.fuel_summary, { "fuel_remaining_l", "fuel_laps_remaining", "fuel_delta_to_plan_l" }) then
    return false
  end
  if not has_fields(snapshot.pace_summary, { "pace_delta_to_target_s_per_lap", "rolling_trend" }) then
    return false
  end
  if not has_fields(snapshot.pit_summary, { "pit_window_state", "primary_call" }) then
    return false
  end
  if not has_fields(snapshot.weather_summary, { "label", "current_weather_type", "current_track_condition", "authoritative", "confidence_band" }) then
    return false
  end
  if not has_fields(snapshot.primary_instruction, { "instruction", "instruction_source", "priority", "requires_acknowledgement" }) then
    return false
  end
  return true
end

function contracts.unwrap_snapshot(envelope)
  if not is_table(envelope) then
    return nil, nil
  end
  if contracts.is_driver_status(envelope) then
    return envelope, envelope
  end
  if contracts.is_driver_status(envelope.driver_status_snapshot) then
    return envelope.driver_status_snapshot, envelope
  end
  return nil, envelope
end

function contracts.safe_text(value, fallback)
  if type(value) ~= "string" or value == "" then
    return fallback
  end
  if #value > namespace.config.max_text_length then
    return string.sub(value, 1, namespace.config.max_text_length - 3) .. "..."
  end
  return value
end

function contracts.optional_number(value)
  if type(value) == "number" then
    return value
  end
  return nil
end

function contracts.metric(value, unit, samples, freshness_s, confidence, reason)
  return {
    value = value,
    unit = unit,
    sample_count = samples or 0,
    freshness_s = freshness_s,
    confidence_band = confidence or (value == nil and "low" or "medium"),
    reason = reason,
  }
end

function contracts.unavailable(unit, reason, samples, freshness_s)
  return contracts.metric(nil, unit, samples or 0, freshness_s, "low", reason or "UNAVAILABLE")
end

-- Race Engine Core V1 contracts are additive to the existing driver-status
-- presentation contract.  Keep these factories free of CSP/UI side effects so
-- host replay and later live consumers use the same field vocabulary.
contracts.schema_versions = {
  telemetry_snapshot = "telemetry-snapshot-v1",
  race_event = "race-event-v1",
  completed_lap = "completed-lap-v1",
  pit_observation = "pit-transition-observation-v1",
  pit_marker = "pit-marker-record-v1",
  calculated_value = "calculated-value-v1",
  forecast = "forecast-envelope-v1",
}

contracts.source_health = { "LIVE", "PARTIAL", "STALE", "OFFLINE" }
contracts.marker_states = { "UNAVAILABLE", "PROVISIONAL", "LEARNED", "CONFIRMED", "CONFLICTED", "MANUAL_OVERRIDE" }
contracts.eligibility_policies = { "STRICT", "OPERATIONAL", "CUSTOM" }

contracts.reason_codes = {
  INITIALIZATION = true,
  IDENTITY_CHANGED = true,
  SESSION_RESTART = true,
  REPLAY_TRANSITION = true,
  LAP_COUNTER_DECREASE = true,
  RESET_COUNTER_CHANGED = true,
  TELEPORT_DETECTED = true,
  SPLINE_JUMP = true,
  WORLD_POSITION_JUMP = true,
  MATERIAL_REFUEL = true,
  SOURCE_UNAVAILABLE = true,
  SOURCE_PARTIAL = true,
  SOURCE_STALE = true,
  UNSUPPORTED = true,
  INSUFFICIENT_SAMPLES = true,
}

local function copy_value(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] ~= nil then return seen[value] end
  local result = {}
  seen[value] = result
  for key, child in pairs(value) do result[copy_value(key, seen)] = copy_value(child, seen) end
  return result
end

local function immutable_value(value)
  if type(value) ~= "table" then return value end
  local source = {}
  for key, child in pairs(value) do source[key] = immutable_value(child) end
  return setmetatable({}, {
    __index = source,
    __newindex = function() error("immutable race contract", 2) end,
    __metatable = "immutable",
  })
end

function contracts.copy(value)
  return copy_value(value)
end

function contracts.immutable(value)
  return immutable_value(copy_value(value))
end

function contracts.identity_key(identity)
  identity = identity or {}
  return table.concat({
    tostring(identity.car_id or ""),
    tostring(identity.track_id or ""),
    tostring(identity.layout_id or ""),
    tostring(identity.session_id or ""),
    tostring(identity.configuration_id or ""),
  }, "|")
end

function contracts.track_layout_key(identity)
  identity = identity or {}
  return tostring(identity.track_id or "") .. "::" .. tostring(identity.layout_id or "")
end

function contracts.snapshot_id(identity, sequence)
  return "snapshot:" .. contracts.identity_key(identity) .. ":" .. tostring(sequence or 0)
end

function contracts.telemetry_snapshot(fields)
  fields = fields or {}
  local identity = fields.identity or {}
  local snapshot = {
    schema_version = contracts.schema_versions.telemetry_snapshot,
    snapshot_id = fields.snapshot_id or contracts.snapshot_id(identity, fields.sequence),
    source_mode = fields.source_mode or "live",
    source_timestamp_s = fields.source_timestamp_s,
    observed_monotonic_s = fields.observed_monotonic_s,
    sequence = fields.sequence,
    source_health = fields.source_health or "OFFLINE",
    identity = contracts.copy(identity),
    track_layout_key = fields.track_layout_key or contracts.track_layout_key(identity),
    session = contracts.copy(fields.session or {}),
    car = contracts.copy(fields.car or {}),
    tyres = contracts.copy(fields.tyres or {}),
    environment = contracts.copy(fields.environment or {}),
    provenance = contracts.copy(fields.provenance or {}),
    availability = contracts.copy(fields.availability or {}),
    failures = contracts.copy(fields.failures or {}),
  }
  return snapshot
end

function contracts.race_event(fields)
  fields = fields or {}
  local event = {
    schema_version = contracts.schema_versions.race_event,
    event_id = fields.event_id,
    sequence = fields.sequence,
    event_type = fields.event_type,
    source_snapshot_id = fields.source_snapshot_id,
    detection_time_s = fields.detection_time_s,
    source_time_s = fields.source_time_s,
    session_time_s = fields.session_time_s,
    identity_key = fields.identity_key,
    confidence = fields.confidence or "medium",
    provenance = contracts.copy(fields.provenance or {}),
    payload = contracts.copy(fields.payload or {}),
    suppression_reason = fields.suppression_reason,
    rejection_reason = fields.rejection_reason,
  }
  return contracts.immutable(event)
end

function contracts.completed_lap(fields)
  fields = fields or {}
  local eligibility = fields.eligibility or {}
  return {
    schema_version = contracts.schema_versions.completed_lap,
    lap_id = fields.lap_id,
    identity_key = fields.identity_key,
    lap_number = fields.lap_number,
    started_at_s = fields.started_at_s,
    completed_at_s = fields.completed_at_s,
    lap_time_s = fields.lap_time_s,
    sectors = contracts.copy(fields.sectors or {}),
    official_validity = fields.official_validity,
    invalidation_reason = fields.invalidation_reason,
    classification = fields.classification,
    fuel = contracts.copy(fields.fuel or {}),
    weather_regime = fields.weather_regime,
    compound = fields.compound,
    pit_reset_interaction = contracts.copy(fields.pit_reset_interaction or {}),
    eligibility = {
      useForPace = eligibility.useForPace,
      useForFuel = eligibility.useForFuel,
      useForTyres = eligibility.useForTyres,
      useForProjection = eligibility.useForProjection,
      useForOfficialAverage = eligibility.useForOfficialAverage,
      policy = eligibility.policy or "OPERATIONAL",
      reasons = contracts.copy(eligibility.reasons or {}),
      manual_override = eligibility.manual_override,
    },
  }
end

function contracts.pit_observation(fields)
  fields = fields or {}
  return {
    schema_version = contracts.schema_versions.pit_observation,
    observation_id = fields.observation_id,
    transition_type = fields.transition_type,
    source_snapshot_id = fields.source_snapshot_id,
    old_state = fields.old_state,
    new_state = fields.new_state,
    entry_classification = fields.entry_classification,
    exit_classification = fields.exit_classification,
    spline = fields.spline,
    world_position = contracts.copy(fields.world_position),
    reset_counter = fields.reset_counter,
    speed_kmh = fields.speed_kmh,
    source_time_s = fields.source_time_s,
    detection_time_s = fields.detection_time_s,
    stability_duration_s = fields.stability_duration_s,
    movement_m = fields.movement_m,
    confidence = fields.confidence or "low",
    confirmation_state = fields.confirmation_state or "PROVISIONAL",
    rejection_reasons = contracts.copy(fields.rejection_reasons or {}),
  }
end

function contracts.pit_marker(fields)
  fields = fields or {}
  return {
    schema_version = contracts.schema_versions.pit_marker,
    track_layout_key = fields.track_layout_key,
    track_id = fields.track_id,
    layout_id = fields.layout_id,
    state = fields.state or "UNAVAILABLE",
    entry_spline = fields.entry_spline,
    exit_spline = fields.exit_spline,
    entry_world_position = contracts.copy(fields.entry_world_position),
    exit_world_position = contracts.copy(fields.exit_world_position),
    accepted_observations = contracts.copy(fields.accepted_observations or {}),
    rejected_observations = contracts.copy(fields.rejected_observations or {}),
    confidence = fields.confidence or 0,
    source = fields.source or "AUTOMATIC",
    first_observed_at_s = fields.first_observed_at_s,
    last_observed_at_s = fields.last_observed_at_s,
    manual_override = fields.manual_override == true,
    timing = contracts.copy(fields.timing or {}),
  }
end

function contracts.calculated_value(fields)
  fields = fields or {}
  return {
    schema_version = contracts.schema_versions.calculated_value,
    value = fields.value,
    unit = fields.unit,
    calculation_version = fields.calculation_version,
    source_fields = contracts.copy(fields.source_fields or {}),
    source_events = contracts.copy(fields.source_events or {}),
    accepted_samples = contracts.copy(fields.accepted_samples or {}),
    rejected_samples = contracts.copy(fields.rejected_samples or {}),
    sample_count = fields.sample_count or 0,
    regime = fields.regime,
    policy = fields.policy,
    freshness_s = fields.freshness_s,
    confidence = fields.confidence,
    uncertainty = fields.uncertainty,
    binding_constraint = fields.binding_constraint,
    unavailable_reason = fields.unavailable_reason,
  }
end

function contracts.forecast(fields)
  fields = fields or {}
  return {
    schema_version = contracts.schema_versions.forecast,
    forecast_id = fields.forecast_id,
    model_id = fields.model_id,
    model_version = fields.model_version,
    generated_at_s = fields.generated_at_s,
    target_at_s = fields.target_at_s,
    value = fields.value,
    unit = fields.unit,
    measured_inputs = contracts.copy(fields.measured_inputs or {}),
    calculated_inputs = contracts.copy(fields.calculated_inputs or {}),
    samples = contracts.copy(fields.samples or {}),
    regime = fields.regime,
    freshness_s = fields.freshness_s,
    confidence = fields.confidence,
    uncertainty = fields.uncertainty,
    binding_constraint = fields.binding_constraint,
    unavailable_reason = fields.unavailable_reason,
    supersedes = fields.supersedes,
  }
end

function contracts.identity(snapshot)
  local identity = snapshot and snapshot.identity or {}
  return {
    car_id = identity.car_id,
    track_id = identity.track_id,
    layout_id = identity.layout_id,
    session_id = identity.session_id,
    driver_name = identity.driver_name,
    key = identity.key,
  }
end

namespace.contracts = contracts
