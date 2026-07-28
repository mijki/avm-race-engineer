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
  local source_health = namespace.live.source_health
  local race_events = namespace.live.race_events
  local telemetry = {}

  local function push_bounded(list, value, maximum)
    if value == nil then return end
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
  end

  local function health_availability(value)
    if value == "LIVE" then return "live" end
    if value == "PARTIAL" then return "partial" end
    if value == "STALE" then return "stale" end
    return "unavailable"
  end

  function telemetry.new(config)
    return {
      source_mode = (config and config.default_source_mode) or "live",
      source_availability = "unavailable",
      source_health = "OFFLINE",
      source_error = nil,
      source_diagnostics = csp.diagnostics(),
      health_tracker = source_health.new(config),
      latest = nil,
      sequence = 0,
      snapshot_history = {},
      snapshot_history_limit = (config and config.max_recent_snapshots) or 48,
      event_stream = race_events.new({ max_events = (config and config.max_events) or 128 }),
      recent_events = {},
      discontinuities = {},
      pit_source = {},
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
      calibration_capture_armed_until = nil,
      engineer_active = nil,
      engineer_history = {},
      engineer_last_id = nil,
      injected_engineer_message = nil,
      last_valid_s = nil,
      last_reset_reason = nil,
    }
  end

  function telemetry.set_source_mode(state, mode, mock_fixture)
    if mode ~= "live" and mode ~= "mock" then return false end
    state.source_mode = mode
    state.source_availability = "unavailable"
    state.source_health = "OFFLINE"
    state.source_error = nil
    state.health_tracker = source_health.new(namespace.config)
    state.event_stream = race_events.new({ max_events = namespace.config.max_events or 128 })
    state.snapshot_history = {}
    state.recent_events = {}
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
    state.last_reset_reason = reason
  end

  local function reset_stint_history(state, reason)
    store_api.reset_stint(state.samples, reason)
    state.last_reset_reason = reason
  end

  local function push_message(state, message)
    if type(message) ~= "table" then return end
    if state.engineer_last_id == message.message_id then
      if state.engineer_active and state.engineer_active.acknowledged == true then
        message.acknowledged = true
      end
      state.engineer_active = message
      return
    end
    state.engineer_last_id = message.message_id
    state.engineer_active = message
    state.engineer_history[#state.engineer_history + 1] = message
    while #state.engineer_history > 6 do table.remove(state.engineer_history, 1) end
  end

  local function update_engineer(state, calculation, now_s, config)
    if type(state.injected_engineer_message) == "table" then
      push_message(state, state.injected_engineer_message)
      return
    end
    local alert = calculation.alerts and calculation.alerts[1]
    local excluded = state.samples.latest_excluded
    local message
    if alert ~= nil then
      local severity = alert.priority and alert.priority <= 2 and "critical" or alert.priority and alert.priority <= 3 and "caution" or "info"
      message = {
        message_id = "local:" .. tostring(alert.kind),
        source = "LOCAL_CALCULATION",
        severity = severity,
        title = alert.label or "ENGINEER",
        detail = alert.reason or "Measured current state",
        created_s = now_s,
        expiry_s = now_s + (((config.alert_expiry_seconds or {}).low) or 35),
        priority = alert.priority or 5,
        requires_acknowledgement = alert.requires_acknowledgement == true,
        acknowledged = false,
        related_reason = alert.reason,
      }
    elseif excluded ~= nil then
      message = {
        message_id = "local:excluded:" .. tostring(excluded.lap_number or "latest"),
        source = "LOCAL_CALCULATION",
        severity = "info",
        title = "LATEST LAP EXCLUDED",
        detail = tostring(excluded.reason or "LAP_EXCLUDED") .. " · representative history preserved",
        created_s = now_s,
        expiry_s = now_s + 20,
        priority = 7,
        requires_acknowledgement = false,
        acknowledged = false,
        related_reason = excluded.reason,
      }
    else
      message = {
        message_id = "local:normal",
        source = "LOCAL_CALCULATION",
        severity = "info",
        title = "CONTINUE CURRENT PACE",
        detail = "Measured state · no urgent instruction",
        created_s = now_s,
        expiry_s = nil,
        priority = 8,
        requires_acknowledgement = false,
        acknowledged = false,
      }
    end
    push_message(state, message)
  end

  local function derive(state, now_s, config)
    state.calculation = calculations.compute({
      snapshot = state.latest,
      stint = state.stint,
      store = state.samples,
      calibration = state.calibration,
      config = config,
      now_s = now_s,
      weather = state.weather_current,
      weather_trend = state.weather_trend,
    })
    update_engineer(state, state.calculation, now_s, config)
    state.status = status_builder.build(state, state.calculation, now_s)
    state.last_derived_s = now_s
  end

  function telemetry.update(state, now_s, config)
    local snapshot, reason = csp.read(state.source_mode, now_s)
    state.source_diagnostics = csp.diagnostics()
    if snapshot == nil then
      state.source_error = reason or "SOURCE_UNAVAILABLE"
      local health = source_health.update(state.health_tracker, now_s, {
        source_mode = state.source_mode,
        usable_core = false,
        read_ok = false,
        reason = reason or "SOURCE_UNAVAILABLE",
      })
      state.source_health = health
      state.source_availability = source_health.availability(state.health_tracker)
      state.source_diagnostics.source_health = health
      state.source_diagnostics.health = source_health.diagnostics(state.health_tracker)
      if state.latest ~= nil and state.last_valid_s ~= nil then
        state.source_diagnostics.update_age_s = math.max(0, now_s - state.last_valid_s)
        derive(state, now_s, config)
      else
        lap_tracker.reset(state.lap, "SOURCE_RECOVERY")
        stint_tracker.reset(state.stint, "SOURCE_RECOVERY")
        reset_model_history(state, "SOURCE_RECOVERY")
        state.status = status_builder.recovery(state.source_mode, state.source_error, state)
      end
      return state.status
    end
    snapshot.observed_monotonic_s = snapshot.observed_monotonic_s or now_s
    state.sequence = state.sequence + 1
    snapshot.sequence = state.sequence
    snapshot = enrich_identity(snapshot)
    local missing_core = snapshot.missing_core or {}
    local optional_missing = snapshot.optional_missing or {}
    local health = source_health.update(state.health_tracker, now_s, {
      source_mode = state.source_mode,
      usable_core = #missing_core == 0,
      optional_degraded = #optional_missing > 0,
      read_ok = true,
      reason = #missing_core > 0 and "CORE_FIELDS_MISSING" or nil,
    })
    state.source_health = health
    state.source_availability = state.source_mode == "mock" and "mock" or health_availability(health)
    snapshot.schema_version = "telemetry-snapshot-v1"
    snapshot.snapshot_id = snapshot.snapshot_id or namespace.contracts.snapshot_id(snapshot.identity, state.sequence)
    snapshot.source_timestamp_s = snapshot.source_timestamp_s or snapshot.observed_monotonic_s
    snapshot.source_health = health
    snapshot.track_layout_key = namespace.contracts.track_layout_key(snapshot.identity)
    snapshot.availability = snapshot.availability or {}
    snapshot.failures = snapshot.failures or {}
    state.source_diagnostics.source_health = health
    state.source_diagnostics.health = source_health.diagnostics(state.health_tracker)
    state.source_diagnostics.recent_snapshot_count = #state.snapshot_history + 1
    push_bounded(state.snapshot_history, namespace.contracts.copy(snapshot), state.snapshot_history_limit)
    state.source_error = nil
    if #missing_core == 0 then state.last_valid_s = now_s end
    state.source_diagnostics.update_age_s = 0
    local previous = state.latest
    local events = race_events.update(state.event_stream, snapshot)
    state.recent_events = events
    for index = 1, #events do
      local event = events[index]
      push_bounded(state.discontinuities, event, config.max_discontinuities or 24)
      if event.event_type == "RESET" or event.event_type == "TELEPORT" or event.event_type == "SPLINE_JUMP" then
        state.last_reset_reason = event.rejection_reason or event.event_type
      end
    end
    if previous then
      local identity_changed = previous.identity and previous.identity.key ~= snapshot.identity.key
      local lap_decreased = previous.session and snapshot.session and type(previous.session.completed_laps) == "number" and type(snapshot.session.completed_laps) == "number" and snapshot.session.completed_laps < previous.session.completed_laps
      local replay_changed = previous.session and snapshot.session and previous.session.replay ~= snapshot.session.replay
      local refuel_jump = previous.car and snapshot.car and type(previous.car.fuel_l) == "number" and type(snapshot.car.fuel_l) == "number" and snapshot.car.fuel_l - previous.car.fuel_l > config.refuel_jump_l
      if identity_changed or lap_decreased or replay_changed then
        reset_model_history(state, identity_changed and "IDENTITY_CHANGED" or (lap_decreased and "SESSION_RESTART" or "REPLAY_STATE_CHANGED"))
      elseif refuel_jump then
        reset_stint_history(state, "REFUEL_TRANSITION")
      end
    end
    state.latest = snapshot
    state.identity = snapshot.identity
    state.pit_source = {
      isInPitlane = snapshot.car and snapshot.car.pit_lane,
      isInPit = snapshot.car and snapshot.car.pit_box,
      spline = snapshot.car and snapshot.car.spline,
      world_position = snapshot.car and snapshot.car.world_position,
      reset_counter = snapshot.car and snapshot.car.reset_counter,
      speed_kmh = snapshot.car and snapshot.car.speed_kmh,
      snapshot_id = snapshot.snapshot_id,
      observed_monotonic_s = snapshot.observed_monotonic_s,
      identity_key = namespace.contracts.identity_key(snapshot.identity),
    }
    local lap_event = lap_tracker.update(state.lap, snapshot)
    stint_tracker.update(state.stint, snapshot, now_s, config.refuel_jump_l)
    if lap_event then
      store_api.record_lap(state.samples, lap_event)
      if lap_event.accepted then
        stint_tracker.accept_lap(state.stint, lap_event)
      end
    end
    store_api.update_tyre_lap(state.samples, snapshot)
    if state.last_weather_s == nil or now_s - state.last_weather_s >= config.weather_update_period_s then
      state.weather_current = weather.update(state.weather, snapshot.environment, now_s)
      store_api.add_weather(state.samples, state.weather_current)
      state.weather_trend = weather.trend(state.weather)
      state.last_weather_s = now_s
    end
    if state.last_derived_s == nil or now_s - state.last_derived_s >= config.derived_update_period_s then
      derive(state, now_s, config)
    end
    return state.status
  end

  function telemetry.current_status(state, now_s, config)
    if state.status == nil then return telemetry.update(state, now_s, config) end
    return state.status
  end

  function telemetry.recent_snapshots(state)
    return namespace.contracts.copy(state.snapshot_history or {})
  end

  function telemetry.recent_events(state)
    return race_events.recent(state.event_stream)
  end

  namespace.live.telemetry = telemetry
end
