local namespace = _G.AVM_PITWALL_F1
local csp = {}

local function call_ui(name, ...)
  if type(ui) ~= "table" or type(ui[name]) ~= "function" then
    return false, nil
  end
  return pcall(ui[name], ...)
end

local function point(x, y)
  if type(vec2) == "function" then
    local ok, result = pcall(vec2, x, y)
    if ok and result ~= nil then
      return result
    end
  end
  return { x = x, y = y }
end

function csp.color(red, green, blue, alpha)
  if type(rgbm) == "function" then
    local ok, result = pcall(rgbm, red, green, blue, alpha or 1)
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
    csp.line(0, 0, 0, 0, color, 1)
  else
    call_ui("separator")
  end
end

function csp.log(message)
  if type(ac) == "table" and type(ac.console) == "function" then
    pcall(ac.console, "AVM PitWall F1: " .. tostring(message), false)
  end
end

namespace.adapters = namespace.adapters or {}
namespace.adapters.csp = csp
