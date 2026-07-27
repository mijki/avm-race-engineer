local namespace = _G.AVM_PITWALL_F1
local csp = {}
local unpack_values = table.unpack or unpack

local function callable(value)
  local value_type = type(value)
  if value_type == "function" or value_type == "userdata" then
    return true
  end
  if value_type == "table" then
    local ok, metatable = pcall(getmetatable, value)
    return ok and metatable ~= nil and metatable.__call ~= nil
  end
  return false
end

local function ui_api()
  local candidate = rawget(_G, "ui")
  local candidate_type = type(candidate)
  if candidate_type == "table" or candidate_type == "userdata" then
    return candidate
  end
  return nil
end

local function member(api, name)
  if api == nil then
    return nil
  end
  local ok, value = pcall(function()
    return api[name]
  end)
  if ok then
    return value
  end
  return nil
end

local function member_type(name)
  local value = member(ui_api(), name)
  if value == nil then
    return "missing"
  end
  return type(value)
end

local function call_ui(name, ...)
  local callback = member(ui_api(), name)
  if callback == nil then
    return "unavailable", nil, "missing member"
  end
  if not callable(callback) then
    return "failed", nil, "member type=" .. type(callback)
  end
  local ok, result = pcall(callback, ...)
  if ok then
    return "drawn", result, nil
  end
  return "failed", nil, tostring(result)
end

local function valid_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function vector_field(vector, field)
  local ok, value = pcall(function()
    return vector[field]
  end)
  return ok and value or nil
end

local function valid_vector(vector)
  if vector == nil then
    return false
  end
  local x = vector_field(vector, "x")
  local y = vector_field(vector, "y")
  return valid_number(x) and valid_number(y)
end

local function construct(name, ...)
  local constructor = rawget(_G, name)
  if constructor == nil then
    return nil
  end
  local ok, result = pcall(constructor, ...)
  if ok and result ~= nil then
    return result
  end
  return nil
end

local function point(x, y)
  local result = construct("vec2", x, y)
  if valid_vector(result) then
    return result
  end
  return nil
end

local function valid_color(value)
  if value == nil then
    return false
  end
  if type(value) ~= "table" then
    return true
  end
  local alpha = value.a
  return valid_number(value.r) and valid_number(value.g) and valid_number(value.b) and valid_number(alpha) and alpha > 0
end

local function record_status(status, name, kind, reason)
  if status == "drawn" then
    namespace.runtime.record_draw(kind or "enhanced")
  else
    namespace.runtime.record_skip(name .. ": " .. tostring(reason or status))
  end
  return status
end

-- The helper above must invoke a draw member once. Keep the status and reason
-- together so a successful protected call is evidence of an emitted call, not
-- an unconditional success returned by the adapter.
local function invoke_draw(name, kind, arguments, reason)
  if reason ~= nil then
    namespace.runtime.record_skip(name .. ": " .. reason)
    return "failed"
  end
  local status, _, detail = call_ui(name, unpack_values(arguments))
  return record_status(status, name, kind, detail)
end

function csp.color(red, green, blue, alpha)
  local safe_alpha = valid_number(alpha) and alpha > 0 and alpha or 1
  local result = construct("rgbm", red, green, blue, safe_alpha)
  if result ~= nil then
    return result
  end
  return { r = red, g = green, b = blue, a = safe_alpha }
end

function csp.point(x, y)
  return point(x, y)
end

local function valid_size(result)
  return result ~= nil
    and valid_number(vector_field(result, "x"))
    and valid_number(vector_field(result, "y"))
    and vector_field(result, "x") > 0
    and vector_field(result, "y") > 0
end

local function size_from(result)
  if valid_size(result) then
    return vector_field(result, "x"), vector_field(result, "y")
  end
  return nil, nil
end

function csp.window_size()
  local status, result = call_ui("availableSpace")
  local width, height = size_from(result)
  if status == "drawn" and width ~= nil then
    return width, height, "availableSpace"
  end

  status, result = call_ui("availableSpaceX")
  local available_width = valid_number(result) and result or nil
  status, result = call_ui("availableSpaceY")
  local available_height = valid_number(result) and result or nil
  if available_width ~= nil and available_height ~= nil and available_width > 0 and available_height > 0 then
    return available_width, available_height, "availableSpaceX/Y"
  end

  status, result = call_ui("windowSize")
  width, height = size_from(result)
  if status == "drawn" and width ~= nil then
    return width, height, "windowSize"
  end

  status, result = call_ui("windowWidth")
  local window_width = valid_number(result) and result or nil
  status, result = call_ui("windowHeight")
  local window_height = valid_number(result) and result or nil
  if window_width ~= nil and window_height ~= nil and window_width > 0 and window_height > 0 then
    return window_width, window_height, "windowWidth/Height"
  end
  return 780, 380, "fallback"
end

function csp.ui_scale()
  local status, result = call_ui("uiScale")
  if status == "drawn" and valid_number(result) and result > 0 then
    return result
  end
  return 1
end

function csp.has(name)
  return callable(member(ui_api(), name))
end

function csp.member_type(name)
  return member_type(name)
end

function csp.capabilities()
  local mandatory_names = { "ui.text" }
  local optional_names = {
    "ui.separator",
    "ui.textColored",
    "ui.windowSize",
    "ui.windowWidth",
    "ui.windowHeight",
    "ui.availableSpace",
    "ui.availableSpaceX",
    "ui.availableSpaceY",
    "ui.windowContentSize",
    "ui.drawText",
    "ui.drawTextClipped",
    "ui.drawRectFilled",
    "ui.drawRect",
    "ui.drawLine",
    "ui.drawCircle",
    "ui.drawCircleFilled",
    "ui.drawTriangleFilled",
    "ui.button",
    "ui.checkbox",
    "ui.setCursorScreenPos",
    "ui.invisibleButton",
  }
  local missing_mandatory = {}
  for index = 1, #mandatory_names do
    local name = mandatory_names[index]
    if not csp.has(string.sub(name, 4)) then
      missing_mandatory[#missing_mandatory + 1] = name
    end
  end
  local missing_optional = {}
  local incompatible_optional = {}
  for index = 1, #optional_names do
    local name = optional_names[index]
    local member_name = string.sub(name, 4)
    if member(ui_api(), member_name) == nil then
      missing_optional[#missing_optional + 1] = name
    elseif not csp.has(member_name) then
      incompatible_optional[#incompatible_optional + 1] = name
    end
  end
  local enhanced_names = {
    "ui.drawText",
    "ui.drawRectFilled",
    "ui.drawRect",
    "ui.drawLine",
    "ui.drawCircle",
    "ui.drawCircleFilled",
    "ui.drawTriangleFilled",
  }
  local enhanced_candidate = true
  for index = 1, #enhanced_names do
    if not csp.has(string.sub(enhanced_names[index], 4)) then
      enhanced_candidate = false
    end
  end
  enhanced_candidate = enhanced_candidate and point(0, 0) ~= nil and construct("rgbm", 1, 1, 1, 1) ~= nil
  local type_names = { "text", "separator", "availableSpace", "windowSize", "drawText", "drawRectFilled" }
  local type_parts = {}
  for index = 1, #type_names do
    local name = type_names[index]
    type_parts[#type_parts + 1] = "ui." .. name .. "=" .. member_type(name)
  end
  namespace.runtime.log_once("csp_api_types_logged", "AVM F1 API types: " .. table.concat(type_parts, " "))
  local required = #missing_mandatory == 0
  return {
    backend = "csp-native",
    required = required,
    level = required and (enhanced_candidate and 2 or 1) or 0,
    -- Presence is only a candidate. app.lua promotes this after real draw
    -- calls succeed in the active window callback.
    enhanced = false,
    enhanced_candidate = enhanced_candidate,
    missing_mandatory = missing_mandatory,
    missing_optional = missing_optional,
    incompatible_optional = incompatible_optional,
    optional_draw_text_clipped = csp.has("drawTextClipped"),
    optional_buttons = csp.has("invisibleButton") and csp.has("setCursorScreenPos"),
  }
end

function csp.text(value)
  local text = type(value) == "string" and value or tostring(value or "")
  local status, _, reason = call_ui("text", text)
  if status == "drawn" then
    namespace.runtime.record_draw("mode_text")
    return status
  end
  namespace.runtime.record_skip("ui.text: " .. tostring(reason or status))
  return status
end

function csp.text_at(value, x, y, color)
  local text = type(value) == "string" and value or tostring(value or "")
  local position = point(x, y)
  if position == nil or not valid_color(color) then
    namespace.runtime.record_skip("ui.drawText: invalid vector or color")
    local fallback_status = csp.text(text)
    if fallback_status == "drawn" then
      namespace.runtime.record_draw("degraded")
      return "degraded"
    end
    return fallback_status
  end
  local status, _, reason = call_ui("drawText", text, position, color)
  if status == "drawn" then
    namespace.runtime.record_draw("enhanced")
    return status
  end
  namespace.runtime.record_skip("ui.drawText: " .. tostring(reason or status))
  local fallback_status = csp.text(text)
  if fallback_status == "drawn" then
    namespace.runtime.record_draw("degraded")
    return "degraded"
  end
  return fallback_status
end

function csp.text_aligned(value, x, y, width, color)
  local text = type(value) == "string" and value or tostring(value or "")
  local left = point(x, y)
  local right = point(x + math.max(1, width), y + 24)
  local alignment = point(0, 0)
  if left ~= nil and right ~= nil and alignment ~= nil and valid_color(color) then
    local status, _, reason = call_ui("drawTextClipped", text, left, right, color, alignment, true)
    if status == "drawn" then
      namespace.runtime.record_draw("enhanced")
      return status
    end
    namespace.runtime.record_skip("ui.drawTextClipped: " .. tostring(reason or status))
  else
    namespace.runtime.record_skip("ui.drawTextClipped: invalid vector or color")
  end
  local fallback_status = csp.text_at(text, x, y, color)
  if fallback_status == "drawn" then
    namespace.runtime.record_draw("degraded")
    return "degraded"
  end
  return fallback_status
end

function csp.rect(x, y, width, height, color, rounding)
  if width == nil or height == nil or width <= 0 or height <= 0 or not valid_color(color) then
    return invoke_draw("drawRectFilled", "enhanced", {}, "invalid bounds or color")
  end
  local first = point(x, y)
  local second = point(x + width, y + height)
  if first == nil or second == nil then
    return invoke_draw("drawRectFilled", "enhanced", {}, "unsupported vector constructor")
  end
  return invoke_draw("drawRectFilled", "enhanced", { first, second, color, rounding or 6 })
end

function csp.outline(x, y, width, height, color, rounding, thickness)
  if width == nil or height == nil or width <= 0 or height <= 0 or not valid_color(color) then
    return invoke_draw("drawRect", "enhanced", {}, "invalid bounds or color")
  end
  local first = point(x, y)
  local second = point(x + width, y + height)
  if first == nil or second == nil then
    return invoke_draw("drawRect", "enhanced", {}, "unsupported vector constructor")
  end
  return invoke_draw("drawRect", "enhanced", { first, second, color, rounding or 6, nil, thickness or 1 })
end

function csp.line(x1, y1, x2, y2, color, thickness)
  local first = point(x1, y1)
  local second = point(x2, y2)
  if first == nil or second == nil or not valid_color(color) or thickness == nil or thickness <= 0 then
    return invoke_draw("ui.drawLine", "enhanced", {}, "invalid vector, color, or thickness")
  end
  return invoke_draw("drawLine", "enhanced", { first, second, color, thickness or 1 })
end

function csp.circle(x, y, radius, color, filled)
  local center = point(x, y)
  local name = filled and "drawCircleFilled" or "drawCircle"
  if center == nil or radius == nil or radius <= 0 or not valid_color(color) then
    return invoke_draw(name, "enhanced", {}, "invalid center, radius, or color")
  end
  local arguments = { center, radius, color, 16 }
  if not filled then
    arguments[5] = 2
  end
  return invoke_draw(name, "enhanced", arguments)
end

function csp.triangle(x1, y1, x2, y2, x3, y3, color)
  local first = point(x1, y1)
  local second = point(x2, y2)
  local third = point(x3, y3)
  if first == nil or second == nil or third == nil or not valid_color(color) then
    return invoke_draw("drawTriangleFilled", "enhanced", {}, "invalid vector or color")
  end
  return invoke_draw("drawTriangleFilled", "enhanced", { first, second, third, color })
end

function csp.button(label, width, height)
  local status, clicked = call_ui("button", label, point(width or 80, height or 24))
  return status == "drawn" and clicked == true
end

function csp.invisible_button_at(label, x, y, width, height)
  local cursor = point(x, y)
  local size = point(width or 80, height or 24)
  if cursor == nil or size == nil then
    namespace.runtime.record_skip("ui.invisibleButton: invalid vector")
    return false
  end
  call_ui("setCursorScreenPos", cursor)
  local status, clicked = call_ui("invisibleButton", label, size)
  return status == "drawn" and clicked == true
end

function csp.checkbox(label, checked)
  local status, clicked = call_ui("checkbox", label, checked == true)
  return status == "drawn" and clicked == true
end

function csp.separator(color)
  if color ~= nil then
    return csp.line(0, 0, 1, 0, color, 1)
  end
  local status, _, reason = call_ui("separator")
  if status == "drawn" then
    namespace.runtime.record_draw("mode_text")
    return status
  end
  namespace.runtime.record_skip("ui.separator: " .. tostring(reason or status))
  local fallback_status = csp.text("--------------------")
  if fallback_status == "drawn" then
    namespace.runtime.record_draw("degraded")
    return "degraded"
  end
  return fallback_status
end

function csp.log(message)
  namespace.runtime.log(message)
end

csp.backend = "csp-native"
namespace.adapters = namespace.adapters or {}
namespace.adapters.csp = csp

-- Live telemetry remains behind the CSP adapter. UI modules only consume the
-- normalized snapshot produced here and never inspect the raw CSP objects.
local telemetry_fixture = nil

local function telemetry_finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function telemetry_field(object, name)
  if object == nil then
    return nil
  end
  local ok, value = pcall(function() return object[name] end)
  if ok and value ~= nil and type(value) ~= "function" then
    return value
  end
  return nil
end

local function telemetry_call(object, name, ...)
  local callback = telemetry_field(object, name)
  if not callable(callback) then
    return nil
  end
  local ok, value = pcall(callback, object, ...)
  return ok and value or nil
end

local function telemetry_first(object, names)
  for index = 1, #names do
    local value = telemetry_field(object, names[index])
    if value ~= nil then
      return value
    end
  end
  return nil
end

local function telemetry_optional_method(object, names)
  for index = 1, #names do
    local value = telemetry_call(object, names[index])
    if value ~= nil then
      return value
    end
  end
  return nil
end

function csp.set_mock_fixture(fixture)
  telemetry_fixture = fixture
end

function csp.clear_mock_fixture()
  telemetry_fixture = nil
end

function csp.normalize(raw, observed_monotonic_s, source_mode)
  if type(raw) ~= "table" then
    return nil, "SOURCE_UNAVAILABLE"
  end
  local identity = raw.identity or {}
  local session = raw.session or {}
  local car = raw.car or {}
  local tyres = raw.tyres or {}
  local environment = raw.environment or {}
  return {
    source_mode = source_mode or raw.source_mode or "live",
    observed_monotonic_s = observed_monotonic_s,
    identity = {
      car_id = identity.car_id,
      track_id = identity.track_id,
      layout_id = identity.layout_id,
      driver_name = identity.driver_name,
      session_id = identity.session_id,
      configuration_id = identity.configuration_id,
    },
    session = {
      type = session.type,
      elapsed_s = session.elapsed_s,
      remaining_s = session.remaining_s,
      lap_limit = session.lap_limit,
      track_length_m = session.track_length_m,
      completed_laps = session.completed_laps,
      current_lap = session.current_lap,
      position = session.position,
      total_cars = session.total_cars,
      paused = session.paused == true,
      replay = session.replay == true,
      active = session.active ~= false,
      finished = session.finished == true,
    },
    car = {
      speed_kmh = car.speed_kmh,
      fuel_l = car.fuel_l,
      fuel_capacity_l = car.fuel_capacity_l,
      spline = car.spline,
      distance_session_km = car.distance_session_km,
      pit_lane = car.pit_lane == true,
      pit_box = car.pit_box == true,
      lap_time_s = car.lap_time_s,
      previous_lap_time_s = car.previous_lap_time_s,
      best_lap_time_s = car.best_lap_time_s,
      lap_valid = car.lap_valid,
      previous_lap_valid = car.previous_lap_valid,
      last_lap_cuts = car.last_lap_cuts,
      reset_counter = car.reset_counter,
    },
    tyres = {
      compound = tyres.compound,
      core_c = tyres.core_c,
      surface_c = tyres.surface_c,
      wear = tyres.wear,
      pressure_kpa = tyres.pressure_kpa,
      optimum_c = tyres.optimum_c,
    },
    environment = {
      ambient_c = environment.ambient_c,
      road_c = environment.road_c,
      wind_kmh = environment.wind_kmh,
      weather_type = environment.weather_type,
      rain_intensity = environment.rain_intensity,
      track_wetness = environment.track_wetness,
      standing_water = environment.standing_water,
      grip = environment.grip,
    },
  }
end

local function telemetry_average(sum, count)
  return count > 0 and sum / count or nil
end

local function read_live_telemetry()
  local ac_api = rawget(_G, "ac")
  if type(ac_api) ~= "table" then
    return nil, "SOURCE_UNAVAILABLE"
  end
  local get_sim = telemetry_field(ac_api, "getSim")
  local get_car = telemetry_field(ac_api, "getCar")
  if not callable(get_sim) or not callable(get_car) then
    return nil, "SOURCE_UNAVAILABLE"
  end
  local ok_sim, sim = pcall(get_sim)
  local ok_car, car = pcall(get_car, 0)
  if not ok_sim or not ok_car or sim == nil or car == nil then
    return nil, "SOURCE_UNAVAILABLE"
  end
  local session_index = telemetry_field(sim, "currentSessionIndex") or 0
  local session = nil
  local get_session = telemetry_field(ac_api, "getSession")
  if callable(get_session) then
    local ok_session, value = pcall(get_session, session_index)
    if ok_session then session = value end
  end
  local get_track_id = telemetry_field(ac_api, "getTrackID")
  local get_layout = telemetry_field(ac_api, "getTrackLayout")
  local get_full_id = telemetry_field(ac_api, "getTrackFullID")
  local track_id = callable(get_track_id) and select(2, pcall(get_track_id)) or nil
  local layout_id = callable(get_layout) and select(2, pcall(get_layout)) or nil
  local full_id = callable(get_full_id) and select(2, pcall(get_full_id, "::")) or nil
  local car_id = telemetry_optional_method(car, { "id" }) or telemetry_field(car, "id")
  local car_name = telemetry_optional_method(car, { "name" }) or telemetry_field(car, "name")
  local driver_name = telemetry_optional_method(car, { "driverName" }) or telemetry_field(car, "driverName")
  local wheels = telemetry_field(car, "wheels") or {}
  local core_sum, surface_sum, pressure_sum, wear_sum, optimum_sum, wheel_count = 0, 0, 0, 0, 0, 0
  for index = 0, 3 do
    local wheel = wheels[index] or wheels[index + 1]
    if wheel ~= nil then
      local core = telemetry_first(wheel, { "tyreCoreTemperature", "coreTemperature" })
      local surface = telemetry_first(wheel, { "tyreMiddleTemperature", "tyreSurfaceTemperature", "surfaceTemperature" })
      local pressure = telemetry_first(wheel, { "tyrePressure", "pressure" })
      local wear = telemetry_first(wheel, { "tyreWear", "wear" })
      local optimum = telemetry_first(wheel, { "tyreOptimumTemperature", "optimumTemperature" })
      if telemetry_finite(core) then core_sum = core_sum + core end
      if telemetry_finite(surface) then surface_sum = surface_sum + surface end
      if telemetry_finite(pressure) then pressure_sum = pressure_sum + pressure end
      if telemetry_finite(wear) then wear_sum = wear_sum + wear end
      if telemetry_finite(optimum) then optimum_sum = optimum_sum + optimum end
      if core ~= nil or surface ~= nil or pressure ~= nil or wear ~= nil then wheel_count = wheel_count + 1 end
    end
  end
  local sim_time_ms = telemetry_field(sim, "time")
  local sim_time = type(sim_time_ms) == "number" and sim_time_ms / 1000 or telemetry_field(sim, "gameTime")
  local lap_count = telemetry_field(car, "lapCount")
  local raw = {
    source_mode = "live",
    identity = {
      car_id = car_id or car_name,
      track_id = track_id,
      layout_id = layout_id,
      driver_name = driver_name,
      session_id = tostring(session_index) .. ":" .. tostring(telemetry_field(session, "startTime") or ""),
      configuration_id = tostring(car_id or car_name or "") .. "@" .. tostring(full_id or track_id or ""),
    },
    session = {
      type = telemetry_field(sim, "raceSessionType"),
      elapsed_s = telemetry_field(sim, "currentSessionTime") and telemetry_field(sim, "currentSessionTime") / 1000 or telemetry_field(sim, "gameTime"),
      remaining_s = telemetry_field(sim, "sessionTimeLeft") and telemetry_field(sim, "sessionTimeLeft") / 1000 or nil,
      lap_limit = telemetry_field(session, "laps"),
      track_length_m = telemetry_field(sim, "trackLengthM"),
      completed_laps = lap_count,
      current_lap = type(lap_count) == "number" and lap_count + 1 or nil,
      position = telemetry_field(car, "racePosition"),
      total_cars = telemetry_field(sim, "carsCount"),
      paused = telemetry_field(sim, "isPaused"),
      replay = telemetry_field(sim, "isReplayActive") or telemetry_field(sim, "isReplayOnlyMode"),
      active = telemetry_field(sim, "isLive") or telemetry_field(sim, "isSessionStarted"),
      finished = telemetry_field(sim, "isSessionFinished") or telemetry_field(session, "isOver"),
    },
    car = {
      speed_kmh = telemetry_field(car, "speedKmh"),
      fuel_l = telemetry_field(car, "fuel"),
      fuel_capacity_l = telemetry_field(car, "maxFuel"),
      spline = telemetry_field(car, "splinePosition"),
      distance_session_km = telemetry_field(car, "distanceDrivenSessionKm"),
      pit_lane = telemetry_field(car, "isInPitlane"),
      pit_box = telemetry_field(car, "isInPit"),
      lap_time_s = telemetry_field(car, "lapTimeMs") and telemetry_field(car, "lapTimeMs") / 1000 or nil,
      previous_lap_time_s = telemetry_field(car, "previousLapTimeMs") and telemetry_field(car, "previousLapTimeMs") / 1000 or nil,
      best_lap_time_s = telemetry_field(car, "bestLapTimeMs") and telemetry_field(car, "bestLapTimeMs") / 1000 or nil,
      lap_valid = telemetry_field(car, "isLapValid"),
      previous_lap_valid = telemetry_field(car, "isLastLapValid"),
      last_lap_cuts = telemetry_field(car, "lastLapCutsCount"),
      reset_counter = telemetry_field(car, "resetCounter"),
    },
    tyres = {
      compound = telemetry_optional_method(car, { "tyresName" }),
      core_c = telemetry_average(core_sum, wheel_count),
      surface_c = telemetry_average(surface_sum, wheel_count),
      wear = telemetry_average(wear_sum, wheel_count),
      pressure_kpa = telemetry_average(pressure_sum, wheel_count) and telemetry_average(pressure_sum, wheel_count) / 100 or nil,
      optimum_c = telemetry_average(optimum_sum, wheel_count),
    },
    environment = {
      ambient_c = telemetry_field(sim, "ambientTemperature"),
      road_c = telemetry_field(sim, "roadTemperature"),
      wind_kmh = telemetry_field(sim, "windSpeedKmh"),
      weather_type = telemetry_field(sim, "weatherType"),
      rain_intensity = telemetry_field(sim, "rainIntensity"),
      track_wetness = telemetry_field(sim, "rainWetness"),
      standing_water = telemetry_field(sim, "rainWater"),
      grip = telemetry_field(sim, "roadGrip"),
    },
    observed_monotonic_s = sim_time,
  }
  return raw, nil
end

function csp.read(source_mode, now_s)
  if source_mode == "mock" then
    if telemetry_fixture == nil then return nil, "SOURCE_UNAVAILABLE" end
    return csp.normalize(telemetry_fixture, now_s, "mock")
  end
  if source_mode ~= "live" then return nil, "SOURCE_UNAVAILABLE" end
  local raw, reason = read_live_telemetry()
  if raw == nil then return nil, reason end
  return csp.normalize(raw, now_s, "live")
end
