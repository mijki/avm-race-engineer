local namespace = _G.AVM_PITWALL_F1
if namespace == nil then
  namespace = {}
  _G.AVM_PITWALL_F1 = namespace
end

namespace.version = "1.0.0-f1"
namespace.modules = namespace.modules or {}
namespace.runtime = namespace.runtime or {}
namespace.runtime.initialized = true
