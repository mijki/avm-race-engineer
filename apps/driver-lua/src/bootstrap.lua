local namespace = rawget(_G, "AVM_PITWALL_F1")
if type(namespace) ~= "table" then
  namespace = {}
  rawset(_G, "AVM_PITWALL_F1", namespace)
end

namespace.version = "1.0.0-f1"
namespace.modules = namespace.modules or {}
namespace.live = namespace.live or {}
namespace.adapters = namespace.adapters or {}
namespace.ui = namespace.ui or {}
namespace.runtime = namespace.runtime or {}
namespace.runtime.initialized = true

local runtime = namespace.runtime
local lifecycle = runtime.lifecycle or {}
runtime.lifecycle = lifecycle

local function callable(value)
  local value_type = type(value)
  if value_type == "function" or value_type == "userdata" then
    return true
  end
  if value_type == "table" then
    local ok, metatable = pcall(getmetatable, value)
    return ok and metatable ~= nil and metatable.__call ~= nil
  end
  return false
end

local function bounded(value)
  local text = tostring(value or "unknown")
  text = string.gsub(text, "[%c]", " ")
  if #text > 120 then
    return string.sub(text, 1, 117) .. "..."
  end
  return text
end

function runtime.log(message)
  local ac_api = rawget(_G, "ac")
  local text = "AVM PitWall F1: " .. bounded(message)
  if type(ac_api) == "table" and type(ac_api.log) == "function" then
    pcall(ac_api.log, text)
  elseif type(ac_api) == "table" and type(ac_api.console) == "function" then
    pcall(ac_api.console, text, false)
  end
end

function runtime.log_once(key, message)
  if lifecycle[key] then
    return
  end
  lifecycle[key] = true
  runtime.log(message)
end

local function new_render_evidence()
  return {
    mode = "unknown",
    native = 0,
    mode_text = 0,
    enhanced = 0,
    degraded = 0,
    skipped = 0,
    first_skip = nil,
    phase = "native",
  }
end

function runtime.record_draw(kind)
  local evidence = runtime.render_evidence or new_render_evidence()
  runtime.render_evidence = evidence
  if kind == "native" then
    evidence.native = evidence.native + 1
  elseif kind == "mode_text" then
    evidence.mode_text = evidence.mode_text + 1
  elseif kind == "enhanced" then
    evidence.enhanced = evidence.enhanced + 1
  elseif kind == "degraded" then
    evidence.degraded = evidence.degraded + 1
  end
end

function runtime.record_skip(reason)
  local evidence = runtime.render_evidence or new_render_evidence()
  runtime.render_evidence = evidence
  evidence.skipped = evidence.skipped + 1
  if evidence.first_skip == nil then
    local detail = tostring(reason or "unspecified")
    detail = string.gsub(detail, "[%c]", " ")
    evidence.first_skip = #detail > 96 and string.sub(detail, 1, 93) .. "..." or detail
  end
end

function runtime.set_render_phase(phase)
  local evidence = runtime.render_evidence or new_render_evidence()
  runtime.render_evidence = evidence
  evidence.phase = phase or "none"
end

function runtime.set_render_mode(mode)
  local evidence = runtime.render_evidence or new_render_evidence()
  runtime.render_evidence = evidence
  evidence.mode = tostring(mode or "unknown")
end

function runtime.mode_draw_count()
  local evidence = runtime.render_evidence or new_render_evidence()
  return evidence.mode_text + evidence.enhanced + evidence.degraded
end

function runtime.log_render_evidence_once()
  local evidence = runtime.render_evidence or new_render_evidence()
  local first_skip = evidence.first_skip or "none"
  runtime.log_once("render_evidence_logged", "AVM F1 render evidence: mode=" .. tostring(evidence.mode)
    .. " native=" .. tostring(evidence.native)
    .. " mode_text=" .. tostring(evidence.mode_text)
    .. " enhanced=" .. tostring(evidence.enhanced)
    .. " degraded=" .. tostring(evidence.degraded)
    .. " skipped=" .. tostring(evidence.skipped)
    .. " first_skip=" .. first_skip)
end

local function direct_text(value)
  local api = rawget(_G, "ui")
  local api_type = type(api)
  if api_type ~= "table" and api_type ~= "userdata" then
    return false
  end
  local ok, callback = pcall(function()
    return api.text
  end)
  if not ok or not callable(callback) then
    return false
  end
  ok = pcall(callback, bounded(value))
  if ok then
    runtime.record_draw("native")
  end
  return ok
end

local function direct_separator()
  local api = rawget(_G, "ui")
  local api_type = type(api)
  if api_type == "table" or api_type == "userdata" then
    local ok, callback = pcall(function()
      return api.separator
    end)
    if ok and callable(callback) then
      local separator_ok = pcall(callback)
      if separator_ok then
        runtime.record_draw("native")
      else
        runtime.record_skip("ui.separator: protected call failed")
        direct_text("--------------------")
      end
    else
      direct_text("--------------------")
    end
  else
    direct_text("--------------------")
  end
end

function runtime.begin_frame()
  lifecycle.entry_shell_drawn = false
  lifecycle.recovery_drawn = false
  runtime.render_evidence = new_render_evidence()
  runtime.body_owner = nil
  runtime.set_render_phase("native")
end

function runtime.draw_entry_shell()
  if lifecycle.entry_shell_drawn then
    return false
  end
  lifecycle.entry_shell_drawn = true
  local drew_title = direct_text("AVM PitWall")
  local drew_status = false
  local drew_detail = false
  if not lifecycle.mode_content_ready and not lifecycle.initialization_attempted then
    direct_separator()
    drew_status = direct_text("F1 runtime active")
    drew_detail = direct_text("Initialising driver display...")
  end
  return drew_title or drew_status or drew_detail
end

function runtime.draw_recovery(stage, detail)
  runtime.draw_entry_shell()
  direct_text("Render recovery")
  direct_text("Stage: " .. bounded(stage or "unknown"))
  direct_text(bounded(detail or "Safe shell retained"))
  runtime.log_once("recovery_logged_" .. tostring(stage), "recovery stage=" .. tostring(stage) .. " detail=" .. bounded(detail))
end

local function callback_entry(dt)
  runtime.begin_frame()
  runtime.log_once("first_callback_logged", "first windowMain entry")
  local drew_shell = runtime.draw_entry_shell()
  if drew_shell then
    runtime.log_once("early_shell_logged", "early native shell drawn")
  end
  local app_entry = runtime.app_entry
  if type(app_entry) ~= "function" then
    runtime.log_once("app_entry_missing_logged", "app entry unavailable after bundle initialization")
    return
  end
  local ok, error_value = pcall(app_entry, dt)
  if not ok then
    runtime.draw_recovery("runtime-entry", error_value)
  end
end

local script_table = rawget(_G, "script")
if type(script_table) ~= "table" then
  script_table = {}
  rawset(_G, "script", script_table)
end

runtime.log_once("bundle_top_level_start_logged", "bundle top-level start")

-- Register both CSP callback shapes before any later module can initialize.
-- The wrappers share one entry so a top-level failure still leaves a visible
-- direct-native recovery surface.
function script.windowMain(dt)
  return callback_entry(dt)
end

function windowMain(dt)
  return callback_entry(dt)
end

runtime.callback_export = "script.windowMain + windowMain"
runtime.callback_registered = true
runtime.log_once("callback_registration_logged", "callback registration complete")
