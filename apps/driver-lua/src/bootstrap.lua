local namespace = rawget(_G, "AVM_PITWALL_F1")
if type(namespace) ~= "table" then
  namespace = {}
  rawset(_G, "AVM_PITWALL_F1", namespace)
end

namespace.version = "1.0.0-f1"
namespace.modules = namespace.modules or {}
namespace.adapters = namespace.adapters or {}
namespace.ui = namespace.ui or {}
namespace.runtime = namespace.runtime or {}
namespace.runtime.initialized = true

local runtime = namespace.runtime
local lifecycle = runtime.lifecycle or {}
runtime.lifecycle = lifecycle

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

local function direct_text(value)
  local api = rawget(_G, "ui")
  if type(api) ~= "table" or type(api.text) ~= "function" then
    return false
  end
  local ok = pcall(api.text, bounded(value))
  return ok
end

local function direct_separator()
  local api = rawget(_G, "ui")
  if type(api) == "table" and type(api.separator) == "function" then
    pcall(api.separator)
  end
end

function runtime.draw_entry_shell()
  local drew_title = direct_text("AVM PitWall")
  direct_separator()
  local drew_status = direct_text("F1 runtime active")
  local drew_detail = direct_text("Initialising driver display...")
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
