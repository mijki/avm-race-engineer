do
  local namespace = _G.AVM_PITWALL_F1
  local contracts = namespace.contracts
  local race_events = {}

  local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
  end

  local function identity(snapshot)
    return snapshot and snapshot.identity or {}
  end

  local function car(snapshot)
    return snapshot and snapshot.car or {}
  end

  local function session(snapshot)
    return snapshot and snapshot.session or {}
  end

  local function environment(snapshot)
    return snapshot and snapshot.environment or {}
  end

  local function distance(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return nil end
    if not (number(left.x) and number(left.y) and number(left.z) and number(right.x) and number(right.y) and number(right.z)) then return nil end
    local dx, dy, dz = left.x - right.x, left.y - right.y, left.z - right.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  function race_events.new(options)
    options = options or {}
    return {
      max_events = options.max_events or 128,
      sequence = 0,
      events = {},
      previous = nil,
      identity_key = nil,
      weather_regime = nil,
    }
  end

  function race_events.emit(state, snapshot, event_type, payload, confidence, rejection, suppression)
    state.sequence = state.sequence + 1
    local source_id = snapshot and snapshot.snapshot_id or "snapshot:unavailable"
    local id = contracts.identity_key(identity(snapshot))
    local event = contracts.race_event({
      event_id = "event:" .. tostring(state.sequence) .. ":" .. tostring(event_type),
      sequence = state.sequence,
      event_type = event_type,
      source_snapshot_id = source_id,
      detection_time_s = snapshot and snapshot.observed_monotonic_s,
      source_time_s = snapshot and snapshot.source_timestamp_s,
      session_time_s = snapshot and snapshot.session and snapshot.session.elapsed_s,
      identity_key = id,
      confidence = confidence or "medium",
      provenance = { source = snapshot and snapshot.source_mode or "unknown", detector = "race-events-v1" },
      payload = payload or {},
      rejection_reason = rejection,
      suppression_reason = suppression,
    })
    state.events[#state.events + 1] = event
    while #state.events > state.max_events do table.remove(state.events, 1) end
    return event
  end

  local function transition(state, snapshot, event_type, payload, confidence, rejection, suppression)
    return race_events.emit(state, snapshot, event_type, payload, confidence, rejection, suppression)
  end

  function race_events.update(state, snapshot)
    if type(snapshot) ~= "table" then return {} end
    local previous = state.previous
    local current_identity = contracts.identity_key(identity(snapshot))
    local current_session, previous_session = session(snapshot), session(previous)
    local current_car, previous_car = car(snapshot), car(previous)
    local current_environment, previous_environment = environment(snapshot), environment(previous)
    local emitted = {}
    local function add(event)
      if event ~= nil then emitted[#emitted + 1] = event end
    end

    if previous == nil then
      add(transition(state, snapshot, "SESSION_STARTED", { initial = true }, "high"))
    else
      if state.identity_key ~= current_identity then
        add(transition(state, snapshot, "IDENTITY_CHANGED", { previous_key = state.identity_key, current_key = current_identity }, "high"))
      end
      if previous_session.replay ~= current_session.replay then
        add(transition(state, snapshot, "REPLAY_TRANSITION", { from = previous_session.replay, to = current_session.replay }, "high"))
      end
      if number(previous_session.completed_laps) and number(current_session.completed_laps) then
        if current_session.completed_laps < previous_session.completed_laps then
          add(transition(state, snapshot, "SESSION_RESTART", { previous_laps = previous_session.completed_laps, current_laps = current_session.completed_laps }, "high"))
          add(transition(state, snapshot, "LAP_COUNTER_DECREASE", {}, "high"))
        elseif current_session.completed_laps > previous_session.completed_laps then
          add(transition(state, snapshot, "LAP_COMPLETED", { lap_number = previous_session.completed_laps, count = current_session.completed_laps - previous_session.completed_laps }, "high"))
        end
      end
      if number(previous_car.reset_counter) and number(current_car.reset_counter) and current_car.reset_counter ~= previous_car.reset_counter then
        add(transition(state, snapshot, "RESET", { from = previous_car.reset_counter, to = current_car.reset_counter }, "high"))
      end
      if number(previous_car.fuel_l) and number(current_car.fuel_l) and current_car.fuel_l - previous_car.fuel_l > 1 then
        add(transition(state, snapshot, "REFUEL", { delta_l = current_car.fuel_l - previous_car.fuel_l }, "medium"))
      end
      if number(previous_car.spline) and number(current_car.spline) then
        local delta = math.abs(current_car.spline - previous_car.spline)
        if delta > 0.20 and delta < 0.80 then
          add(transition(state, snapshot, "SPLINE_JUMP", { delta = delta }, "medium", "SPLINE_JUMP"))
        end
      end
      local world_m = distance(previous_car.world_position, current_car.world_position)
      if world_m ~= nil and world_m > 1000 then
        add(transition(state, snapshot, "TELEPORT", { movement_m = world_m }, "high", "WORLD_POSITION_JUMP"))
      end
      if previous_car.pit_lane ~= true and current_car.pit_lane == true then
        add(transition(state, snapshot, "PIT_ENTRY_CANDIDATE", { old_state = false, new_state = true }, "low"))
      elseif previous_car.pit_lane == true and current_car.pit_lane ~= true then
        add(transition(state, snapshot, "PIT_EXIT_CANDIDATE", { old_state = true, new_state = false }, "low"))
      end
      if previous_car.pit_box ~= true and current_car.pit_box == true then
        add(transition(state, snapshot, "PIT_BOX_ARRIVAL", { old_state = false, new_state = true }, "medium"))
      elseif previous_car.pit_box == true and current_car.pit_box ~= true then
        add(transition(state, snapshot, "PIT_BOX_DEPARTURE", { old_state = true, new_state = false }, "medium"))
      end
      if current_session.finished == true and previous_session.finished ~= true then
        add(transition(state, snapshot, "SESSION_ENDED", {}, "high"))
      end
      local regime = current_environment.weather_regime
      if regime ~= nil and state.weather_regime ~= nil and regime ~= state.weather_regime then
        add(transition(state, snapshot, "WEATHER_REGIME_CHANGED", { from = state.weather_regime, to = regime }, "medium"))
      end
      state.weather_regime = regime or state.weather_regime
    end
    state.identity_key = current_identity
    if state.weather_regime == nil then state.weather_regime = current_environment.weather_regime end
    state.previous = contracts.copy(snapshot)
    return emitted
  end

  function race_events.replay(snapshots, options)
    local state = race_events.new(options)
    local result = {}
    for index = 1, #(snapshots or {}) do
      local events = race_events.update(state, snapshots[index])
      for event_index = 1, #events do result[#result + 1] = events[event_index] end
    end
    return result
  end

  function race_events.recent(state)
    -- Events are immutable proxies; returning the bounded collection preserves
    -- their read-only contract without attempting to copy proxy internals.
    return state.events or {}
  end

  namespace.live.race_events = race_events
end
