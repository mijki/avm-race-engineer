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
  if type(metric) == "table" and metric.value ~= nil then
    return formatting.metric(metric, places, "--")
  end
  local reason = metric and metric.reason
  if reason == "INSUFFICIENT_SAMPLES" then return "Waiting for representative lap" end
  if reason == "PIT_ENTRY_NOT_CALIBRATED" then return "Pit entry not calibrated" end
  if reason == "PIT_ROUTE_NOT_CONFIGURED" then return "Pit route not configured" end
  if reason == "TARGET_NOT_CONFIGURED" then return "Not configured" end
  if reason == "UNSUPPORTED" then return "Unsupported" end
  if reason == "STALE_TELEMETRY" then return "Stale" end
  return "--"
end

local function live_duration(metric)
  if type(metric) == "table" and metric.value ~= nil then
    return formatting.duration(metric.value)
  end
  return metric and metric.reason == "INSUFFICIENT_SAMPLES" and "Waiting for representative lap" or "--"
end

local function live_safe(value)
  return value == nil and "Unavailable" or tostring(value)
end

local function live_number(value, decimals, suffix)
  return type(value) == "number" and formatting.number(value, decimals, suffix) or "--"
end

local function metric_tone(metric, threshold)
  if type(metric) ~= "table" or type(metric.value) ~= "number" or type(threshold) ~= "number" then
    return "neutral"
  end
  local magnitude = math.abs(metric.value)
  if magnitude >= threshold * 2 then return "critical" end
  if magnitude >= threshold then return "warning" end
  return "good"
end

local function display_metric(metric, places)
  return live_metric(metric, places)
end

local function live_reduce_v2(status, mode)
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
  local configuration = status.configuration or {}
  local source = status.source or { mode = "live", availability = "unavailable", label = "Source unavailable" }
  local availability = source.availability or "unavailable"
  local source_labels = { live = "LIVE", partial = "PARTIAL", stale = "STALE", unavailable = "OFFLINE", mock = "MOCK" }
  local source_label = source_labels[availability] or "OFFLINE"
  local source_tone = availability == "live" and "good" or availability == "stale" and "stale" or availability == "partial" and "warning" or "critical"
  local progress = status.stint and status.stint.progress and status.stint.progress.value or 0
  local engineer = status.engineer and status.engineer.active or nil
  local alert = status.alerts and status.alerts[1] or nil
  local current_or_alert_title = engineer and engineer.title or alert and alert.label or "NO ACTIVE INSTRUCTION"
  local current_or_alert_detail = engineer and engineer.detail or alert and alert.reason or "Measured current state · no urgent instruction"
  local alert_priority = engineer and engineer.priority or alert and alert.priority or 8
  if availability == "unavailable" then
    current_or_alert_title = "LIVE DATA UNAVAILABLE"
    current_or_alert_detail = "Open Garage diagnostics for the local CSP source failure."
    alert_priority = 1
  elseif availability == "stale" then
    current_or_alert_title = "LIVE DATA STALE"
    current_or_alert_detail = "Last valid values are retained; risky recommendations are suppressed."
    alert_priority = 3
  end
  local alert_tone = alert_priority <= 2 and "critical" or alert_priority <= 5 and "warning" or "info"
  local function health(state, label, detail)
    local good = state == "LIVE" or state == "CONNECTED"
    local degraded = state == "PARTIAL" or state == "STALE" or state == "DEGRADED"
    return {
      state = state,
      label = label,
      detail = detail,
      tone = good and "good" or degraded and "warning" or (state == "MOCK" or state == "NOT USED" or state == "NOT ASSIGNED") and "stale" or "critical",
      shape = good and "filled" or degraded and "warning" or (state == "MOCK" or state == "NOT USED" or state == "NOT ASSIGNED") and "hollow" or "crossed",
    }
  end
  local tel = health(source_label, "TEL", source.label or "Local CSP telemetry")
  local bridge = health("NOT USED", "BRG", "Bridge is not configured in the local-only slice")
  local engineer_health = health("NOT ASSIGNED", "ENG", "Engineer source is not configured")
  local pit_metric = status.pit and status.pit.distance or nil
  local pit_reason = status.pit and status.pit.calibration_reason or "PIT_ENTRY_NOT_CALIBRATED"
  local pressure_unit = configuration.pressure_unit == "kPa" and "kPa" or "psi"
  local pace_threshold = configuration.pace_delta_threshold_s or 0.50
  local fuel_threshold = configuration.fuel_comparison_threshold_l or 0.05
  local pressure_threshold = configuration.pressure_delta_threshold_psi or 0.50
  local wheel_values = {}
  for index = 1, 4 do
    local wheel = tyres.wheels and tyres.wheels[index] or {}
    local pressure_metric = pressure_unit == "kPa" and wheel.pressure_kpa or wheel.pressure_psi
    local pressure_target_metric = pressure_unit == "kPa" and wheel.pressure_target_kpa or wheel.pressure_target_psi
    local pressure_delta = pressure_unit == "kPa" and wheel.pressure_delta_kpa or wheel.pressure_delta_psi
    local damage = {}
    if wheel.flat_spot and wheel.flat_spot.value and wheel.flat_spot.value >= 10 then damage[#damage + 1] = "FLAT SPOT " .. live_metric(wheel.flat_spot, 0) end
    local wheel_tone = wheel.state == "FLAT_SPOTTED" and "critical" or wheel.state == "OPTIMAL" and "good" or wheel.state == "UNKNOWN" and "stale" or "warning"
    local pressure_tone = metric_tone(pressure_delta, pressure_threshold)
    local temperature_tone = metric_tone(wheel.temperature_delta_c, configuration.temperature_delta_threshold_c or 15)
    if wheel_tone == "good" and pressure_tone ~= "neutral" and pressure_tone ~= "good" then wheel_tone = pressure_tone end
    if wheel_tone == "good" and temperature_tone ~= "neutral" and temperature_tone ~= "good" then wheel_tone = temperature_tone end
    wheel_values[index] = {
      label = wheel.label or ({ "FL", "FR", "RL", "RR" })[index],
      temperature = live_metric(wheel.core_c, 0),
      temperature_target = live_metric(wheel.temperature_target_c, 0),
      temperature_delta = live_metric(wheel.temperature_delta_c, 0),
      lap_min = live_number(wheel.lap_min_c, 0, " C"),
      lap_max = live_number(wheel.lap_max_c, 0, " C"),
      pressure = display_metric(pressure_metric, 1),
      pressure_target = display_metric(pressure_target_metric, 1),
      pressure_target_source = wheel.pressure_target_source or "UNAVAILABLE",
      pressure_delta = live_metric(pressure_delta, 1),
      life = live_metric(wheel.life, 0),
      wear = live_metric(wheel.wear, 0),
      damage = #damage > 0 and table.concat(damage, " · ") or "",
      state = formatting.readable_tyre_state(wheel.state or "UNKNOWN"),
      grain = live_metric(wheel.grain, 0),
      blister = live_metric(wheel.blister, 0),
      tone = wheel_tone,
      pressure_tone = pressure_tone,
    }
  end
  local weather_type = current_weather.weather_type and formatting.weather_type(current_weather.weather_type, current_weather) or "Unknown"
  local weather_condition = formatting.track_condition(current_weather.track_wetness, current_weather.rain_intensity, "Unknown")
  local wind_speed = live_number(current_weather.wind_kmh, 0, " km/h")
  local wind_direction = current_weather.wind_cardinal or formatting.cardinal_direction(current_weather.wind_direction_deg, nil)
  local wind = wind_direction and wind_speed .. " · " .. wind_direction or (current_weather.wind_kmh and wind_speed or "Wind unavailable")
  local context = status.stint and status.stint.current_lap and live_metric(status.stint.current_lap, 0) or "--"
  local elapsed_context = live_duration(status.stint and status.stint.elapsed)
  local remaining_context = live_duration(status.stint and status.stint.remaining)
  local remaining_estimated = status.stint and status.stint.remaining and status.stint.remaining.value ~= nil and status.stint.remaining.reason ~= "session time"
  local header_parts = {}
  if status.stint and status.stint.current_lap and status.stint.current_lap.value ~= nil then
    header_parts[#header_parts + 1] = "STINT " .. formatting.number(status.stint.current_lap.value, 0, "")
  end
  if session.current_lap then header_parts[#header_parts + 1] = "LAP " .. tostring(session.current_lap) end
  if elapsed_context ~= "--:--" then header_parts[#header_parts + 1] = elapsed_context end
  if remaining_context ~= "--:--" then header_parts[#header_parts + 1] = remaining_context .. (remaining_estimated and "~" or "") end
  if session.remaining_s then header_parts[#header_parts + 1] = formatting.time(session.remaining_s) .. " LEFT" end
  local header_context = table.concat(header_parts, " / ")
  local connection_age = source.freshness_s and formatting.number(source.freshness_s * 1000, 0, " ms") or "--"
  return {
    mode = chosen_mode,
    available = availability ~= "unavailable",
    fallback = availability == "unavailable",
    fallback_reason = formatting.reason(source.error),
    product_name = namespace.config.product_name,
    build_name = namespace.config.build_name,
    session_name = formatting.session_type(session.type),
    scenario_id = source.mode == "mock" and "MOCK" or "LIVE",
    lap = session.current_lap and tostring(session.current_lap) or "--",
    planned_lap = session.lap_limit and tostring(session.lap_limit) or "--",
    stint = live_metric(status.stint and status.stint.completed_laps, 0),
    stint_lap = context,
    total_stints = "--",
    progress = progress,
    connection_state = availability,
    connection_tone = tone_for_connection(availability == "partial" and "degraded" or availability),
    confidence = formatting.confidence(fuel.per_lap and fuel.per_lap.confidence_band),
    confidence_tone = fuel.per_lap and fuel.per_lap.confidence_band == "high" and "good" or "warning",
    source = { availability = availability, state = source_label, label = source_label, detail = current_or_alert_detail, error = source.error, diagnostics = source.diagnostics },
    health = { telemetry = tel, bridge = bridge, engineer = engineer_health },
    alert = {
      text = formatting.reason(current_or_alert_title),
      detail = formatting.reason(current_or_alert_detail),
      priority = alert_priority <= 2 and "high" or alert_priority <= 5 and "normal" or "low",
      tone = alert_tone,
      requires_acknowledgement = engineer and engineer.requires_acknowledgement == true or alert and alert.requires_acknowledgement == true or false,
      acknowledged = engineer and engineer.acknowledged == true or false,
      alert_id = engineer and engineer.message_id or alert and alert.kind or "live-measurements",
      family = engineer and engineer.source or "live_measurements",
      status = engineer and engineer.acknowledged and "ACKNOWLEDGED" or engineer and engineer.requires_acknowledgement and "ACK" or "VISIBLE",
    },
    timing = {
      elapsed = live_duration(status.stint and status.stint.elapsed),
      remaining = live_duration(status.stint and status.stint.remaining),
      target = live_duration(status.stint and status.stint.endpoint),
      remaining_is_estimated = status.stint and status.stint.remaining and status.stint.remaining.value ~= nil and status.stint.remaining.reason ~= "session time" or false,
      progress = progress,
      context = context,
    },
    fuel = {
      current = live_metric(fuel.current, 1),
      range = live_metric(fuel.laps_remaining, 1),
      distance_to_pit = live_metric(pit_metric, 0),
      pit_route = live_number(status.pit and status.pit.route_additional_m, 0, " m"),
      expected_at_pit = live_metric(fuel.predicted_at_pit, 1),
      delta = live_metric(fuel.delta_target, 2),
      target = live_metric(fuel.target_per_lap, 2),
      average = live_metric(fuel.per_lap, 2),
      latest_valid = live_metric(fuel.latest_valid, 2),
      latest_completed = live_metric(fuel.latest_completed, 2),
      vs_target = live_metric(fuel.delta_target, 2),
      vs_average = live_metric(fuel.delta_average, 2),
      average_vs_target = live_metric(fuel.average_vs_target, 2),
      required_saving = "--",
      next_stop = "--",
      used = live_metric(fuel.used_stint, 1),
      per_lap = live_metric(fuel.per_lap, 2),
      per_km = live_metric(fuel.per_km, 2),
      per_min = live_metric(fuel.per_min, 2),
      confidence = formatting.confidence(fuel.per_lap and fuel.per_lap.confidence_band),
      pit_reason = formatting.reason(pit_reason),
      predicted_metric = fuel.predicted_at_pit,
      target_delta = live_metric(fuel.delta_target, 2),
      status = alert and alert.kind == "SAVE_FUEL" and "SAVE FUEL" or "Measured range",
      tone = metric_tone(fuel.delta_target, fuel_threshold),
    },
    pace = {
      delta = live_metric(pace.delta_to_target or pace.delta, 2),
      delta_metric = pace.delta_to_target or pace.delta,
      target = live_metric(pace.target, 3),
      average = live_metric(pace.rolling, 3),
      latest_valid = live_metric(pace.latest_valid, 3),
      latest_completed = live_metric(pace.latest_completed, 3),
      vs_target = live_metric(pace.delta_to_target, 3),
      vs_average = live_metric(pace.delta_to_average, 3),
      average_vs_target = live_metric(pace.average_vs_target, 3),
      status = availability == "unavailable" and "--" or pace.delta_to_target and pace.delta_to_target.value and pace.delta_to_target.value > pace_threshold and "SLOWER THAN TARGET" or pace.latest_valid and pace.latest_valid.value and "ON TARGET" or "WAITING FOR VALID LAP",
      tone = metric_tone(pace.delta_to_target, pace_threshold),
      last_lap = live_metric(pace.latest_valid, 3),
      trend = formatting.confidence(pace.rolling and pace.rolling.confidence_band),
      trend_values = {},
      current = live_metric(pace.current, 3),
      rolling = live_metric(pace.rolling, 3),
      confidence = formatting.confidence(pace.rolling and pace.rolling.confidence_band),
    },
    tyres = {
      compound = tyres.compound and formatting.weather_type(tyres.compound) or "--",
      wear = live_metric(tyres.wear, 0),
      condition = formatting.readable_tyre_state(tyres.state or "UNKNOWN"),
      state = formatting.readable_tyre_state(tyres.state or "UNKNOWN"),
      temperature = live_metric(tyres.core_c, 0) .. " / " .. live_metric(tyres.surface_c, 0),
      wheels = wheel_values,
      wheel_values = wheel_values,
      temperature_source = tyres.temperature_source or "CSP tyreCoreTemperature",
      color_tone = tyres.state == "OPTIMAL" and "good" or tyres.state == "UNKNOWN" and "stale" or "warning",
    },
    pit = {
      window = live_metric(pit_metric, 0),
      recommendation = alert and formatting.reason(alert.label) or (pit_metric and "CALIBRATED" or "CONFIGURE IN GARAGE"),
      next_fuel = "--",
      next_tyres = "--",
      service = "--",
      state = status.pit and status.pit.calibrated and "CALIBRATED" or "NOT CALIBRATED",
      live_state = status.pit and status.pit.live_state or "ON_TRACK",
      live_pit_lane = status.pit and status.pit.live_pit_lane,
      live_pit_box = status.pit and status.pit.live_pit_box,
      marker_state = status.pit and status.pit.marker_state or "UNAVAILABLE",
      marker_confidence = status.pit and status.pit.marker_confidence or 0,
      observation_count = status.pit and status.pit.observation_count or 0,
      override = status.pit and status.pit.override == true or false,
      box_in_laps = nil,
    },
    weather = {
      label = "MEASURED",
      current = weather_type,
      condition = weather_condition,
      next_change = future.text or "No reliable future forecast",
      eta = "No ETA",
      source = current_weather.source or "Measured now",
      confidence = availability == "live" and "High confidence" or "Unknown",
      implication = "No forecast promise",
      crossover = "No tyre crossover signal",
      authoritative = future.authoritative == true,
      temperatures = "Air " .. live_number(current_weather.ambient_c, 0, " C") .. " / Road " .. live_number(current_weather.road_c, 0, " C"),
      wind = wind,
      wind_degrees = current_weather.wind_direction_deg and live_number(current_weather.wind_direction_deg, 0, "°") or "Unavailable",
      track = weather_condition .. " · " .. live_number(current_weather.track_wetness and current_weather.track_wetness * 100, 0, "% wet"),
      grip = current_weather.grip and formatting.grip(current_weather.grip) or "Unavailable",
      trend = weather.trend and weather.trend.text or "Trend unavailable",
      future = future.text or "No reliable future forecast",
      timeline = {},
    },
    connections = {
      engineer = "NOT ASSIGNED",
      bridge = "NOT USED",
      telemetry = connection_age,
      source = source_label,
      telemetry_state = tel.state,
      bridge_state = bridge.state,
      engineer_state = engineer_health.state,
    },
    header = {
      session = formatting.session_type(session.type),
      lap = session.current_lap and ("LAP " .. tostring(session.current_lap)) or "LAP --",
      position = session.position and session.total_cars and (tostring(session.position) .. "/" .. tostring(session.total_cars)) or "--",
      source = source_label,
      source_mode = source.mode,
      source_tone = source_tone,
      context = header_context,
      indicators = { telemetry = tel, bridge = bridge, engineer = engineer_health },
    },
    raw = {
      speed = live_number(status.car and status.car.speed_kmh, 0, " km/h"),
      spline = live_number(status.car and status.car.spline, 3, ""),
      pit_lane = status.car and (status.car.pit_lane == nil and "Unavailable" or status.car.pit_lane and "Yes" or "No") or "Unavailable",
      pit_box = status.car and (status.car.pit_box == nil and "Unavailable" or status.car.pit_box and "Yes" or "No") or "Unavailable",
    },
    diagnostics = {
      samples_laps = diagnostics.sample_summary and diagnostics.sample_summary.laps or 0,
      samples_fuel = diagnostics.sample_summary and diagnostics.sample_summary.fuel or 0,
      samples_pace = diagnostics.sample_summary and diagnostics.sample_summary.pace or 0,
      samples_weather = diagnostics.sample_summary and diagnostics.sample_summary.weather or 0,
      excluded_laps = diagnostics.sample_summary and diagnostics.sample_summary.excluded or 0,
      excluded_reason = diagnostics.sample_summary and diagnostics.sample_summary.latest_excluded_reason or nil,
      regime = live_safe(diagnostics.current_regime),
      freshness = source.freshness_s and formatting.number(source.freshness_s, 1, " s") or "--",
      update_age = source.diagnostics and source.diagnostics.update_age_s and formatting.number(source.diagnostics.update_age_s, 1, " s") or "--",
      source_error = source.error or diagnostics.source_error,
      first_failure = source.diagnostics and source.diagnostics.first_failure or source.error,
      probe = source.diagnostics and source.diagnostics.probe or "Unavailable",
      normalization_rejection = source.diagnostics and source.diagnostics.first_normalization_rejection or "None",
      api = source.diagnostics and source.diagnostics.api or {},
      core_valid = source.diagnostics and source.diagnostics.normalized_core and source.diagnostics.normalized_core.valid or false,
      core_missing = source.diagnostics and source.diagnostics.normalized_core and source.diagnostics.normalized_core.missing or {},
      optional_missing = source.diagnostics and source.diagnostics.optional_missing or {},
      identity = identity,
      last_reset_reason = diagnostics.last_reset_reason,
      raw = diagnostics.raw,
      calibration = diagnostics.calibration,
      calibration_armed = diagnostics.calibration_armed,
      pit_learning = diagnostics.pit_learning,
      engineer_history = status.engineer and status.engineer.history or {},
    },
    calibration = {
      summary = diagnostics.calibration and ("Validated for " .. live_safe(diagnostics.calibration.track_id) .. " / " .. live_safe(diagnostics.calibration.layout_id)) or formatting.reason(pit_reason),
      track_id = diagnostics.calibration and diagnostics.calibration.track_id,
      layout_id = diagnostics.calibration and diagnostics.calibration.layout_id,
      pit_entry_spline = diagnostics.calibration and diagnostics.calibration.pit_entry_spline,
      route_additional_m = status.pit and status.pit.route_additional_m,
      status = status.pit and status.pit.calibrated and "CALIBRATED" or "NOT CALIBRATED",
      armed = diagnostics.calibration_armed == true,
    },
    configuration = status.configuration or {},
    trace = status.trace or {},
  }
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
  local source = status.source or { mode = "live", availability = "unavailable", label = "Source unavailable" }
  local alert = status.alerts and status.alerts[1] or nil
  local availability = source.availability or (source.mode == "live" and "live" or source.mode == "mock" and "partial" or "unavailable")
  local state = availability
  local progress_metric = status.stint and status.stint.progress or nil
  local progress = progress_metric and progress_metric.value or nil
  local source_labels = { live = "LIVE", partial = "PARTIAL", stale = "STALE", unavailable = "OFFLINE", mock = "MOCK" }
  local source_label = source_labels[availability] or "OFFLINE"
  local source_tone = availability == "live" and "good" or availability == "stale" and "stale" or availability == "partial" and "warning" or "critical"
  local weather_label = current_weather.weather_type and "Measured" or "Unknown"
  local weather_type = current_weather.weather_type and formatting.weather_type(current_weather.weather_type) or "Unknown"
  local weather_condition = type(current_weather.track_wetness) == "number" and (current_weather.track_wetness > 0.08 and "Wet" or "Dry") or "Unknown"
  local connection_age = source.freshness_s and formatting.number(source.freshness_s * 1000, 0, " ms") or "--"
  local alert_label = alert and formatting.reason(alert.label) or "Measured current state"
  local alert_detail = alert and formatting.reason(alert.reason) or "No live instruction is available."
  if availability == "unavailable" then
    alert_label = "Live data unavailable"
    alert_detail = "Unable to read current CSP car/session telemetry. Open Garage diagnostics for details."
  elseif availability == "stale" then
    alert_label = "Live data stale"
    alert_detail = "The last valid sample is older than the live threshold."
  elseif availability == "partial" then
    alert_label = "Live data partial"
    alert_detail = "Some current telemetry fields are unavailable."
  elseif alert and alert.kind == "LOW_CONFIDENCE" then
    alert_label = "Waiting for representative lap"
    alert_detail = "Current car/session values are measured; model values are still warming up."
  end
  local pit_metric = status.pit and status.pit.distance or nil
  local pit_reason = status.pit and status.pit.calibration_reason or "PIT_ENTRY_NOT_CALIBRATED"
  local vm = {
    mode = chosen_mode,
    available = availability ~= "unavailable",
    fallback = availability == "unavailable",
    fallback_reason = formatting.reason(source.error),
    product_name = namespace.config.product_name,
    build_name = namespace.config.build_name,
    session_name = formatting.session_type(session.type),
    scenario_id = source.mode == "mock" and "MOCK" or "LIVE",
    lap = session.current_lap and ("" .. tostring(session.current_lap)) or "--",
    planned_lap = session.lap_limit and ("" .. tostring(session.lap_limit)) or "--",
    stint = live_metric(status.stint and status.stint.completed_laps, 0),
    total_stints = "--",
    progress = progress or 0,
    connection_state = state,
    connection_tone = state == "live" and "live" or state == "stale" and "stale" or state == "partial" and "degraded" or "offline",
    confidence = formatting.confidence(fuel.per_lap and fuel.per_lap.confidence_band),
    confidence_tone = fuel.per_lap and fuel.per_lap.confidence_band == "high" and "good" or "warning",
    source = {
      availability = availability,
      state = source_label,
      label = source_label,
      detail = alert_detail,
      error = source.error,
    },
    alert = {
      text = alert_label,
      detail = alert_detail,
      priority = availability == "unavailable" and "high" or alert and (alert.priority and alert.priority <= 2 and "high" or "normal") or "low",
      tone = availability == "unavailable" and "critical" or alert and alert.priority and alert.priority <= 2 and "warning" or "info",
      requires_acknowledgement = false,
      alert_id = alert and alert.kind or "live-measurements",
      family = "live_measurements",
      status = source_label,
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
      pit_route = "--",
      expected_at_pit = live_metric(fuel.predicted_at_pit, 1),
      delta = live_metric(fuel.delta_target, 1),
      required_saving = "--",
      next_stop = "--",
      used = live_metric(fuel.used_stint, 1),
      per_lap = live_metric(fuel.per_lap, 2),
      per_km = live_metric(fuel.per_km, 2),
      per_min = live_metric(fuel.per_min, 2),
      confidence = formatting.confidence(fuel.per_lap and fuel.per_lap.confidence_band),
      pit_reason = formatting.reason(pit_reason),
      predicted_metric = fuel.predicted_at_pit,
      target_delta = live_metric(fuel.delta_target, 1),
      status = availability == "unavailable" and "--" or alert and alert.kind == "SAVE_FUEL" and "SAVE FUEL" or "Measured range",
    },
    pace = {
      delta = live_metric(pace.delta, 2),
      delta_metric = pace.delta,
      status = availability == "unavailable" and "--" or pace.delta and pace.delta.value and pace.delta.value > 0.5 and "Off target" or pace.delta and pace.delta.value and "On target" or "Waiting for representative lap",
      last_lap = live_metric(pace.current, 3),
      trend = formatting.confidence(pace.rolling and pace.rolling.confidence_band),
      trend_values = {},
      current = live_metric(pace.current, 3),
      rolling = live_metric(pace.rolling, 3),
      confidence = formatting.confidence(pace.rolling and pace.rolling.confidence_band),
    },
    tyres = {
      compound = tyres.compound and formatting.weather_type(tyres.compound) or "--",
      wear = live_metric(tyres.wear, 0),
      condition = tyres.state and formatting.readable_tyre_state(tyres.state) or "Unknown",
      state = tyres.state and formatting.readable_tyre_state(tyres.state) or "Unknown",
      temperature = live_metric(tyres.core_c, 0) .. " / " .. live_metric(tyres.surface_c, 0),
      color_tone = tyres.state == "OPTIMAL" and "good" or "warning",
      color = nil,
    },
    pit = {
      window = live_metric(pit_metric, 0),
      recommendation = availability == "unavailable" and "--" or alert and formatting.reason(alert.label) or formatting.reason(pit_reason),
      next_fuel = "--",
      next_tyres = "--",
      service = "--",
      state = pit_metric and "Measured" or "Unknown",
      live_state = status.pit and status.pit.live_state or "ON_TRACK",
      live_pit_lane = status.pit and status.pit.live_pit_lane,
      live_pit_box = status.pit and status.pit.live_pit_box,
      marker_state = status.pit and status.pit.marker_state or "UNAVAILABLE",
      marker_confidence = status.pit and status.pit.marker_confidence or 0,
      observation_count = status.pit and status.pit.observation_count or 0,
      override = status.pit and status.pit.override == true or false,
      box_in_laps = nil,
    },
    weather = {
      label = weather_label,
      current = weather_type,
      condition = weather_condition,
      next_change = future.text or "No reliable future forecast",
      eta = "No ETA",
      source = current_weather.source or "Measured now",
      confidence = availability == "live" and "High confidence" or "Unknown",
      implication = "No forecast promise",
      crossover = "No tyre crossover signal",
      authoritative = future.authoritative == true,
      temperatures = "Air " .. live_number(current_weather.ambient_c, 0, " C") .. "  Road " .. live_number(current_weather.road_c, 0, " C"),
      track = "Grip " .. live_number(current_weather.grip, 2, "") .. "  Wet " .. live_number(current_weather.track_wetness and current_weather.track_wetness * 100, 0, "%"),
      trend = weather.trend and weather.trend.text or "Trend unavailable",
      future = future.text or "No reliable future forecast",
      timeline = {},
    },
    connections = {
      engineer = "Local only",
      bridge = availability == "live" and "Local CSP" or availability == "partial" and "Partial CSP" or availability == "stale" and "Stale CSP" or "Unavailable",
      telemetry = connection_age,
      source = source_label,
    },
    header = {
      session = formatting.session_type(session.type),
      lap = session.current_lap and ("Lap " .. tostring(session.current_lap)) or "Lap --",
      position = session.position and (tostring(session.position) .. "/" .. tostring(session.total_cars or "?")) or "--",
      source = source_label,
      source_mode = source.mode,
      source_tone = source_tone,
    },
    raw = {
      speed = live_number(status.car and status.car.speed_kmh, 0, " km/h"),
      spline = live_number(status.car and status.car.spline, 3, ""),
      pit_lane = status.car and (status.car.pit_lane == nil and "Unavailable" or status.car.pit_lane and "Yes" or "No") or "Unavailable",
      pit_box = status.car and (status.car.pit_box == nil and "Unavailable" or status.car.pit_box and "Yes" or "No") or "Unavailable",
    },
    diagnostics = {
      samples_laps = diagnostics.sample_summary and diagnostics.sample_summary.laps or 0,
      samples_fuel = diagnostics.sample_summary and diagnostics.sample_summary.fuel or 0,
      samples_pace = diagnostics.sample_summary and diagnostics.sample_summary.pace or 0,
      samples_weather = diagnostics.sample_summary and diagnostics.sample_summary.weather or 0,
      regime = live_safe(diagnostics.current_regime),
      freshness = source.freshness_s and formatting.number(source.freshness_s, 1, " s") or "--",
      update_age = source.diagnostics and source.diagnostics.update_age_s and formatting.number(source.diagnostics.update_age_s, 1, " s") or "--",
      source_error = source.error or diagnostics.source_error,
      first_failure = source.diagnostics and source.diagnostics.first_failure or source.error,
      probe = source.diagnostics and source.diagnostics.probe or "Unavailable",
      normalization_rejection = source.diagnostics and source.diagnostics.first_normalization_rejection or "None",
      api = source.diagnostics and source.diagnostics.api or {},
      core_valid = source.diagnostics and source.diagnostics.normalized_core and source.diagnostics.normalized_core.valid or false,
      core_missing = source.diagnostics and source.diagnostics.normalized_core and source.diagnostics.normalized_core.missing or {},
      optional_missing = source.diagnostics and source.diagnostics.optional_missing or {},
      identity = identity,
      last_reset_reason = diagnostics.last_reset_reason,
      raw = diagnostics.raw,
      pit_learning = diagnostics.pit_learning,
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
    return live_reduce_v2(envelope, mode)
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
