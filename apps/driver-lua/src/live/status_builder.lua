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
    local result = {
      schema_version = "driver-status-local-f2",
      source = {
        mode = state.source_mode,
        label = state.source_mode == "live" and "Live telemetry" or "Mock diagnostics",
        error = state.source_error,
        freshness_s = calculation.freshness_s,
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
      },
      stint = calculation.stint,
      fuel = calculation.fuel,
      pace = calculation.pace,
      tyres = calculation.tyres,
      weather = {
        current = weather,
        trend = calculation.weather.trend,
        future = calculation.weather.future,
      },
      pit = calculation.pit,
      alerts = calculation.alerts,
      diagnostics = {
        sample_summary = namespace.live.sample_store.summary(state.samples),
        current_regime = state.stint.regime,
        stint_start_monotonic_s = state.stint.start_monotonic_s,
        fuel_at_stint_start_l = state.stint.start_fuel_l,
        calibration = state.calibration,
        raw = snapshot,
        source_error = state.source_error,
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
    return {
      schema_version = "driver-status-local-f2",
      source = { mode = "recovery", requested_mode = source_mode, label = "Recovery", error = reason, freshness_s = nil },
      identity = {},
      session = {}, car = {},
      stint = { elapsed = unavailable, completed_laps = unavailable, remaining = unavailable, endpoint = unavailable, progress = unavailable },
      fuel = { current = unavailable, used_stint = unavailable, per_lap = unavailable, per_km = unavailable, per_min = unavailable, laps_remaining = unavailable, time_remaining = unavailable, distance_remaining = unavailable, predicted_at_pit = unavailable, delta_target = unavailable },
      pace = { current = unavailable, previous_representative = unavailable, rolling = unavailable, delta = unavailable },
      tyres = { compound = nil, core_c = unavailable, surface_c = unavailable, wear = unavailable, pressure_kpa = unavailable, state = "UNKNOWN" },
      weather = { current = {}, trend = { label = "UNKNOWN", text = "Measured trend: Unavailable" }, future = namespace.live.weather.future() },
      pit = { distance = unavailable, calibrated = false, calibration_reason = reason },
      alerts = { { kind = "LOW_CONFIDENCE", label = "LIVE SOURCE UNAVAILABLE", priority = 2, reason = reason } },
      diagnostics = { sample_summary = state and namespace.live.sample_store.summary(state.samples) or {}, current_regime = "unknown", raw = nil, source_error = reason },
      trace = {},
      updated_s = nil,
    }
  end

  namespace.live.status_builder = status_builder
end
