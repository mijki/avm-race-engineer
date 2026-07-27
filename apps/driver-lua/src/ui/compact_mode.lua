local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local icons = namespace.ui.icons
local compact = {}

local function row(box, label, value, offset, tone, icon)
  components.status_line(label, value, box.x + 10, box.y + offset, box.width - 20, tone, icon)
end

function compact.render(vm, boxes)
  local fuel = boxes.cards.fuel
  components.card(fuel, "FUEL", "fuel", vm.connection_tone == "stale" and "stale" or "good")
  row(fuel, "FUEL RANGE", vm.fuel.range, 32, "good", "distance")
  row(fuel, "FUEL", vm.fuel.current, 54, "info")
  row(fuel, "EXPECTED AT PIT ENTRY", vm.fuel.expected_at_pit, 76, "info", "pit_entry")
  components.label("DISTANCE TO PIT ENTRY", fuel.x + 10, fuel.y + fuel.height - 29, theme.color("muted"))
  components.value(vm.fuel.distance_to_pit, fuel.x + fuel.width * 0.58, fuel.y + fuel.height - 29, theme.color("text"))

  local pace = boxes.cards.pace
  components.card(pace, "PACE", "pace", vm.pace.status == "PUSH" and "good" or "info")
  row(pace, "TARGET PACE", vm.pace.delta, 32, "info")
  row(pace, "STATUS", vm.pace.status, 54, vm.pace.status == "SAVE" and "warning" or "good")
  row(pace, "LAST LAP", vm.pace.last_lap, 76, "text")
  components.badge(string.upper(vm.pace.trend), pace.x + pace.width - 86, pace.y + 8, 76, "info")

  local tyres = boxes.cards.tyres
  components.card(tyres, "TYRES", "tyres", "good")
  row(tyres, "COMPOUND", vm.tyres.compound, 32, "good")
  row(tyres, "WEAR", vm.tyres.wear, 54, "info")
  row(tyres, "CONDITION", vm.tyres.condition, 76, vm.tyres.condition == "GOOD" and "good" or "warning")
  components.value(vm.tyres.temperature, tyres.x + 10, tyres.y + tyres.height - 29, theme.color("muted"))

  local pit = boxes.cards.pit
  components.card(pit, "PIT STRATEGY", "pit", vm.pit.state == "box_now" and "critical" or "warning")
  row(pit, "PIT WINDOW", vm.pit.window, 32, "warning")
  row(pit, "CALL", vm.pit.recommendation, 54, vm.pit.state == "box_now" and "critical" or "warning")
  row(pit, "NEXT STOP", vm.pit.next_fuel, 76, "info")
  components.value("TYRES " .. vm.pit.next_tyres, pit.x + 10, pit.y + pit.height - 29, theme.color("text"))

  local weather = boxes.cards.weather
  components.card(weather, "WEATHER", "dry", vm.weather.label == "STALE" and "stale" or vm.weather.label == "UNKNOWN" and "warning" or "info")
  icons.draw(vm.weather.label == "SCHEDULED" and "heavy_rain" or vm.weather.label == "ESTIMATED" and "light_rain" or "dry", weather.x + weather.width - 34, weather.y + 8, 20, theme.tone(vm.weather.label == "ESTIMATED" and "warning" or "info"))
  components.value(vm.weather.label .. "  " .. vm.weather.current .. "  " .. vm.weather.condition, weather.x + 10, weather.y + 31, theme.color("text"))
  components.value(vm.weather.next_change .. "  " .. vm.weather.eta, weather.x + 10, weather.y + 49, theme.tone(vm.weather.label == "UNKNOWN" or vm.weather.label == "STALE" and "warning" or "info"))
  components.label(vm.weather.source .. "  |  " .. vm.weather.confidence, weather.x + weather.width - 190, weather.y + 49, theme.color("muted"))
end

function compact.render_simplified(vm, requested_mode)
  csp.text("Simplified rendering mode")
  csp.separator()
  csp.text("AVM PitWall | Compact Mode")
  csp.text("MODE: COMPACT" .. (requested_mode ~= "compact" and " (requested " .. tostring(requested_mode or "unknown") .. ")" or ""))
  csp.text("STINT: " .. vm.stint .. " / " .. vm.total_stints .. "    LAP: " .. vm.lap .. " / " .. vm.planned_lap)
  csp.text("ELAPSED: " .. vm.timing.elapsed .. "    REMAINING: " .. vm.timing.remaining .. (vm.timing.remaining_is_estimated and " (estimated)" or ""))
  csp.text("TARGET STINT: " .. vm.timing.target)
  csp.text("FUEL: " .. vm.fuel.current .. "    RANGE: " .. vm.fuel.range)
  csp.text("DISTANCE TO PIT ENTRY: " .. vm.fuel.distance_to_pit)
  csp.text("WEATHER: " .. vm.weather.current .. " / " .. vm.weather.condition)
  csp.text("NEXT WEATHER: " .. vm.weather.next_change .. "    ETA: " .. vm.weather.eta)
  csp.text("ENGINEER: " .. vm.alert.text .. " - " .. vm.alert.detail)
  csp.text("BRIDGE: " .. vm.connections.bridge .. "    ENGINEER: " .. vm.connections.engineer)
  csp.text("TELEMETRY: " .. vm.connections.telemetry)
end

namespace.ui.compact = compact
