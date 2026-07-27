local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local icons = namespace.ui.icons
local expanded = {}

local function line(box, label, value, y, tone)
  if type(box.height) ~= "number" or y + 15 > box.y + box.height - 3 then return end
  components.label(label, box.x + 10, y, theme.color("muted"))
  components.safe_text(value or "--", box.x + 10, y + 15, math.max(20, (box.width or 20) - 20), theme.tone(tone or "info"))
end

function expanded.render(vm, boxes)
  components.header(vm, boxes.header)
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
  if fuel.height >= 190 then
    line(fuel, "TARGET / AVG", vm.fuel.target .. " / " .. vm.fuel.average, fuel.y + 136, "text")
    line(fuel, "LATEST VALID VS TARGET", vm.fuel.vs_target, fuel.y + 171, "info")
    if fuel.height >= 225 then
      line(fuel, "VALID VS AVG", vm.fuel.vs_average, fuel.y + 206, "info")
      line(fuel, "AVG VS TARGET", vm.fuel.average_vs_target, fuel.y + 241, "info")
    end
    components.label("DISTANCE TO PIT ENTRY", fuel.x + 10, fuel.y + fuel.height - 39, theme.color("muted"))
    components.safe_text(vm.fuel.distance_to_pit, fuel.x + 10, fuel.y + fuel.height - 24, fuel.width * 0.44, theme.color("text"))
    components.safe_text("PIT ROUTE  " .. vm.fuel.pit_route, fuel.x + fuel.width * 0.52, fuel.y + fuel.height - 24, fuel.width * 0.44, theme.color("text"))
  end

  local pace = boxes.cards.pace
  components.card(pace, "PACE", "pace", "info")
  line(pace, "TARGET DELTA", vm.pace.delta, pace.y + 31, "info")
  line(pace, "STATUS", vm.pace.status, pace.y + 66, vm.pace.status == "SAVE" and "warning" or "good")
  line(pace, "LAST REPRESENTATIVE LAP", vm.pace.last_lap, pace.y + 101, "text")
  if pace.height >= 190 then
    line(pace, "TARGET / AVG", vm.pace.target .. " / " .. vm.pace.average, pace.y + 136, "text")
    line(pace, "VALID VS AVG", vm.pace.vs_average, pace.y + 171, "info")
    if pace.height >= 225 then
      line(pace, "AVG VS TARGET", vm.pace.average_vs_target, pace.y + 206, "info")
      line(pace, "LATEST COMPLETED", vm.pace.latest_completed, pace.y + 241, "info")
    end
    components.label("ROLLING TREND  " .. string.upper(vm.pace.trend), pace.x + 10, pace.y + pace.height - 24, theme.color("muted"))
    local trend = vm.pace.trend_values
    if csp.has("drawLine") then
      for index = 1, #trend - 1 do
        local left = pace.x + 10 + (index - 1) * ((pace.width - 20) / math.max(1, #trend - 1))
        local right = pace.x + 10 + index * ((pace.width - 20) / math.max(1, #trend - 1))
        local left_y = pace.y + pace.height * 0.64 - trend[index] * 10
        local right_y = pace.y + pace.height * 0.64 - trend[index + 1] * 10
        csp.line(left, left_y, right, right_y, theme.color("cyan"), 2)
      end
    end
  end

  local tyres = boxes.cards.tyres
  components.card(tyres, "TYRES", "tyres", "good")
  line(tyres, "COMPOUND", vm.tyres.compound, tyres.y + 31, "good")
  line(tyres, "WEAR", vm.tyres.wear, tyres.y + 66, "info")
  line(tyres, "CONDITION", vm.tyres.condition, tyres.y + 101, "good")
  if tyres.height >= 155 then
    local wheel_text = {}
    for index = 1, 4 do
      local wheel = vm.tyres.wheels and vm.tyres.wheels[index]
      wheel_text[#wheel_text + 1] = wheel and (wheel.label .. " " .. wheel.temperature .. " " .. wheel.pressure_delta .. " " .. wheel.life) or "--"
    end
    components.safe_text(table.concat(wheel_text, "  |  "), tyres.x + 10, tyres.y + tyres.height - 42, tyres.width - 20, theme.color("muted"))
    components.safe_text(vm.tyres.temperature_source or vm.tyres.temperature, tyres.x + 10, tyres.y + tyres.height - 24, tyres.width - 20, theme.color("muted"))
  end

  local pit = boxes.cards.pit
  components.card(pit, "PIT STRATEGY", "pit", "warning")
  line(pit, "WINDOW", vm.pit.window, pit.y + 31, "warning")
  line(pit, "RECOMMENDATION", vm.pit.recommendation, pit.y + 66, vm.pit.state == "box_now" and "critical" or "warning")
  line(pit, "NEXT FUEL", vm.pit.next_fuel, pit.y + 101, "info")
  if pit.height >= 190 then
    components.safe_text("TYRES " .. vm.pit.next_tyres .. "  |  " .. vm.pit.service, pit.x + 10, pit.y + pit.height - 24, pit.width - 20, theme.color("muted"))
  end

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
  components.safe_text(vm.weather.wind .. "  |  " .. vm.weather.track .. "  |  Grip " .. vm.weather.grip, weather.x + 10, weather.y + weather.height - 42, weather.width - 20, theme.color("cyan"))
  components.safe_text(vm.weather.source .. "  |  " .. vm.weather.confidence .. "  |  " .. vm.weather.implication, weather.x + 10, weather.y + weather.height - 24, weather.width - 20, theme.color("muted"))

  local connections = boxes.cards.connections
  components.card(connections, "TRUST", "telemetry", vm.connection_tone)
  if connections.height >= 50 then
    components.status_line("TEL", vm.connections.telemetry_state, connections.x + 10, connections.y + 34, connections.width - 20, vm.health.telemetry.tone, "telemetry")
  end
  if connections.height >= 73 then
    components.status_line("BRG", vm.connections.bridge_state, connections.x + 10, connections.y + 57, connections.width - 20, vm.health.bridge.tone, "bridge")
  end
  if connections.height >= 96 then
    components.status_line("ENG", vm.connections.engineer_state, connections.x + 10, connections.y + 80, connections.width - 20, vm.health.engineer.tone, "engineer")
  end
end

local function value(value, fallback)
  local text = tostring(value or "")
  return text == "" and (fallback or "UNAVAILABLE") or text
end

function expanded.render_text_first(vm)
  csp.text("AVM PitWall")
  csp.text("MODE: Expanded")
  csp.text("STINT: " .. value(vm.stint) .. " / " .. value(vm.total_stints) .. "    LAP: " .. value(vm.lap) .. " / " .. value(vm.planned_lap))
  csp.text("TIME: Elapsed: " .. value(vm.timing.elapsed) .. "    Remaining: " .. value(vm.timing.remaining) .. "    Target: " .. value(vm.timing.target))
  csp.text("FUEL: Range: " .. value(vm.fuel.range) .. "    Current: " .. value(vm.fuel.current) .. "    Pit entry: " .. value(vm.fuel.expected_at_pit))
  csp.text("PACE: Status: " .. value(vm.pace.status) .. "    Delta: " .. value(vm.pace.delta) .. "    Last lap: " .. value(vm.pace.last_lap))
  csp.text("TYRES: Compound: " .. value(vm.tyres.compound) .. "    Condition: " .. value(vm.tyres.condition) .. "    Wear: " .. value(vm.tyres.wear))
  csp.text("PIT: Window: " .. value(vm.pit.window) .. "    Call: " .. value(vm.pit.recommendation))
  csp.text("WEATHER: Current: " .. value(vm.weather.current) .. "    Next change: " .. value(vm.weather.next_change))
  csp.text("ENGINEER: " .. value(vm.alert.text, "NO ACTIVE INSTRUCTION"))
  csp.text("CONNECTION: Bridge: " .. value(vm.connections.bridge) .. "    Engineer: " .. value(vm.connections.engineer) .. "    Telemetry age: " .. value(vm.connections.telemetry))
end

namespace.ui.expanded = expanded
