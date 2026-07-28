do
  local namespace = _G.AVM_PITWALL_F1
  local identity = {}

  function identity.key(snapshot)
    local value = snapshot and snapshot.identity or {}
    return table.concat({
      tostring(value.car_id or ""),
      tostring(value.track_id or ""),
      tostring(value.layout_id or ""),
      tostring(value.session_id or ""),
      tostring(value.configuration_id or ""),
    }, "|")
  end

  function identity.normalize(snapshot)
    local source = snapshot and snapshot.identity or {}
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    result.key = identity.key(snapshot)
    return result
  end

  function identity.changed(previous, snapshot)
    if previous == nil then return true, "IDENTITY_INITIALIZED" end
    local current = identity.key(snapshot)
    if current ~= previous.key then return true, "IDENTITY_CHANGED" end
    local session = snapshot and snapshot.session or {}
    local previous_session = previous.session or {}
    if previous_session.completed_laps ~= nil and type(session.completed_laps) == "number" and session.completed_laps < previous_session.completed_laps then
      return true, "SESSION_RESTART" end
    if previous.replay ~= nil and previous.replay ~= session.replay then return true, "REPLAY_STATE_CHANGED" end
    return false, nil
  end

  function identity.discontinuities(previous, snapshot, options)
    options = options or {}
    local reasons = {}
    if previous == nil or snapshot == nil then
      reasons[#reasons + 1] = "INITIALIZATION"
      return reasons
    end
    local previous_car, current_car = previous.car or {}, snapshot.car or {}
    local previous_session, current_session = previous.session or {}, snapshot.session or {}
    if identity.key(previous) ~= identity.key(snapshot) then reasons[#reasons + 1] = "IDENTITY_CHANGED" end
    if previous_session.replay ~= current_session.replay then reasons[#reasons + 1] = "REPLAY_TRANSITION" end
    if type(previous_session.completed_laps) == "number" and type(current_session.completed_laps) == "number" and current_session.completed_laps < previous_session.completed_laps then
      reasons[#reasons + 1] = "LAP_COUNTER_DECREASE"
    end
    if type(previous_car.reset_counter) == "number" and type(current_car.reset_counter) == "number" and previous_car.reset_counter ~= current_car.reset_counter then
      reasons[#reasons + 1] = "RESET_COUNTER_CHANGED"
    end
    if type(previous_car.spline) == "number" and type(current_car.spline) == "number" then
      local delta = math.abs(current_car.spline - previous_car.spline)
      if delta > (options.spline_jump_threshold or 0.20) and delta < (1 - (options.spline_wrap_threshold or 0.20)) then
        reasons[#reasons + 1] = "SPLINE_JUMP"
      end
    end
    local left, right = previous_car.world_position, current_car.world_position
    if type(left) == "table" and type(right) == "table" and type(left.x) == "number" and type(left.y) == "number" and type(left.z) == "number" and type(right.x) == "number" and type(right.y) == "number" and type(right.z) == "number" then
      local dx, dy, dz = left.x - right.x, left.y - right.y, left.z - right.z
      if math.sqrt(dx * dx + dy * dy + dz * dz) > (options.world_jump_threshold_m or 1000) then reasons[#reasons + 1] = "WORLD_POSITION_JUMP" end
    end
    if type(previous_car.fuel_l) == "number" and type(current_car.fuel_l) == "number" and current_car.fuel_l - previous_car.fuel_l > (options.refuel_jump_l or 1) then
      reasons[#reasons + 1] = "MATERIAL_REFUEL"
    end
    return reasons
  end

  namespace.live.session_identity = identity
end
