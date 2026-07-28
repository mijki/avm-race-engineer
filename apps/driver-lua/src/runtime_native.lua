local namespace = _G.AVM_PITWALL_F1
local native = {}

local function callable(value)
  local value_type = type(value)
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
  if ok and callable(value) then
    return value
  end
  return nil
end

local function point(x, y)
  local constructor = rawget(_G, "vec2")
  if callable(constructor) then
    local ok, result = pcall(constructor, x, y)
    if ok and result ~= nil then
      return result
    end
  end
  return nil
end

local function color(red, green, blue, alpha)
  local constructor = rawget(_G, "rgbm")
  if callable(constructor) then
    local ok, result = pcall(constructor, red, green, blue, alpha or 1)
    if ok and result ~= nil then
      return result
    end
  end
  return { r = red, g = green, b = blue, a = alpha or 1 }
end

local function invoke(name, ...)
  local api = ui_api()
  local callback = member(api, name)
  if callback == nil or not callable(callback) then
    return false
  end
  local ok = pcall(callback, ...)
  return ok
end

local function safe_text(value)
  local text = tostring(value or "")
  text = string.gsub(text, "[%c]", " ")
  if #text > 140 then
    text = string.sub(text, 1, 137) .. "..."
  end
  return text
end

function native.window_size()
  local api = ui_api()
  local callback = member(api, "availableSpace") or member(api, "windowSize")
  if callback ~= nil then
    local ok, result = pcall(callback)
    if ok and result ~= nil and type(result.x) == "number" and type(result.y) == "number" and result.x > 0 and result.y > 0 then
      return result.x, result.y
    end
  end
  return 780, 380
end

function native.has_draw_api()
  return member(ui_api(), "drawText") ~= nil and member(ui_api(), "drawRectFilled") ~= nil
end

function native.fill(x, y, width, height, fill_color, rounding)
  local first = point(x, y)
  local second = point(x + math.max(1, width), y + math.max(1, height))
  if first == nil or second == nil then
    return false
  end
  return invoke("drawRectFilled", first, second, fill_color, rounding or 0)
end

function native.outline(x, y, width, height, line_color, rounding, thickness)
  local first = point(x, y)
  local second = point(x + math.max(1, width), y + math.max(1, height))
  if first == nil or second == nil then
    return false
  end
  return invoke("drawRect", first, second, line_color, rounding or 0, nil, thickness or 1)
end

function native.text_at(value, x, y, text_color)
  local text = safe_text(value)
  local position = point(x, y)
  if position ~= nil and invoke("drawText", text, position, text_color) then
    return true
  end
  if invoke("textColored", text, text_color) then
    return true
  end
  local drew = invoke("text", text)
  if drew then
    return true
  end
  return native.emergency(text)
end

function native.log(message)
  namespace.runtime.log(message)
end

function native.draw_canary()
  local width, height = native.window_size()
  local drew_background = native.fill(0, 0, width, height, color(0.035, 0.045, 0.06, 1), 0)
  local drew_header = native.fill(12, 12, math.max(180, width - 24), 92, color(0.10, 0.13, 0.18, 1), 6)
  local drew_title = native.text_at("AVM PitWall", 28, 28, color(0.95, 0.98, 1, 1))
  local drew_status = native.text_at("F1 runtime active", 28, 56, color(0.25, 0.85, 1, 1))
  return drew_background or drew_header or drew_title or drew_status
end

function native.draw_recovery(stage, detail)
  local width, height = native.window_size()
  local drew_background = native.fill(0, 0, width, height, color(0.035, 0.045, 0.06, 1), 0)
  local panel_width = math.max(160, width - 20)
  local panel_height = math.max(120, height - 20)
  local drew_panel = native.fill(10, 10, panel_width, panel_height, color(0.10, 0.13, 0.18, 1), 8)
  local drew_outline = native.outline(10, 10, panel_width, panel_height, color(1, 0.18, 0.18, 1), 8, 2)
  local drew_title = native.text_at("AVM PitWall", 28, 28, color(0.95, 0.98, 1, 1))
  local drew_recovery = native.text_at("Render recovery", 28, 58, color(1, 0.35, 0.35, 1))
  local drew_stage = native.text_at("Stage: " .. safe_text(stage or "unknown"), 28, 84, color(0.72, 0.78, 0.86, 1))
  local drew_detail = native.text_at(safe_text(detail or "Safe shell retained"), 28, 110, color(0.95, 0.98, 1, 1))
  if drew_background or drew_panel or drew_outline or drew_title or drew_recovery or drew_stage or drew_detail then
    return true
  end
  return native.emergency("Render recovery")
end

function native.emergency(message)
  local api = ui_api()
  local callback = member(api, "text")
  if callback ~= nil then
    local ok = pcall(callback, "AVM PitWall")
    if ok then
      pcall(callback, safe_text(message or "Runtime recovery"))
      return true
    end
  end
  return false
end

namespace.runtime.native = native
