local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local garage = {}

local function value(input, fallback)
  local text = tostring(input or "")
  return text == "" and (fallback or "UNAVAILABLE") or text
end

local function line(text, x, y, tone)
  components.label(text, x, y, theme.tone(tone or "text"))
end

function garage.render(vm, boxes, state)
  local overview = boxes.cards.overview
  components.card(overview, "LIVE SOURCE / GARAGE DIAGNOSTICS", "setup", "selected")
  components.value(value(vm.header.source, "RECOVERY"), overview.x + 10, overview.y + 31, theme.color("cyan"))
  components.label(value(vm.header.session, "SESSION UNAVAILABLE") .. "  |  " .. value(vm.connection_state, "degraded"), overview.x + 10, overview.y + 52, theme.color("muted"))
  components.label("Garage is the only surface for mock selection and pit-entry calibration.", overview.x + overview.width * 0.48, overview.y + 33, theme.color("muted"))

  local scenarios_box = boxes.cards.scenarios
  components.card(scenarios_box, "MOCK / SOURCE CONTROLS", "flag", "selected")
  local controls = { "USE LIVE SOURCE", "MOCK BASELINE", "MOCK ALTERNATE" }
  local columns = 3
  local button_width = (scenarios_box.width - 30) / columns
  for index = 1, #controls do
    local x = scenarios_box.x + 10 + (index - 1) * (button_width + 5)
    local label = controls[index]
    if components.button(label, x, scenarios_box.y + 32, button_width, label == "USE LIVE SOURCE" and "good" or "selected") then
      if label == "USE LIVE SOURCE" then
        state:set_source_mode("live")
      elseif label == "MOCK BASELINE" then
        state:set_mock_scenario("baseline")
      else
        state:set_mock_scenario("alternate")
      end
    end
  end

  local settings = boxes.cards.settings
  components.card(settings, "PRESENTATION / CALIBRATION", "setup", "info")
  components.label("MODE", settings.x + 10, settings.y + 34, theme.color("muted"))
  components.value("GARAGE / DIAGNOSTICS", settings.x + 10, settings.y + 50, theme.color("text"))
  if components.button("CAPTURE CURRENT SPLINE", settings.x + 10, settings.y + 78, settings.width - 20, "warning") then
    state:capture_calibration()
  end
  if components.button("RESET CALIBRATION", settings.x + 10, settings.y + 108, settings.width - 20, "critical") then
    state:reset_calibration()
  end
  if components.button(state.settings.sound_enabled and "SOUND ON" or "SOUND OFF", settings.x + 10, settings.y + 138, settings.width - 20, state.settings.sound_enabled and "good" or "stale") then
    state.settings.sound_enabled = not state.settings.sound_enabled
    state.save_settings()
  end

  local diagnostics = boxes.cards.diagnostics
  components.card(diagnostics, "RAW TELEMETRY / TRACEABILITY", "telemetry", "info")
  components.status_line("SOURCE", value(vm.connections.source, "UNAVAILABLE"), diagnostics.x + 10, diagnostics.y + 34, diagnostics.width * 0.22, vm.header.source_mode == "live" and "good" or "warning")
  components.status_line("FRESHNESS", value(vm.diagnostics.freshness), diagnostics.x + diagnostics.width * 0.25, diagnostics.y + 34, diagnostics.width * 0.22, "info")
  components.status_line("REGIME", value(vm.diagnostics.regime), diagnostics.x + diagnostics.width * 0.50, diagnostics.y + 34, diagnostics.width * 0.22, "info")
  components.status_line("AUDIO", namespace.adapters.audio.status(), diagnostics.x + diagnostics.width * 0.75, diagnostics.y + 34, diagnostics.width * 0.20, namespace.adapters.audio.available and "good" or "warning")
  components.label("Speed " .. value(vm.raw.speed) .. "  |  Spline " .. value(vm.raw.spline) .. "  |  Pit lane " .. value(vm.raw.pit_lane) .. "  |  Pit box " .. value(vm.raw.pit_box), diagnostics.x + 10, diagnostics.y + 58, theme.color("text"))
  components.label("Fuel " .. value(vm.fuel.current) .. "  |  Pace " .. value(vm.pace.current) .. "  |  Weather " .. value(vm.weather.current), diagnostics.x + 10, diagnostics.y + 76, theme.color("text"))
  components.label("Samples: laps " .. tostring(vm.diagnostics.samples_laps) .. "  fuel " .. tostring(vm.diagnostics.samples_fuel) .. "  pace " .. tostring(vm.diagnostics.samples_pace) .. "  weather " .. tostring(vm.diagnostics.samples_weather), diagnostics.x + 10, diagnostics.y + 94, theme.color("muted"))
  components.label("Calibration: " .. value(vm.calibration.summary), diagnostics.x + 10, diagnostics.y + 112, theme.color("muted"))
  components.label("No live-source failure selects mock data automatically.", diagnostics.x + 10, diagnostics.y + 130, theme.color("muted"))
end

function garage.render_text_first(vm, state)
  csp.text("AVM PitWall")
  csp.text("MODE: Garage / Diagnostics")
  csp.text("SOURCE: " .. value(vm.connections.source, "UNAVAILABLE") .. "    SESSION: " .. value(vm.header.session, "UNKNOWN SESSION"))
  csp.text("RAW: SPEED " .. value(vm.raw.speed) .. "    SPLINE " .. value(vm.raw.spline) .. "    PIT LANE " .. value(vm.raw.pit_lane))
  csp.text("FUEL: CURRENT " .. value(vm.fuel.current) .. "    RANGE " .. value(vm.fuel.range) .. "    PIT ENTRY " .. value(vm.fuel.distance_to_pit))
  csp.text("PACE: CURRENT " .. value(vm.pace.current) .. "    ROLLING " .. value(vm.pace.rolling) .. "    TYRES " .. value(vm.tyres.state))
  csp.text("WEATHER: " .. value(vm.weather.current) .. "    TREND " .. value(vm.weather.trend))
  csp.text("SAMPLES: LAPS " .. tostring(vm.diagnostics.samples_laps) .. "    FUEL " .. tostring(vm.diagnostics.samples_fuel) .. "    PACE " .. tostring(vm.diagnostics.samples_pace))
  csp.text("CALIBRATION: " .. value(vm.calibration.summary))
  csp.text("MOCK BASELINE / MOCK ALTERNATE are Garage-only diagnostics")
  csp.text("LIVE failures remain unavailable; no mock substitution")
end

namespace.ui.garage = garage
