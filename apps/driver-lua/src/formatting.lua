local namespace = _G.AVM_PITWALL_F1
local formatting = {}

function formatting.value(value, suffix, fallback)
  if value == nil then
    return fallback or "UNAVAILABLE"
  end
  return tostring(value) .. (suffix or "")
end

function formatting.number(value, decimals, suffix, fallback)
  if type(value) ~= "number" then
    return fallback or "UNAVAILABLE"
  end
  return string.format("%." .. tostring(decimals or 1) .. "f", value) .. (suffix or "")
end

function formatting.time(seconds, fallback)
  if type(seconds) ~= "number" or seconds < 0 then
    return fallback or "UNAVAILABLE"
  end
  local whole = math.floor(seconds + 0.5)
  local hours = math.floor(whole / 3600)
  local minutes = math.floor((whole % 3600) / 60)
  local remaining = whole % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, remaining)
  end
  return string.format("%02d:%02d", minutes, remaining)
end

function formatting.lap_time(seconds, fallback)
  if type(seconds) ~= "number" or seconds < 0 then
    return fallback or "UNAVAILABLE"
  end
  local minutes = math.floor(seconds / 60)
  local remaining = seconds - minutes * 60
  return string.format("%d:%06.3f", minutes, remaining)
end

function formatting.distance(metres, fallback)
  if type(metres) ~= "number" or metres < 0 then
    return fallback or "UNAVAILABLE"
  end
  if metres < 1000 then
    return string.format("%dm", math.floor(metres + 0.5))
  end
  local kilometres = metres / 1000
  if kilometres <= 10 then
    return string.format("%.2f km", kilometres)
  end
  return string.format("%.1f km", kilometres)
end

function formatting.fuel(litres, fallback)
  if type(litres) ~= "number" or litres < 0 then
    return fallback or "UNAVAILABLE"
  end
  return string.format("%.1f L", litres)
end

function formatting.signed(value, unit, fallback)
  if type(value) ~= "number" then
    return fallback or "UNAVAILABLE"
  end
  local sign = value >= 0 and "+" or ""
  return string.format("%s%.2f %s", sign, value, unit or "")
end

function formatting.confidence(band)
  local labels = {
    high = "High confidence",
    medium = "Medium confidence",
    low = "Low confidence",
    stale = "Stale",
  }
  return labels[band] or "Unknown"
end

function formatting.eta(lower, upper, fallback)
  if type(lower) ~= "number" then
    return fallback or "NO ETA"
  end
  if type(upper) == "number" and upper ~= lower then
    return string.format("%d-%d MIN", lower, upper)
  end
  return string.format("%d MIN", lower)
end

function formatting.mode_label(mode)
  if mode == "expanded" then
    return "EXPANDED RACE"
  end
  if mode == "garage" then
    return "GARAGE / DIAGNOSTICS"
  end
  return "COMPACT RACE"
end

function formatting.cardinal_direction(degrees, fallback)
  if type(degrees) ~= "number" then return fallback or "Unavailable" end
  local normalized = degrees % 360
  local directions = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  local index = math.floor((normalized + 22.5) / 45) % 8 + 1
  return directions[index]
end

function formatting.grip(value, fallback)
  if type(value) ~= "number" then return fallback or "Unavailable" end
  local normalized = value <= 1 and value * 100 or value
  return string.format("%.0f%%", math.max(0, math.min(100, normalized)))
end

function formatting.track_condition(wetness, rain, fallback)
  if type(wetness) ~= "number" and type(rain) ~= "number" then return fallback or "Unknown" end
  local amount = math.max(wetness or 0, rain or 0)
  if amount <= 0.08 then return "Dry" end
  if amount <= 0.30 then return "Damp" end
  return "Wet"
end

function formatting.metric(metric, places, unavailable)
  if type(metric) ~= "table" or metric.value == nil then
    return unavailable or formatting.reason(metric and metric.reason)
  end
  return formatting.number(metric.value, places or 1, metric.unit or "")
end

function formatting.duration(seconds)
  return formatting.time(seconds, "--:--")
end

function formatting.reason(reason)
  local readable = {
    MEASURED_CURRENT = "Measured now",
    NO_TRUSTWORTHY_CONSTRAINT = "No trustworthy constraint",
    NO_TRUSTWORTHY_FUTURE_CHANGE = "No reliable future forecast",
    LOW_CONFIDENCE = "Low confidence",
    INSUFFICIENT_SAMPLES = "Waiting for representative lap",
    SOURCE_PARTIAL = "Some live fields unavailable",
    SOURCE_STALE = "Live data is stale",
    PIT_ENTRY_NOT_CALIBRATED = "Pit entry not calibrated",
    PIT_ENTRY_WRAPAROUND_APPLIED = "Pit entry after start/finish",
    STALE_TELEMETRY = "Live telemetry is stale",
    SOURCE_UNAVAILABLE = "Live source unavailable",
    IDENTITY_CHANGED = "Session identity changed",
    SESSION_RESTART = "Session restarted",
    INVALID_LAP = "Lap excluded from model",
    PIT_LAP_EXCLUDED = "Pit lap excluded from model",
    WET_LAP_EXCLUDED = "Wet lap excluded from model",
    CAUTION_LAP_EXCLUDED = "Caution lap excluded from model",
    REFUEL_TRANSITION = "Refuel transition excluded",
    PIT_ROUTE_NOT_CONFIGURED = "Pit route addition not configured",
    TARGET_NOT_CONFIGURED = "Target not configured",
    USER_CONFIG = "User configured",
    UNSUPPORTED = "Unsupported by this car/source",
    CSP_TYRE_WEAR_0_TO_1 = "CSP wear 0..1; displayed as life",
    CSP_TYRE_GRAIN_UNVERIFIED = "CSP graining scale unverified",
    CSP_TYRE_BLISTER_UNVERIFIED = "CSP blistering scale unverified",
    CSP_TYRE_FLATSPOT_UNIT_SCALE = "CSP flat spotting 0..1 reference scale",
  }
  return readable[reason] or (reason and tostring(reason) or "Unavailable")
end

function formatting.weather_type(value, context)
  if value == nil or value == "" then
    return "Unavailable"
  end
  local raw = tostring(value)
  if raw:match("^CURRENT%s+%d+") then
    return formatting.track_condition(context and context.track_wetness, context and context.rain_intensity, "Measured") == "Dry" and "Dry" or "Measured"
  end
  local text = raw:match("([^%.]+)$") or raw
  local numeric = tonumber(text)
  if numeric ~= nil then
    local map = { [0] = "Clear", [1] = "Few clouds", [2] = "Cloudy", [3] = "Light rain", [4] = "Heavy rain", [5] = "Storm" }
    return map[numeric] or "Measured"
  end
  text = text:gsub("_", " "):lower()
  return text:sub(1, 1):upper() .. text:sub(2)
end

function formatting.session_type(value)
  if value == nil or value == "" then
    return "Session unavailable"
  end
  local text = tostring(value):match("([^%.]+)$") or tostring(value)
  return text:gsub("_", " "):upper()
end

function formatting.readable_tyre_state(value)
  local labels = {
    COLD = "Cold",
    OPTIMAL = "In range",
    HOT = "Hot",
    WORN = "Worn",
    GRAINING = "Graining",
    BLISTERING = "Blistering",
    FLAT_SPOTTED = "Flat spotted",
    UNKNOWN = "Unknown",
  }
  return labels[value] or formatting.weather_type(value)
end

namespace.formatting = formatting
