local namespace = _G.AVM_PITWALL_F1
local csp = {}

local function callable(value)
  local value_type = type(value)
  return value_type == "function" or value_type == "userdata"
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
  if ok and callable(value) then
    return value
  end
  return nil
end

local function call_ui(name, ...)
  local api = ui_api()
  local callback = member(api, name)
  if callback == nil then
    return false, nil
  end
  return pcall(callback, ...)
end

local function point(x, y)
  local constructor = rawget(_G, "vec2")
  if type(constructor) == "function" then
    local ok, result = pcall(constructor, x, y)
    if ok and result ~= nil then
      return result
    end
  end
  return { x = x, y = y }
end

function csp.color(red, green, blue, alpha)
  local constructor = rawget(_G, "rgbm")
  if type(constructor) == "function" then
    local ok, result = pcall(constructor, red, green, blue, alpha or 1)
    if ok and result ~= nil then
      return result
    end
  end
  return { r = red, g = green, b = blue, a = alpha or 1 }
end

function csp.point(x, y)
  return point(x, y)
end

function csp.window_size()
  local ok, result = call_ui("windowSize")
  if ok and result ~= nil and type(result.x) == "number" and type(result.y) == "number" then
    return result.x, result.y
  end
  return 780, 380
end

function csp.has(name)
  return member(ui_api(), name) ~= nil
end

function csp.capabilities()
  local mandatory_names = { "ui.text" }
  local optional_names = {
    "ui.separator",
    "ui.textColored",
    "ui.windowSize",
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
  for index = 1, #optional_names do
    local name = optional_names[index]
    if not csp.has(string.sub(name, 4)) then
      missing_optional[#missing_optional + 1] = name
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
  local enhanced = #missing_mandatory == 0
  for index = 1, #enhanced_names do
    enhanced = enhanced and csp.has(string.sub(enhanced_names[index], 4))
  end
  return {
    backend = "csp-native",
    required = #missing_mandatory == 0,
    level = #missing_mandatory == 0 and (enhanced and 2 or 1) or 0,
    enhanced = enhanced,
    missing_mandatory = missing_mandatory,
    missing_optional = missing_optional,
    optional_draw_text_clipped = csp.has("drawTextClipped"),
    optional_buttons = csp.has("invisibleButton") and csp.has("setCursorScreenPos"),
  }
end

function csp.text(value, color)
  local text = type(value) == "string" and value or tostring(value or "")
  if color ~= nil then
    local ok = call_ui("textColored", text, color)
    if ok then
      return true
    end
  end
  local ok = call_ui("text", text)
  return ok
end

function csp.text_at(value, x, y, color)
  local ok = call_ui("drawText", type(value) == "string" and value or tostring(value or ""), point(x, y), color)
  if ok then
    return true
  end
  return csp.text(value, color)
end

function csp.text_aligned(value, x, y, width, color)
  local ok = call_ui("drawTextClipped", type(value) == "string" and value or tostring(value or ""), point(x, y), point(x + width, y + 24), color, point(0, 0), true)
  if ok then
    return true
  end
  return csp.text_at(value, x, y, color)
end

function csp.rect(x, y, width, height, color, rounding)
  local ok = call_ui("drawRectFilled", point(x, y), point(x + width, y + height), color, rounding or 6)
  return ok
end

function csp.outline(x, y, width, height, color, rounding, thickness)
  local ok = call_ui("drawRect", point(x, y), point(x + width, y + height), color, rounding or 6, nil, thickness or 1)
  return ok
end

function csp.line(x1, y1, x2, y2, color, thickness)
  local ok = call_ui("drawLine", point(x1, y1), point(x2, y2), color, thickness or 1)
  return ok
end

function csp.circle(x, y, radius, color, filled)
  local name = filled and "drawCircleFilled" or "drawCircle"
  local ok = call_ui(name, point(x, y), radius, color, 16, filled and nil or 2)
  return ok
end

function csp.triangle(x1, y1, x2, y2, x3, y3, color)
  local ok = call_ui("drawTriangleFilled", point(x1, y1), point(x2, y2), point(x3, y3), color)
  return ok
end

function csp.button(label, width, height)
  local ok, clicked = call_ui("button", label, point(width or 80, height or 24))
  return ok and clicked == true
end

function csp.invisible_button_at(label, x, y, width, height)
  call_ui("setCursorScreenPos", point(x, y))
  local ok, clicked = call_ui("invisibleButton", label, point(width or 80, height or 24))
  return ok and clicked == true
end

function csp.checkbox(label, checked)
  local ok, clicked = call_ui("checkbox", label, checked == true)
  return ok and clicked == true
end

function csp.separator(color)
  if color ~= nil then
    return csp.line(0, 0, 0, 0, color, 1)
  else
    local ok = call_ui("separator")
    if ok then
      return true
    end
    return csp.text("--------------------")
  end
end

function csp.log(message)
  namespace.runtime.log(message)
end

namespace.adapters = namespace.adapters or {}
csp.backend = "csp-native"
namespace.adapters.csp = csp
