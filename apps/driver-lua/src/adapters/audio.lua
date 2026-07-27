local namespace = _G.AVM_PITWALL_F1
local audio = { available = false, events = {}, last_error = nil }

local sound_files = {
  info = "assets/sounds/info.wav",
  warning = "assets/sounds/warning.wav",
  critical = "assets/sounds/critical.wav",
  ack = "assets/sounds/ack.wav",
}

local function can_create_event()
  local ac_api = rawget(_G, "ac")
  return type(ac_api) == "table" and type(ac_api.AudioEvent) == "table" and type(ac_api.AudioEvent.fromFile) == "function"
end

function audio.play(kind, enabled, volume)
  if enabled == false then
    return false
  end
  local filename = sound_files[kind] or sound_files.info
  if not can_create_event() then
    audio.last_error = "audio API unavailable"
    return false
  end
  local event = audio.events[kind]
  if event == nil then
    local ac_api = rawget(_G, "ac")
    local ok, created = pcall(ac_api.AudioEvent.fromFile, { filename = filename, use3D = false, loop = false })
    if not ok or created == nil then
      audio.last_error = tostring(created or "audio event creation failed")
      return false
    end
    event = created
    audio.events[kind] = event
  end
  if type(event.setVolume) == "function" then
    pcall(event.setVolume, event, volume or namespace.config.sound_volume)
  end
  if type(event.start) ~= "function" then
    audio.last_error = "audio event has no start method"
    return false
  end
  local ok, result = pcall(event.start, event)
  audio.available = ok
  if not ok then
    audio.last_error = tostring(result)
  end
  return ok
end

function audio.status()
  if audio.available then
    return "READY"
  end
  if audio.last_error ~= nil then
    return "UNAVAILABLE"
  end
  return "NOT TESTED"
end

function audio.test(kind, settings)
  return audio.play(kind, settings.sound_enabled, settings.sound_volume)
end

namespace.adapters.audio = audio
