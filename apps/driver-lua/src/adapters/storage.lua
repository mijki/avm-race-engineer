local namespace = _G.AVM_PITWALL_F1
local storage = {}

local storage_key = "avm_race_engineer_f1_presentation_v1"
local pit_marker_storage_key = "avm_race_engineer_pit_markers_v1"

local function defaults()
  return {
    mode = namespace.config.default_mode,
    ui_scale = namespace.config.ui_scale,
    sound_enabled = true,
    sound_volume = namespace.config.sound_volume,
    reduced_animation = false,
    scenario = namespace.config.default_scenario,
    targets = {},
  }
end

function storage.defaults()
  return defaults()
end

local function valid(value)
  if type(value) ~= "table" then
    return false
  end
  if value.mode ~= "compact" and value.mode ~= "expanded" and value.mode ~= "garage" then
    return false
  end
  if type(value.ui_scale) ~= "number" or value.ui_scale < 1 or value.ui_scale > 1.5 then
    return false
  end
  if type(value.sound_enabled) ~= "boolean" or type(value.sound_volume) ~= "number" or value.sound_volume < 0 or value.sound_volume > 1 then
    return false
  end
  if type(value.reduced_animation) ~= "boolean" or type(value.scenario) ~= "string" then
    return false
  end
  if value.targets ~= nil and type(value.targets) ~= "table" then
    return false
  end
  return true
end

function storage.load()
  local safe = defaults()
  local ac_api = rawget(_G, "ac")
  if type(ac_api) ~= "table" or type(ac_api.load) ~= "function" then
    return safe
  end
  local ok, value = pcall(ac_api.load, storage_key)
  if ok and valid(value) then
    return value
  end
  return safe
end

function storage.save(value)
  local ac_api = rawget(_G, "ac")
  if not valid(value) or type(ac_api) ~= "table" or type(ac_api.store) ~= "function" then
    return false
  end
  local ok = pcall(ac_api.store, storage_key, value)
  return ok
end

local function calibration_key(identity)
  if type(identity) ~= "table" or identity.track_id == nil or identity.layout_id == nil then
    return nil
  end
  return tostring(identity.track_id) .. "::" .. tostring(identity.layout_id)
end

storage.calibration_values = storage.calibration_values or {}
storage.pit_marker_values = storage.pit_marker_values or {}

function storage.load_calibration(identity)
  local key = calibration_key(identity)
  if key == nil then
    return nil
  end
  local stored = storage.calibration_values[key]
  if type(stored) ~= "table" then
    return nil
  end
  local copy = {}
  for name, value in pairs(stored) do
    copy[name] = value
  end
  return copy
end

function storage.save_calibration(identity, calibration)
  local key = calibration_key(identity)
  if key == nil or type(calibration) ~= "table" then
    return false
  end
  storage.calibration_values[key] = {
    track_id = calibration.track_id,
    layout_id = calibration.layout_id,
    track_length_m = calibration.track_length_m,
    pit_entry_spline = calibration.pit_entry_spline,
    pit_route_additional_m = calibration.pit_route_additional_m or 0,
    source = calibration.source or "garage_capture",
    last_modified = calibration.last_modified,
    validation_status = calibration.validation_status,
  }
  return true
end

function storage.reset_calibration(identity)
  local key = calibration_key(identity)
  if key == nil then
    return false
  end
  storage.calibration_values[key] = nil
  return true
end

local function marker_key(identity)
  if type(identity) ~= "table" or identity.track_id == nil or identity.layout_id == nil then return nil end
  return tostring(identity.track_id) .. "::" .. tostring(identity.layout_id)
end

local function marker_valid(marker, key)
  return type(marker) == "table"
    and marker.schema_version == "pit-marker-record-v1"
    and marker.track_layout_key == key
    and type(marker.state) == "string"
    and type(marker.accepted_observations) == "table"
    and type(marker.rejected_observations) == "table"
    and type(marker.manual_override) == "boolean"
end

function storage.load_pit_marker(identity)
  local key = marker_key(identity)
  if key == nil then return nil end
  local stored = storage.pit_marker_values[key]
  local ac_api = rawget(_G, "ac")
  if stored == nil and type(ac_api) == "table" and type(ac_api.load) == "function" then
    local ok, all = pcall(ac_api.load, pit_marker_storage_key)
    if ok and type(all) == "table" then stored = all[key] end
  end
  if not marker_valid(stored, key) then return nil end
  local copy = {}
  for name, value in pairs(stored) do copy[name] = value end
  return copy
end

function storage.save_pit_marker(identity, marker)
  local key = marker_key(identity)
  if key == nil or not marker_valid(marker, key) then return false end
  local bounded_accepted = {}
  local bounded_rejected = {}
  for index = math.max(1, #marker.accepted_observations - 23), #marker.accepted_observations do bounded_accepted[#bounded_accepted + 1] = marker.accepted_observations[index] end
  for index = math.max(1, #marker.rejected_observations - 23), #marker.rejected_observations do bounded_rejected[#bounded_rejected + 1] = marker.rejected_observations[index] end
  storage.pit_marker_values[key] = {
    schema_version = "pit-marker-record-v1",
    track_layout_key = key,
    track_id = marker.track_id,
    layout_id = marker.layout_id,
    state = marker.state,
    entry_spline = marker.entry_spline,
    exit_spline = marker.exit_spline,
    entry_world_position = marker.entry_world_position,
    exit_world_position = marker.exit_world_position,
    accepted_observations = bounded_accepted,
    rejected_observations = bounded_rejected,
    confidence = marker.confidence or 0,
    source = marker.source or "AUTOMATIC",
    first_observed_at_s = marker.first_observed_at_s,
    last_observed_at_s = marker.last_observed_at_s,
    manual_override = marker.manual_override == true,
    timing = marker.timing or {},
  }
  if type(ac_api) == "table" and type(ac_api.store) == "function" then
    local all = {}
    for marker_key_value, value in pairs(storage.pit_marker_values) do all[marker_key_value] = value end
    pcall(ac_api.store, pit_marker_storage_key, all)
  end
  return true
end

function storage.reset_pit_marker(identity)
  local key = marker_key(identity)
  if key == nil then return false end
  storage.pit_marker_values[key] = nil
  return true
end

namespace.adapters.storage = storage
