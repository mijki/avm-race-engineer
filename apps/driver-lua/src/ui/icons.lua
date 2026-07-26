local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local icons = {}

local function ring(x, y, size, color)
  csp.circle(x + size * 0.5, y + size * 0.5, size * 0.34, color, false)
end

function icons.draw(name, x, y, size, color)
  local tint = color or theme.tone("info")
  local half = size * 0.5
  if name == "fuel" then
    csp.rect(x + size * 0.32, y + size * 0.18, size * 0.30, size * 0.64, tint, 2)
    csp.line(x + size * 0.62, y + size * 0.30, x + size * 0.82, y + size * 0.30, tint, 2)
    csp.line(x + size * 0.82, y + size * 0.30, x + size * 0.82, y + size * 0.62, tint, 2)
  elseif name == "pace" or name == "elapsed" or name == "remaining" or name == "target" then
    ring(x, y, size, tint)
    csp.line(x + half, y + half, x + half, y + size * 0.28, tint, 2)
    csp.line(x + half, y + half, x + size * 0.70, y + size * 0.62, tint, 2)
  elseif name == "tyres" then
    ring(x, y, size, tint)
    csp.circle(x + half, y + half, size * 0.14, tint, true)
  elseif name == "pit" or name == "pit_entry" then
    csp.line(x + size * 0.25, y + size * 0.72, x + size * 0.75, y + size * 0.72, tint, 2)
    csp.line(x + size * 0.5, y + size * 0.18, x + size * 0.5, y + size * 0.72, tint, 2)
    csp.triangle(x + size * 0.34, y + size * 0.24, x + size * 0.66, y + size * 0.24, x + size * 0.50, y + size * 0.05, tint)
  elseif name == "distance" then
    csp.line(x + size * 0.18, y + size * 0.50, x + size * 0.82, y + size * 0.50, tint, 2)
    csp.triangle(x + size * 0.18, y + size * 0.50, x + size * 0.36, y + size * 0.38, x + size * 0.36, y + size * 0.62, tint)
    csp.triangle(x + size * 0.82, y + size * 0.50, x + size * 0.64, y + size * 0.38, x + size * 0.64, y + size * 0.62, tint)
  elseif name == "dry" then
    csp.circle(x + size * 0.5, y + size * 0.5, size * 0.24, tint, true)
    for index = 0, 3 do
      local dx = index % 2 == 0 and size * 0.14 or size * 0.86
      local dy = index < 2 and size * 0.14 or size * 0.86
      csp.line(x + size * 0.5, y + size * 0.5, x + dx, y + dy, tint, 1)
    end
  elseif name == "cloud" or name == "light_rain" or name == "rain" or name == "heavy_rain" or name == "wet_track" then
    csp.circle(x + size * 0.38, y + size * 0.50, size * 0.19, tint, true)
    csp.circle(x + size * 0.58, y + size * 0.42, size * 0.25, tint, true)
    csp.rect(x + size * 0.24, y + size * 0.48, size * 0.54, size * 0.18, tint, 3)
    if name ~= "cloud" then
      csp.line(x + size * 0.34, y + size * 0.76, x + size * 0.30, y + size * 0.92, tint, 1)
      csp.line(x + size * 0.52, y + size * 0.76, x + size * 0.48, y + size * 0.92, tint, 1)
      csp.line(x + size * 0.70, y + size * 0.76, x + size * 0.66, y + size * 0.92, tint, 1)
    end
  elseif name == "critical" or name == "warning" then
    csp.triangle(x + half, y + size * 0.08, x + size * 0.90, y + size * 0.86, x + size * 0.10, y + size * 0.86, tint)
    csp.line(x + half, y + size * 0.34, x + half, y + size * 0.62, theme.color("black"), 2)
    csp.circle(x + half, y + size * 0.74, size * 0.04, theme.color("black"), true)
  elseif name == "flag" then
    csp.line(x + size * 0.24, y + size * 0.12, x + size * 0.24, y + size * 0.88, tint, 2)
    csp.triangle(x + size * 0.28, y + size * 0.18, x + size * 0.84, y + size * 0.28, x + size * 0.28, y + size * 0.48, tint)
  elseif name == "ack" then
    csp.line(x + size * 0.18, y + size * 0.54, x + size * 0.42, y + size * 0.78, tint, 2)
    csp.line(x + size * 0.42, y + size * 0.78, x + size * 0.84, y + size * 0.22, tint, 2)
  elseif name == "engineer" or name == "bridge" or name == "telemetry" then
    csp.circle(x + half, y + half, size * 0.28, tint, false)
    csp.line(x + size * 0.18, y + half, x + size * 0.36, y + half, tint, 2)
    csp.line(x + size * 0.64, y + half, x + size * 0.82, y + half, tint, 2)
  elseif name == "offline" or name == "stale" or name == "low_confidence" then
    ring(x, y, size, tint)
    csp.line(x + size * 0.20, y + size * 0.20, x + size * 0.80, y + size * 0.80, tint, 2)
  elseif name == "setup" then
    csp.rect(x + size * 0.18, y + size * 0.28, size * 0.64, size * 0.46, tint, 3)
    csp.line(x + size * 0.32, y + size * 0.18, x + size * 0.68, y + size * 0.18, tint, 2)
  else
    ring(x, y, size, tint)
  end
end

namespace.ui.icons = icons
