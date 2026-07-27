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
  local first_y = box.y + 31
  local second_y = box.y + math.min(68, math.max(58, box.height - 38))
  if box.height >= 70 then
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
  components.card(header, "AVM PitWall", nil, vm.header.source_tone)
  components.safe_text(vm.header.session .. "  " .. vm.header.lap, header.x + 108, header.y + 9, header.width - 198, theme.color("muted"))
  components.badge(vm.header.source, header.x + header.width - 78, header.y + 4, 70, vm.header.source_tone)

  local fuel = boxes.cards.fuel
  card_metrics(fuel, "FUEL", "fuel", "good", {
    "CURRENT", vm.fuel.current, "info", "PIT ENTRY", vm.fuel.distance_to_pit, "muted",
  }, {
    "RANGE", vm.fuel.range, "good", "AT ENTRY", vm.fuel.expected_at_pit, "info",
  })

  local pace = boxes.cards.pace
  card_metrics(pace, "PACE", "pace", "info", {
    "CURRENT", vm.pace.last_lap, "text", "STATUS", vm.pace.status, "good",
  }, {
    "DELTA", vm.pace.delta, "info", "CONFIDENCE", vm.pace.confidence, "muted",
  })

  local pit = boxes.cards.pit
  card_metrics(pit, "PIT", "pit", "warning", {
    "DISTANCE", vm.pit.window, "warning", "CALL", vm.pit.recommendation, "warning",
  }, {
    "ENTRY", vm.fuel.distance_to_pit, "info", "STATE", vm.pit.state, "muted",
  })

  local tyres = boxes.cards.tyres
  card_metrics(tyres, "TYRES", "tyres", "good", {
    "COMPOUND", vm.tyres.compound, "good", "WEAR", vm.tyres.wear, "info",
  }, {
    "TEMP", vm.tyres.temperature, "info", "STATE", vm.tyres.condition, "muted",
  })

  local weather = boxes.cards.weather
  card_metrics(weather, "WEATHER", "dry", "info", {
    "CURRENT", vm.weather.current, "text", "TRACK", vm.weather.condition, "info",
  }, {
    "AIR / ROAD", vm.weather.temperatures, "muted", "WETNESS", vm.weather.track, "muted",
  })

  local status = boxes.cards.engineer or boxes.footer
  components.card(status, "ENGINEER", nil, vm.alert.tone)
  components.safe_text(vm.alert.text, status.x + 78, status.y + 4, status.width * 0.34, theme.tone(vm.alert.tone))
  components.safe_text(vm.alert.detail, status.x + status.width * 0.46, status.y + 4, status.width * 0.50, theme.color("muted"))
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
  csp.text("STINT: " .. value(vm.stint) .. " / " .. value(vm.total_stints) .. "    LAP: " .. value(vm.lap) .. " / " .. value(vm.planned_lap))
  csp.text("TIME: ELAPSED: " .. value(vm.timing.elapsed) .. "    REMAINING: " .. value(vm.timing.remaining))
  csp.text("TARGET STINT: " .. value(vm.timing.target))
  csp.text("FUEL: STATUS: " .. value(vm.fuel.current) .. "    RANGE: " .. value(vm.fuel.range))
  csp.text("FUEL: DISTANCE TO PIT ENTRY: " .. value(vm.fuel.distance_to_pit) .. "    PIT ROUTE: " .. value(vm.fuel.pit_route))
  csp.text("FUEL: EXPECTED AT PIT ENTRY: " .. value(vm.fuel.expected_at_pit))
  csp.text("PACE: STATUS: " .. value(vm.pace.status) .. "    DELTA: " .. value(vm.pace.delta))
  csp.text("PACE: TARGET PACE: " .. value(vm.pace.delta) .. "    LAST LAP: " .. value(vm.pace.last_lap))
  csp.text("TYRES: COMPOUND: " .. value(vm.tyres.compound) .. "    CONDITION: " .. value(vm.tyres.condition))
  csp.text("WEATHER: CURRENT: " .. value(vm.weather.current) .. " / " .. value(vm.weather.condition))
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
