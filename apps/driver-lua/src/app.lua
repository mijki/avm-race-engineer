local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local layout = namespace.ui.layout
local compact = namespace.ui.compact
local expanded = namespace.ui.expanded
local garage = namespace.ui.garage
local fallback = namespace.ui.fallback
local app = {}

local function stage(state, name, callback)
  local ok, error_value = pcall(callback)
  if not ok then
    state.last_failure_stage = name
    state.last_failure = tostring(error_value)
    return false
  end
  return true
end

local function draw_header(vm, boxes, state)
  local header = boxes.header
  csp.rect(header.x, header.y, header.width, header.height, theme.color("surface"), 7)
  csp.outline(header.x, header.y, header.width, header.height, theme.color("border"), 7, 1)
  csp.text_at("AVM", header.x + 12, header.y + 7, theme.color("text"))
  csp.text_at("PitWall", header.x + 50, header.y + 7, theme.color("cyan"))
  csp.text_at(vm.session_name, header.x + 126, header.y + 9, theme.color("text"))
  csp.text_at("STINT  " .. vm.stint .. " / " .. vm.total_stints, header.x + header.width * 0.58, header.y + 9, theme.color("green"))
  csp.text_at("LAP  " .. vm.lap .. " / " .. vm.planned_lap, header.x + header.width * 0.76, header.y + 9, theme.color("text"))
  namespace.ui.components.progress(header.x + 12, header.y + header.height - 10, header.width - 24, vm.progress, "green")
end

local function draw_banner(vm, boxes, state)
  local banner = boxes.banner
  local critical = vm.alert.priority == "critical"
  local tone = critical and "critical" or vm.alert.priority == "high" and "warning" or "info"
  csp.rect(banner.x, banner.y, banner.width, banner.height, theme.color(critical and "red" or "surface_alt", critical and 0.16 or 1), 7)
  csp.outline(banner.x, banner.y, banner.width, banner.height, theme.tone(tone), critical and 2 or 1, 1)
  namespace.ui.icons.draw(critical and "critical" or "flag", banner.x + 10, banner.y + 10, 24, theme.tone(tone))
  csp.text_at(vm.alert.text, banner.x + 44, banner.y + 8, theme.tone(tone))
  csp.text_aligned(vm.alert.detail, banner.x + 44, banner.y + 29, banner.width - 150, theme.color("text"))
  if vm.alert.requires_acknowledgement or vm.alert.status == "ACKNOWLEDGED" then
    local ack_label = vm.alert.status == "ACKNOWLEDGED" and "ACKED" or "ACK"
    if namespace.ui.components.button(ack_label, banner.x + banner.width - 92, banner.y + 12, 78, vm.alert.status == "ACKNOWLEDGED" and "good" or "critical") and vm.alert.status ~= "ACKNOWLEDGED" then
      namespace.app_state.acknowledge()
    end
  elseif banner.height >= 46 then
    if namespace.ui.components.button("REPEAT", banner.x + banner.width - 92, banner.y + 12, 78, "info") then
      namespace.app_state.repeat_latest()
    end
  end
end

local function draw_footer(vm, boxes, state)
  local footer = boxes.footer
  csp.rect(footer.x, footer.y, footer.width, footer.height, theme.color("black"), 5)
  namespace.ui.icons.draw(vm.connection_tone == "live" and "engineer" or "offline", footer.x + 8, footer.y + 5, 14, theme.tone(vm.connection_tone))
  csp.text_at("Engineer: " .. vm.connections.engineer, footer.x + 28, footer.y + 7, theme.color("muted"))
  namespace.ui.icons.draw(vm.connection_tone == "live" and "bridge" or "stale", footer.x + footer.width * 0.37, footer.y + 5, 14, theme.tone(vm.connection_tone))
  csp.text_at("Bridge: " .. vm.connections.bridge, footer.x + footer.width * 0.37 + 20, footer.y + 7, theme.color("muted"))
  csp.text_at("Telemetry: " .. vm.connections.telemetry, footer.x + footer.width * 0.70, footer.y + 7, theme.tone(vm.connection_tone))
end

function app.windowMain(dt)
  local state = namespace.app_state.ensure()
  namespace.app_state.update(dt)
  local vm = namespace.app_state.get_view_model(state.mode)
  local width, height = csp.window_size()
  local boxes = layout.for_mode(width, height, state.mode, vm.alert.priority == "critical")
  csp.rect(0, 0, width, height, theme.color("background"), 0)
  local shell_ok = stage(state, "shell", function()
    draw_header(vm, boxes, state)
    draw_banner(vm, boxes, state)
    draw_footer(vm, boxes, state)
  end)
  if not shell_ok then
    fallback.render(state.last_failure_stage, state.last_failure)
    return
  end
  local mode_ok = stage(state, "mode_" .. state.mode, function()
    if state.mode == "expanded" then
      expanded.render(vm, boxes)
    elseif state.mode == "garage" then
      garage.render(vm, boxes, state)
    else
      compact.render(vm, boxes)
    end
  end)
  if not mode_ok then
    fallback.render(state.last_failure_stage, state.last_failure)
  end
end

function app.reset_for_test()
  namespace.app_state.initialized = false
  namespace.app_state.dirty = true
end

namespace.app = app
_G.windowMain = function(dt)
  return namespace.app.windowMain(dt)
end
