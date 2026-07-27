local namespace = _G.AVM_PITWALL_F1
local layout = {}

local function card(x, y, width, height)
  return { x = x, y = y, width = width, height = height }
end

local function safe_size(value, fallback)
  return type(value) == "number" and value > 0 and value or fallback
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function contained(box, width, height)
  return layout.intersects(box, width, height)
    and box.x >= 0
    and box.y >= 0
    and box.x + box.width <= width
    and box.y + box.height <= height
end

function layout.for_mode(width, height, mode, critical)
  width = safe_size(width, 780)
  height = safe_size(height, 380)
  local margin = 8
  local gap = 6
  local outer = { x = margin, y = 6, width = math.max(280, width - margin * 2), height = math.max(150, height - 12) }
  local header_height = mode == "garage" and 32 or clamp(height * 0.08, 26, 32)
  local result = {
    outer = outer,
    header = card(outer.x, outer.y, outer.width, header_height),
    banner = nil,
    footer = nil,
    cards = {},
    metrics = { padding = 10, gap = gap, line_height = 14, header_height = header_height },
  }

  if mode == "compact" then
    local footer_height = clamp(height * 0.085, 30, 38)
    local body_y = outer.y + header_height + gap
    local footer_y = outer.y + outer.height - footer_height
    local body_height = math.max(52, footer_y - gap - body_y)
    local primary_height = math.floor((body_height - gap) * 0.58)
    primary_height = clamp(primary_height, 72, math.max(72, body_height - gap - 52))
    local secondary_height = body_height - primary_height - gap
    if secondary_height < 52 then
      secondary_height = 52
      primary_height = math.max(42, body_height - secondary_height - gap)
    end
    local primary_width = (outer.width - gap * 2) / 3
    local secondary_width = (outer.width - gap) / 2
    result.cards.fuel = card(outer.x, body_y, primary_width, primary_height)
    result.cards.pace = card(outer.x + primary_width + gap, body_y, primary_width, primary_height)
    result.cards.pit = card(outer.x + (primary_width + gap) * 2, body_y, primary_width, primary_height)
    local secondary_y = body_y + primary_height + gap
    result.cards.tyres = card(outer.x, secondary_y, secondary_width, secondary_height)
    result.cards.weather = card(outer.x + secondary_width + gap, secondary_y, secondary_width, secondary_height)
    result.footer = card(outer.x, footer_y, outer.width, footer_height)
    result.banner = result.footer
    result.cards.engineer = result.footer
    result.cards.message = result.footer
  elseif mode == "expanded" then
    local body_y = outer.y + header_height + gap
    local body_height = math.max(110, outer.y + outer.height - body_y)
    local row_gap = gap
    local row_height = math.max(24, (body_height - row_gap * 4) / 5)
    local left_card_height = math.max(24, (body_height - row_gap * 2) / 3)
    local left_width = outer.width * 0.43
    local right_x = outer.x + left_width + gap
    local right_width = outer.width - left_width - gap
    result.cards.timing = card(right_x, body_y, right_width, row_height)
    result.cards.message = card(right_x, body_y + row_height + row_gap, right_width, row_height)
    result.cards.tyres = card(right_x, body_y + (row_height + row_gap) * 2, right_width, row_height)
    result.cards.weather = card(right_x, body_y + (row_height + row_gap) * 3, right_width, row_height)
    result.cards.connections = card(right_x, body_y + (row_height + row_gap) * 4, right_width, row_height)
    result.cards.fuel = card(outer.x, body_y, left_width, left_card_height)
    result.cards.pace = card(outer.x, body_y + left_card_height + row_gap, left_width, left_card_height)
    result.cards.pit = card(outer.x, body_y + (left_card_height + row_gap) * 2, left_width, left_card_height)
  else
    local body_y = outer.y + header_height + gap
    local overview_height = 50
    local controls_y = body_y + overview_height + gap
    local controls_height = 86
    local diagnostics_y = controls_y + controls_height + gap
    local diagnostics_height = math.max(52, outer.y + outer.height - diagnostics_y)
    result.cards.overview = card(outer.x, body_y, outer.width, overview_height)
    result.cards.scenarios = card(outer.x, controls_y, outer.width * 0.58, controls_height)
    result.cards.settings = card(outer.x + outer.width * 0.58 + gap, controls_y, outer.width * 0.42 - gap, controls_height)
    result.cards.diagnostics = card(outer.x, diagnostics_y, outer.width, diagnostics_height)
  end
  return result
end

function layout.intersects(box, width, height)
  return type(box) == "table"
    and type(width) == "number"
    and type(height) == "number"
    and type(box.x) == "number"
    and type(box.y) == "number"
    and type(box.width) == "number"
    and type(box.height) == "number"
    and box.x == box.x
    and box.y == box.y
    and box.width == box.width
    and box.height == box.height
    and box.width > 0
    and box.height > 0
    and box.x < width
    and box.y < height
    and box.x + box.width > 0
    and box.y + box.height > 0
end

function layout.valid(boxes, width, height, mode, critical)
  if type(boxes) ~= "table" or type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
    return false
  end
  for _, box in pairs(boxes) do
    if type(box) == "table" and box.x ~= nil and not contained(box, width, height) then
      return false
    end
  end
  if type(boxes.cards) == "table" then
    local unique_cards = {}
    for _, box in pairs(boxes.cards) do
      if not contained(box, width, height) then return false end
      local seen = false
      for index = 1, #unique_cards do
        if unique_cards[index] == box then seen = true; break end
      end
      if not seen then unique_cards[#unique_cards + 1] = box end
    end
    for left_index = 1, #unique_cards do
      local left = unique_cards[left_index]
      for right_index = left_index + 1, #unique_cards do
        local right = unique_cards[right_index]
        if left.x < right.x + right.width and right.x < left.x + left.width and left.y < right.y + right.height and right.y < left.y + left.height then
          return false
        end
      end
    end
  end
  return true
end

function layout.required_boxes(width, height, mode, critical)
  local result = layout.for_mode(width, height, mode, critical)
  local cards = result.cards
  local fallback_width = math.max(160, width - 20)
  local fallback_height = math.max(120, height - 20)
  return {
    header = result.header,
    stint_timing = cards.timing or cards.overview or result.header,
    fuel = cards.fuel or cards.overview or result.header,
    weather = cards.weather or cards.overview or result.header,
    engineer_message = cards.engineer or cards.message or result.banner or result.header,
    fallback_shell = { x = 10, y = 10, width = fallback_width, height = fallback_height },
  }
end

namespace.ui.layout = layout
