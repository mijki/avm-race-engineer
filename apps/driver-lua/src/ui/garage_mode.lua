local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local garage = {}

local function value(input, fallback)
  local text = tostring(input or "")
  return text == "" and (fallback or "Unavailable") or text
end

local function list(values, fallback)
  if type(values) ~= "table" or #values == 0 then return fallback or "None" end
  return table.concat(values, ", ")
end

local function api_state(api, name)
  local entry = type(api) == "table" and api[name] or nil
  if type(entry) ~= "table" then return name .. " unavailable" end
  return name .. " " .. tostring(entry.member_type or entry.result_type or "unknown") .. " -> " .. tostring(entry.result_type or "nil")
end

function garage.render(vm, boxes, state)
  local overview = boxes.cards.overview
  components.card(overview, "LIVE SOURCE / GARAGE DIAGNOSTICS", "setup", "selected")
  components.value(value(vm.header.source, "OFFLINE"), overview.x + 10, overview.y + 25, theme.color("cyan"))
  components.safe_text(value(vm.header.session, "SESSION UNAVAILABLE") .. "  |  " .. value(vm.connection_state, "unavailable"), overview.x + 110, overview.y + 25, overview.width - 120, theme.color("muted"))

  local scenarios_box = boxes.cards.scenarios
  components.card(scenarios_box, "SOURCE CONTROLS", "flag", "selected")
  local controls = { "USE LIVE SOURCE", "MOCK BASELINE", "MOCK ALTERNATE" }
  local button_width = (scenarios_box.width - 30) / #controls
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
  components.card(settings, "CALIBRATION", "setup", "info")
  components.safe_text("Mode  GARAGE / DIAGNOSTICS", settings.x + 10, settings.y + 32, settings.width - 20, theme.color("muted"))
  local calibration_button_width = (settings.width - 25) / 2
  if components.button("CAPTURE SPLINE", settings.x + 10, settings.y + 52, calibration_button_width, "warning") then
    state:capture_calibration()
  end
  if components.button("RESET CALIBRATION", settings.x + 15 + calibration_button_width, settings.y + 52, calibration_button_width, "critical") then
    state:reset_calibration()
  end

  local diagnostics = boxes.cards.diagnostics
  components.card(diagnostics, "RAW TELEMETRY / TRACEABILITY", "telemetry", "info")
  local api = vm.diagnostics.api
  local raw = vm.diagnostics.raw or {}
  local raw_session = raw.session or {}
  local raw_car = raw.car or {}
  local row = diagnostics.y + 30
  components.safe_text("Source " .. value(vm.source.state, "OFFLINE") .. "  |  Age " .. value(vm.diagnostics.update_age, "--") .. "  |  Core " .. (vm.diagnostics.core_valid and "valid" or "partial"), diagnostics.x + 10, row, diagnostics.width - 20, theme.color("text"))
  components.safe_text("Failure " .. value(vm.diagnostics.first_failure, "None"), diagnostics.x + 10, row + 17, diagnostics.width - 20, theme.color("warning"))
  components.safe_text("API " .. api_state(api, "getSim") .. "  |  " .. api_state(api, "getCar") .. "  |  " .. api_state(api, "getSession"), diagnostics.x + 10, row + 34, diagnostics.width - 20, theme.color("muted"))
  components.safe_text("API track " .. api_state(api, "getTrackID") .. "  |  " .. api_state(api, "getTrackLayout") .. "  |  " .. api_state(api, "getTyresName"), diagnostics.x + 10, row + 51, diagnostics.width - 20, theme.color("muted"))
  components.safe_text("Core missing " .. list(vm.diagnostics.core_missing) .. "  |  Optional " .. list(vm.diagnostics.optional_missing), diagnostics.x + 10, row + 68, diagnostics.width - 20, theme.color("muted"))
  components.safe_text("Core values fuel " .. value(raw_car.fuel_l) .. "  speed " .. value(raw_car.speed_kmh) .. "  lap " .. value(raw_session.current_lap) .. "  time " .. value(raw_session.elapsed_s) .. "  spline " .. value(raw_car.spline), diagnostics.x + 10, row + 85, diagnostics.width - 20, theme.color("text"))
  components.safe_text("Identity " .. value(vm.diagnostics.identity and vm.diagnostics.identity.car_id, "--") .. " / " .. value(vm.diagnostics.identity and vm.diagnostics.identity.track_id, "--") .. " / " .. value(vm.diagnostics.identity and vm.diagnostics.identity.layout_id, "--"), diagnostics.x + 10, row + 102, diagnostics.width - 20, theme.color("text"))
  components.safe_text("Samples laps " .. tostring(vm.diagnostics.samples_laps) .. "  fuel " .. tostring(vm.diagnostics.samples_fuel) .. "  pace " .. tostring(vm.diagnostics.samples_pace) .. "  weather " .. tostring(vm.diagnostics.samples_weather), diagnostics.x + 10, row + 119, diagnostics.width - 20, theme.color("muted"))
  components.safe_text("Reset " .. value(vm.diagnostics.last_reset_reason, "None") .. "  |  Calibration " .. value(vm.calibration.summary), diagnostics.x + 10, row + 136, diagnostics.width - 20, theme.color("muted"))
  components.safe_text("Renderer AVM PitWall / " .. value(state.mode, "unknown") .. " / cards  |  Layout " .. string.format("%.0fx%.0f", boxes.outer.width, boxes.outer.height), diagnostics.x + 10, row + 153, diagnostics.width - 20, theme.color("muted"))
end

function garage.render_text_first(vm, state)
  csp.text("AVM PitWall")
  csp.text("MODE: Garage / Diagnostics")
  csp.text("SOURCE: " .. value(vm.source and vm.source.state, "OFFLINE") .. "    SESSION: " .. value(vm.header.session, "UNKNOWN SESSION"))
  csp.text("RAW: SPEED " .. value(vm.raw.speed) .. "    SPLINE " .. value(vm.raw.spline) .. "    PIT LANE " .. value(vm.raw.pit_lane))
  csp.text("FUEL: CURRENT " .. value(vm.fuel.current) .. "    RANGE " .. value(vm.fuel.range) .. "    PIT ENTRY " .. value(vm.fuel.distance_to_pit))
  csp.text("PACE: CURRENT " .. value(vm.pace.current) .. "    ROLLING " .. value(vm.pace.rolling) .. "    TYRES " .. value(vm.tyres.state))
  csp.text("WEATHER: " .. value(vm.weather.current) .. "    TREND " .. value(vm.weather.trend))
  csp.text("SAMPLES: LAPS " .. tostring(vm.diagnostics.samples_laps) .. "    FUEL " .. tostring(vm.diagnostics.samples_fuel) .. "    PACE " .. tostring(vm.diagnostics.samples_pace))
  csp.text("FAILURE: " .. value(vm.diagnostics.first_failure, "None"))
  csp.text("NORMALIZATION: " .. value(vm.diagnostics.normalization_rejection, "None"))
  csp.text("CALIBRATION: " .. value(vm.calibration.summary))
  csp.text("MOCK BASELINE / MOCK ALTERNATE are Garage-only diagnostics")
  csp.text("LIVE failures remain unavailable; no mock substitution")
end

namespace.ui.garage = garage
