local namespace = _G.AVM_PITWALL_F1
local csp = {}
local unpack_values = table.unpack or unpack

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

local function ui_api()
  local candidate = rawget(_G, "ui")
  local candidate_type = type(candidate)
  if candidate_type == "table" or candidate_type == "userdata" then
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

function csp.window_size()
  local status, result = call_ui("availableSpace")
  local width, height = size_from(result)
  if status == "drawn" and width ~= nil then
    return width, height, "availableSpace"
  end

  status, result = call_ui("availableSpaceX")
  local available_width = valid_number(result) and result or nil
  status, result = call_ui("availableSpaceY")
  local available_height = valid_number(result) and result or nil
  if available_width ~= nil and available_height ~= nil and available_width > 0 and available_height > 0 then
    return available_width, available_height, "availableSpaceX/Y"
  end

  status, result = call_ui("windowSize")
  width, height = size_from(result)
  if status == "drawn" and width ~= nil then
    return width, height, "windowSize"
  end

  status, result = call_ui("windowWidth")
  local window_width = valid_number(result) and result or nil
  status, result = call_ui("windowHeight")
  local window_height = valid_number(result) and result or nil
  if window_width ~= nil and window_height ~= nil and window_width > 0 and window_height > 0 then
    return window_width, window_height, "windowWidth/Height"
  end
  return 780, 380, "fallback"
end

function csp.ui_scale()
  local status, result = call_ui("uiScale")
  if status == "drawn" and valid_number(result) and result > 0 then
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

function csp.text_aligned(value, x, y, width, color)
  local text = type(value) == "string" and value or tostring(value or "")
  local left = point(x, y)
  local right = point(x + math.max(1, width), y + 24)
  local alignment = point(0, 0)
  if left ~= nil and right ~= nil and alignment ~= nil and valid_color(color) then
    local status, _, reason = call_ui("drawTextClipped", text, left, right, color, alignment, true)
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
