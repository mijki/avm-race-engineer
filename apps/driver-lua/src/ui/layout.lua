local namespace = _G.AVM_PITWALL_F1
local layout = {}

local function card(x, y, width, height)
  return { x = x, y = y, width = width, height = height }
end

local function safe_size(value, fallback)
  return type(value) == "number" and value > 0 and value or fallback
end

local function fit_heights(total, first_ratio, first_min, second_ratio, second_min, third_min, gap)
  local available = math.max(first_min + second_min + third_min, total - gap * 2)
  local first = math.max(first_min, available * first_ratio)
  local second = math.max(second_min, available * second_ratio)
  if first + second > available - third_min then
    local scale = math.max(0, (available - third_min) / math.max(1, first + second))
    first = math.max(first_min, first * scale)
    second = math.max(second_min, second * scale)
  end
  local third = math.max(third_min, available - first - second)
  local overflow = first + second + third - available
  if overflow > 0 then
    third = math.max(1, third - overflow)
  end
  return first, second, third
end

function layout.for_mode(width, height, mode, critical)
  width = safe_size(width, 780)
  height = safe_size(height, 380)
  local gap = 6
  local outer = { x = 8, y = 8, width = math.max(300, width - 16), height = math.max(180, height - 16) }
  local header_height = mode == "garage" and 48 or 44
  local banner_height = critical and 56 or 38
  local footer_height = mode == "garage" and 32 or 26
  local content_y = outer.y + header_height + gap + banner_height + gap
  local content_height = math.max(70, outer.height - header_height - banner_height - footer_height - gap * 4)
  local content_width = outer.width
  local result = { outer = outer, header = card(outer.x, outer.y, outer.width, header_height), banner = card(outer.x, outer.y + header_height + gap, outer.width, banner_height), footer = card(outer.x, outer.y + outer.height - footer_height, outer.width, footer_height), cards = {} }

  if mode == "compact" then
    local weather_height = math.max(24, math.min(54, content_height * 0.27))
    local grid_height = math.max(2, content_height - weather_height - gap)
    local row_height = math.max(1, (grid_height - gap) / 2)
    local column_width = (content_width - gap) / 2
    result.cards.fuel = card(outer.x, content_y, column_width, row_height)
    result.cards.pace = card(outer.x + column_width + gap, content_y, column_width, row_height)
    result.cards.tyres = card(outer.x, content_y + row_height + gap, column_width, row_height)
    result.cards.pit = card(outer.x + column_width + gap, content_y + row_height + gap, column_width, row_height)
    result.cards.weather = card(outer.x, content_y + grid_height + gap, content_width, weather_height)
  elseif mode == "expanded" then
    local top_height, middle_height, bottom_height = fit_heights(content_height, 0.28, 24, 0.34, 30, 20, gap)
    local column_width = (content_width - gap) / 2
    result.cards.timing = card(outer.x, content_y, column_width, top_height)
    result.cards.message = card(outer.x + column_width + gap, content_y, column_width, top_height)
    local middle_y = content_y + top_height + gap
    local cell_width = (content_width - gap * 3) / 4
    result.cards.fuel = card(outer.x, middle_y, cell_width, middle_height)
    result.cards.pace = card(outer.x + cell_width + gap, middle_y, cell_width, middle_height)
    result.cards.tyres = card(outer.x + (cell_width + gap) * 2, middle_y, cell_width, middle_height)
    result.cards.pit = card(outer.x + (cell_width + gap) * 3, middle_y, cell_width, middle_height)
    local bottom_y = middle_y + middle_height + gap
    result.cards.weather = card(outer.x, bottom_y, content_width * 0.74, bottom_height)
    result.cards.connections = card(outer.x + content_width * 0.74 + gap, bottom_y, content_width * 0.26 - gap, bottom_height)
  else
    local top_height, row_height, _ = fit_heights(content_height, 0.22, 30, 0.39, 24, 24, gap)
    result.cards.overview = card(outer.x, content_y, outer.width, top_height)
    result.cards.scenarios = card(outer.x, content_y + top_height + gap, outer.width * 0.58, row_height)
    result.cards.settings = card(outer.x + outer.width * 0.58 + gap, content_y + top_height + gap, outer.width * 0.42 - gap, row_height)
    result.cards.diagnostics = card(outer.x, content_y + top_height + row_height + gap * 2, outer.width, row_height)
  end
  return result
end

function layout.intersects(box, width, height)
  return type(box) == "table"
    and box.width > 0
    and box.height > 0
    and box.x < width
    and box.y < height
    and box.x + box.width > 0
    and box.y + box.height > 0
end

function layout.required_boxes(width, height, mode, critical)
  local result = layout.for_mode(width, height, mode, critical)
  local cards = result.cards
  local fallback_width = math.max(160, width - 20)
  local fallback_height = math.max(120, height - 20)
  return {
    header = result.header,
    stint_timing = cards.timing or cards.overview or result.banner,
    fuel = cards.fuel or cards.overview or result.banner,
    weather = cards.weather or cards.overview or result.banner,
    engineer_message = result.banner,
    fallback_shell = { x = 10, y = 10, width = fallback_width, height = fallback_height },
  }
end

namespace.ui.layout = layout
