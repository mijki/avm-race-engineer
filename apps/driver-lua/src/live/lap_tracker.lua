do
  local namespace = _G.AVM_PITWALL_F1
  local identity = namespace.live.session_identity
  local lap_tracker = {}

  function lap_tracker.new()
    return {
      previous = nil,
      lap_start_fuel_l = nil,
      lap_start_distance_km = nil,
      out_lap_pending = false,
      identity_key = nil,
      last_lap_count = nil,
      reset_reason = nil,
    }
  end

  function lap_tracker.reset(state, reason)
    state.previous = nil
    state.lap_start_fuel_l = nil
    state.lap_start_distance_km = nil
    state.out_lap_pending = false
    state.identity_key = nil
    state.last_lap_count = nil
    state.reset_reason = reason
  end

  local function lap_count(snapshot)
    return snapshot and snapshot.session and snapshot.session.completed_laps
  end

  local function classify(snapshot, in_lap, out_lap)
    if in_lap then return "pit_lane" end
    if out_lap then return "out_lap" end
    local environment = snapshot.environment or {}
    if type(environment.track_wetness) == "number" and environment.track_wetness > 0.08 then return "wet" end
    if type(environment.rain_intensity) == "number" and environment.rain_intensity > 0.05 then return "wet" end
    local speed = snapshot.car and snapshot.car.speed_kmh
    if type(speed) == "number" and speed < 30 then return "caution_slow" end
    return "green_valid"
  end

  function lap_tracker.update(state, snapshot)
    if type(snapshot) ~= "table" then return nil end
    local current_key = identity.key(snapshot)
    if state.identity_key ~= nil and current_key ~= state.identity_key then
      lap_tracker.reset(state, "IDENTITY_CHANGED")
    end
    state.identity_key = current_key
    local car = snapshot.car or {}
    local session = snapshot.session or {}
    local previous = state.previous
    if state.lap_start_fuel_l == nil then state.lap_start_fuel_l = car.fuel_l end
    if state.lap_start_distance_km == nil then state.lap_start_distance_km = car.distance_session_km end
    local event = nil
    local count = lap_count(snapshot)
    local previous_count = previous and lap_count(previous) or nil
    if previous_count ~= nil and count ~= nil and count < previous_count then
      lap_tracker.reset(state, "SESSION_RESTART")
      state.identity_key = current_key
      state.lap_start_fuel_l = car.fuel_l
      state.lap_start_distance_km = car.distance_session_km
    elseif previous_count ~= nil and count ~= nil and count > previous_count then
      local complete_count = count - previous_count
      local previous_car = previous.car or {}
      local in_lap = previous_car.pit_lane == true or car.pit_lane == true
      local out_lap = state.out_lap_pending
      local regime = classify(snapshot, in_lap, out_lap)
      local valid = car.previous_lap_valid
      if valid == nil then valid = previous_car.lap_valid end
      local cuts = car.last_lap_cuts or 0
      local fuel_used = nil
      if type(state.lap_start_fuel_l) == "number" and type(car.fuel_l) == "number" then
        local delta = state.lap_start_fuel_l - car.fuel_l
        if delta >= 0 and delta < 0.8 * math.max(state.lap_start_fuel_l, 1) then fuel_used = delta end
      end
      local distance = nil
      if type(state.lap_start_distance_km) == "number" and type(car.distance_session_km) == "number" then
        local delta = car.distance_session_km - state.lap_start_distance_km
        if delta > 0 and delta < 100 then distance = delta end
      end
      local excluded_reason = nil
      if complete_count ~= 1 then excluded_reason = "INCOMPLETE_LAP" end
      if in_lap then excluded_reason = "PIT_LAP_EXCLUDED" end
      if out_lap then excluded_reason = "OUT_LAP_EXCLUDED" end
      if excluded_reason == nil and regime == "wet" then excluded_reason = "WET_LAP_EXCLUDED" end
      if excluded_reason == nil and regime == "caution_slow" then excluded_reason = "CAUTION_LAP_EXCLUDED" end
      if valid ~= true or cuts > 0 then excluded_reason = "INVALID_LAP" end
      if fuel_used == nil and type(state.lap_start_fuel_l) == "number" then excluded_reason = excluded_reason or "REFUEL_TRANSITION" end
      event = {
        lap_number = previous_count,
        lap_time_s = car.previous_lap_time_s,
        fuel_used_l = fuel_used,
        distance_km = distance,
        accepted = excluded_reason == nil,
        reason = excluded_reason,
        regime = regime,
        pit_lane = in_lap,
        out_lap = out_lap,
        incomplete = complete_count ~= 1,
      }
      state.out_lap_pending = false
      state.lap_start_fuel_l = car.fuel_l
      state.lap_start_distance_km = car.distance_session_km
    end
    if previous and previous.car and previous.car.pit_lane == true and car.pit_lane ~= true then
      state.out_lap_pending = true
    end
    state.previous = snapshot
    state.last_lap_count = count
    return event
  end

  lap_tracker.on_snapshot = lap_tracker.update
  namespace.live.lap_tracker = lap_tracker
end
