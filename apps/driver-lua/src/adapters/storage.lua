local namespace = _G.AVM_PITWALL_F1
local storage = {}

local storage_key = "avm_race_engineer_f1_presentation_v1"

local function defaults()
  return {
    mode = namespace.config.default_mode,
    ui_scale = namespace.config.ui_scale,
    sound_enabled = true,
    sound_volume = namespace.config.sound_volume,
    reduced_animation = false,
    scenario = namespace.config.default_scenario,
  }
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
  return true
end

function storage.load()
  local safe = defaults()
  if type(ac) ~= "table" or type(ac.load) ~= "function" then
    return safe
  end
  local ok, value = pcall(ac.load, storage_key)
  if ok and valid(value) then
    return value
  end
  return safe
end

function storage.save(value)
  if not valid(value) or type(ac) ~= "table" or type(ac.store) ~= "function" then
    return false
  end
  local ok = pcall(ac.store, storage_key, value)
  return ok
end

namespace.adapters.storage = storage
