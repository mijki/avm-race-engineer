do
  local namespace = _G.AVM_PITWALL_F1
  local csp = namespace.adapters.csp
  local identity = namespace.live.session_identity
  local lap_tracker = namespace.live.lap_tracker
  local stint_tracker = namespace.live.stint_tracker
  local store_api = namespace.live.sample_store
  local weather = namespace.live.weather
  local calculations = namespace.live.calculations
  local status_builder = namespace.live.status_builder
  local telemetry = {}

  function telemetry.new(config)
    return {
      source_mode = (config and config.default_source_mode) or "live",
      source_error = nil,
      latest = nil,
      identity = nil,
      lap = lap_tracker.new(),
      stint = stint_tracker.new(),
      samples = store_api.new(config and config.max_samples or 12, config and config.max_weather_samples or 20),
      weather = weather.new(config and config.max_weather_samples or 20),
      weather_current = nil,
      weather_trend = { label = "UNKNOWN", text = "Measured trend: Waiting for more readings" },
      calculation = nil,
      status = nil,
      last_derived_s = nil,
      last_weather_s = nil,
      calibration = nil,
    }
  end

  function telemetry.set_source_mode(state, mode, mock_fixture)
    if mode ~= "live" and mode ~= "mock" then return false end
    state.source_mode = mode
    state.source_error = nil
    if mode == "mock" then csp.set_mock_fixture(mock_fixture) else csp.clear_mock_fixture() end
    return true
  end

  function telemetry.set_calibration(state, calibration)
    state.calibration = calibration
  end

  local function enrich_identity(snapshot)
    snapshot.identity = identity.normalize(snapshot)
    return snapshot
  end

  local function reset_model_history(state, reason)
    store_api.reset(state.samples, reason)
    state.weather = weather.new(state.samples.weather_count)
    state.weather_current = nil
    state.weather_trend = { label = "UNKNOWN", text = "Measured trend: Waiting for more readings" }
    state.calculation = nil
    state.last_derived_s = nil
    state.last_weather_s = nil
  end

  function telemetry.update(state, now_s, config)
    local snapshot, reason = csp.read(state.source_mode, now_s)
    if snapshot == nil then
      state.latest = nil
      state.source_error = reason or "SOURCE_UNAVAILABLE"
      lap_tracker.reset(state.lap, "SOURCE_RECOVERY")
      stint_tracker.reset(state.stint, "SOURCE_RECOVERY")
      reset_model_history(state, "SOURCE_RECOVERY")
      state.status = status_builder.recovery(state.source_mode, state.source_error, state)
      return state.status
    end
    snapshot.observed_monotonic_s = snapshot.observed_monotonic_s or now_s
    snapshot = enrich_identity(snapshot)
    state.source_error = nil
    local previous = state.latest
    if previous then
      local identity_changed = previous.identity and previous.identity.key ~= snapshot.identity.key
      local lap_decreased = previous.session and snapshot.session and type(previous.session.completed_laps) == "number" and type(snapshot.session.completed_laps) == "number" and snapshot.session.completed_laps < previous.session.completed_laps
      local replay_changed = previous.session and snapshot.session and previous.session.replay ~= snapshot.session.replay
      local pit_boundary = previous.car and snapshot.car and previous.car.pit_lane ~= snapshot.car.pit_lane
      local refuel_jump = previous.car and snapshot.car and type(previous.car.fuel_l) == "number" and type(snapshot.car.fuel_l) == "number" and snapshot.car.fuel_l - previous.car.fuel_l > config.refuel_jump_l
      if identity_changed or lap_decreased or replay_changed or pit_boundary or refuel_jump then
        reset_model_history(state, identity_changed and "IDENTITY_CHANGED" or (lap_decreased and "SESSION_RESTART" or (replay_changed and "REPLAY_STATE_CHANGED" or (refuel_jump and "REFUEL_TRANSITION" or "PIT_BOUNDARY"))))
      end
    end
    state.latest = snapshot
    state.identity = snapshot.identity
    local lap_event = lap_tracker.update(state.lap, snapshot)
    stint_tracker.update(state.stint, snapshot, now_s, config.refuel_jump_l)
    if lap_event then
      if lap_event.accepted then
        store_api.add_lap(state.samples, lap_event)
        stint_tracker.accept_lap(state.stint, lap_event)
      end
    end
    if state.last_weather_s == nil or now_s - state.last_weather_s >= config.weather_update_period_s then
      state.weather_current = weather.update(state.weather, snapshot.environment, now_s)
      store_api.add_weather(state.samples, state.weather_current)
      state.weather_trend = weather.trend(state.weather)
      state.last_weather_s = now_s
    end
    if state.last_derived_s == nil or now_s - state.last_derived_s >= config.derived_update_period_s then
      state.calculation = calculations.compute({
        snapshot = snapshot,
        stint = state.stint,
        store = state.samples,
        calibration = state.calibration,
        config = config,
        now_s = now_s,
        weather = state.weather_current,
        weather_trend = state.weather_trend,
      })
      state.status = status_builder.build(state, state.calculation, now_s)
      state.last_derived_s = now_s
    end
    return state.status
  end

  function telemetry.current_status(state, now_s, config)
    if state.status == nil then return telemetry.update(state, now_s, config) end
    return state.status
  end

  namespace.live.telemetry = telemetry
end
