do
  local namespace = _G.AVM_PITWALL_F1
  local identity = namespace.live.session_identity
  local stint_tracker = {}

  function stint_tracker.new()
    return {
      active = false,
      start_monotonic_s = nil,
      start_fuel_l = nil,
      start_lap = nil,
      completed_laps = 0,
      current_lap = 0,
      regime = "unknown",
      identity_key = nil,
      previous = nil,
      end_reason = nil,
      last_update_s = nil,
    }
  end

  function stint_tracker.reset(state, reason)
    state.active = false
    state.start_monotonic_s = nil
    state.start_fuel_l = nil
    state.start_lap = nil
    state.completed_laps = 0
    state.current_lap = 0
    state.regime = "unknown"
    state.identity_key = nil
    state.previous = nil
    state.end_reason = reason
  end

  local function on_track(snapshot)
    local car = snapshot.car or {}
    return car.pit_lane ~= true and car.pit_box ~= true
  end

  function stint_tracker.update(state, snapshot, now_s, fuel_jump_l)
    if type(snapshot) ~= "table" then return end
    local key = identity.key(snapshot)
    local session = snapshot.session or {}
    local car = snapshot.car or {}
    local previous = state.previous
    if state.identity_key ~= nil and key ~= state.identity_key then
      stint_tracker.reset(state, "IDENTITY_CHANGED")
    end
    state.identity_key = key
    if previous and previous.session and type(session.completed_laps) == "number" and type(previous.session.completed_laps) == "number" and session.completed_laps < previous.session.completed_laps then
      stint_tracker.reset(state, "SESSION_RESTART")
      state.identity_key = key
    end
    if previous and previous.session and previous.session.replay ~= session.replay then
      stint_tracker.reset(state, "REPLAY_STATE_CHANGED")
      state.identity_key = key
    end
    if previous and previous.car and type(previous.car.fuel_l) == "number" and type(car.fuel_l) == "number" and car.fuel_l - previous.car.fuel_l > (fuel_jump_l or 1.0) and not car.pit_lane then
      stint_tracker.reset(state, "REFUEL_TRANSITION")
      state.identity_key = key
    end
    local left_pit = previous and previous.car and previous.car.pit_lane == true and car.pit_lane ~= true
    if state.active and (car.pit_lane == true or car.pit_box == true) then
      state.active = false
      state.end_reason = "PIT_ENTRY"
    end
    if not state.active and on_track(snapshot) and session.active ~= false and session.finished ~= true then
      state.active = true
      state.start_monotonic_s = now_s
      state.start_fuel_l = car.fuel_l
      state.start_lap = session.current_lap or ((session.completed_laps or 0) + 1)
      state.completed_laps = 0
      state.current_lap = state.start_lap
      state.regime = left_pit and "out_lap" or "green_valid"
      state.end_reason = nil
    elseif state.active then
      state.current_lap = session.current_lap or state.current_lap
      if car.pit_lane then state.regime = "pit_lane" end
    end
    if session.finished == true then
      state.active = false
      state.end_reason = "SESSION_END"
    end
    state.last_update_s = now_s
    state.previous = snapshot
  end

  function stint_tracker.accept_lap(state, event)
    if state.active and type(event) == "table" and event.accepted == true then
      state.completed_laps = state.completed_laps + 1
      state.regime = event.regime or "green_valid"
    end
  end

  function stint_tracker.elapsed(state, now_s)
    if not state.active or type(state.start_monotonic_s) ~= "number" then return nil end
    return math.max(0, now_s - state.start_monotonic_s)
  end

  namespace.live.stint_tracker = stint_tracker
end
