local namespace = _G.AVM_PITWALL_F1
local csp = {}
local unpack_values = table.unpack or unpack

local function callable(value)
  local value_type = type(value)
  -- CSP exposes some callable members as LuaJIT cdata (for example
  -- ui.windowSize and ui.availableSpace). Keep the adapter permissive at this
  -- boundary; protected calls below still decide whether a member actually
  -- works in the active runtime.
  if value_type == "function" or value_type == "userdata" or value_type == "cdata" then
    return true
  end
  if value_type == "table" then
    local ok, metatable = pcall(getmetatable, value)
    return ok and metatable ~= nil and metatable.__call ~= nil
  end
  return false
end

local function ui_api()
  local candidate = rawget(_G, "ui")
  local candidate_type = type(candidate)
  if candidate_type == "table" or candidate_type == "userdata" or candidate_type == "cdata" then
    return candidate
  end
  return nil
end

local function member(api, name)
  if api == nil then
    return nil
  end
  local ok, value = pcall(function()
    return api[name]
  end)
  if ok then
    return value
  end
  return nil
end

local function member_type(name)
  local value = member(ui_api(), name)
  if value == nil then
    return "missing"
  end
  return type(value)
end

local function call_ui(name, ...)
  local callback = member(ui_api(), name)
  if callback == nil then
    return "unavailable", nil, "missing member"
  end
  if not callable(callback) then
    return "failed", nil, "member type=" .. type(callback)
  end
  local ok, result = pcall(callback, ...)
  if ok then
    return "drawn", result, nil
  end
  return "failed", nil, tostring(result)
end

local function valid_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function vector_field(vector, field)
  local ok, value = pcall(function()
    return vector[field]
  end)
  return ok and value or nil
end

local function valid_vector(vector)
  if vector == nil then
    return false
  end
  local x = vector_field(vector, "x")
  local y = vector_field(vector, "y")
  return valid_number(x) and valid_number(y)
end

local function construct(name, ...)
  local constructor = rawget(_G, name)
  if constructor == nil then
    return nil
  end
  local ok, result = pcall(constructor, ...)
  if ok and result ~= nil then
    return result
  end
  return nil
end

local function point(x, y)
  local result = construct("vec2", x, y)
  if valid_vector(result) then
    return result
  end
  return nil
end

local function valid_color(value)
  if value == nil then
    return false
  end
  if type(value) ~= "table" then
    return true
  end
  local alpha = value.a
  return valid_number(value.r) and valid_number(value.g) and valid_number(value.b) and valid_number(alpha) and alpha > 0
end

local function record_status(status, name, kind, reason)
  if status == "drawn" then
    namespace.runtime.record_draw(kind or "enhanced")
  else
    namespace.runtime.record_skip(name .. ": " .. tostring(reason or status))
  end
  return status
end

-- The helper above must invoke a draw member once. Keep the status and reason
-- together so a successful protected call is evidence of an emitted call, not
-- an unconditional success returned by the adapter.
local function invoke_draw(name, kind, arguments, reason)
  if reason ~= nil then
    namespace.runtime.record_skip(name .. ": " .. reason)
    return "failed"
  end
  local status, _, detail = call_ui(name, unpack_values(arguments))
  return record_status(status, name, kind, detail)
end

function csp.color(red, green, blue, alpha)
  local safe_alpha = valid_number(alpha) and alpha > 0 and alpha or 1
  local result = construct("rgbm", red, green, blue, safe_alpha)
  if result ~= nil then
    return result
  end
  return { r = red, g = green, b = blue, a = safe_alpha }
end

function csp.point(x, y)
  return point(x, y)
end

local function valid_size(result)
  return result ~= nil
    and valid_number(vector_field(result, "x"))
    and valid_number(vector_field(result, "y"))
    and vector_field(result, "x") > 0
    and vector_field(result, "y") > 0
end

local function size_from(result)
  if valid_size(result) then
    return vector_field(result, "x"), vector_field(result, "y")
  end
  return nil, nil
end

local function read_ui_member(name)
  local candidate = member(ui_api(), name)
  if candidate == nil then
    return "unavailable", nil, "missing member"
  end
  if callable(candidate) then
    return call_ui(name)
  end
  return "value", candidate, nil
end

function csp.window_size()
  local status, result = read_ui_member("availableSpace")
  local width, height = size_from(result)
  if (status == "drawn" or status == "value") and width ~= nil then
    return width, height, "availableSpace"
  end

  status, result = read_ui_member("availableSpaceX")
  local available_width = valid_number(result) and result or nil
  status, result = read_ui_member("availableSpaceY")
  local available_height = valid_number(result) and result or nil
  if available_width ~= nil and available_height ~= nil and available_width > 0 and available_height > 0 then
    return available_width, available_height, "availableSpaceX/Y"
  end

  status, result = read_ui_member("windowSize")
  width, height = size_from(result)
  if (status == "drawn" or status == "value") and width ~= nil then
    return width, height, "windowSize"
  end

  status, result = read_ui_member("windowWidth")
  local window_width = valid_number(result) and result or nil
  status, result = read_ui_member("windowHeight")
  local window_height = valid_number(result) and result or nil
  if window_width ~= nil and window_height ~= nil and window_width > 0 and window_height > 0 then
    return window_width, window_height, "windowWidth/Height"
  end
  return 780, 380, "fallback"
end

-- Enhanced draw calls use the active CSP working area. Expose the native
-- origin for Garage diagnostics and future screen-space adapters without
-- making UI modules depend on CSP coordinates.
function csp.content_origin()
  local status, result = read_ui_member("cursorStartPos")
  if (status == "drawn" or status == "value") and valid_vector(result) then
    return vector_field(result, "x"), vector_field(result, "y"), "cursorStartPos"
  end
  status, result = read_ui_member("windowPos")
  if (status == "drawn" or status == "value") and valid_vector(result) then
    return vector_field(result, "x"), vector_field(result, "y"), "windowPos"
  end
  return 0, 0, "window-local"
end

function csp.ui_scale()
  local status, result = read_ui_member("uiScale")
  if (status == "drawn" or status == "value") and valid_number(result) and result > 0 then
    return result
  end
  return 1
end

function csp.has(name)
  return callable(member(ui_api(), name))
end

function csp.member_type(name)
  return member_type(name)
end

function csp.capabilities()
  local mandatory_names = { "ui.text" }
  local optional_names = {
    "ui.separator",
    "ui.textColored",
    "ui.windowSize",
    "ui.windowWidth",
    "ui.windowHeight",
    "ui.availableSpace",
    "ui.availableSpaceX",
    "ui.availableSpaceY",
    "ui.windowContentSize",
    "ui.windowPos",
    "ui.cursorStartPos",
    "ui.drawText",
    "ui.drawTextClipped",
    "ui.drawRectFilled",
    "ui.drawRect",
    "ui.drawLine",
    "ui.drawCircle",
    "ui.drawCircleFilled",
    "ui.drawTriangleFilled",
    "ui.button",
    "ui.checkbox",
    "ui.setCursorScreenPos",
    "ui.invisibleButton",
    "ui.inputText",
    "ui.slider",
  }
  local missing_mandatory = {}
  for index = 1, #mandatory_names do
    local name = mandatory_names[index]
    if not csp.has(string.sub(name, 4)) then
      missing_mandatory[#missing_mandatory + 1] = name
    end
  end
  local missing_optional = {}
  local incompatible_optional = {}
  for index = 1, #optional_names do
    local name = optional_names[index]
    local member_name = string.sub(name, 4)
    if member(ui_api(), member_name) == nil then
      missing_optional[#missing_optional + 1] = name
    elseif not csp.has(member_name) then
      incompatible_optional[#incompatible_optional + 1] = name
    end
  end
  local enhanced_names = {
    "ui.drawText",
    "ui.drawRectFilled",
    "ui.drawRect",
    "ui.drawLine",
    "ui.drawCircle",
    "ui.drawCircleFilled",
    "ui.drawTriangleFilled",
  }
  local enhanced_candidate = true
  for index = 1, #enhanced_names do
    if not csp.has(string.sub(enhanced_names[index], 4)) then
      enhanced_candidate = false
    end
  end
  enhanced_candidate = enhanced_candidate and point(0, 0) ~= nil and construct("rgbm", 1, 1, 1, 1) ~= nil
  local type_names = { "text", "separator", "availableSpace", "windowSize", "drawText", "drawRectFilled" }
  local type_parts = {}
  for index = 1, #type_names do
    local name = type_names[index]
    type_parts[#type_parts + 1] = "ui." .. name .. "=" .. member_type(name)
  end
  namespace.runtime.log_once("csp_api_types_logged", "AVM F1 API types: " .. table.concat(type_parts, " "))
  local required = #missing_mandatory == 0
  return {
    backend = "csp-native",
    required = required,
    level = required and (enhanced_candidate and 2 or 1) or 0,
    -- Presence is only a candidate. app.lua promotes this after real draw
    -- calls succeed in the active window callback.
    enhanced = false,
    enhanced_candidate = enhanced_candidate,
    missing_mandatory = missing_mandatory,
    missing_optional = missing_optional,
    incompatible_optional = incompatible_optional,
    optional_draw_text_clipped = csp.has("drawTextClipped"),
    optional_buttons = csp.has("invisibleButton") and csp.has("setCursorScreenPos"),
    optional_configuration = csp.has("inputText") and csp.has("slider"),
  }
end

function csp.text(value)
  local text = type(value) == "string" and value or tostring(value or "")
  local status, _, reason = call_ui("text", text)
  if status == "drawn" then
    namespace.runtime.record_draw("mode_text")
    return status
  end
  namespace.runtime.record_skip("ui.text: " .. tostring(reason or status))
  return status
end

function csp.text_at(value, x, y, color)
  local text = type(value) == "string" and value or tostring(value or "")
  local position = point(x, y)
  if position == nil or not valid_color(color) then
    namespace.runtime.record_skip("ui.drawText: invalid vector or color")
    local fallback_status = csp.text(text)
    if fallback_status == "drawn" then
      namespace.runtime.record_draw("degraded")
      return "degraded"
    end
    return fallback_status
  end
  local status, _, reason = call_ui("drawText", text, position, color)
  if status == "drawn" then
    namespace.runtime.record_draw("enhanced")
    return status
  end
  namespace.runtime.record_skip("ui.drawText: " .. tostring(reason or status))
  local fallback_status = csp.text(text)
  if fallback_status == "drawn" then
    namespace.runtime.record_draw("degraded")
    return "degraded"
  end
  return fallback_status
end

function csp.text_aligned(value, x, y, width, color, height)
  local text = type(value) == "string" and value or tostring(value or "")
  local left = point(x, y)
  local clip_height = math.max(1, height or 24)
  local right = point(x + math.max(1, width), y + clip_height)
  local alignment = point(0, 0)
  if left ~= nil and right ~= nil and alignment ~= nil and valid_color(color) then
    local status, _, reason = call_ui("drawTextClipped", text, left, right, color, alignment, false)
    if status == "drawn" then
      namespace.runtime.record_draw("enhanced")
      return status
    end
    namespace.runtime.record_skip("ui.drawTextClipped: " .. tostring(reason or status))
  else
    namespace.runtime.record_skip("ui.drawTextClipped: invalid vector or color")
  end
  local fallback_status = csp.text_at(text, x, y, color)
  if fallback_status == "drawn" then
    namespace.runtime.record_draw("degraded")
    return "degraded"
  end
  return fallback_status
end

function csp.rect(x, y, width, height, color, rounding)
  if width == nil or height == nil or width <= 0 or height <= 0 or not valid_color(color) then
    return invoke_draw("drawRectFilled", "enhanced", {}, "invalid bounds or color")
  end
  local first = point(x, y)
  local second = point(x + width, y + height)
  if first == nil or second == nil then
    return invoke_draw("drawRectFilled", "enhanced", {}, "unsupported vector constructor")
  end
  return invoke_draw("drawRectFilled", "enhanced", { first, second, color, rounding or 6 })
end

function csp.outline(x, y, width, height, color, rounding, thickness)
  if width == nil or height == nil or width <= 0 or height <= 0 or not valid_color(color) then
    return invoke_draw("drawRect", "enhanced", {}, "invalid bounds or color")
  end
  local first = point(x, y)
  local second = point(x + width, y + height)
  if first == nil or second == nil then
    return invoke_draw("drawRect", "enhanced", {}, "unsupported vector constructor")
  end
  return invoke_draw("drawRect", "enhanced", { first, second, color, rounding or 6, nil, thickness or 1 })
end

function csp.line(x1, y1, x2, y2, color, thickness)
  local first = point(x1, y1)
  local second = point(x2, y2)
  if first == nil or second == nil or not valid_color(color) or thickness == nil or thickness <= 0 then
    return invoke_draw("ui.drawLine", "enhanced", {}, "invalid vector, color, or thickness")
  end
  return invoke_draw("drawLine", "enhanced", { first, second, color, thickness or 1 })
end

function csp.circle(x, y, radius, color, filled)
  local center = point(x, y)
  local name = filled and "drawCircleFilled" or "drawCircle"
  if center == nil or radius == nil or radius <= 0 or not valid_color(color) then
    return invoke_draw(name, "enhanced", {}, "invalid center, radius, or color")
  end
  local arguments = { center, radius, color, 16 }
  if not filled then
    arguments[5] = 2
  end
  return invoke_draw(name, "enhanced", arguments)
end

function csp.triangle(x1, y1, x2, y2, x3, y3, color)
  local first = point(x1, y1)
  local second = point(x2, y2)
  local third = point(x3, y3)
  if first == nil or second == nil or third == nil or not valid_color(color) then
    return invoke_draw("drawTriangleFilled", "enhanced", {}, "invalid vector or color")
  end
  return invoke_draw("drawTriangleFilled", "enhanced", { first, second, third, color })
end

function csp.button(label, width, height)
  local status, clicked = call_ui("button", label, point(width or 80, height or 24))
  return status == "drawn" and clicked == true
end

function csp.invisible_button_at(label, x, y, width, height)
  local cursor = point(x, y)
  local size = point(width or 80, height or 24)
  if cursor == nil or size == nil then
    namespace.runtime.record_skip("ui.invisibleButton: invalid vector")
    return false
  end
  call_ui("setCursorScreenPos", cursor)
  local status, clicked = call_ui("invisibleButton", label, size)
  return status == "drawn" and clicked == true
end

function csp.checkbox(label, checked)
  local status, clicked = call_ui("checkbox", label, checked == true)
  return status == "drawn" and clicked == true
end

function csp.input_text(label, value)
  local callback = member(ui_api(), "inputText")
  if callback == nil or not callable(callback) then return value, false end
  local ok, result, changed = pcall(callback, label, tostring(value or ""))
  if ok and type(result) == "string" then return result, changed == true end
  return value, false
end

function csp.input_text_at(label, value, x, y)
  local cursor = point(x, y)
  if cursor ~= nil and csp.has("setCursorScreenPos") then
    call_ui("setCursorScreenPos", cursor)
  end
  return csp.input_text(label, value)
end

function csp.slider(label, value, minimum, maximum, format)
  local callback = member(ui_api(), "slider")
  if callback == nil or not callable(callback) or type(value) ~= "number" then return value, false end
  local ok, result, changed = pcall(callback, label, value, minimum, maximum, format)
  if ok and type(result) == "number" then return result, changed == true end
  return value, false
end

function csp.separator(color)
  if color ~= nil then
    return csp.line(0, 0, 1, 0, color, 1)
  end
  local status, _, reason = call_ui("separator")
  if status == "drawn" then
    namespace.runtime.record_draw("mode_text")
    return status
  end
  namespace.runtime.record_skip("ui.separator: " .. tostring(reason or status))
  local fallback_status = csp.text("--------------------")
  if fallback_status == "drawn" then
    namespace.runtime.record_draw("degraded")
    return "degraded"
  end
  return fallback_status
end

function csp.log(message)
  namespace.runtime.log(message)
end

csp.backend = "csp-native"
namespace.adapters = namespace.adapters or {}
namespace.adapters.csp = csp

-- Live telemetry remains behind the CSP adapter. UI modules only consume the
-- normalized snapshot produced here and never inspect the raw CSP objects.
local telemetry_fixture = nil
local live_diagnostics = {
  availability = "unavailable",
  source_health = "OFFLINE",
  first_failure = nil,
  first_normalization_rejection = nil,
  api = {},
  normalized_core = { valid = false, missing = {} },
  optional_missing = {},
  identity = {},
  update_age_s = nil,
}

local telemetry_core_fields = {
  "session.elapsed_s",
  "session.current_lap",
  "car.speed_kmh",
  "car.fuel_l",
  "car.spline",
  "car.lap_time_s",
}

local telemetry_optional_fields = {
  "identity.track_id",
  "identity.layout_id",
  "identity.car_id",
  "session.remaining_s",
  "session.lap_limit",
  "session.position",
  "session.total_cars",
  "session.track_length_m",
  "car.previous_lap_time_s",
  "car.best_lap_time_s",
  "car.pit_lane",
  "car.pit_box",
  "car.reset_counter",
  "car.world_position",
  "tyres.compound",
  "tyres.core_c",
  "tyres.surface_c",
  "tyres.pressure_kpa",
  "tyres.wear",
  "environment.ambient_c",
  "environment.road_c",
  "environment.weather_type",
  "environment.rain_intensity",
  "environment.track_wetness",
  "environment.standing_water",
}

local function telemetry_finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function telemetry_safe_text(value)
  local ok, result = pcall(tostring, value)
  local text = ok and result or "<unprintable>"
  text = string.gsub(text, "[%c]", " ")
  if #text > 120 then
    return string.sub(text, 1, 117) .. "..."
  end
  return text
end

local function telemetry_value_text(value)
  if value == nil then return "nil" end
  if type(value) == "string" then return "\"" .. telemetry_safe_text(value) .. "\"" end
  return telemetry_safe_text(value)
end

local function telemetry_member(object, name)
  if object == nil then return nil end
  local ok, value = pcall(function() return object[name] end)
  return ok and value or nil
end

local function telemetry_field(object, name)
  local value = telemetry_member(object, name)
  -- State fields can themselves be LuaJIT cdata values. Only a Lua function
  -- is unambiguously a method here; callable cdata is handled at API call
  -- sites so numeric/vector state is not discarded as "not a field".
  if value ~= nil and type(value) ~= "function" then
    return value
  end
  return nil
end

local function telemetry_index(object, index)
  if object == nil then return nil end
  local ok, value = pcall(function() return object[index] end)
  return ok and value or nil
end

local function telemetry_invoke(callback, receiver, ...)
  if not callable(callback) then
    return false, nil, "not callable"
  end
  local ok, value = pcall(callback, ...)
  if ok then
    return true, value, nil
  end
  local first_error = telemetry_safe_text(value)
  if receiver ~= nil then
    local retry_ok, retry_value = pcall(callback, receiver, ...)
    if retry_ok then
      return true, retry_value, nil
    end
    return false, nil, first_error .. " | receiver call: " .. telemetry_safe_text(retry_value)
  end
  return false, nil, first_error
end

local function telemetry_call(object, name, ...)
  local callback = telemetry_member(object, name)
  local ok, value = telemetry_invoke(callback, object, ...)
  return ok and value or nil
end

local function telemetry_call_api(api, name, ...)
  local callback = telemetry_member(api, name)
  local ok, value, error_value = telemetry_invoke(callback, nil, ...)
  return ok, value, error_value, callback
end

local function telemetry_first(object, names)
  for index = 1, #names do
    local value = telemetry_field(object, names[index])
    if value ~= nil then return value end
  end
  return nil
end

local function telemetry_average(sum, count)
  return count > 0 and sum / count or nil
end

local function telemetry_path(snapshot, path)
  local value = snapshot
  for part in string.gmatch(path, "[^%.]+") do
    value = type(value) == "table" and value[part] or nil
  end
  return value
end

local function telemetry_present(value)
  if value == nil then return false end
  if type(value) == "number" then return telemetry_finite(value) end
  if type(value) == "string" then return value ~= "" end
  return true
end

local function telemetry_classify(snapshot)
  local missing_core = {}
  for index = 1, #telemetry_core_fields do
    local field = telemetry_core_fields[index]
    if not telemetry_present(telemetry_path(snapshot, field)) then
      missing_core[#missing_core + 1] = field
    end
  end
  local optional_missing = {}
  for index = 1, #telemetry_optional_fields do
    local field = telemetry_optional_fields[index]
    if not telemetry_present(telemetry_path(snapshot, field)) then
      optional_missing[#optional_missing + 1] = field
    end
  end
  local valid = #missing_core == 0
  local complete = valid and #optional_missing == 0
  live_diagnostics.normalized_core = { valid = valid, missing = missing_core }
  live_diagnostics.optional_missing = optional_missing
  live_diagnostics.availability = complete and "live" or "partial"
  return complete and "live" or "partial", missing_core, optional_missing
end

local function telemetry_probe_result(member_value, attempted, ok, result, error_value)
  if member_value == nil then return "missing" end
  if not callable(member_value) then return type(member_value) .. "/not-callable" end
  if not attempted then return type(member_value) .. "/not-called" end
  if ok then return type(member_value) .. "->" .. type(result) end
  return type(member_value) .. "/error=" .. telemetry_safe_text(error_value)
end

local function record_live_probe(ac_api, get_sim, sim_attempted, sim_ok, sim, sim_error, get_car, car_attempted, car_ok, car, car_error, get_session, session_attempted, session_ok, session, session_error, failure)
  local probe = "AVM F1 live source probe: ac=" .. type(ac_api)
    .. " getSim=" .. telemetry_probe_result(get_sim, sim_attempted, sim_ok, sim, sim_error)
    .. " getCar=" .. telemetry_probe_result(get_car, car_attempted, car_ok, car, car_error)
    .. " getSession=" .. telemetry_probe_result(get_session, session_attempted, session_ok, session, session_error)
    .. " car0=" .. (car_attempted and (car_ok and type(car) or "error=" .. telemetry_safe_text(car_error)) or "not-called")
    .. " sim=" .. (sim_attempted and (sim_ok and type(sim) or "error=" .. telemetry_safe_text(sim_error)) or "not-called")
    .. " session=" .. (session_attempted and (session_ok and type(session) or "error=" .. telemetry_safe_text(session_error)) or "not-called")
    .. " failure=" .. telemetry_safe_text(failure or "none")
  if live_diagnostics.probe == nil then
    live_diagnostics.probe = probe
    live_diagnostics.first_failure = failure
    namespace.runtime.log_once("live_source_probe_logged", probe)
  end
end

local function normalization_rejection(field, value, reason)
  local message = "AVM F1 live normalization rejected: field=" .. tostring(field)
    .. " value_type=" .. type(value)
    .. " value=" .. telemetry_value_text(value)
    .. " reason=" .. tostring(reason)
  if live_diagnostics.first_normalization_rejection == nil then
    live_diagnostics.first_normalization_rejection = message
    namespace.runtime.log_once("live_normalization_rejected_logged", message)
  end
end

function csp.set_mock_fixture(fixture)
  telemetry_fixture = fixture
end

function csp.clear_mock_fixture()
  telemetry_fixture = nil
end

function csp.diagnostics()
  return live_diagnostics
end

function csp.normalize(raw, observed_monotonic_s, source_mode)
  if type(raw) ~= "table" then
    normalization_rejection("snapshot", raw, "SOURCE_UNAVAILABLE")
    return nil, "SOURCE_UNAVAILABLE"
  end
  local identity = type(raw.identity) == "table" and raw.identity or {}
  local session = type(raw.session) == "table" and raw.session or {}
  local car = type(raw.car) == "table" and raw.car or {}
  local tyres = type(raw.tyres) == "table" and raw.tyres or {}
  local environment = type(raw.environment) == "table" and raw.environment or {}
  local normalized = {
    schema_version = "telemetry-snapshot-v1",
    snapshot_id = raw.snapshot_id,
    source_mode = source_mode or raw.source_mode or "live",
    source_timestamp_s = raw.source_timestamp_s or raw.observed_monotonic_s,
    observed_monotonic_s = observed_monotonic_s,
    sequence = raw.sequence,
    identity = {
      car_id = identity.car_id,
      track_id = identity.track_id,
      layout_id = identity.layout_id,
      driver_name = identity.driver_name,
      session_id = identity.session_id,
      configuration_id = identity.configuration_id,
    },
    session = {
      type = session.type,
      elapsed_s = session.elapsed_s,
      remaining_s = session.remaining_s,
      lap_limit = session.lap_limit,
      track_length_m = session.track_length_m,
      completed_laps = session.completed_laps,
      current_lap = session.current_lap,
      position = session.position,
      total_cars = session.total_cars,
      paused = session.paused == true,
      replay = session.replay == true,
      active = session.active ~= false,
      finished = session.finished == true,
    },
    car = {
      speed_kmh = car.speed_kmh,
      fuel_l = car.fuel_l,
      fuel_capacity_l = car.fuel_capacity_l,
      spline = car.spline,
      distance_session_km = car.distance_session_km,
      pit_lane = car.pit_lane,
      pit_box = car.pit_box,
      world_position = car.world_position,
      lap_time_s = car.lap_time_s,
      previous_lap_time_s = car.previous_lap_time_s,
      best_lap_time_s = car.best_lap_time_s,
      lap_valid = car.lap_valid,
      previous_lap_valid = car.previous_lap_valid,
      last_lap_cuts = car.last_lap_cuts,
      reset_counter = car.reset_counter,
    },
    tyres = {
      compound = tyres.compound,
      core_c = tyres.core_c,
      surface_c = tyres.surface_c,
      wear = tyres.wear,
      pressure_kpa = tyres.pressure_kpa,
      optimum_c = tyres.optimum_c,
      wheels = tyres.wheels,
    },
    environment = {
      ambient_c = environment.ambient_c,
      road_c = environment.road_c,
      wind_kmh = environment.wind_kmh,
      wind_direction_deg = environment.wind_direction_deg,
      weather_type = environment.weather_type,
      rain_intensity = environment.rain_intensity,
      track_wetness = environment.track_wetness,
      standing_water = environment.standing_water,
      grip = environment.grip,
    },
  }
  local availability, missing_core = telemetry_classify(normalized)
  if source_mode == "mock" then
    live_diagnostics.availability = "mock"
    live_diagnostics.source_health = "LIVE"
    normalized.source_availability = "mock"
    normalized.source_health = "LIVE"
  else
    normalized.source_availability = availability
    normalized.source_health = (#missing_core == 0 and #live_diagnostics.optional_missing == 0) and "LIVE" or (#missing_core == 0 and "PARTIAL" or "OFFLINE")
    live_diagnostics.source_health = normalized.source_health
  end
  normalized.missing_core = missing_core
  normalized.optional_missing = live_diagnostics.optional_missing
  normalized.availability = {}
  for index = 1, #telemetry_core_fields do
    local field = telemetry_core_fields[index]
    local value = telemetry_path(normalized, field)
    normalized.availability[field] = {
      available = telemetry_present(value),
      unit = field:find("speed") and "km/h" or field:find("fuel") and "L" or field:find("time") and "s" or nil,
      provenance = telemetry_present(value) and "CSP" or nil,
      freshness_s = 0,
      reason = telemetry_present(value) and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE",
    }
  end
  for index = 1, #telemetry_optional_fields do
    local field = telemetry_optional_fields[index]
    local value = telemetry_path(normalized, field)
    normalized.availability[field] = {
      available = telemetry_present(value),
      provenance = telemetry_present(value) and "CSP" or nil,
      freshness_s = 0,
      reason = telemetry_present(value) and "MEASURED_CURRENT" or "OPTIONAL_FIELD_UNAVAILABLE",
    }
  end
  normalized.failures = {
    missing_core = telemetry_finite(#missing_core) and missing_core or {},
    missing_optional = live_diagnostics.optional_missing,
    first_failure = live_diagnostics.first_failure,
    first_normalization_rejection = live_diagnostics.first_normalization_rejection,
  }
  if #missing_core > 0 then
    normalization_rejection(missing_core[1], telemetry_path(normalized, missing_core[1]), "SOURCE_PARTIAL")
  end
  return normalized, nil
end

local function read_live_telemetry()
  local ac_api = rawget(_G, "ac")
  local get_sim = telemetry_member(ac_api, "getSim")
  local get_car = telemetry_member(ac_api, "getCar")
  local get_session = telemetry_member(ac_api, "getSession")
  local sim_attempted, sim_ok, sim, sim_error = false, false, nil, nil
  local car_attempted, car_ok, car, car_error = false, false, nil, nil
  local session_attempted, session_ok, session, session_error = false, false, nil, nil
  local failure = nil
  local function fail(detail)
    if failure == nil then failure = detail end
  end

  if ac_api == nil or (type(ac_api) ~= "table" and type(ac_api) ~= "userdata" and type(ac_api) ~= "cdata") then
    fail("ac type=" .. type(ac_api))
  end
  if not callable(get_sim) then
    fail("getSim not callable type=" .. type(get_sim))
  else
    sim_attempted = true
    sim_ok, sim, sim_error = telemetry_invoke(get_sim, nil)
    if not sim_ok then fail("getSim failed: " .. telemetry_safe_text(sim_error)) end
    if sim_ok and sim == nil then fail("getSim returned nil") end
  end
  if not callable(get_car) then
    fail("getCar not callable type=" .. type(get_car))
  else
    car_attempted = true
    car_ok, car, car_error = telemetry_invoke(get_car, nil, 0)
    if not car_ok then fail("getCar(0) failed: " .. telemetry_safe_text(car_error)) end
    if car_ok and car == nil then fail("getCar(0) returned nil") end
  end
  if sim_ok and sim ~= nil then
    if not callable(get_session) then
      session_error = "missing or non-callable member"
      fail("getSession not callable type=" .. type(get_session))
    else
      local session_index = telemetry_field(sim, "currentSessionIndex") or 0
      session_attempted = true
      session_ok, session, session_error = telemetry_invoke(get_session, nil, session_index)
      if not session_ok then fail("getSession(" .. tostring(session_index) .. ") failed: " .. telemetry_safe_text(session_error)) end
      if session_ok and session == nil then fail("getSession(" .. tostring(session_index) .. ") returned nil") end
    end
  end
  live_diagnostics.api = {
    ac_type = type(ac_api),
    getSim = { member_type = type(get_sim), callable = callable(get_sim), result_type = type(sim), protected_ok = sim_ok, error = sim_error },
    getCar = { member_type = type(get_car), callable = callable(get_car), result_type = type(car), protected_ok = car_ok, error = car_error },
    getSession = { member_type = type(get_session), callable = callable(get_session), result_type = type(session), protected_ok = session_ok, error = session_error },
    car0 = { result_type = type(car), protected_ok = car_ok },
    sim = { result_type = type(sim), protected_ok = sim_ok },
    session = { result_type = type(session), protected_ok = session_ok },
  }
  if not sim_ok or sim == nil or not car_ok or car == nil then
    record_live_probe(ac_api, get_sim, sim_attempted, sim_ok, sim, sim_error, get_car, car_attempted, car_ok, car, car_error, get_session, session_attempted, session_ok, session, session_error, failure)
    live_diagnostics.availability = "unavailable"
    return nil, "SOURCE_UNAVAILABLE"
  end

  local session_index = telemetry_field(sim, "currentSessionIndex") or 0
  local api_records = {}
  local function api_value(name, ...)
    local ok, value, error_value, callback = telemetry_call_api(ac_api, name, ...)
    api_records[name] = {
      exists = callback ~= nil,
      member_type = type(callback),
      callable = callable(callback),
      protected_ok = ok,
      result_type = type(value),
      error = error_value,
    }
    if not callable(callback) then
      fail(name .. " not callable type=" .. type(callback))
      return nil
    end
    if not ok then
      fail(name .. " failed: " .. telemetry_safe_text(error_value))
      return nil
    end
    return value
  end
  local track_id = api_value("getTrackID")
  local layout_id = api_value("getTrackLayout")
  local full_id = api_value("getTrackFullID", "::")
  local car_id = api_value("getCarID", 0)
  local car_name = api_value("getCarName", 0)
  local driver_name = telemetry_field(car, "driverName")
  local compound = api_value("getTyresName", 0)
  local wheels = telemetry_field(car, "wheels") or {}
  local core_sum, surface_sum, pressure_sum, wear_sum, optimum_sum, wheel_count = 0, 0, 0, 0, 0, 0
  local wheel_values = {}
  local wheel_labels = { "FL", "FR", "RL", "RR" }
  local zero_based_wheels = telemetry_index(wheels, 0) ~= nil
  for index = 0, 3 do
    local wheel_index = zero_based_wheels and index or index + 1
    local wheel = telemetry_index(wheels, wheel_index)
    if wheel ~= nil then
      local core = telemetry_first(wheel, { "tyreCoreTemperature", "coreTemperature" })
      local surface = telemetry_first(wheel, { "tyreMiddleTemperature", "tyreSurfaceTemperature", "surfaceTemperature" })
      local pressure = telemetry_first(wheel, { "tyrePressure", "pressure" })
      local wear = telemetry_first(wheel, { "tyreWear", "wear" })
      local optimum = telemetry_first(wheel, { "tyreOptimumTemperature", "optimumTemperature" })
      local inside = telemetry_first(wheel, { "tyreInsideTemperature", "insideTemperature" })
      local middle = telemetry_first(wheel, { "tyreMiddleTemperature", "middleTemperature" })
      local outside = telemetry_first(wheel, { "tyreOutsideTemperature", "outsideTemperature" })
      local static_pressure = telemetry_first(wheel, { "tyreStaticPressure", "staticPressure" })
      local grain = telemetry_first(wheel, { "tyreGrain", "grain" })
      local blister = telemetry_first(wheel, { "tyreBlister", "blister" })
      local flat_spot = telemetry_first(wheel, { "tyreFlatSpot", "flatSpot" })
      if telemetry_finite(core) then core_sum = core_sum + core end
      if telemetry_finite(surface) then surface_sum = surface_sum + surface end
      if telemetry_finite(pressure) then pressure_sum = pressure_sum + pressure end
      if telemetry_finite(wear) then wear_sum = wear_sum + wear end
      if telemetry_finite(optimum) then optimum_sum = optimum_sum + optimum end
      if core ~= nil or surface ~= nil or pressure ~= nil or wear ~= nil then wheel_count = wheel_count + 1 end
      wheel_values[index + 1] = {
        label = wheel_labels[index + 1],
        core_c = core,
        inside_c = inside,
        middle_c = middle,
        outside_c = outside,
        optimum_c = optimum,
        pressure_psi = pressure,
        pressure_kpa = telemetry_finite(pressure) and pressure * 6.894757293 or nil,
        static_pressure_psi = static_pressure,
        wear = wear,
        grain = grain,
        blister = blister,
        flat_spot = flat_spot,
        -- The installed SDK documents the fields but not ranges for grain and
        -- blister. Preserve raw values for Garage diagnostics; only flat spot
        -- has a verified unit-scale reference in the inspected apps.
        damage_scale = {
          grain = "UNVERIFIED",
          blister = "UNVERIFIED",
          flat_spot = "CSP_REFERENCE_0_TO_1",
        },
      }
    end
  end
  local function milliseconds(value)
    return type(value) == "number" and telemetry_finite(value) and value / 1000 or nil
  end
  local sim_time_ms = telemetry_field(sim, "time")
  local lap_count = telemetry_field(car, "lapCount")
  local lap_time_ms = telemetry_field(car, "lapTimeMs")
  local previous_lap_time_ms = telemetry_field(car, "previousLapTimeMs")
  local best_lap_time_ms = telemetry_field(car, "bestLapTimeMs")
  local current_session_time_ms = telemetry_field(sim, "currentSessionTime")
  local session_time_left_ms = telemetry_field(sim, "sessionTimeLeft")
  local environment_fields = {}
  for _, name in ipairs({ "ambientTemperature", "roadTemperature", "weatherType", "rainIntensity", "rainWetness", "rainWater", "roadGrip", "windSpeedKmh", "windDirectionDeg" }) do
    local member_value = telemetry_member(sim, name)
    environment_fields[name] = { exists = member_value ~= nil, member_type = type(member_value), value_type = type(telemetry_field(sim, name)) }
  end
  local raw = {
    source_mode = "live",
    identity = {
      car_id = car_id or car_name,
      track_id = track_id,
      layout_id = layout_id,
      driver_name = driver_name,
      session_id = tostring(session_index) .. ":" .. tostring(telemetry_field(session, "startTime") or ""),
      configuration_id = tostring(car_id or car_name or "") .. "@" .. tostring(full_id or track_id or ""),
    },
    session = {
      type = telemetry_field(sim, "raceSessionType"),
      elapsed_s = milliseconds(current_session_time_ms) or telemetry_field(sim, "gameTime"),
      remaining_s = milliseconds(session_time_left_ms),
      lap_limit = telemetry_field(session, "laps"),
      track_length_m = telemetry_field(sim, "trackLengthM"),
      completed_laps = lap_count,
      current_lap = type(lap_count) == "number" and lap_count + 1 or nil,
      position = telemetry_field(car, "racePosition"),
      total_cars = telemetry_field(sim, "carsCount"),
      paused = telemetry_field(sim, "isPaused"),
      replay = telemetry_field(sim, "isReplayActive") or telemetry_field(sim, "isReplayOnlyMode"),
      active = telemetry_field(sim, "isLive") or telemetry_field(sim, "isSessionStarted"),
      finished = telemetry_field(sim, "isSessionFinished") or telemetry_field(session, "isOver"),
    },
    car = {
      speed_kmh = telemetry_field(car, "speedKmh"),
      fuel_l = telemetry_field(car, "fuel"),
      fuel_capacity_l = telemetry_field(car, "maxFuel"),
      spline = telemetry_field(car, "splinePosition"),
      distance_session_km = telemetry_field(car, "distanceDrivenSessionKm"),
      pit_lane = telemetry_field(car, "isInPitlane"),
      pit_box = telemetry_field(car, "isInPit"),
      world_position = telemetry_field(car, "position") or telemetry_field(car, "worldPosition"),
      lap_time_s = milliseconds(lap_time_ms),
      previous_lap_time_s = milliseconds(previous_lap_time_ms),
      best_lap_time_s = milliseconds(best_lap_time_ms),
      lap_valid = telemetry_field(car, "isLapValid"),
      previous_lap_valid = telemetry_field(car, "isLastLapValid"),
      last_lap_cuts = telemetry_field(car, "lastLapCutsCount"),
      reset_counter = telemetry_field(car, "resetCounter"),
    },
    tyres = {
      compound = compound,
      core_c = telemetry_average(core_sum, wheel_count),
      surface_c = telemetry_average(surface_sum, wheel_count),
      wear = telemetry_average(wear_sum, wheel_count),
      -- StateWheel.tyrePressure is reported in PSI; the normalized contract
      -- stores kPa for the calculation and view-model layers.
      pressure_kpa = telemetry_average(pressure_sum, wheel_count) and telemetry_average(pressure_sum, wheel_count) * 6.894757293 or nil,
      optimum_c = telemetry_average(optimum_sum, wheel_count),
      wheels = wheel_values,
    },
    environment = {
      ambient_c = telemetry_field(sim, "ambientTemperature"),
      road_c = telemetry_field(sim, "roadTemperature"),
      wind_kmh = telemetry_field(sim, "windSpeedKmh"),
      wind_direction_deg = telemetry_field(sim, "windDirectionDeg"),
      weather_type = telemetry_field(sim, "weatherType"),
      rain_intensity = telemetry_field(sim, "rainIntensity"),
      track_wetness = telemetry_field(sim, "rainWetness"),
      standing_water = telemetry_field(sim, "rainWater"),
      grip = telemetry_field(sim, "roadGrip"),
    },
    observed_monotonic_s = type(sim_time_ms) == "number" and sim_time_ms / 1000 or nil,
  }
  live_diagnostics.identity = raw.identity
  live_diagnostics.api = {
    ac = { exists = ac_api ~= nil, member_type = type(ac_api) },
    ac_type = type(ac_api),
    getSim = { member_type = type(get_sim), callable = callable(get_sim), result_type = type(sim), protected_ok = sim_ok, error = sim_error },
    getCar = { member_type = type(get_car), callable = callable(get_car), result_type = type(car), protected_ok = car_ok, error = car_error },
    getSession = { member_type = type(get_session), callable = callable(get_session), result_type = type(session), protected_ok = session_ok, error = session_error },
    car0 = { result_type = type(car), protected_ok = car_ok },
    sim = { result_type = type(sim), protected_ok = sim_ok },
    session = { result_type = type(session), protected_ok = session_ok },
    track = { track_id_type = type(track_id), layout_type = type(layout_id), full_id_type = type(full_id) },
    environment = { ambient_type = type(raw.environment.ambient_c), road_type = type(raw.environment.road_c), weather_type = type(raw.environment.weather_type), rain_type = type(raw.environment.track_wetness) },
    environment_fields = environment_fields,
    getTrackID = api_records.getTrackID,
    getTrackLayout = api_records.getTrackLayout,
    getTrackFullID = api_records.getTrackFullID,
    getCarID = api_records.getCarID,
    getCarName = api_records.getCarName,
    getTyresName = api_records.getTyresName,
  }
  record_live_probe(ac_api, get_sim, sim_attempted, sim_ok, sim, sim_error, get_car, car_attempted, car_ok, car, car_error, get_session, session_attempted, session_ok, session, session_error, failure)
  return raw, nil
end

function csp.read(source_mode, now_s)
  if source_mode == "mock" then
    if telemetry_fixture == nil then
      live_diagnostics.availability = "unavailable"
      return nil, "SOURCE_UNAVAILABLE"
    end
    return csp.normalize(telemetry_fixture, now_s, "mock")
  end
  if source_mode ~= "live" then return nil, "SOURCE_UNAVAILABLE" end
  local raw, reason = read_live_telemetry()
  if raw == nil then return nil, reason end
  return csp.normalize(raw, now_s, "live")
end
