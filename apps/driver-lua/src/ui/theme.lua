local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp

local theme = {
  background = { 0.025, 0.035, 0.045, 1 },
  surface = { 0.055, 0.075, 0.09, 1 },
  surface_alt = { 0.075, 0.095, 0.11, 1 },
  border = { 0.16, 0.20, 0.22, 1 },
  text = { 0.92, 0.95, 0.96, 1 },
  muted = { 0.49, 0.56, 0.59, 1 },
  cyan = { 0.10, 0.72, 0.92, 1 },
  green = { 0.34, 0.86, 0.20, 1 },
  amber = { 0.98, 0.66, 0.10, 1 },
  red = { 0.94, 0.18, 0.18, 1 },
  blue = { 0.22, 0.54, 0.84, 1 },
  grey = { 0.38, 0.43, 0.45, 1 },
  black = { 0.01, 0.015, 0.02, 1 },
}

function theme.color(name, alpha)
  local value = theme[name] or theme.text
  return csp.color(value[1], value[2], value[3], alpha or value[4])
end

function theme.tone(name)
  if name == "good" or name == "live" then
    return theme.color("green")
  end
  if name == "warning" or name == "degraded" then
    return theme.color("amber")
  end
  if name == "critical" then
    return theme.color("red")
  end
  if name == "info" or name == "selected" then
    return theme.color("cyan")
  end
  if name == "stale" or name == "offline" then
    return theme.color("grey")
  end
  return theme.color("text")
end

function theme.metric_color(metric)
  if type(metric) ~= "table" then
    return theme.color("muted")
  end
  if metric.confidence_band == "low" then
    return theme.color("amber")
  end
  return theme.color("text")
end

namespace.ui = namespace.ui or {}
namespace.ui.theme = theme
