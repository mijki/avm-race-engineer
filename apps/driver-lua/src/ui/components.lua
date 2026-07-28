local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local icons = namespace.ui.icons
local components = {}

function components.card(box, title, icon, tone)
  if csp.has("drawRectFilled") then
    csp.rect(box.x, box.y, box.width, box.height, theme.color("surface"), 7)
  end
  if csp.has("drawRect") then
    csp.outline(box.x, box.y, box.width, box.height, theme.color("border"), 7, 1)
  end
  if icon ~= nil then
    icons.draw(icon, box.x + 10, box.y + 8, 18, theme.tone(tone or "info"))
    csp.text_at(title, box.x + 34, box.y + 9, theme.color("muted"))
  else
    csp.text_at(title, box.x + 10, box.y + 9, theme.color("muted"))
  end
end

function components.label(text, x, y, color)
  csp.text_at(text, x, y, color or theme.color("muted"))
end

function components.value(text, x, y, color)
  csp.text_at(text, x, y, color or theme.color("text"))
end

function components.badge(text, x, y, width, tone)
  local color = theme.tone(tone or "info")
  if csp.has("drawRectFilled") then
    csp.rect(x, y, width, 20, theme.color("surface_alt"), 5)
  end
  if csp.has("drawRect") then
    csp.outline(x, y, width, 20, color, 5, 1)
  end
  csp.text_aligned(text, x + 5, y + 3, width - 10, color, 16)
end

function components.indicator(indicator, x, y, width)
  indicator = indicator or {}
  local color = theme.tone(indicator.tone or "neutral")
  local shape = indicator.shape or "hollow"
  local center_x = x + 7
  local center_y = y + 9
  if shape == "filled" or shape == "warning" then
    csp.circle(center_x, center_y, 4, color, true)
  else
    csp.circle(center_x, center_y, 4, color, false)
    if shape == "crossed" then
      csp.line(center_x - 4, center_y - 4, center_x + 4, center_y + 4, color, 1.5)
    end
  end
  components.safe_text(indicator.label or "--", x + 15, y + 2, math.max(20, (width or 54) - 15), color)
end

function components.header(vm, box)
  if type(box) ~= "table" then return end
  local header = vm and vm.header or {}
  components.card(box, "AVM PitWall", nil, header.source_tone)
  local indicator_width = 50
  local indicator_gap = 3
  local indicator_x = box.x + box.width - indicator_width * 3 - indicator_gap * 2 - 8
  local context_width = math.max(40, indicator_x - box.x - 108)
  components.safe_text(header.context ~= "" and header.context or ((header.session or "") .. "  " .. (header.lap or "")), box.x + 108, box.y + 9, context_width, theme.color("muted"))
  local indicators = header.indicators or {}
  components.indicator(indicators.telemetry, indicator_x, box.y + 5, indicator_width)
  components.indicator(indicators.bridge, indicator_x + indicator_width + indicator_gap, box.y + 5, indicator_width)
  components.indicator(indicators.engineer, indicator_x + (indicator_width + indicator_gap) * 2, box.y + 5, indicator_width)
end

function components.metric(label, value, x, y, width, tone)
  components.label(label, x, y, theme.color("muted"))
  components.value(value, x, y + 15, theme.tone(tone or "info"))
  if width ~= nil then
    csp.line(x, y + 43, x + width, y + 43, theme.color("border"), 1)
  end
end

function components.progress(x, y, width, ratio, active_tone)
  local safe_ratio = type(ratio) == "number" and math.max(0, math.min(1, ratio)) or 0
  if not csp.has("drawRectFilled") then
    return
  end
  csp.rect(x, y, width, 5, theme.color("surface_alt"), 3)
  if safe_ratio > 0 then
    csp.rect(x, y, width * safe_ratio, 5, theme.tone(active_tone or "info"), 3)
  end
end

function components.button(label, x, y, width, tone)
  local color = theme.tone(tone or "info")
  if csp.has("drawRectFilled") then
    csp.rect(x, y, width, 24, theme.color("surface_alt"), 5)
  end
  if csp.has("drawRect") then
    csp.outline(x, y, width, 24, color, 5, 1)
  end
  csp.text_aligned(label, x + 4, y + 4, width - 8, color)
  if not csp.has("invisibleButton") or not csp.has("setCursorScreenPos") then
    return false
  end
  local clicked = csp.invisible_button_at(label, x, y, width, 24)
  return clicked
end

function components.status_line(label, value, x, y, width, tone, icon)
  if icon ~= nil then
    icons.draw(icon, x, y + 1, 14, theme.tone(tone or "info"))
    x = x + 20
  end
  components.label(label, x, y, theme.color("muted"))
  components.value(value, x + width * 0.42, y, theme.tone(tone or "info"))
end

function components.section_title(text, box, tone)
  csp.text_at(text, box.x + 10, box.y + 8, theme.tone(tone or "info"))
end

function components.safe_text(text, x, y, width, color)
  local safe = tostring(text or "UNAVAILABLE")
  if type(width) == "number" and width > 0 then
    local max_chars = math.max(1, math.floor(width / 7))
    if #safe > max_chars then
      local short = {
        ["Waiting for representative lap"] = "WARMING",
        ["No reliable future forecast"] = "NO FORECAST",
        ["No active instruction"] = "NO ACTION",
        ["Not configured"] = "NOT SET",
        ["Pit entry not calibrated"] = "NOT CALIBRATED",
        ["High confidence"] = "HIGH",
        ["Medium confidence"] = "MEDIUM",
        ["Low confidence"] = "LOW",
      }
      safe = short[safe] or string.sub(safe, 1, max_chars)
    end
  end
  csp.text_aligned(safe, x, y, width, color or theme.color("text"))
end

namespace.ui.components = components
