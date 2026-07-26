local namespace = _G.AVM_PITWALL_F1
local csp = namespace.adapters.csp
local theme = namespace.ui.theme
local icons = namespace.ui.icons
local fallback = {}

function fallback.render(stage, detail)
  local width, height = csp.window_size()
  csp.rect(0, 0, width, height, theme.color("background"), 0)
  csp.rect(10, 10, width - 20, height - 20, theme.color("surface"), 8)
  csp.outline(10, 10, width - 20, height - 20, theme.color("red"), 8, 2)
  icons.draw("critical", 28, 28, 30, theme.color("red"))
  csp.text_at("AVM PitWall", 70, 28, theme.color("text"))
  csp.text_at("RENDER FAILURE", 28, 78, theme.color("red"))
  csp.text_at("Stage: " .. tostring(stage or "unknown"), 28, 108, theme.color("muted"))
  csp.text_aligned(tostring(detail or "The safe fallback shell is active."), 28, 138, width - 56, theme.color("text"))
  csp.text_aligned("Recover by reopening the app or selecting Garage / Diagnostics.", 28, 170, width - 56, theme.color("muted"))
end

namespace.ui.fallback = fallback
