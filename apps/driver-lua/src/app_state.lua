local namespace = _G.AVM_PITWALL_F1
local config = namespace.config
local telemetry = namespace.live.telemetry
local live_mock = namespace.live.mock_scenarios
local legacy_mock = namespace.mock_scenarios
local storage = namespace.adapters.storage
local view_model = namespace.view_model
local state = {
  initialized = false,
  dirty = true,
  clock = 0,
  mode = config.default_mode,
  source_mode = config.default_source_mode,
  mock_scenario = "baseline",
  scenario_id = config.default_scenario,
  settings = {},
  envelope = nil,
  live = nil,
  latest_status = nil,
  view_models = {},
  alerts = nil,
  scenario_history = {},
}

local function known_legacy_scenario(id)
  local ids = legacy_mock.list()
  for index = 1, #ids do
    if ids[index] == id then return true end
  end
  return false
end

local function load_legacy_scenario(id)
  state.scenario_id = known_legacy_scenario(id) and id or config.default_scenario
  state.envelope = legacy_mock.load(state.scenario_id)
  state.scenario_history[#state.scenario_history + 1] = state.scenario_id
  while #state.scenario_history > config.max_scenario_history do
    table.remove(state.scenario_history, 1)
  end
end

local function set_live_source()
  state.source_mode = "live"
  state.live = telemetry.new(config)
  telemetry.set_source_mode(state.live, "live")
  if state.live.identity ~= nil then
    telemetry.set_calibration(state.live, storage.load_calibration(state.live.identity))
  end
end

function state.initialize(settings_override)
  if state.initialized then return state end
  state.settings = settings_override or storage.load()
  if type(state.settings) ~= "table" then state.settings = storage.defaults() end
  state.mode = state.settings.mode or config.default_mode
  if state.mode ~= "compact" and state.mode ~= "expanded" and state.mode ~= "garage" then
    state.mode = config.default_mode
  end
  state.source_mode = config.default_source_mode
  state.mock_scenario = "baseline"
  load_legacy_scenario(state.settings.scenario or config.default_scenario)
  state.alerts = namespace.alert_state.new()
  if state.envelope and state.envelope.engineer_message then
    namespace.alert_state.ingest(state.alerts, state.envelope.engineer_message, state.clock)
  end
  set_live_source()
  state.initialized = true
  return state
end

function state.ensure(settings_override)
  return state.initialize(settings_override)
end

function state.update(dt)
  state.initialize()
  local delta = type(dt) == "number" and math.max(0, math.min(dt, 0.25)) or 0.016
  state.clock = state.clock + delta
  local status = telemetry.update(state.live, state.clock, config)
  if state.live.latest and state.live.calibration == nil then
    state.live.calibration = storage.load_calibration(state.live.identity)
    telemetry.set_calibration(state.live, state.live.calibration)
  end
  state.latest_status = status
  state.view_models.compact = view_model.reduce(status, "compact")
  state.view_models.expanded = view_model.reduce(status, "expanded")
  state.view_models.garage = view_model.reduce(status, "garage")
  state.dirty = false
  return status
end

function state.get_view_model(mode)
  state.initialize()
  local chosen = mode or state.mode
  if state.view_models[chosen] ~= nil then return state.view_models[chosen] end
  local status = state.latest_status or namespace.live.status_builder.recovery(state.source_mode, "SOURCE_UNAVAILABLE", state.live)
  state.view_models[chosen] = view_model.reduce(status, chosen)
  return state.view_models[chosen]
end

function state.set_mode(mode)
  if mode ~= "compact" and mode ~= "expanded" and mode ~= "garage" then return false end
  state.mode = mode
  state.settings.mode = mode
  state.dirty = true
  state.save_settings()
  return true
end

function state.set_source_mode(self, value)
  if self.mode ~= "garage" then return false end
  if value ~= "live" then return false end
  set_live_source()
  self.latest_status = nil
  self.view_models = {}
  return true
end

function state.set_mock_scenario(self, name)
  if self.mode ~= "garage" then return false end
  local fixture = live_mock.get(name)
  if fixture == nil then return false end
  self.mock_scenario = name
  self.source_mode = "mock"
  self.live = telemetry.new(config)
  telemetry.set_source_mode(self.live, "mock", fixture)
  self.latest_status = nil
  self.view_models = {}
  return true
end

function state.set_scenario(id)
  if state.mode ~= "garage" or not known_legacy_scenario(id) then return false end
  load_legacy_scenario(id)
  state.settings.scenario = state.scenario_id
  state.save_settings()
  -- Legacy scenarios remain a Garage-only catalog. They never become a
  -- recovery fallback for a failed live source; selecting one explicitly
  -- enters the bounded baseline mock source for diagnostics.
  return state.set_mock_scenario(state, "baseline")
end

function state.capture_calibration(self)
  local snapshot = self.live and self.live.latest
  if snapshot == nil or snapshot.car == nil or (snapshot.car.speed_kmh or math.huge) > config.calibration_speed_limit_kmh then return false end
  local length = snapshot.session and snapshot.session.track_length_m
  local spline = snapshot.car.spline
  if type(length) ~= "number" or length <= 0 or type(spline) ~= "number" or spline < 0 or spline >= 1 then return false end
  local identity = self.live.identity
  self.live.calibration = {
    track_id = identity.track_id,
    layout_id = identity.layout_id,
    track_length_m = length,
    pit_entry_spline = spline,
    pit_route_additional_m = 0,
    source = "garage_capture",
    last_modified = self.clock,
    validation_status = "valid",
  }
  storage.save_calibration(identity, self.live.calibration)
  return true
end

function state.reset_calibration(self)
  if self.live and self.live.identity then storage.reset_calibration(self.live.identity) end
  if self.live then self.live.calibration = nil end
  return true
end

function state.set_pit_route_additional_distance(self, distance_m)
  local snapshot = self.live and self.live.latest
  if self.mode ~= "garage" or snapshot == nil or snapshot.car == nil or (snapshot.car.speed_kmh or math.huge) > config.calibration_speed_limit_kmh then return false end
  if self.live.calibration == nil or type(distance_m) ~= "number" or distance_m < 0 or distance_m > 5000 then return false end
  self.live.calibration.pit_route_additional_m = distance_m
  storage.save_calibration(self.live.identity, self.live.calibration)
  return true
end

function state.save_settings()
  return storage.save(state.settings)
end

function state.acknowledge()
  local active = namespace.alert_state.active(state.alerts)
  if active == nil then return false end
  local changed = namespace.alert_state.acknowledge(state.alerts, active.alert_id, state.clock)
  if changed then namespace.adapters.audio.play("ack", state.settings.sound_enabled, state.settings.sound_volume) end
  return changed
end

function state.repeat_latest()
  local active = namespace.alert_state.active(state.alerts)
  if active == nil then return false end
  active.last_delivered_at = state.clock
  namespace.adapters.audio.play(active.sound_kind or "info", state.settings.sound_enabled, state.settings.sound_volume)
  return true
end

function state.test_sound(kind)
  return namespace.adapters.audio.test(kind or "info", state.settings)
end

function state.reset_for_test()
  state.initialized = false
  state.dirty = true
  state.clock = 0
  state.live = nil
  state.latest_status = nil
  state.view_models = {}
  state.settings = {}
  state.source_mode = config.default_source_mode
  state.mode = config.default_mode
end

namespace.app_state = state
