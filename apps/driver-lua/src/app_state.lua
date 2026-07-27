local namespace = _G.AVM_PITWALL_F1
local state = {
  initialized = false,
  dirty = true,
  clock = 0,
  mode = "compact",
  scenario_id = "NORMAL_ON_PLAN_DRY",
  settings = {},
  envelope = nil,
  alerts = nil,
  view_models = {},
  scenario_history = {},
}

local function known_scenario(id)
  local ids = namespace.mock_scenarios.list()
  for index = 1, #ids do
    if ids[index] == id then
      return true
    end
  end
  return false
end

local function seed_alerts()
  state.alerts = namespace.alert_state.new()
  if state.envelope ~= nil and state.envelope.engineer_message ~= nil then
    namespace.alert_state.ingest(state.alerts, state.envelope.engineer_message, state.clock)
  end
end

local function load_scenario(id)
  state.scenario_id = known_scenario(id) and id or namespace.config.default_scenario
  state.envelope = namespace.mock_scenarios.load(state.scenario_id)
  seed_alerts()
  state.scenario_history[#state.scenario_history + 1] = state.scenario_id
  while #state.scenario_history > namespace.config.max_scenario_history do
    table.remove(state.scenario_history, 1)
  end
  state.dirty = true
end

function state.initialize(settings_override)
  if state.initialized then
    return state
  end
  state.settings = settings_override or namespace.adapters.storage.load()
  if type(state.settings) ~= "table" then
    state.settings = namespace.adapters.storage.defaults()
  end
  state.mode = state.settings.mode or namespace.config.default_mode
  if state.mode ~= "compact" and state.mode ~= "expanded" and state.mode ~= "garage" then
    state.mode = namespace.config.default_mode
  end
  load_scenario(state.settings.scenario or namespace.config.default_scenario)
  state.initialized = true
  return state
end

function state.ensure(settings_override)
  return state.initialize(settings_override)
end

function state.update(dt)
  state.initialize()
  state.clock = state.clock + (type(dt) == "number" and math.max(0, math.min(dt, 0.25)) or 0.016)
  local sound = namespace.alert_state.tick(state.alerts, state.clock)
  if sound ~= nil then
    namespace.adapters.audio.play(sound, state.settings.sound_enabled, state.settings.sound_volume)
  end
end

function state.prepare()
  state.initialize()
  if not state.dirty then
    return
  end
  state.view_models.compact = namespace.view_model.reduce(state.envelope, "compact")
  state.view_models.expanded = namespace.view_model.reduce(state.envelope, "expanded")
  state.view_models.garage = namespace.view_model.reduce(state.envelope, "garage")
  state.dirty = false
end

function state.get_view_model(mode)
  state.prepare()
  local chosen = mode or state.mode
  local vm = state.view_models[chosen] or state.view_models.compact
  local active = namespace.alert_state.active(state.alerts)
  if active ~= nil then
    vm.alert.text = active.text
    vm.alert.detail = active.detail or vm.alert.detail
    vm.alert.priority = active.priority
    vm.alert.requires_acknowledgement = active.requires_acknowledgement
    vm.alert.alert_id = active.alert_id
    vm.alert.status = active.status == "acknowledged" and "ACKNOWLEDGED" or active.requires_acknowledgement and "ACK REQUIRED" or "VISIBLE"
    vm.alert.tone = active.priority == "critical" and "critical" or active.priority == "high" and "warning" or "info"
  end
  return vm
end

function state.set_mode(mode)
  if mode ~= "compact" and mode ~= "expanded" and mode ~= "garage" then
    return false
  end
  state.mode = mode
  state.settings.mode = mode
  state.dirty = true
  state.save_settings()
  return true
end

function state.set_scenario(id)
  if not known_scenario(id) then
    return false
  end
  load_scenario(id)
  state.settings.scenario = state.scenario_id
  state.save_settings()
  return true
end

function state.acknowledge()
  local active = namespace.alert_state.active(state.alerts)
  if active == nil then
    return false
  end
  local changed, result = namespace.alert_state.acknowledge(state.alerts, active.alert_id, state.clock)
  if changed and result == "acknowledged" then
    namespace.adapters.audio.play("ack", state.settings.sound_enabled, state.settings.sound_volume)
  end
  return changed
end

function state.repeat_latest()
  local active = namespace.alert_state.active(state.alerts)
  if active == nil then
    return false
  end
  active.last_delivered_at = state.clock
  namespace.adapters.audio.play(active.sound_kind or "info", state.settings.sound_enabled, state.settings.sound_volume)
  return true
end

function state.test_sound(kind)
  return namespace.adapters.audio.test(kind or "info", state.settings)
end

function state.save_settings()
  namespace.adapters.storage.save(state.settings)
end

namespace.app_state = state
