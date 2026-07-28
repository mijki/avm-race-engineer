local namespace = _G.AVM_PITWALL_F1
local native = namespace.runtime.native
local fallback = {}

function fallback.render(stage, detail)
  return native.draw_recovery(stage, detail)
end

namespace.ui.fallback = fallback
