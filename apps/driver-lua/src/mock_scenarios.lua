local namespace = _G.AVM_PITWALL_F1
local scenarios = {}

local function clone(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, child in pairs(value) do
    result[key] = clone(child)
  end
  return result
end

local function set_message(envelope, text, priority, acknowledgement, family, supersedes)
  envelope.engineer_message.text = text
  envelope.engineer_message.priority = priority
  envelope.engineer_message.requires_acknowledgement = acknowledgement == true
  envelope.engineer_message.family = family or "engineer_message"
  envelope.engineer_message.supersedes = supersedes
  envelope.driver_status_snapshot.primary_instruction.priority = priority
  envelope.driver_status_snapshot.primary_instruction.requires_acknowledgement = acknowledgement == true
end

local function base()
  return {
    scenario_id = "NORMAL_ON_PLAN_DRY",
    fixture_status = "valid",
    session_name = "Endurance Qualifying",
    lap_number = 18,
    planned_lap = 26,
    stint_timing = { elapsed_s = 1902, remaining_s = 738, target_s = 2640, remaining_is_estimated = true },
    driver_status_snapshot = {
      schema_version = "0.1.0",
      snapshot_id = "driver-f1-normal-on-plan-dry",
      session_id = "session-f1-demo",
      car_id = "car-avm-demo",
      driver_id = "driver-demo",
      strategy_revision = "accepted-r3",
      calculated_race_state_id = "state-f1-normal-001",
      forecast_snapshot_id = "forecast-f1-normal-001",
      weather_forecast_id = "weather-f1-estimated-001",
      generated_at_utc = "2026-07-26T18:00:00Z",
      valid_until_utc = "2026-07-26T18:00:05Z",
      connection_state = "live",
      stint_summary = { current_stint_number = 2, total_planned_stints = 4, stint_progress_ratio = 0.72, predicted_stint_end_lap = 26 },
      fuel_summary = { fuel_remaining_l = 18.7, fuel_laps_remaining = 6.4, fuel_delta_to_plan_l = 1.2, next_stop_fuel_addition_l = 46.0 },
      pace_summary = { pace_delta_to_target_s_per_lap = 0.18, rolling_trend = "stable" },
      pit_summary = { pit_window_state = "prepare", primary_call = "on_plan", box_in_laps = nil },
      weather_summary = { label = "CURRENT", current_weather_type = "Dry", current_track_condition = "dry", next_change_summary = nil, change_eta_min_lower = nil, change_eta_min_upper = nil, authoritative = false, expected_tyre_crossover = nil, strategy_implication = "M3 remains the correct dry compound.", source_type = "measured_current", confidence_band = "high" },
      primary_instruction = { instruction = "none", instruction_source = "none", priority = "low", requires_acknowledgement = false },
      confidence_badge = "high",
      reason_codes = { "WEATHER_CURRENT_ONLY" },
    },
    fuel_details = { distance_to_pit_entry_m = 2120, pit_route_addition_m = 200, predicted_at_pit_entry_l = 13.9, required_saving_l_per_lap = nil, target_fuel_l = 17.5 },
    pace_details = { last_representative_lap_s = 494.231, status = "ON TARGET", trend = { -0.02, 0.08, 0.18, 0.12, 0.18 } },
    tyre_details = { compound = "M3", wear_percent = 68, condition = "GOOD", temperature_state = "BALANCED", wheel_values = { "FL 68C", "FR 69C", "RL 65C", "RR 66C" }, next_stop_compound = "M3" },
    pit_details = { earliest_lap = 24, optimal_lap = 25, latest_lap = 26, window_text = "LAP 24 - 26", recommendation = "ON PLAN", next_stop_fuel_l = 46, next_stop_tyres = "M3", service = "No repairs" },
    weather_timeline = {
      { horizon = "NOW", weather = "Dry", condition = "DRY", temperature = "24 C", label = "CURRENT" },
      { horizon = "+5", weather = "Dry", condition = "DRY", temperature = "24 C", label = "CURRENT" },
      { horizon = "+10", weather = "Dry", condition = "DRY", temperature = "23 C", label = "CURRENT" },
      { horizon = "+15", weather = "Dry", condition = "DRY", temperature = "23 C", label = "CURRENT" },
      { horizon = "+20", weather = "Dry", condition = "DRY", temperature = "23 C", label = "CURRENT" },
      { horizon = "+25", weather = "Dry", condition = "DRY", temperature = "22 C", label = "CURRENT" },
      { horizon = "+30", weather = "Dry", condition = "DRY", temperature = "22 C", label = "CURRENT" },
    },
    engineer_message = { text = "RUN TO PLAN", detail = "No urgent instruction", priority = "low", family = "state", alert_id = "state-on-plan", requires_acknowledgement = false, supersedes = nil },
    connections = { engineer = "Connected", bridge = "Online", telemetry_age_ms = 120, source_label = "MOCK FIXTURE" },
  }
end

local function apply_overlay(envelope, id)
  envelope.scenario_id = id
  local snapshot = envelope.driver_status_snapshot
  if id == "FUEL_SAVE_REQUIRED" then
    snapshot.fuel_summary.fuel_delta_to_plan_l = -1.8
    snapshot.fuel_summary.fuel_laps_remaining = 4.9
    snapshot.pace_summary.pace_delta_to_target_s_per_lap = 0.65
    snapshot.pit_summary.primary_call = "save_fuel"
    snapshot.primary_instruction.instruction = "save_fuel"
    snapshot.primary_instruction.instruction_source = "forecast_engine"
    snapshot.confidence_badge = "medium"
    snapshot.reason_codes = { "FUEL_MODEL_ESTIMATED", "FUEL_RESERVE_BELOW_TARGET" }
    envelope.fuel_details.required_saving_l_per_lap = 0.12
    envelope.pace_details.status = "SAVE"
    set_message(envelope, "SAVE FUEL", "high", false, "fuel_state")
  elseif id == "EXCESS_FUEL_PUSH" then
    snapshot.fuel_summary.fuel_delta_to_plan_l = 2.4
    snapshot.fuel_summary.fuel_laps_remaining = 7.1
    snapshot.pace_summary.pace_delta_to_target_s_per_lap = -0.35
    snapshot.pace_summary.rolling_trend = "improving"
    snapshot.pit_summary.primary_call = "push"
    snapshot.primary_instruction.instruction = "push"
    snapshot.primary_instruction.instruction_source = "forecast_engine"
    snapshot.reason_codes = {}
    envelope.pace_details.status = "PUSH"
    envelope.engineer_message = { text = "PUSH", detail = "Safe fuel margin", priority = "normal", family = "pace_state", alert_id = "push-safe", requires_acknowledgement = false }
  elseif id == "BOX_THIS_LAP" then
    snapshot.pit_summary.pit_window_state = "box_now"
    snapshot.pit_summary.primary_call = "box_this_lap"
    snapshot.primary_instruction.instruction = "box_this_lap"
    snapshot.primary_instruction.instruction_source = "engineer"
    snapshot.primary_instruction.priority = "critical"
    snapshot.reason_codes = { "PIT_WINDOW_OPEN" }
    envelope.pit_details.recommendation = "BOX THIS LAP"
    set_message(envelope, "BOX BOX - THIS LAP", "critical", true, "pit_call")
    envelope.engineer_message.detail = "Fuel 46 L  |  M3 tyres  |  No repairs"
  elseif id == "BOX_IN_THREE_LAPS" then
    snapshot.pit_summary.pit_window_state = "prepare"
    snapshot.pit_summary.primary_call = "box_in_n_laps"
    snapshot.pit_summary.box_in_laps = 3
    snapshot.primary_instruction.instruction = "box_in_laps"
    snapshot.primary_instruction.instruction_source = "forecast_engine"
    snapshot.primary_instruction.priority = "high"
    snapshot.primary_instruction.requires_acknowledgement = true
    snapshot.reason_codes = { "PIT_WINDOW_NOT_OPEN" }
    envelope.pit_details.recommendation = "BOX IN 3 LAPS"
    set_message(envelope, "BOX IN 3 LAPS", "high", true, "pit_call")
  elseif id == "STAY_OUT" then
    snapshot.pit_summary.pit_window_state = "open"
    snapshot.pit_summary.primary_call = "stay_out"
    snapshot.primary_instruction.instruction = "stay_out"
    snapshot.primary_instruction.instruction_source = "engineer"
    snapshot.primary_instruction.priority = "high"
    snapshot.reason_codes = { "STRATEGY_REVISION_ACCEPTED" }
    envelope.pit_details.recommendation = "STAY OUT"
    set_message(envelope, "STAY OUT", "high", true, "pit_call", "box-previous")
  elseif id == "ESTIMATED_RAIN" then
    snapshot.weather_summary.label = "ESTIMATED"
    snapshot.weather_summary.next_change_summary = "Light rain"
    snapshot.weather_summary.change_eta_min_lower = 8
    snapshot.weather_summary.change_eta_min_upper = 12
    snapshot.weather_summary.expected_tyre_crossover = "CROSSOVER NEAR LAP 24"
    snapshot.weather_summary.strategy_implication = "Prepare an intermediate tyre decision."
    snapshot.weather_summary.source_type = "estimated_model"
    snapshot.weather_summary.confidence_band = "medium"
    snapshot.weather_forecast_id = "weather-f1-estimated-001"
    snapshot.reason_codes = { "WEATHER_ESTIMATED_ONLY" }
    envelope.weather_timeline[3].weather = "Light rain"
    envelope.weather_timeline[3].condition = "DAMP"
    envelope.weather_timeline[3].label = "ESTIMATED"
    envelope.weather_timeline[4].weather = "Rain"
    envelope.weather_timeline[4].condition = "WETTING"
    envelope.weather_timeline[4].label = "ESTIMATED"
    envelope.engineer_message = { text = "RAIN EXPECTED", detail = "8-12 MIN | ESTIMATED | MEDIUM CONFIDENCE", priority = "normal", family = "weather_or_traffic", alert_id = "rain-estimated", requires_acknowledgement = false }
  elseif id == "SCHEDULED_HEAVY_RAIN" then
    snapshot.weather_summary.label = "SCHEDULED"
    snapshot.weather_summary.next_change_summary = "Heavy rain"
    snapshot.weather_summary.change_eta_min_lower = 10
    snapshot.weather_summary.change_eta_min_upper = 10
    snapshot.weather_summary.authoritative = true
    snapshot.weather_summary.expected_tyre_crossover = "WET CROSSOVER LAP 22"
    snapshot.weather_summary.strategy_implication = "Pit for wet tyres before the scheduled cell."
    snapshot.weather_summary.source_type = "controller_schedule"
    snapshot.weather_summary.confidence_band = "high"
    snapshot.weather_forecast_id = "weather-f1-scheduled-001"
    snapshot.reason_codes = { "WEATHER_SCHEDULE_AUTHORITATIVE" }
    for index = 3, 7 do
      envelope.weather_timeline[index].weather = "Heavy rain"
      envelope.weather_timeline[index].condition = "WET"
      envelope.weather_timeline[index].label = "SCHEDULED"
    end
    envelope.engineer_message = { text = "HEAVY RAIN SCHEDULED", detail = "IN 10 MIN | CONTROLLER SCHEDULE", priority = "high", family = "weather_or_traffic", alert_id = "rain-scheduled", requires_acknowledgement = false }
  elseif id == "UNKNOWN_FUTURE_WEATHER" then
    snapshot.weather_summary.label = "UNKNOWN"
    snapshot.weather_summary.next_change_summary = nil
    snapshot.weather_summary.change_eta_min_lower = nil
    snapshot.weather_summary.change_eta_min_upper = nil
    snapshot.weather_summary.source_type = "unknown"
    snapshot.weather_summary.confidence_band = "blocked"
    snapshot.weather_summary.strategy_implication = nil
    snapshot.weather_forecast_id = nil
    snapshot.confidence_badge = "blocked"
    snapshot.reason_codes = { "WEATHER_UNKNOWN_FUTURE" }
    for index = 2, 7 do
      envelope.weather_timeline[index].weather = "Unknown"
      envelope.weather_timeline[index].condition = "UNKNOWN"
      envelope.weather_timeline[index].label = "UNKNOWN"
    end
    envelope.engineer_message = { text = "WEATHER UNKNOWN", detail = "CURRENT DRY CONDITIONS RETAINED", priority = "normal", family = "weather_or_traffic", alert_id = "weather-unknown", requires_acknowledgement = false }
  elseif id == "STALE_WEATHER" then
    snapshot.connection_state = "stale"
    snapshot.weather_summary.label = "STALE"
    snapshot.weather_summary.next_change_summary = nil
    snapshot.weather_summary.change_eta_min_lower = nil
    snapshot.weather_summary.change_eta_min_upper = nil
    snapshot.weather_summary.source_type = "estimated_model"
    snapshot.weather_summary.confidence_band = "low"
    snapshot.weather_summary.strategy_implication = nil
    snapshot.confidence_badge = "low"
    snapshot.reason_codes = { "WEATHER_SOURCE_STALE", "TELEMETRY_STALE" }
    envelope.connections.bridge = "STALE"
    envelope.connections.telemetry_age_ms = 12600
    envelope.engineer_message = { text = "WEATHER STALE", detail = "LAST KNOWN CURRENT CONDITION RETAINED", priority = "high", family = "connection_state", alert_id = "weather-stale", requires_acknowledgement = false }
  elseif id == "LOW_CONFIDENCE_FORECAST" then
    snapshot.confidence_badge = "low"
    snapshot.pit_summary.primary_call = "low_confidence"
    snapshot.primary_instruction.instruction = "low_confidence"
    snapshot.primary_instruction.instruction_source = "forecast_engine"
    snapshot.reason_codes = { "SAMPLE_SET_TOO_SMALL", "FORECAST_HORIZON_LONG" }
    envelope.engineer_message = { text = "LOW CONFIDENCE", detail = "INSUFFICIENT REPRESENTATIVE SAMPLES", priority = "normal", family = "stint_state", alert_id = "low-confidence", requires_acknowledgement = false }
  elseif id == "WAITING_FOR_VALID_DATA" then
    snapshot.connection_state = "degraded"
    snapshot.stint_summary.current_stint_number = nil
    snapshot.stint_summary.stint_progress_ratio = nil
    snapshot.fuel_summary.fuel_remaining_l = nil
    snapshot.fuel_summary.fuel_laps_remaining = nil
    snapshot.fuel_summary.fuel_delta_to_plan_l = nil
    snapshot.pace_summary.pace_delta_to_target_s_per_lap = nil
    snapshot.pace_summary.rolling_trend = "unknown"
    snapshot.pit_summary.pit_window_state = "unknown"
    snapshot.pit_summary.primary_call = "waiting_for_valid_data"
    snapshot.weather_summary.label = "UNKNOWN"
    snapshot.weather_summary.current_weather_type = nil
    snapshot.weather_summary.current_track_condition = "unknown"
    snapshot.weather_summary.source_type = nil
    snapshot.weather_summary.confidence_band = "blocked"
    snapshot.confidence_badge = "blocked"
    snapshot.primary_instruction.instruction = "waiting_for_valid_data"
    snapshot.primary_instruction.instruction_source = "local_safe_fallback"
    snapshot.reason_codes = { "TELEMETRY_MISSING_REQUIRED_FIELD", "CALCULATION_BLOCKED" }
    envelope.engineer_message = { text = "WAITING FOR VALID DATA", detail = "NO ZERO SUBSTITUTION", priority = "normal", family = "connection_state", alert_id = "waiting-data", requires_acknowledgement = false }
  elseif id == "BRIDGE_OFFLINE" then
    snapshot.connection_state = "stale"
    snapshot.reason_codes = { "TELEMETRY_STALE" }
    envelope.connections.bridge = "OFFLINE"
    envelope.connections.telemetry_age_ms = 18500
    envelope.engineer_message = { text = "BRIDGE OFFLINE", detail = "LAST SAFE SNAPSHOT RETAINED", priority = "high", family = "connection_state", alert_id = "bridge-offline", requires_acknowledgement = false }
  elseif id == "ENGINEER_OFFLINE" then
    snapshot.connection_state = "degraded"
    snapshot.primary_instruction.instruction_source = "local_safe_fallback"
    snapshot.reason_codes = { "ENGINEER_CHANNEL_UNAVAILABLE" }
    envelope.connections.engineer = "OFFLINE"
    envelope.engineer_message = { text = "ENGINEER OFFLINE", detail = "LOCAL RACE STATE REMAINS VISIBLE", priority = "high", family = "connection_state", alert_id = "engineer-offline", requires_acknowledgement = false }
  elseif id == "MALFORMED_SNAPSHOT" then
    envelope.fixture_status = "malformed"
    envelope.driver_status_snapshot = { schema_version = "broken", snapshot_id = nil }
    envelope.engineer_message = { text = "FALLBACK SHELL", detail = "MALFORMED FIXTURE", priority = "high", family = "connection_state", alert_id = "malformed", requires_acknowledgement = false }
  elseif id == "TRAFFIC_WARNING" then
    snapshot.primary_instruction.instruction = "push"
    snapshot.primary_instruction.instruction_source = "engineer"
    snapshot.reason_codes = { "TRAFFIC_APPROACHING" }
    envelope.connections.source_label = "MOCK FIXTURE | TRAFFIC"
    envelope.engineer_message = { text = "FASTER CLASS APPROACHING", detail = "TRAFFIC AHEAD - HOLD LINE", priority = "high", family = "weather_or_traffic", alert_id = "traffic-faster-class", requires_acknowledgement = false }
  elseif id == "SETUP_AVAILABLE" then
    snapshot.primary_instruction.instruction_source = "engineer"
    snapshot.reason_codes = { "SETUP_AVAILABLE" }
    envelope.engineer_message = { text = "SETUP AVAILABLE", detail = "GARAGE REVIEW ONLY - NO AUTO APPLY", priority = "low", family = "engineer_message", alert_id = "setup-available", requires_acknowledgement = false }
  elseif id == "REPLAN_REQUIRED" then
    snapshot.pit_summary.primary_call = "replan_required"
    snapshot.primary_instruction.instruction = "replan_required"
    snapshot.primary_instruction.instruction_source = "forecast_engine"
    snapshot.primary_instruction.priority = "high"
    snapshot.primary_instruction.requires_acknowledgement = true
    snapshot.confidence_badge = "low"
    snapshot.reason_codes = { "STRATEGY_INFEASIBLE", "REPLAN_REQUIRED" }
    envelope.engineer_message = { text = "REPLAN REQUIRED", detail = "CURRENT ACCEPTED PLAN IS NOT FEASIBLE", priority = "high", family = "stint_state", alert_id = "replan-required", requires_acknowledgement = true }
  end
  return envelope
end

local scenario_order = {
  "NORMAL_ON_PLAN_DRY", "FUEL_SAVE_REQUIRED", "EXCESS_FUEL_PUSH", "BOX_THIS_LAP", "BOX_IN_THREE_LAPS", "STAY_OUT",
  "ESTIMATED_RAIN", "SCHEDULED_HEAVY_RAIN", "UNKNOWN_FUTURE_WEATHER", "STALE_WEATHER", "LOW_CONFIDENCE_FORECAST",
  "WAITING_FOR_VALID_DATA", "BRIDGE_OFFLINE", "ENGINEER_OFFLINE", "MALFORMED_SNAPSHOT", "TRAFFIC_WARNING", "SETUP_AVAILABLE", "REPLAN_REQUIRED",
}

function scenarios.list()
  local result = {}
  for index = 1, #scenario_order do
    result[index] = scenario_order[index]
  end
  return result
end

function scenarios.load(id)
  local chosen = id or namespace.config.default_scenario
  local result = base()
  if chosen ~= "NORMAL_ON_PLAN_DRY" then
    result = apply_overlay(result, chosen)
  end
  result.scenario_id = chosen
  return result
end

namespace.mock_scenarios = scenarios
