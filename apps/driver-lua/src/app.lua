local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local layout = namespace.ui.layout
local compact = namespace.ui.compact
local expanded = namespace.ui.expanded
local garage = namespace.ui.garage
local fallback = namespace.ui.fallback
local app = {}
local runtime = namespace.runtime
local lifecycle = runtime.lifecycle or {}

namespace.runtime.lifecycle = lifecycle

local function bounded(value)
  local text = tostring(value or "unknown")
  text = string.gsub(text, "[%c]", " ")
  if #text > 120 then
    text = string.sub(text, 1, 117) .. "..."
  end
  return text
end

local function log_once(key, message)
  runtime.log_once(key, message)
end

local function join_names(values)
  if type(values) ~= "table" or #values == 0 then
    return "none"
  end
  local result = {}
  for index = 1, math.min(#values, 8) do
    result[#result + 1] = values[index]
  end
  if #values > 8 then
    result[#result + 1] = "..."
  end
  return table.concat(result, ",")
end

local function log_capabilities(capabilities)
  log_once("capabilities_logged", "AVM F1 capabilities: level=" .. tostring(capabilities.level)
    .. " enhanced=" .. tostring(capabilities.enhanced)
    .. " candidate=" .. tostring(capabilities.enhanced_candidate)
    .. " simplified=" .. tostring(not capabilities.enhanced)
    .. " missing_mandatory=" .. join_names(capabilities.missing_mandatory)
    .. " missing_optional=" .. join_names(capabilities.missing_optional)
    .. " incompatible_optional=" .. join_names(capabilities.incompatible_optional))
end

local function recover(stage, detail)
  lifecycle.initialization_attempted = true
  lifecycle.recovery_stage = stage
  lifecycle.recovery_detail = bounded(detail)
  local ok = pcall(runtime.draw_recovery, stage, lifecycle.recovery_detail)
  if not ok then
    pcall(fallback.render, stage, lifecycle.recovery_detail)
  end
end

local function box_summary(box)
  if type(box) ~= "table" then
    return "invalid"
  end
  return string.format("%.0f,%.0f %.0fx%.0f", box.x or 0, box.y or 0, box.width or 0, box.height or 0)
end

local function log_layout(width, height, scale, boxes, source, strategy)
  local first_card = boxes.cards.fuel or boxes.cards.timing or boxes.cards.overview
  local weather = boxes.cards.weather or boxes.cards.diagnostics
  local message = boxes.cards.message or boxes.banner
  log_once("layout_geometry_logged", "AVM F1 layout: content_width=" .. tostring(width)
    .. " content_height=" .. tostring(height)
    .. " ui_scale=" .. tostring(scale)
    .. " source=" .. tostring(source)
    .. " strategy=" .. tostring(strategy)
    .. " header=" .. box_summary(boxes.header)
    .. " first_card=" .. box_summary(first_card)
    .. " weather=" .. box_summary(weather)
    .. " message=" .. box_summary(message))
end

local function render_enhanced_mode(vm, boxes, state)
  if runtime.layout_strategy == "flow" then
    runtime.record_skip("enhanced renderer: flow layout selected")
    return false, "flow layout selected"
  end
  if runtime.capabilities == nil or not runtime.capabilities.enhanced_candidate then
    runtime.record_skip("enhanced renderer: no callable enhanced API")
    return false, "no callable enhanced API"
  end
  local before = runtime.render_evidence and runtime.render_evidence.enhanced or 0
  runtime.set_render_phase("enhanced")
  local ok, error_value = pcall(function()
    if state.mode == "expanded" then
      expanded.render(vm, boxes)
    elseif state.mode == "garage" then
      garage.render(vm, boxes, state)
    else
      compact.render(vm, boxes)
    end
  end)
  local after = runtime.render_evidence and runtime.render_evidence.enhanced or 0
  if not ok then
    runtime.record_skip("enhanced renderer failed: " .. bounded(error_value))
    return false, bounded(error_value)
  end
  if after <= before then
    runtime.record_skip("enhanced renderer emitted zero operations")
    return false, "zero enhanced operations"
  end
  runtime.capabilities.enhanced = true
  return true, nil
end

local function render_text_first(vm, state)
  runtime.set_render_phase("mode_text")
  if state.mode == "expanded" then
    expanded.render_text_first(vm)
  elseif state.mode == "garage" then
    garage.render_text_first(vm, state)
  elseif not runtime.capabilities.enhanced then
    compact.render_simplified(vm, state.mode)
  else
    compact.render_text_first(vm, state.mode, false)
  end
  runtime.set_render_phase("none")
end

local function run_stage(name, callback)
  lifecycle.stage = name
  if namespace.runtime.test_fail_stage == name then
    local detail = "forced failure for host validation"
    runtime.log_once("stage_failure_" .. name, "stage=" .. name .. " detail=" .. detail)
    return false, detail
  end
  local ok, result = pcall(callback)
  if not ok then
    local detail = bounded(result)
    runtime.log_once("stage_failure_" .. name, "stage=" .. name .. " detail=" .. detail)
    return false, detail
  end
  return true, result
end

function app.windowMain(dt)
  log_once("bundle_logged", "bundle version=" .. namespace.version .. " entry=AVM_PitWall_F1.lua")
  log_once("initialization_logged", "F1 initialization started")
  lifecycle.callback_count = (lifecycle.callback_count or 0) + 1

  local namespace_ok, namespace_error = run_stage("namespace-ready", function()
    assert(type(namespace.adapters) == "table", "adapter namespace unavailable")
    assert(type(namespace.ui) == "table", "UI namespace unavailable")
    assert(type(namespace.app_state) == "table", "application state unavailable")
  end)
  if not namespace_ok then
    recover("namespace-ready", namespace_error)
    return
  end
  log_once("namespace_ready_logged", "namespace ready")

  local capability_ok, capability_error = run_stage("capabilities", function()
    local capabilities = csp.capabilities()
    runtime.capabilities = capabilities
    if not capabilities.required then
      error("Missing mandatory API: " .. join_names(capabilities.missing_mandatory))
    end
    assert(capabilities.backend == "csp-native", "unexpected runtime adapter")
    return capabilities
  end)
  if not capability_ok then
    local detail = capability_error
    if runtime.capabilities ~= nil and not runtime.capabilities.required then
      detail = "Missing mandatory API: " .. join_names(runtime.capabilities.missing_mandatory)
    end
    recover("capabilities", detail)
    return
  end

  local settings
  local storage_ok, storage_error = run_stage("storage", function()
    settings = assert(namespace.adapters.storage.load(), "presentation storage unavailable")
  end)
  if not storage_ok then
    recover("storage", storage_error)
    return
  end

  local state
  local state_ok, state_error = run_stage("app-state", function()
    state = assert(namespace.app_state.ensure(settings), "application state unavailable")
    assert(state.mode == "compact" or state.mode == "expanded" or state.mode == "garage", "invalid default mode")
  end)
  if not state_ok then
    recover("app-state", state_error)
    return
  end
  log_once("app_state_ready_logged", "app state ready")
  log_once("scenario_logged", "default scenario selected=" .. tostring(state.scenario_id))
  log_once("mode_logged", "default mode selected=" .. tostring(state.mode))

  local live_ok, live_error = run_stage("live-telemetry", function()
    local status = namespace.app_state.update(dt)
    assert(type(status) == "table", "live telemetry status unavailable")
  end)
  if not live_ok then
    recover("live-telemetry", live_error)
    return
  end

  local snapshot_ok, snapshot_error = run_stage("default-fixture", function()
    assert(type(state.envelope) == "table", "deterministic fixture unavailable")
  end)
  if not snapshot_ok then
    recover("default-fixture", snapshot_error)
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
  log_once("view_model_ready_logged", "view model ready")

  local width, height, boxes
  local layout_ok, layout_error = run_stage("layout", function()
    local source
    width, height, source = csp.window_size()
    local scale = csp.ui_scale()
    boxes = layout.for_mode(width, height, state.mode, vm.alert.priority == "critical")
    local valid = layout.valid(boxes, width, height, state.mode, vm.alert.priority == "critical")
    runtime.layout_strategy = source == "fallback" or not valid and "flow" or "cards"
    if not valid then
      runtime.record_skip("layout: invalid or off-screen bounds")
    end
    log_layout(width, height, scale, boxes, source, runtime.layout_strategy)
  end)
  if not layout_ok then
    recover("layout", layout_error)
    return
  end
  log_once("layout_ready_logged", "layout ready")

  local selected_mode_ok, selected_mode_error = run_stage("selected-mode", function()
    runtime.set_render_mode(state.mode)
    local enhanced_ok, enhanced_error = render_enhanced_mode(vm, boxes, state)
    if not enhanced_ok then
      runtime.set_render_phase("mode_text")
      render_text_first(vm, state)
      runtime.log_once("enhanced_fallback_logged", "enhanced renderer unavailable: " .. tostring(enhanced_error or "unknown reason") .. "; text-first mode retained")
    else
      runtime.set_render_phase("none")
    end
    runtime.capabilities.enhanced = enhanced_ok
    log_capabilities(runtime.capabilities)
    if runtime.mode_draw_count() <= 0 then
      error("mode renderer emitted no visible operations")
    end
    lifecycle.mode_content_ready = true
    runtime.log_render_evidence_once()
  end)
  if not selected_mode_ok then
    recover("selected-mode", selected_mode_error)
    return
  end
  log_once("selected_mode_logged", "selected mode rendered")

  local alert_ok, alert_error = run_stage("alerts", function()
    -- Text-first mode owns the visible engineer message.
    if not lifecycle.mode_content_ready then
      runtime.record_skip("alerts: mode text not ready")
    end
  end)
  if not alert_ok then
    recover("alerts", alert_error)
    return
  end

  local footer_ok, footer_error = run_stage("footer", function()
    -- Text-first mode owns the visible connection state as well.
    if not lifecycle.mode_content_ready then
      runtime.record_skip("footer: mode text not ready")
    end
  end)
  if not footer_ok then
    recover("footer", footer_error)
    return
  end

  local audio_ok, audio_error = run_stage("audio", function()
    namespace.app_state.update(dt)
  end)
  if not audio_ok then
    runtime.log_once("audio_degraded_logged", "audio degraded detail=" .. bounded(audio_error))
  end
  if runtime.mode_draw_count() > 0 then
    log_once("full_mode_logged", "full mode rendered")
  else
    recover("selected-mode", "no visible mode-specific draw operation")
  end
end

function app.reset_for_test()
  namespace.app_state.reset_for_test()
  for key in pairs(lifecycle) do
    lifecycle[key] = nil
  end
end

namespace.app = app
runtime.app_entry = app.windowMain
  runtime.log_once("app_entry_registered_logged", "application entry registered")
