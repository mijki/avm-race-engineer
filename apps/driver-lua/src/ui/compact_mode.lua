local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local compact = {}

local function metric(box, label, value, x, y, width, tone)
  components.label(label, x, y, theme.color("muted"))
  components.safe_text(value or "--", x, y + 14, width, theme.tone(tone or "info"))
end

local function card_metrics(box, title, icon, tone, left, right)
  components.card(box, title, icon, tone)
  local inner_x = box.x + 10
  local inner_width = box.width - 20
  local column_width = (inner_width - 10) / 2
  local first_y = box.y + (box.height < 70 and 27 or 31)
  local second_y = box.y + math.min(68, math.max(58, box.height - 38))
  if box.height >= 52 then
    metric(box, left[1], left[2], inner_x, first_y, column_width, left[3])
    metric(box, right[1], right[2], inner_x + column_width + 10, first_y, column_width, right[3])
  end
  if box.height >= 96 then
    metric(box, left[4], left[5], inner_x, second_y, column_width, left[6])
    metric(box, right[4], right[5], inner_x + column_width + 10, second_y, column_width, right[6])
  end
end

function compact.render(vm, boxes)
  local header = boxes.header
  components.header(vm, header)

  local fuel = boxes.cards.fuel
  card_metrics(fuel, "FUEL", "fuel", "good", {
    "CURRENT", vm.fuel.current, "info", "TARGET", vm.fuel.target, "neutral",
  }, {
    "RANGE", vm.fuel.range, "info", "VS TARGET", vm.fuel.vs_target, vm.fuel.tone or "neutral",
  })

  local pace = boxes.cards.pace
  card_metrics(pace, "PACE", "pace", "info", {
    "LAST VALID", vm.pace.last_lap, "text", "TARGET", vm.pace.target, "neutral",
  }, {
    "VS TARGET", vm.pace.vs_target, vm.pace.tone or "neutral", "5-LAP AVG", vm.pace.average, "info",
  })

  local pit = boxes.cards.pit
  card_metrics(pit, "PIT", "pit", "warning", {
    "DISTANCE", vm.pit.window, "warning", "AT ENTRY", vm.fuel.expected_at_pit, "info",
  }, {
    "CALL", vm.pit.recommendation, "warning", "STATE", vm.pit.state, "muted",
  })

  local tyres = boxes.cards.tyres
  components.card(tyres, "TYRES", "tyres", vm.tyres.color_tone or "info")
  local wheel_list = vm.tyres.wheels or {}
  local cell_width = math.max(20, (tyres.width - 30) / 2)
  local cell_height = math.max(20, (tyres.height - 38) / 2)
  for index = 1, 4 do
    local wheel = wheel_list[index] or { label = ({ "FL", "FR", "RL", "RR" })[index], temperature = "--", pressure_delta = "--", life = "--", state = "Unknown" }
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = tyres.x + 10 + col * (cell_width + 10)
    local y = tyres.y + 28 + row * (cell_height + 6)
    if csp.has("drawRectFilled") then csp.rect(x, y, cell_width, cell_height, theme.color("surface_alt"), 4) end
    local summary = wheel.label .. "  " .. wheel.temperature
    if cell_height >= 34 then summary = summary .. "  " .. wheel.life end
    components.safe_text(summary, x + 5, y + 3, cell_width - 10, theme.tone(wheel.tone or "info"))
    if cell_height >= 34 then
      components.safe_text(wheel.pressure_delta .. "  " .. wheel.state, x + 5, y + 18, cell_width - 10, theme.color("muted"))
    end
  end

  local weather = boxes.cards.weather
  components.card(weather, "WEATHER", "cloud", "info")
  components.safe_text(vm.weather.current .. "  ·  " .. vm.weather.condition, weather.x + 10, weather.y + 30, weather.width - 20, theme.color("text"))
  components.safe_text(vm.weather.temperatures, weather.x + 10, weather.y + 46, weather.width - 20, theme.color("muted"))
  components.safe_text("WIND  " .. vm.weather.wind, weather.x + 10, weather.y + 62, weather.width - 20, theme.color("cyan"))
  if weather.height >= 98 then
    components.safe_text("TRACK  " .. vm.weather.track .. "  GRIP " .. vm.weather.grip, weather.x + 10, weather.y + weather.height - 18, weather.width - 20, theme.color("muted"))
  end

  local status = boxes.cards.engineer or boxes.footer
  components.card(status, "ENGINEER", nil, vm.alert.tone)
  components.safe_text(vm.alert.text, status.x + 78, status.y + 4, status.width * 0.34, theme.tone(vm.alert.tone))
  components.safe_text(vm.alert.detail, status.x + status.width * 0.46, status.y + 4, status.width * 0.38, theme.color("muted"))
  if vm.alert.requires_acknowledgement then
    components.badge(vm.alert.acknowledged and "ACKNOWLEDGED" or "ACK", status.x + status.width - 74, status.y + 4, 64, vm.alert.acknowledged and "good" or "critical")
  end
end

local function value(value, fallback)
  local text = tostring(value or "")
  return text == "" and (fallback or "--") or text
end

function compact.render_text_first(vm, requested_mode, simplified)
  local mode_label = requested_mode == "compact" and "Compact" or "Compact (requested " .. value(requested_mode, "unknown") .. ")"
  local message = value(vm.alert.text, "NO ACTIVE INSTRUCTION")
  csp.text(simplified and "Simplified rendering mode" or "AVM PitWall")
  if requested_mode == "compact" then
    csp.text("MODE: COMPACT")
  else
    csp.text("MODE: " .. string.upper(mode_label))
  end
  csp.text("STINT: " .. value(vm.stint) .. "    STINT LAP: " .. value(vm.stint_lap) .. "    RACE LAP: " .. value(vm.race_lap or vm.lap) .. " / " .. value(vm.planned_lap))
  csp.text("TIME: ELAPSED: " .. value(vm.timing.elapsed) .. "    REMAINING: " .. value(vm.timing.remaining))
  csp.text("TARGET STINT: " .. value(vm.timing.target))
  csp.text("FUEL: STATUS: " .. value(vm.fuel.current) .. "    RANGE: " .. value(vm.fuel.range))
  csp.text("FUEL: DISTANCE TO PIT ENTRY: " .. value(vm.fuel.distance_to_pit) .. "    PIT ROUTE: " .. value(vm.fuel.pit_route))
  csp.text("FUEL: EXPECTED AT PIT ENTRY: " .. value(vm.fuel.expected_at_pit))
  csp.text("PACE: STATUS: " .. value(vm.pace.status) .. "    VS TARGET: " .. value(vm.pace.vs_target or vm.pace.delta))
  csp.text("PACE: TARGET PACE: " .. value(vm.pace.target) .. "    LAST VALID: " .. value(vm.pace.last_lap) .. "    AVG: " .. value(vm.pace.average))
  csp.text("FUEL: TARGET/LAP: " .. value(vm.fuel.target) .. "    AVG: " .. value(vm.fuel.average) .. "    VS TARGET: " .. value(vm.fuel.vs_target))
  csp.text("TYRES: COMPOUND: " .. value(vm.tyres.compound) .. "    CONDITION: " .. value(vm.tyres.condition))
  csp.text("WEATHER: CURRENT: " .. value(vm.weather.current) .. " / " .. value(vm.weather.condition) .. "    WIND: " .. value(vm.weather.wind))
  csp.text("NEXT WEATHER: " .. value(vm.weather.next_change) .. "    ETA: " .. value(vm.weather.eta))
  csp.text("WEATHER: SOURCE: " .. value(vm.weather.source) .. "    CONFIDENCE: " .. value(vm.weather.confidence))
  csp.text("ENGINEER: " .. message)
  csp.text("CONNECTION: BRIDGE: " .. value(vm.connections.bridge) .. "    ENGINEER: " .. value(vm.connections.engineer))
  csp.text("CONNECTION: TELEMETRY AGE: " .. value(vm.connections.telemetry))
end

function compact.render_simplified(vm, requested_mode)
  compact.render_text_first(vm, requested_mode, true)
end

namespace.ui.compact = compact
