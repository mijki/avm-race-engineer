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
