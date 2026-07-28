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
      stint_id = nil,
      stint_number = 0,
      completed_laps = 0,
      current_stint_lap = 0,
      current_lap = 0,
      regime = "unknown",
      identity_key = nil,
      previous = nil,
      previous_stint = nil,
      stint_history = {},
      awaiting_boundary = false,
      end_reason = nil,
      last_update_s = nil,
    }
  end

  function stint_tracker.reset(state, reason)
    state.active = false
    state.start_monotonic_s = nil
    state.start_fuel_l = nil
    state.start_lap = nil
    state.stint_id = nil
    state.stint_number = 0
    state.completed_laps = 0
    state.current_stint_lap = 0
    state.current_lap = 0
    state.regime = "unknown"
    state.identity_key = nil
    state.previous = nil
    state.previous_stint = nil
    state.stint_history = {}
    state.awaiting_boundary = false
    state.end_reason = reason
  end

  local function on_track(snapshot)
    local car = snapshot.car or {}
    return car.pit_lane ~= true and car.pit_box ~= true
  end

  local function archive_current(state, end_s, reason)
    if state.stint_number <= 0 or state.stint_id == nil then return end
    local previous = {
      stint_id = state.stint_id,
      stint_number = state.stint_number,
      identity_key = state.identity_key,
      start_monotonic_s = state.start_monotonic_s,
      end_monotonic_s = end_s,
      start_lap = state.start_lap,
      completed_laps = state.current_stint_lap,
      end_reason = reason,
    }
    state.previous_stint = previous
    state.stint_history[#state.stint_history + 1] = previous
    while #state.stint_history > 4 do table.remove(state.stint_history, 1) end
  end

  local function begin_stint(state, snapshot, now_s, boundary_confirmed)
    local session = snapshot.session or {}
    local car = snapshot.car or {}
    if boundary_confirmed then
      archive_current(state, now_s, "PIT_EXIT_CONFIRMED")
      state.stint_number = state.stint_number + 1
    elseif state.stint_number == 0 then
      state.stint_number = 1
    end
    state.stint_id = "stint:" .. tostring(state.identity_key or "unknown") .. ":" .. tostring(state.stint_number)
    state.active = true
    state.awaiting_boundary = false
    state.start_monotonic_s = now_s
    state.start_fuel_l = car.fuel_l
    -- AC exposes current_lap as the one-based lap in progress. It is kept for
    -- timing/diagnostics only; completed current-stint progress is separate.
    state.start_lap = session.current_lap or ((session.completed_laps or 0) + 1)
    state.completed_laps = 0
    state.current_stint_lap = 0
    state.current_lap = session.current_lap or state.start_lap
    state.regime = boundary_confirmed and "out_lap" or "green_valid"
    state.end_reason = nil
  end

  function stint_tracker.update(state, snapshot, now_s, fuel_jump_l, boundary_event)
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
    if state.active and (car.pit_lane == true or car.pit_box == true) then
      state.active = false
      state.awaiting_boundary = true
      state.end_reason = "PIT_ENTRY"
    end
    local confirmed_exit = type(boundary_event) == "table" and boundary_event.event_type == "PIT_EXIT_CONFIRMED"
    if not state.active and on_track(snapshot) and session.active ~= false and session.finished ~= true then
      if state.stint_number == 0 then
        begin_stint(state, snapshot, now_s, false)
      elseif state.awaiting_boundary and confirmed_exit then
        begin_stint(state, snapshot, now_s, true)
      end
    elseif state.active then
      state.current_lap = session.current_lap or state.current_lap
      if car.pit_lane then state.regime = "pit_lane" end
    end
    if session.finished == true then
      state.active = false
      state.awaiting_boundary = false
      state.end_reason = "SESSION_END"
    end
    state.last_update_s = now_s
    state.previous = snapshot
  end

  function stint_tracker.accept_lap(state, event)
    -- Progress counts a completed lap belonging to the active stint even when
    -- that lap is excluded from pace/fuel samples (for example the out-lap).
    if state.active and type(event) == "table" and event.incomplete ~= true then
      state.current_stint_lap = state.current_stint_lap + 1
      state.completed_laps = state.current_stint_lap
      state.regime = event.regime or "green_valid"
    end
  end

  function stint_tracker.elapsed(state, now_s)
    if not state.active or type(state.start_monotonic_s) ~= "number" then return nil end
    return math.max(0, now_s - state.start_monotonic_s)
  end

  namespace.live.stint_tracker = stint_tracker
end
