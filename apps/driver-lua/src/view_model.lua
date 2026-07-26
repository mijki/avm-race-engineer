local namespace = _G.AVM_PITWALL_F1
local contracts = namespace.contracts
local formatting = namespace.formatting
local view_model = {}

local function text(value, fallback)
  return contracts.safe_text(value, fallback or "UNAVAILABLE")
end

local function tone_for_connection(state)
  if state == "live" then
    return "live"
  end
  if state == "degraded" then
    return "degraded"
  end
  if state == "stale" then
    return "stale"
  end
  return "offline"
end

local function tone_for_priority(priority)
  if priority == "critical" then
    return "critical"
  end
  if priority == "high" then
    return "warning"
  end
  return "info"
end

function view_model.fallback(mode, reason)
  return {
    mode = mode or "compact",
    available = false,
    fallback = true,
    fallback_reason = text(reason, "WAITING FOR VALID DATA"),
    product_name = namespace.config.product_name,
    session_name = "No valid session",
    connection_state = "degraded",
    connection_tone = "degraded",
    alert = { text = "FALLBACK SHELL", detail = "Visible safety surface retained", priority = "high", requires_acknowledgement = false },
    timing = { elapsed = "UNAVAILABLE", remaining = "UNAVAILABLE", target = "UNAVAILABLE", remaining_is_estimated = false, progress = 0 },
    fuel = { current = "UNAVAILABLE", range = "UNAVAILABLE", distance_to_pit = "UNAVAILABLE", pit_route = "UNAVAILABLE", expected_at_pit = "UNAVAILABLE", delta = "UNAVAILABLE" },
    pace = { delta = "UNAVAILABLE", status = "WAITING", last_lap = "UNAVAILABLE", trend = "unknown" },
    tyres = { compound = "UNAVAILABLE", wear = "UNAVAILABLE", condition = "UNKNOWN", temperature = "UNKNOWN", wheel_values = {} },
    pit = { window = "UNAVAILABLE", recommendation = "WAITING FOR VALID DATA", next_fuel = "UNAVAILABLE", next_tyres = "UNAVAILABLE", service = "UNAVAILABLE" },
    weather = { label = "UNKNOWN", current = "UNAVAILABLE", condition = "UNKNOWN", next_change = "NO TRUSTWORTHY FUTURE DATA", eta = "NO ETA", source = "UNKNOWN", confidence = "BLOCKED", implication = "No forecast promise", timeline = {} },
    connections = { engineer = "UNKNOWN", bridge = "UNKNOWN", telemetry = "UNKNOWN", source = "FALLBACK" },
  }
end

function view_model.reduce(envelope, mode)
  local chosen_mode = mode or "compact"
  local snapshot, wrapper = contracts.unwrap_snapshot(envelope)
  if snapshot == nil then
    return view_model.fallback(chosen_mode, "WAITING FOR VALID DATA")
  end
  local status = snapshot.primary_instruction
  local message = wrapper.engineer_message or {}
  local timing = wrapper.stint_timing or {}
  local fuel_details = wrapper.fuel_details or {}
  local pace_details = wrapper.pace_details or {}
  local tyre_details = wrapper.tyre_details or {}
  local pit_details = wrapper.pit_details or {}
  local weather_summary = snapshot.weather_summary or {}
  local connections = wrapper.connections or {}
  local active_text = message.text
  if type(active_text) ~= "string" or active_text == "" or message.family == "state" then
    active_text = status.instruction == "none" and "RUN TO PLAN" or string.upper(string.gsub(status.instruction or "ENGINEER MESSAGE", "_", " "))
  end
  local active_priority = message.priority or status.priority or "low"
  local active_detail = message.detail or "Latest valid instruction"
  local active_ack = message.requires_acknowledgement == true or status.requires_acknowledgement == true
  local state = snapshot.connection_state or "degraded"
  local progress = snapshot.stint_summary.stint_progress_ratio
  local weather_label = weather_summary.label or "UNKNOWN"
  local timeline = wrapper.weather_timeline or {}
  local result = {
    mode = chosen_mode,
    available = true,
    fallback = false,
    product_name = namespace.config.product_name,
    build_name = namespace.config.build_name,
    session_name = text(wrapper.session_name, "UNKNOWN SESSION"),
    scenario_id = wrapper.scenario_id or "UNKNOWN",
    lap = formatting.value(wrapper.lap_number, "", "UNAVAILABLE"),
    planned_lap = formatting.value(wrapper.planned_lap, "", "UNAVAILABLE"),
    stint = formatting.value(snapshot.stint_summary.current_stint_number, "", "UNAVAILABLE"),
    total_stints = formatting.value(snapshot.stint_summary.total_planned_stints, "", "UNAVAILABLE"),
    progress = progress or 0,
    connection_state = state,
    connection_tone = tone_for_connection(state),
    confidence = formatting.confidence(snapshot.confidence_badge),
    confidence_tone = snapshot.confidence_badge == "high" and "good" or snapshot.confidence_badge == "medium" and "warning" or "stale",
    alert = {
      text = text(active_text, "ENGINEER MESSAGE"),
      detail = text(active_detail, "No further detail"),
      priority = active_priority,
      tone = tone_for_priority(active_priority),
      requires_acknowledgement = active_ack,
      alert_id = message.alert_id or snapshot.snapshot_id,
      family = message.family or "engineer_message",
      status = active_ack and "ACK REQUIRED" or "VISIBLE",
    },
    timing = {
      elapsed = formatting.time(timing.elapsed_s),
      remaining = formatting.time(timing.remaining_s),
      target = formatting.time(timing.target_s),
      remaining_is_estimated = timing.remaining_is_estimated == true,
      progress = progress or 0,
    },
    fuel = {
      current = formatting.fuel(snapshot.fuel_summary.fuel_remaining_l),
      range = formatting.number(snapshot.fuel_summary.fuel_laps_remaining, 1, " laps"),
      distance_to_pit = formatting.distance(fuel_details.distance_to_pit_entry_m),
      pit_route = formatting.distance(fuel_details.pit_route_addition_m),
      expected_at_pit = formatting.fuel(fuel_details.predicted_at_pit_entry_l),
      delta = formatting.signed(snapshot.fuel_summary.fuel_delta_to_plan_l, "L"),
      required_saving = formatting.fuel(fuel_details.required_saving_l_per_lap),
      next_stop = formatting.fuel(snapshot.fuel_summary.next_stop_fuel_addition_l),
    },
    pace = {
      delta = formatting.signed(snapshot.pace_summary.pace_delta_to_target_s_per_lap, "s"),
      status = text(pace_details.status, "WAITING"),
      last_lap = formatting.lap_time(pace_details.last_representative_lap_s),
      trend = snapshot.pace_summary.rolling_trend or "unknown",
      trend_values = pace_details.trend or {},
    },
    tyres = {
      compound = text(tyre_details.compound, "UNAVAILABLE"),
      wear = formatting.number(tyre_details.wear_percent, 0, "%"),
      condition = text(tyre_details.condition, "UNKNOWN"),
      temperature = text(tyre_details.temperature_state, "UNKNOWN"),
      wheel_values = tyre_details.wheel_values or {},
      next_stop = text(tyre_details.next_stop_compound, "UNAVAILABLE"),
    },
    pit = {
      window = text(pit_details.window_text, "UNAVAILABLE"),
      recommendation = text(pit_details.recommendation, string.upper(string.gsub(snapshot.pit_summary.primary_call or "WAITING_FOR_VALID_DATA", "_", " "))),
      next_fuel = formatting.fuel(pit_details.next_stop_fuel_l),
      next_tyres = text(pit_details.next_stop_tyres, "UNAVAILABLE"),
      service = text(pit_details.service, "UNAVAILABLE"),
      state = snapshot.pit_summary.pit_window_state or "unknown",
      box_in_laps = snapshot.pit_summary.box_in_laps,
      earliest = pit_details.earliest_lap,
      optimal = pit_details.optimal_lap,
      latest = pit_details.latest_lap,
    },
    weather = {
      label = weather_label,
      current = text(weather_summary.current_weather_type, "UNAVAILABLE"),
      condition = string.upper(text(weather_summary.current_track_condition, "unknown")),
      next_change = text(weather_summary.next_change_summary, "NO TRUSTWORTHY FUTURE CHANGE"),
      eta = formatting.eta(weather_summary.change_eta_min_lower, weather_summary.change_eta_min_upper),
      source = string.upper(text(weather_summary.source_type, "unknown")),
      confidence = formatting.confidence(weather_summary.confidence_band),
      implication = text(weather_summary.strategy_implication, "No forecast promise"),
      crossover = text(weather_summary.expected_tyre_crossover, "NO TYRE CROSSOVER SIGNAL"),
      authoritative = weather_summary.authoritative == true,
      timeline = timeline,
    },
    connections = {
      engineer = text(connections.engineer, "UNKNOWN"),
      bridge = text(connections.bridge, "UNKNOWN"),
      telemetry = formatting.value(connections.telemetry_age_ms, " ms", "UNKNOWN"),
      source = text(connections.source_label, "MOCK FIXTURE"),
    },
  }
  if chosen_mode == "compact" then
    result.weather.timeline = { timeline[1], timeline[2], timeline[3] }
  elseif chosen_mode == "expanded" then
    result.weather.timeline = { timeline[1], timeline[2], timeline[3], timeline[4] }
  end
  return result
end

namespace.view_model = view_model
