do
  local namespace = _G.AVM_PITWALL_F1
  local track_model = {}

  local function valid_number(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
  end

  function track_model.validate(calibration, identity)
    if type(calibration) ~= "table" then return false, "PIT_ENTRY_NOT_CALIBRATED" end
    if identity and (calibration.track_id ~= identity.track_id or calibration.layout_id ~= identity.layout_id) then
      return false, "PIT_ENTRY_NOT_CALIBRATED"
    end
    if not valid_number(calibration.track_length_m) then return false, "PIT_ENTRY_NOT_CALIBRATED" end
    if type(calibration.pit_entry_spline) ~= "number" or calibration.pit_entry_spline < 0 or calibration.pit_entry_spline >= 1 then
      return false, "PIT_ENTRY_NOT_CALIBRATED"
    end
    return true, "VALID"
  end

  function track_model.forward_distance(current_spline, pit_entry_spline, track_length_m)
    if type(current_spline) ~= "number" or type(pit_entry_spline) ~= "number" or not valid_number(track_length_m) then
      return nil, "PIT_ENTRY_NOT_CALIBRATED"
    end
    if current_spline < 0 or current_spline >= 1 or pit_entry_spline < 0 or pit_entry_spline >= 1 then
      return nil, "PIT_ENTRY_NOT_CALIBRATED"
    end
    local delta = pit_entry_spline - current_spline
    local wrapped = delta < 0
    if wrapped then delta = delta + 1 end
    local reason = wrapped and "PIT_ENTRY_WRAPAROUND_APPLIED" or "MEASURED_CURRENT"
    return delta * track_length_m, reason
  end

  function track_model.distance_to_pit(snapshot, calibration)
    local identity = snapshot and snapshot.identity or nil
    local valid, reason = track_model.validate(calibration, identity)
    if not valid then return nil, reason end
    local spline = snapshot.car and snapshot.car.spline or nil
    return track_model.forward_distance(spline, calibration.pit_entry_spline, calibration.track_length_m)
  end

  namespace.live.track_model = track_model
end
