do
  local namespace = _G.AVM_PITWALL_F1
  local status_builder = {}
  local contracts = namespace.contracts

  local function trace(vm_field, calc_field, raw_inputs, metric)
    return {
      view_model_field = vm_field,
      calculated_state_field = calc_field,
      raw_telemetry_inputs = raw_inputs,
      sample_count = metric and metric.sample_count or 0,
      confidence = metric and metric.confidence_band or "low",
      freshness_s = metric and metric.freshness_s or nil,
      reason = metric and metric.reason or "SOURCE_UNAVAILABLE",
    }
  end

  local function field_or(value, fallback)
    return value ~= nil and value or fallback
  end

  function status_builder.build(state, calculation, now_s)
    local snapshot = state.latest or {}
    local session = snapshot.session or {}
    local car = snapshot.car or {}
    local weather = calculation.weather.current or {}
    local availability = state.source_availability or "unavailable"
    local source_labels = {
      live = "Live",
      partial = "Partial live",
      stale = "Stale live",
      unavailable = "Source unavailable",
      mock = "Garage mock",
    }
    local engineer = state.engineer_active
    if type(engineer) == "table" and type(engineer.expiry_s) == "number" and now_s > engineer.expiry_s and engineer.requires_acknowledgement ~= true then
      engineer = nil
    end
    local result = {
      schema_version = "driver-status-local-f2",
      source = {
        mode = state.source_mode,
        availability = availability,
        health = state.source_health or "OFFLINE",
        label = source_labels[availability] or source_labels.unavailable,
        error = state.source_error,
        freshness_s = calculation.freshness_s,
        diagnostics = state.source_diagnostics,
      },
      health = {
        telemetry = availability,
        bridge = "NOT_USED",
        engineer = "NOT_ASSIGNED",
      },
      identity = contracts.identity(snapshot),
      session = {
        type = session.type,
        elapsed_s = session.elapsed_s,
        remaining_s = session.remaining_s,
        lap_limit = session.lap_limit,
        completed_laps = session.completed_laps,
        current_lap = session.current_lap,
        position = session.position,
        total_cars = session.total_cars,
        paused = session.paused,
        replay = session.replay,
        active = session.active,
      },
      car = {
        speed_kmh = car.speed_kmh,
        fuel_l = car.fuel_l,
        spline = car.spline,
        pit_lane = car.pit_lane,
        pit_box = car.pit_box,
        lap_time_s = car.lap_time_s,
        best_lap_time_s = car.best_lap_time_s,
        reset_counter = car.reset_counter,
        world_position = car.world_position,
      },
      pit_source = state.pit_source or {},
      stint = calculation.stint,
      fuel = calculation.fuel,
      pace = calculation.pace,
      tyres = calculation.tyres,
      weather = {
        current = weather,
        trend = calculation.weather.trend,
        future = calculation.weather.future,
      },
      pit = {
        distance = calculation.pit.distance,
        calibrated = calculation.pit.calibrated,
        calibration_reason = calculation.pit.calibration_reason,
        route_additional_m = calculation.pit.route_additional_m,
        live_state = state.pit_diagnostics and state.pit_diagnostics.state or "ON_TRACK",
        live_pit_lane = state.pit_diagnostics and state.pit_diagnostics.live_pit_lane or car.pit_lane,
        live_pit_box = state.pit_diagnostics and state.pit_diagnostics.live_pit_box or car.pit_box,
        marker_state = state.pit_diagnostics and state.pit_diagnostics.marker_state or "UNAVAILABLE",
        marker_confidence = state.pit_diagnostics and state.pit_diagnostics.confidence or 0,
        observation_count = state.pit_diagnostics and state.pit_diagnostics.accepted_observations or 0,
        rejected_observation_count = state.pit_diagnostics and state.pit_diagnostics.rejected_observations or 0,
        current_visit = state.pit_diagnostics and state.pit_diagnostics.current_visit,
        last_visit = state.pit_diagnostics and state.pit_diagnostics.last_visit,
        latest_observation = state.pit_diagnostics and state.pit_diagnostics.latest_observation,
        latest_rejection = state.pit_diagnostics and state.pit_diagnostics.latest_rejection,
        override = state.pit_marker and state.pit_marker.manual_override == true or false,
      },
      alerts = calculation.alerts,
      configuration = calculation.configuration or {},
      engineer = {
        active = engineer,
        history = state.engineer_history or {},
      },
      diagnostics = {
        sample_summary = namespace.live.sample_store.summary(state.samples),
        current_regime = state.stint.regime,
        stint_start_monotonic_s = state.stint.start_monotonic_s,
        fuel_at_stint_start_l = state.stint.start_fuel_l,
        calibration = state.calibration,
        calibration_armed = state.calibration_capture_armed_until ~= nil and now_s <= state.calibration_capture_armed_until,
        calibration_arm_expires_s = state.calibration_capture_armed_until,
        raw = snapshot,
        source_error = state.source_error,
        source_availability = availability,
        source_diagnostics = state.source_diagnostics,
        source_health = state.source_health or "OFFLINE",
        health = namespace.live.source_health.diagnostics(state.health_tracker),
        recent_snapshot_count = #(state.snapshot_history or {}),
        recent_events = state.recent_events or {},
        discontinuities = state.discontinuities or {},
        pit_source = state.pit_source or {},
        pit_learning = state.pit_diagnostics or {},
        last_reset_reason = state.last_reset_reason,
        excluded_laps = state.samples.excluded_laps,
        latest_excluded = state.samples.latest_excluded,
        engineer_history = state.engineer_history or {},
      },
      trace = {},
      updated_s = now_s,
    }
    result.trace["fuel.current"] = trace("fuel.current", "fuel.current", { "car.fuel_l" }, result.fuel.current)
    result.trace["fuel.per_lap"] = trace("fuel.range_laps", "fuel.per_lap", { "completed_lap.fuel_used_l" }, result.fuel.per_lap)
    result.trace["fuel.predicted_at_pit"] = trace("fuel.predicted_at_pit", "fuel.predicted_at_pit", { "car.fuel_l", "car.spline", "track.track_length_m", "calibration.pit_entry_spline" }, result.fuel.predicted_at_pit)
    result.trace["pace.rolling"] = trace("pace.rolling", "pace.rolling", { "completed_lap.lap_time_s" }, result.pace.rolling)
    result.trace["pit.distance"] = trace("pit.distance_to_entry", "pit.distance", { "car.spline", "track.track_length_m", "calibration.pit_entry_spline" }, result.pit.distance)
    result.trace["weather.current"] = trace("weather.current", "weather.current", { "sim.weatherType", "sim.rainWetness", "sim.ambientTemperature", "sim.roadTemperature" }, contracts.metric(weather.weather_type, "", 1, calculation.freshness_s, "high", "MEASURED_CURRENT"))
    return result
  end

  function status_builder.recovery(source_mode, reason, state)
    local unavailable = contracts.unavailable("", reason or "SOURCE_UNAVAILABLE", 0, nil)
    local source_diagnostics = state and state.source_diagnostics or nil
    return {
      schema_version = "driver-status-local-f2",
      source = { mode = source_mode or "live", availability = "unavailable", health = "OFFLINE", requested_mode = source_mode, label = "Source unavailable", error = reason, freshness_s = nil, diagnostics = source_diagnostics },
      health = { telemetry = "unavailable", bridge = "NOT_USED", engineer = "NOT_ASSIGNED" },
      identity = {},
      session = {}, car = {},
      stint = { elapsed = unavailable, completed_laps = unavailable, remaining = unavailable, endpoint = unavailable, progress = unavailable },
      fuel = { current = unavailable, used_stint = unavailable, per_lap = unavailable, per_km = unavailable, per_min = unavailable, laps_remaining = unavailable, time_remaining = unavailable, distance_remaining = unavailable, predicted_at_pit = unavailable, delta_target = unavailable },
      pace = { current = unavailable, previous_representative = unavailable, rolling = unavailable, delta = unavailable },
      tyres = { compound = nil, core_c = unavailable, surface_c = unavailable, wear = unavailable, pressure_kpa = unavailable, state = "UNKNOWN" },
      weather = { current = {}, trend = { label = "UNKNOWN", text = "Measured trend: Unavailable" }, future = namespace.live.weather.future() },
      pit = { distance = unavailable, calibrated = false, calibration_reason = reason, live_state = "ON_TRACK", live_pit_lane = false, live_pit_box = false, marker_state = "UNAVAILABLE", marker_confidence = 0, observation_count = 0, rejected_observation_count = 0, override = false },
      alerts = { { kind = "SOURCE_UNAVAILABLE", label = "LIVE DATA UNAVAILABLE", priority = 2, reason = reason } },
      engineer = { active = { message_id = "recovery:source", source = "LOCAL_CALCULATION", severity = "critical", title = "LIVE DATA UNAVAILABLE", detail = reason, priority = 2, requires_acknowledgement = false, acknowledged = false }, history = {} },
      diagnostics = { sample_summary = state and namespace.live.sample_store.summary(state.samples) or {}, current_regime = "unknown", raw = nil, source_error = reason, source_availability = "unavailable", source_health = "OFFLINE", source_diagnostics = source_diagnostics, last_reset_reason = state and state.last_reset_reason or nil, recent_snapshot_count = state and #(state.snapshot_history or {}) or 0, recent_events = state and state.recent_events or {} },
      trace = {},
      updated_s = nil,
    }
  end

  namespace.live.status_builder = status_builder
end
