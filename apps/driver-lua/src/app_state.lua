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
  runtime_config = nil,
  pit_marker_loaded = false,
}

local function effective_config(settings)
  local result = {}
  for key, value in pairs(config) do result[key] = value end
  result.targets = {}
  for key, value in pairs(config.targets or {}) do result.targets[key] = value end
  local saved = settings and settings.targets
  if type(saved) == "table" then
    for key, value in pairs(saved) do result.targets[key] = value end
  end
  return result
end

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
  state.pit_marker_loaded = false
  if state.live.identity ~= nil then
    telemetry.set_calibration(state.live, storage.load_calibration(state.live.identity))
  end
end

function state.initialize(settings_override)
  if state.initialized then return state end
  state.settings = settings_override or storage.load()
  if type(state.settings) ~= "table" then state.settings = storage.defaults() end
  state.runtime_config = effective_config(state.settings)
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
  local status = telemetry.update(state.live, state.clock, state.runtime_config or config)
  if state.live.latest and not state.pit_marker_loaded then
    local stored_marker = storage.load_pit_marker(state.live.identity)
    telemetry.set_pit_marker(state.live, stored_marker)
    state.pit_marker_loaded = true
  end
  if state.live.pit_marker and state.live.pit_marker_dirty == true then
    storage.save_pit_marker(state.live.identity, state.live.pit_marker)
    state.live.pit_marker_dirty = false
  end
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

function state.set_target(self, name, value)
  if self.mode ~= "garage" or type(name) ~= "string" then return false end
  local limits = {
    pace_s = { minimum = 1, maximum = 1000 },
    fuel_per_lap_l = { minimum = 0.01, maximum = 100 },
    stint_minutes = { minimum = 1, maximum = 1440 },
    planned_pit_lap = { minimum = 1, maximum = 10000 },
  }
  local limit = limits[name]
  if limit == nil or (value ~= nil and (type(value) ~= "number" or value < limit.minimum or value > limit.maximum)) then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  self.runtime_config.targets[name] = value
  self.settings.targets = self.settings.targets or {}
  self.settings.targets[name] = value
  self.save_settings()
  self.latest_status = nil
  self.view_models = {}
  return true
end

function state.set_pressure_unit(self, unit)
  if self.mode ~= "garage" or (unit ~= "psi" and unit ~= "kPa") then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  self.runtime_config.targets.pressure_unit = unit
  self.settings.targets = self.settings.targets or {}
  self.settings.targets.pressure_unit = unit
  self.save_settings()
  return true
end

function state.set_pressure_target(self, compound, wheel, value)
  if self.mode ~= "garage" or type(compound) ~= "string" or type(wheel) ~= "string" then return false end
  if value ~= nil and (type(value) ~= "number" or value < 1 or value > 100) then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  local targets = self.runtime_config.targets.pressure_targets_psi
  if type(targets) ~= "table" then targets = {}; self.runtime_config.targets.pressure_targets_psi = targets end
  targets[compound] = targets[compound] or {}
  if type(targets[compound]) ~= "table" then targets[compound] = {} end
  targets[compound][wheel] = value
  self.settings.targets = self.settings.targets or {}
  self.settings.targets.pressure_targets_psi = targets
  self.save_settings()
  self.latest_status = nil
  self.view_models = {}
  return true
end

function state.set_temperature_target(self, compound, wheel, value)
  if self.mode ~= "garage" or type(compound) ~= "string" or type(wheel) ~= "string" then return false end
  if value ~= nil and (type(value) ~= "number" or value < -50 or value > 250) then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  local targets = self.runtime_config.targets.temperature_targets_c
  if type(targets) ~= "table" then targets = {}; self.runtime_config.targets.temperature_targets_c = targets end
  targets[compound] = targets[compound] or {}
  if type(targets[compound]) ~= "table" then targets[compound] = {} end
  targets[compound][wheel] = value
  self.settings.targets = self.settings.targets or {}
  self.settings.targets.temperature_targets_c = targets
  self.save_settings()
  self.latest_status = nil
  self.view_models = {}
  return true
end

function state.set_comparison_threshold(self, name, value)
  if self.mode ~= "garage" or type(name) ~= "string" or type(value) ~= "number" then return false end
  local limits = {
    pace_delta_threshold_s = { minimum = 0.01, maximum = 10 },
    fuel_comparison_threshold_l = { minimum = 0.01, maximum = 10 },
    pressure_delta_threshold_psi = { minimum = 0.01, maximum = 20 },
    temperature_delta_threshold_c = { minimum = 0.1, maximum = 100 },
  }
  local limit = limits[name]
  if limit == nil or value < limit.minimum or value > limit.maximum then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  self.runtime_config.targets[name] = value
  self.settings.targets = self.settings.targets or {}
  self.settings.targets[name] = value
  self.save_settings()
  self.latest_status = nil
  self.view_models = {}
  return true
end

function state.set_strategy_profile(self, profile)
  if self.mode ~= "garage" or (profile ~= nil and (type(profile) ~= "string" or #profile > 64)) then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  self.runtime_config.targets.strategy_profile = profile
  self.settings.targets = self.settings.targets or {}
  self.settings.targets.strategy_profile = profile
  self.save_settings()
  return true
end

function state.set_endurance_rule(self, name, value)
  if self.mode ~= "garage" or type(name) ~= "string" then return false end
  local numeric_rules = {
    maximum_driver_stint_minutes = true,
    max_continuous_driving_minutes = true,
    minimum_rest_minutes = true,
    minimum_fuel_l = true,
    maximum_fuel_l = true,
    required_pit_stops = true,
  }
  local boolean_rules = { mandatory_driver_change = true, mandatory_tyre_rules = true }
  if numeric_rules[name] and (type(value) ~= "number" or value < 0) then return false end
  if boolean_rules[name] and type(value) ~= "boolean" then return false end
  if not numeric_rules[name] and not boolean_rules[name] then return false end
  self.runtime_config = self.runtime_config or effective_config(self.settings)
  if type(self.runtime_config.targets.endurance_rules) ~= "table" then self.runtime_config.targets.endurance_rules = {} end
  self.runtime_config.targets.endurance_rules[name] = value
  self.settings.targets = self.settings.targets or {}
  self.settings.targets.endurance_rules = self.runtime_config.targets.endurance_rules
  self.save_settings()
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
  if self.mode ~= "garage" or self.live == nil or type(self.live.calibration_capture_armed_until) ~= "number" or self.clock > self.live.calibration_capture_armed_until then return false end
  if snapshot == nil or snapshot.car == nil or (snapshot.car.speed_kmh or math.huge) > config.calibration_speed_limit_kmh then return false end
  local length = snapshot.session and snapshot.session.track_length_m
  local spline = snapshot.car.spline
  if type(length) ~= "number" or length <= 0 or type(spline) ~= "number" or spline < 0 or spline >= 1 then return false end
  local identity = self.live.identity
  if type(identity) ~= "table" or identity.track_id == nil or identity.layout_id == nil then return false end
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
  self.live.calibration_capture_armed_until = nil
  return true
end

function state.arm_calibration(self)
  local snapshot = self.live and self.live.latest
  if self.mode ~= "garage" or snapshot == nil or snapshot.car == nil or (snapshot.car.speed_kmh or math.huge) > config.calibration_speed_limit_kmh then return false end
  self.live.calibration_capture_armed_until = self.clock + config.calibration_arm_timeout_s
  return true
end

function state.reset_calibration(self)
  if self.live and self.live.identity then storage.reset_calibration(self.live.identity) end
  if self.live then self.live.calibration = nil end
  return true
end

state.clear_calibration = state.reset_calibration

function state.validate_calibration(self)
  local snapshot = self.live and self.live.latest
  return namespace.live.track_model.validate(self.live and self.live.calibration, snapshot and snapshot.identity)
end

function state.test_pit_distance(self)
  local snapshot = self.live and self.live.latest
  if snapshot == nil then return nil, "SOURCE_UNAVAILABLE" end
  local calibration = self.live.calibration or namespace.live.pit_learning.calibration(self.live.pit, snapshot)
  return namespace.live.track_model.distance_to_pit(snapshot, calibration)
end

function state.set_pit_marker_override(self, entry_spline, exit_spline)
  local snapshot = self.live and self.live.latest
  if self.mode ~= "garage" or snapshot == nil or snapshot.identity == nil then return false end
  if type(entry_spline) ~= "number" or entry_spline < 0 or entry_spline >= 1 then return false end
  if exit_spline ~= nil and (type(exit_spline) ~= "number" or exit_spline < 0 or exit_spline >= 1) then return false end
  local marker = self.live.pit_marker or {}
  marker.track_layout_key = namespace.contracts.track_layout_key(snapshot.identity)
  marker.track_id = snapshot.identity.track_id
  marker.layout_id = snapshot.identity.layout_id
  marker.entry_spline = entry_spline
  marker.exit_spline = exit_spline
  marker.state = "MANUAL_OVERRIDE"
  marker.manual_override = true
  marker.source = "MANUAL_OVERRIDE"
  marker.schema_version = "pit-marker-record-v1"
  marker.accepted_observations = marker.accepted_observations or {}
  marker.rejected_observations = marker.rejected_observations or {}
  marker.timing = marker.timing or {}
  self.live.pit_marker = namespace.live.pit_learning.manual_override(self.live.pit, marker)
  storage.save_pit_marker(self.live.identity, self.live.pit_marker)
  return true
end

function state.clear_pit_marker_override(self)
  if self.live == nil then return false end
  local changed = namespace.live.pit_learning.clear_override(self.live.pit)
  self.live.pit_marker = self.live.pit.marker
  if changed then storage.save_pit_marker(self.live.identity, self.live.pit_marker) end
  return changed
end

function state.reset_pit_learning(self)
  if self.live == nil then return false end
  if self.live.identity then storage.reset_pit_marker(self.live.identity) end
  self.live.pit_marker = nil
  self.live.pit = namespace.live.pit_learning.new(self.runtime_config or config)
  self.live.pit_marker_dirty = false
  self.pit_marker_loaded = true
  return true
end

state.set_pit_override = state.set_pit_marker_override
state.clear_pit_override = state.clear_pit_marker_override
state.return_to_automatic_learning = state.clear_pit_marker_override

function state.inject_engineer_message(self, title, detail, priority, requires_acknowledgement)
  if self.mode ~= "garage" or self.live == nil then return false end
  local message_id = "garage:" .. tostring(self.clock)
  self.live.injected_engineer_message = {
    message_id = message_id,
    source = "GARAGE_TEST",
    severity = (priority or 8) <= 2 and "critical" or "info",
    title = tostring(title or "ENGINEER TEST"),
    detail = tostring(detail or "Garage-injected message"),
    created_s = self.clock,
    expiry_s = nil,
    priority = priority or 8,
    requires_acknowledgement = requires_acknowledgement == true,
    acknowledged = false,
  }
  self.latest_status = nil
  self.view_models = {}
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
  if state.live and state.live.engineer_active and state.live.engineer_active.requires_acknowledgement then
    state.live.engineer_active.acknowledged = true
    return true
  end
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
  state.runtime_config = nil
  state.pit_marker_loaded = false
end

namespace.app_state = state
