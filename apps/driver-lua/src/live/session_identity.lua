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
    if previous.completed_laps ~= nil and type(session.completed_laps) == "number" and session.completed_laps < previous.completed_laps then
      return true, "SESSION_RESTART" end
    if previous.replay ~= nil and previous.replay ~= session.replay then return true, "REPLAY_STATE_CHANGED" end
    return false, nil
  end

  namespace.live.session_identity = identity
end
