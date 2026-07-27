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
  if type(band) ~= "string" then
    return "UNKNOWN"
  end
  return string.upper(band:gsub("_", " "))
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
    INSUFFICIENT_SAMPLES = "Waiting for representative laps",
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
  }
  return readable[reason] or (reason and tostring(reason) or "Unavailable")
end

function formatting.weather_type(value)
  if value == nil or value == "" then
    return "Unavailable"
  end
  local text = tostring(value):match("([^%.]+)$") or tostring(value)
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
    UNKNOWN = "Unknown",
  }
  return labels[value] or formatting.weather_type(value)
end

namespace.formatting = formatting
