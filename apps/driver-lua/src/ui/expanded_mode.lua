local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local icons = namespace.ui.icons
local expanded = {}

local function line(box, label, value, y, tone)
  components.label(label, box.x + 10, y, theme.color("muted"))
  components.value(value, box.x + 10, y + 15, theme.tone(tone or "info"))
end

function expanded.render(vm, boxes)
  local timing = boxes.cards.timing
  components.card(timing, "STINT TIMING", "elapsed", "info")
  local column = timing.width / 3
  line({ x = timing.x, width = column }, "ELAPSED", vm.timing.elapsed, timing.y + 32, "text")
  line({ x = timing.x + column, width = column }, "REMAINING", vm.timing.remaining .. (vm.timing.remaining_is_estimated and " *" or ""), timing.y + 32, "warning")
  line({ x = timing.x + column * 2, width = column }, "TARGET", vm.timing.target, timing.y + 32, "cyan")
  components.progress(timing.x + 10, timing.y + timing.height - 15, timing.width - 20, vm.timing.progress, "info")

  local message = boxes.cards.message
  components.card(message, "ENGINEER MESSAGE", "flag", vm.alert.tone)
  components.safe_text(vm.alert.text, message.x + 10, message.y + 33, message.width - 20, theme.tone(vm.alert.tone))
  components.safe_text(vm.alert.detail, message.x + 10, message.y + 52, message.width - 20, theme.color("muted"))
  components.badge(vm.alert.status, message.x + 10, message.y + message.height - 27, math.min(118, message.width - 20), vm.alert.requires_acknowledgement and "critical" or "info")

  local fuel = boxes.cards.fuel
  components.card(fuel, "FUEL", "fuel", "good")
  line(fuel, "FUEL RANGE", vm.fuel.range, fuel.y + 31, "good")
  line(fuel, "CURRENT", vm.fuel.current, fuel.y + 66, "info")
  line(fuel, "AT PIT ENTRY", vm.fuel.expected_at_pit, fuel.y + 101, "info")
  components.label("DISTANCE TO PIT ENTRY", fuel.x + 10, fuel.y + fuel.height - 39, theme.color("muted"))
  components.value(vm.fuel.distance_to_pit, fuel.x + 10, fuel.y + fuel.height - 23, theme.color("text"))
  components.value("PIT ROUTE  " .. vm.fuel.pit_route, fuel.x + fuel.width * 0.52, fuel.y + fuel.height - 23, theme.color("text"))

  local pace = boxes.cards.pace
  components.card(pace, "PACE", "pace", "info")
  line(pace, "TARGET DELTA", vm.pace.delta, pace.y + 31, "info")
  line(pace, "STATUS", vm.pace.status, pace.y + 66, vm.pace.status == "SAVE" and "warning" or "good")
  line(pace, "LAST REPRESENTATIVE LAP", vm.pace.last_lap, pace.y + 101, "text")
  components.label("ROLLING TREND  " .. string.upper(vm.pace.trend), pace.x + 10, pace.y + pace.height - 24, theme.color("muted"))
  local trend = vm.pace.trend_values
  for index = 1, #trend - 1 do
    local left = pace.x + 10 + (index - 1) * ((pace.width - 20) / math.max(1, #trend - 1))
    local right = pace.x + 10 + index * ((pace.width - 20) / math.max(1, #trend - 1))
    local left_y = pace.y + pace.height * 0.64 - trend[index] * 10
    local right_y = pace.y + pace.height * 0.64 - trend[index + 1] * 10
    csp.line(left, left_y, right, right_y, theme.color("cyan"), 2)
  end

  local tyres = boxes.cards.tyres
  components.card(tyres, "TYRES", "tyres", "good")
  line(tyres, "COMPOUND", vm.tyres.compound, tyres.y + 31, "good")
  line(tyres, "WEAR", vm.tyres.wear, tyres.y + 66, "info")
  line(tyres, "CONDITION", vm.tyres.condition, tyres.y + 101, "good")
  components.label(vm.tyres.temperature, tyres.x + 10, tyres.y + tyres.height - 24, theme.color("muted"))

  local pit = boxes.cards.pit
  components.card(pit, "PIT STRATEGY", "pit", "warning")
  line(pit, "WINDOW", vm.pit.window, pit.y + 31, "warning")
  line(pit, "RECOMMENDATION", vm.pit.recommendation, pit.y + 66, vm.pit.state == "box_now" and "critical" or "warning")
  line(pit, "NEXT FUEL", vm.pit.next_fuel, pit.y + 101, "info")
  components.label("TYRES " .. vm.pit.next_tyres .. "  |  " .. vm.pit.service, pit.x + 10, pit.y + pit.height - 24, theme.color("muted"))

  local weather = boxes.cards.weather
  components.card(weather, "WEATHER TIMELINE", "cloud", vm.weather.label == "STALE" and "stale" or "info")
  components.badge(vm.weather.label, weather.x + weather.width - 96, weather.y + 8, 84, vm.weather.label == "ESTIMATED" and "warning" or vm.weather.label == "STALE" and "stale" or "info")
  local timeline = vm.weather.timeline
  local cell_width = (weather.width - 20) / math.max(1, #timeline)
  for index = 1, #timeline do
    local point = timeline[index] or {}
    local x = weather.x + 10 + (index - 1) * cell_width
    components.label(point.horizon or "--", x, weather.y + 34, theme.color("muted"))
    components.safe_text(point.weather or "UNKNOWN", x, weather.y + 50, cell_width - 4, theme.color("text"))
    components.label(point.condition or "UNKNOWN", x, weather.y + 68, theme.color("cyan"))
  end
  components.label(vm.weather.source .. "  |  " .. vm.weather.confidence .. "  |  " .. vm.weather.implication, weather.x + 10, weather.y + weather.height - 18, theme.color("muted"))

  local connections = boxes.cards.connections
  components.card(connections, "HEALTH", "telemetry", vm.connection_tone)
  components.status_line("ENGINEER", vm.connections.engineer, connections.x + 10, connections.y + 34, connections.width - 20, vm.connection_tone, "engineer")
  components.status_line("BRIDGE", vm.connections.bridge, connections.x + 10, connections.y + 57, connections.width - 20, vm.connection_tone, "bridge")
  components.status_line("TELEMETRY", vm.connections.telemetry, connections.x + 10, connections.y + 80, connections.width - 20, vm.connection_tone, "telemetry")
end

namespace.ui.expanded = expanded
