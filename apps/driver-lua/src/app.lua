local namespace = _G.AVM_PITWALL_F1
local native = namespace.runtime.native
local csp = namespace.adapters.csp
local layout = namespace.ui.layout
local compact = namespace.ui.compact
local expanded = namespace.ui.expanded
local garage = namespace.ui.garage
local fallback = namespace.ui.fallback
local theme = namespace.ui.theme
local app = {}
local lifecycle = namespace.runtime.lifecycle or {}

namespace.runtime.lifecycle = lifecycle
namespace.runtime.callback_export = "script.windowMain"

local function bounded(value)
  local text = tostring(value or "unknown")
  text = string.gsub(text, "[%c]", " ")
  if #text > 120 then
    text = string.sub(text, 1, 117) .. "..."
  end
  return text
end

local function log_once(key, message)
  if lifecycle[key] then
    return
  end
  lifecycle[key] = true
  csp.log(message)
end

local function recover(stage, detail)
  lifecycle.recovery_stage = stage
  lifecycle.recovery_detail = bounded(detail)
  local ok = pcall(fallback.render, stage, lifecycle.recovery_detail)
  if not ok then
    native.emergency("Render recovery")
  end
  log_once("recovery_logged_" .. tostring(stage), "recovery stage=" .. tostring(stage) .. " detail=" .. lifecycle.recovery_detail)
end

local function run_stage(name, callback)
  lifecycle.stage = name
  if namespace.runtime.test_fail_stage == name then
    local detail = "forced failure for host validation"
    csp.log("stage=" .. name .. " detail=" .. detail)
    return false, detail
  end
  local ok, result = pcall(callback)
  if not ok then
    local detail = bounded(result)
    csp.log("stage=" .. name .. " detail=" .. detail)
    return false, detail
  end
  return true, result
end

local function draw_header(vm, boxes)
  local header = boxes.header
  csp.rect(header.x, header.y, header.width, header.height, theme.color("surface"), 7)
  csp.outline(header.x, header.y, header.width, header.height, theme.color("border"), 7, 1)
  csp.text_at("AVM", header.x + 12, header.y + 7, theme.color("text"))
  csp.text_at("PitWall", header.x + 50, header.y + 7, theme.color("cyan"))
  csp.text_at(vm.session_name, header.x + 126, header.y + 9, theme.color("text"))
  csp.text_at("STINT  " .. vm.stint .. " / " .. vm.total_stints, header.x + header.width * 0.58, header.y + 9, theme.color("green"))
  csp.text_at("LAP  " .. vm.lap .. " / " .. vm.planned_lap, header.x + header.width * 0.76, header.y + 9, theme.color("text"))
  namespace.ui.components.progress(header.x + 12, header.y + header.height - 10, header.width - 24, vm.progress, "green")
end

local function draw_banner(vm, boxes, state)
  local banner = boxes.banner
  local critical = vm.alert.priority == "critical"
  local tone = critical and "critical" or vm.alert.priority == "high" and "warning" or "info"
  csp.rect(banner.x, banner.y, banner.width, banner.height, theme.color(critical and "red" or "surface_alt", critical and 0.16 or 1), 7)
  csp.outline(banner.x, banner.y, banner.width, banner.height, theme.tone(tone), critical and 2 or 1, 1)
  namespace.ui.icons.draw(critical and "critical" or "flag", banner.x + 10, banner.y + 10, 24, theme.tone(tone))
  csp.text_at(vm.alert.text, banner.x + 44, banner.y + 8, theme.tone(tone))
  csp.text_aligned(vm.alert.detail, banner.x + 44, banner.y + 29, banner.width - 150, theme.color("text"))
  if vm.alert.requires_acknowledgement or vm.alert.status == "ACKNOWLEDGED" then
    local ack_label = vm.alert.status == "ACKNOWLEDGED" and "ACKED" or "ACK"
    if namespace.ui.components.button(ack_label, banner.x + banner.width - 92, banner.y + 12, 78, vm.alert.status == "ACKNOWLEDGED" and "good" or "critical") and vm.alert.status ~= "ACKNOWLEDGED" then
      namespace.app_state.acknowledge()
    end
  elseif banner.height >= 46 then
    if namespace.ui.components.button("REPEAT", banner.x + banner.width - 92, banner.y + 12, 78, "info") then
      namespace.app_state.repeat_latest()
    end
  end
end

local function draw_footer(vm, boxes)
  local footer = boxes.footer
  csp.rect(footer.x, footer.y, footer.width, footer.height, theme.color("black"), 5)
  namespace.ui.icons.draw(vm.connection_tone == "live" and "engineer" or "offline", footer.x + 8, footer.y + 5, 14, theme.tone(vm.connection_tone))
  csp.text_at("Engineer: " .. vm.connections.engineer, footer.x + 28, footer.y + 7, theme.color("muted"))
  namespace.ui.icons.draw(vm.connection_tone == "live" and "bridge" or "stale", footer.x + footer.width * 0.37, footer.y + 5, 14, theme.tone(vm.connection_tone))
  csp.text_at("Bridge: " .. vm.connections.bridge, footer.x + footer.width * 0.37 + 20, footer.y + 7, theme.color("muted"))
  csp.text_at("Telemetry: " .. vm.connections.telemetry, footer.x + footer.width * 0.70, footer.y + 7, theme.tone(vm.connection_tone))
end

function app.windowMain(dt)
  log_once("bundle_logged", "bundle version=" .. namespace.version .. " entry=AVM_PitWall_F1.lua callback=script.windowMain")
  log_once("initialization_logged", "F1 initialization started")
  lifecycle.callback_count = (lifecycle.callback_count or 0) + 1

  local canary_drawn = native.draw_canary()
  if canary_drawn then
    log_once("first_callback_logged", "first callback entered")
    log_once("first_shell_logged", "first visible shell rendered")
  else
    native.emergency("F1 runtime active")
  end

  local capability_ok, capability_error = run_stage("runtime-capability-check", function()
    local capabilities = csp.capabilities()
    assert(capabilities.required, "required CSP drawing API unavailable")
    assert(capabilities.backend == "csp-native", "unexpected runtime adapter")
    return capabilities
  end)
  if not capability_ok then
    recover("runtime-capability-check", capability_error)
    return
  end

  local state
  local state_ok, state_error = run_stage("application-state", function()
    state = assert(namespace.app_state.ensure(), "application state unavailable")
    assert(state.mode == "compact" or state.mode == "expanded" or state.mode == "garage", "invalid default mode")
  end)
  if not state_ok then
    recover("application-state", state_error)
    return
  end
  log_once("scenario_logged", "default scenario selected=" .. tostring(state.scenario_id))
  log_once("mode_logged", "default mode selected=" .. tostring(state.mode))

  local snapshot_ok, snapshot_error = run_stage("mock-snapshot", function()
    assert(type(state.envelope) == "table", "deterministic fixture unavailable")
  end)
  if not snapshot_ok then
    recover("mock-snapshot", snapshot_error)
    return
  end

  local vm
  local view_model_ok, view_model_error = run_stage("view-model", function()
    vm = assert(namespace.app_state.get_view_model(state.mode), "view-model unavailable")
    assert(type(vm.alert) == "table", "view-model alert unavailable")
  end)
  if not view_model_ok then
    recover("view-model", view_model_error)
    return
  end

  local width, height, boxes
  local selection_ok, selection_error = run_stage("selected-mode", function()
    width, height = csp.window_size()
    boxes = layout.for_mode(width, height, state.mode, vm.alert.priority == "critical")
    assert(layout.intersects(boxes.header, width, height), "header layout is not visible")
    assert(layout.intersects(boxes.footer, width, height), "footer layout is not visible")
    for name, required_box in pairs(layout.required_boxes(width, height, state.mode, vm.alert.priority == "critical")) do
      assert(layout.intersects(required_box, width, height), name .. " layout is not visible")
    end
  end)
  if not selection_ok then
    recover("selected-mode", selection_error)
    return
  end

  local shell_ok, shell_error = run_stage("base-shell", function()
    csp.rect(0, 0, width, height, theme.color("background"), 0)
    draw_header(vm, boxes)
  end)
  if not shell_ok then
    recover("base-shell", shell_error)
    return
  end

  local mode_name = state.mode
  local mode_ok, mode_error = run_stage("mode-render-" .. mode_name, function()
    if mode_name == "expanded" then
      expanded.render(vm, boxes)
    elseif mode_name == "garage" then
      garage.render(vm, boxes, state)
    else
      compact.render(vm, boxes)
    end
  end)
  if not mode_ok then
    recover("mode-render-" .. mode_name, mode_error)
    return
  end

  local alert_ok, alert_error = run_stage("alert-overlay", function()
    draw_banner(vm, boxes, state)
  end)
  if not alert_ok then
    recover("alert-overlay", alert_error)
    return
  end

  local footer_ok, footer_error = run_stage("connection-footer", function()
    draw_footer(vm, boxes)
  end)
  if not footer_ok then
    recover("connection-footer", footer_error)
    return
  end

  local audio_ok, audio_error = run_stage("audio-side-effects", function()
    namespace.app_state.update(dt)
  end)
  if not audio_ok then
    csp.log("audio-side-effects degraded detail=" .. bounded(audio_error))
  end
  log_once("full_mode_logged", "full mode rendered")
end

function app.reset_for_test()
  namespace.app_state.initialized = false
  namespace.app_state.dirty = true
  for key in pairs(lifecycle) do
    lifecycle[key] = nil
  end
end

namespace.app = app
if type(rawget(_G, "script")) ~= "table" then
  rawset(_G, "script", {})
end
function script.windowMain(dt)
  return namespace.app.windowMain(dt)
end
