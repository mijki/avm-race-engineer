local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local components = namespace.ui.components
local icons = namespace.ui.icons
local garage = {}

function garage.render(vm, boxes, state)
  local overview = boxes.cards.overview
  components.card(overview, "F1 DEVELOPMENT FIXTURE", "setup", "selected")
  components.value(vm.scenario_id or "UNKNOWN", overview.x + 10, overview.y + 31, theme.color("cyan"))
  components.label(vm.session_name .. "  |  " .. vm.connection_state .. "  |  " .. vm.confidence, overview.x + 10, overview.y + 52, theme.color("muted"))
  components.label("Garage mode is stationary-only. No strategy, setup, or live state is edited here.", overview.x + overview.width * 0.48, overview.y + 33, theme.color("muted"))

  local scenarios_box = boxes.cards.scenarios
  components.card(scenarios_box, "MOCK SCENARIOS", "flag", "selected")
  local ids = namespace.mock_scenarios.list()
  local columns = 3
  local button_width = (scenarios_box.width - 30) / columns
  local button_height = 22
  for index = 1, #ids do
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    local x = scenarios_box.x + 10 + column * (button_width + 5)
    local y = scenarios_box.y + 32 + row * (button_height + 4)
    local selected = ids[index] == state.scenario_id
    if selected then
      csp.rect(x, y, button_width, button_height, theme.color("surface_alt"), 4)
      csp.outline(x, y, button_width, button_height, theme.color("cyan"), 4, 1)
    end
    if components.button(ids[index], x, y, button_width, selected and "selected" or "info") then
      namespace.app_state.set_scenario(ids[index])
    end
  end

  local settings = boxes.cards.settings
  components.card(settings, "PRESENTATION", "setup", "info")
  components.label("MODE", settings.x + 10, settings.y + 34, theme.color("muted"))
  components.value("GARAGE / DIAGNOSTICS", settings.x + 10, settings.y + 50, theme.color("text"))
  if components.button(state.settings.sound_enabled and "SOUND ON" or "SOUND OFF", settings.x + 10, settings.y + 78, settings.width - 20, state.settings.sound_enabled and "good" or "stale") then
    state.settings.sound_enabled = not state.settings.sound_enabled
    namespace.app_state.save_settings()
  end
  if components.button("TEST CRITICAL SOUND", settings.x + 10, settings.y + 108, settings.width - 20, "critical") then
    namespace.app_state.test_sound("critical")
  end
  if components.button("TEST ACK SOUND", settings.x + 10, settings.y + 138, settings.width - 20, "info") then
    namespace.app_state.test_sound("ack")
  end

  local diagnostics = boxes.cards.diagnostics
  components.card(diagnostics, "CONTRACT / SOURCE DIAGNOSTICS", "telemetry", "info")
  components.status_line("SNAPSHOT", vm.available and "VALID" or "MALFORMED", diagnostics.x + 10, diagnostics.y + 34, diagnostics.width * 0.22, vm.available and "good" or "critical")
  components.status_line("WEATHER", vm.weather.label, diagnostics.x + diagnostics.width * 0.25, diagnostics.y + 34, diagnostics.width * 0.22, vm.weather.label == "UNKNOWN" and "warning" or "info")
  components.status_line("AUDIO", namespace.adapters.audio.status(), diagnostics.x + diagnostics.width * 0.50, diagnostics.y + 34, diagnostics.width * 0.22, namespace.adapters.audio.available and "good" or "warning")
  components.status_line("SOURCE", vm.connections.source, diagnostics.x + diagnostics.width * 0.75, diagnostics.y + 34, diagnostics.width * 0.20, "muted")
  components.label("No networking, live telemetry, strategy calculation, weather calculation, or setup application is present in F1.", diagnostics.x + 10, diagnostics.y + 58, theme.color("muted"))
end

namespace.ui.garage = garage
