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

local function live_metric(metric, places)
  return formatting.metric(metric, places, formatting.reason(metric and metric.reason))
end

local function live_duration(metric)
  if type(metric) ~= "table" or metric.value == nil then
    return formatting.reason(metric and metric.reason)
  end
  return formatting.duration(metric.value)
end

local function live_safe(value)
  return value == nil and "Unavailable" or tostring(value)
end

local function live_reduce(status, mode)
  status = status or {}
  local chosen_mode = mode or "compact"
  local identity = status.identity or {}
  local session = status.session or {}
  local fuel = status.fuel or {}
  local pace = status.pace or {}
  local tyres = status.tyres or {}
  local weather = status.weather or {}
  local current_weather = weather.current or {}
  local future = weather.future or {}
  local diagnostics = status.diagnostics or {}
  local source = status.source or { mode = "recovery", label = "Recovery" }
  local alert = status.alerts and status.alerts[1] or nil
  local state = source.mode == "live" and "live" or source.mode == "mock" and "degraded" or "degraded"
  local progress_metric = status.stint and status.stint.progress or nil
  local progress = progress_metric and progress_metric.value or nil
  local source_label = source.label or "Recovery"
  local source_tone = source.mode == "live" and "good" or source.mode == "mock" and "warning" or "critical"
  local weather_label = current_weather.weather_type and "CURRENT" or "UNKNOWN"
  local weather_type = formatting.weather_type(current_weather.weather_type)
  local weather_condition = type(current_weather.track_wetness) == "number" and (current_weather.track_wetness > 0.08 and "WET" or "DRY") or "UNKNOWN"
  local connection_age = source.freshness_s and formatting.number(source.freshness_s * 1000, 0, " ms") or "Unavailable"
  local alert_label = alert and alert.label or "Live measurements only"
  local pit_metric = status.pit and status.pit.distance or nil
  local pit_reason = status.pit and status.pit.calibration_reason or "PIT_ENTRY_NOT_CALIBRATED"
  local vm = {
    mode = chosen_mode,
    available = source.mode ~= "recovery",
    fallback = source.mode == "recovery",
    fallback_reason = formatting.reason(source.error),
    product_name = namespace.config.product_name,
    build_name = namespace.config.build_name,
    session_name = formatting.session_type(session.type),
    scenario_id = source.mode == "mock" and "MOCK" or "LIVE",
    lap = session.current_lap and ("" .. tostring(session.current_lap)) or "UNAVAILABLE",
    planned_lap = session.lap_limit and ("" .. tostring(session.lap_limit)) or "UNAVAILABLE",
    stint = live_metric(status.stint and status.stint.completed_laps, 0),
    total_stints = "UNAVAILABLE",
    progress = progress or 0,
    connection_state = state,
    connection_tone = state == "live" and "live" or "degraded",
    confidence = formatting.confidence(fuel.per_lap and fuel.per_lap.confidence_band),
    confidence_tone = fuel.per_lap and fuel.per_lap.confidence_band == "high" and "good" or "warning",
    alert = {
      text = alert_label,
      detail = alert and (alert.reason or "Measured local state") or "No live instruction is available",
      priority = alert and (alert.priority and alert.priority <= 2 and "high" or "normal") or "low",
      tone = alert and alert.priority and alert.priority <= 2 and "warning" or "info",
      requires_acknowledgement = false,
      alert_id = alert and alert.kind or "live-measurements",
      family = "live_measurements",
      status = "VISIBLE",
    },
    timing = {
      elapsed = live_duration(status.stint and status.stint.elapsed),
      remaining = live_duration(status.stint and status.stint.remaining),
      target = live_duration(status.stint and status.stint.endpoint),
      remaining_is_estimated = false,
      progress = progress or 0,
    },
    fuel = {
      current = live_metric(fuel.current, 1),
      range = live_metric(fuel.laps_remaining, 1),
      distance_to_pit = live_metric(pit_metric, 0),
      pit_route = "Unavailable",
      expected_at_pit = live_metric(fuel.predicted_at_pit, 1),
      delta = live_metric(fuel.delta_target, 1),
      required_saving = "Unavailable",
      next_stop = "Unavailable",
      used = live_metric(fuel.used_stint, 1),
      per_lap = live_metric(fuel.per_lap, 2),
      per_km = live_metric(fuel.per_km, 2),
      per_min = live_metric(fuel.per_min, 2),
      confidence = formatting.confidence(fuel.per_lap and fuel.per_lap.confidence_band),
      pit_reason = formatting.reason(pit_reason),
      predicted_metric = fuel.predicted_at_pit,
      target_delta = live_metric(fuel.delta_target, 1),
      status = alert and alert.kind or "MEASURED RANGE",
    },
    pace = {
      delta = live_metric(pace.delta, 2),
      delta_metric = pace.delta,
      status = pace.delta and pace.delta.value and pace.delta.value > 0.5 and "OFF TARGET" or "REPRESENTATIVE PACE",
      last_lap = live_metric(pace.current, 3),
      trend = "measured",
      trend_values = {},
      current = live_metric(pace.current, 3),
      rolling = live_metric(pace.rolling, 3),
      confidence = formatting.confidence(pace.rolling and pace.rolling.confidence_band),
    },
    tyres = {
      compound = formatting.weather_type(tyres.compound),
      wear = live_metric(tyres.wear, 0),
      condition = formatting.readable_tyre_state(tyres.state),
      state = formatting.readable_tyre_state(tyres.state),
      temperature = live_metric(tyres.core_c, 0) .. " / " .. live_metric(tyres.surface_c, 0),
      color_tone = tyres.state == "OPTIMAL" and "good" or "warning",
      color = theme and theme.tone and theme.tone("warning") or nil,
    },
    pit = {
      window = live_metric(pit_metric, 0),
      recommendation = alert and alert.label or formatting.reason(pit_reason),
      next_fuel = "Unavailable",
      next_tyres = "Unavailable",
      service = "Unavailable",
      state = pit_metric and "measured" or "unknown",
      box_in_laps = nil,
    },
    weather = {
      label = weather_label,
      current = weather_type,
      condition = weather_condition,
      next_change = future.text or "No reliable future forecast",
      eta = "NO ETA",
      source = current_weather.source or "CSP MEASURED CURRENT",
      confidence = "High confidence",
      implication = "No forecast promise",
      crossover = "NO TYRE CROSSOVER SIGNAL",
      authoritative = future.authoritative == true,
      temperatures = "Air " .. formatting.number(current_weather.ambient_c, 0, " °C") .. "  Road " .. formatting.number(current_weather.road_c, 0, " °C"),
      track = "Grip " .. formatting.number(current_weather.grip, 2, "") .. "  Wet " .. formatting.number(current_weather.track_wetness and current_weather.track_wetness * 100, 0, "%"),
      trend = weather.trend and weather.trend.text or "Measured trend: Unavailable",
      future = future.text or "No reliable future forecast",
      timeline = {},
    },
    connections = {
      engineer = "LOCAL ONLY",
      bridge = source.mode == "live" and "CSP LIVE" or source.mode == "mock" and "MOCK DIAGNOSTICS" or "SOURCE UNAVAILABLE",
      telemetry = connection_age,
      source = source_label,
    },
    header = {
      session = formatting.session_type(session.type),
      lap = session.current_lap and ("Lap " .. tostring(session.current_lap)) or "Lap unavailable",
      position = session.position and (tostring(session.position) .. "/" .. tostring(session.total_cars or "?")) or "Unavailable",
      source = source_label,
      source_mode = source.mode,
      source_tone = source_tone,
    },
    raw = {
      speed = formatting.number(status.car and status.car.speed_kmh, 0, " km/h"),
      spline = formatting.number(status.car and status.car.spline, 3, ""),
      pit_lane = status.car and (status.car.pit_lane and "Yes" or "No") or "Unavailable",
      pit_box = status.car and (status.car.pit_box and "Yes" or "No") or "Unavailable",
    },
    diagnostics = {
      samples_laps = diagnostics.sample_summary and diagnostics.sample_summary.laps or 0,
      samples_fuel = diagnostics.sample_summary and diagnostics.sample_summary.fuel or 0,
      samples_pace = diagnostics.sample_summary and diagnostics.sample_summary.pace or 0,
      samples_weather = diagnostics.sample_summary and diagnostics.sample_summary.weather or 0,
      regime = live_safe(diagnostics.current_regime),
      freshness = source.freshness_s and formatting.number(source.freshness_s, 1, " s") or "Unavailable",
      source_error = diagnostics.source_error,
      raw = diagnostics.raw,
    },
    calibration = {
      summary = diagnostics.calibration and ("Validated for " .. live_safe(diagnostics.calibration.track_id) .. " / " .. live_safe(diagnostics.calibration.layout_id)) or formatting.reason(pit_reason),
    },
    trace = status.trace or {},
  }
  return vm
end

function view_model.reduce(envelope, mode)
  if type(envelope) == "table" and envelope.schema_version == "driver-status-local-f2" then
    return live_reduce(envelope, mode)
  end
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
