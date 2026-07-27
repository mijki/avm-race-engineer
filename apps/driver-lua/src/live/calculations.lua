do
  local namespace = _G.AVM_PITWALL_F1
  local contracts = namespace.contracts
  local track_model = namespace.live.track_model
  local calculations = {}

  local function values(list)
    local result = {}
    for _, value in ipairs(list or {}) do
      if type(value) == "number" and value == value and value < math.huge and value > -math.huge then result[#result + 1] = value end
    end
    return result
  end

  local function average(list)
    local clean = values(list)
    if #clean == 0 then return nil, 0 end
    local sum = 0
    for _, value in ipairs(clean) do sum = sum + value end
    return sum / #clean, #clean
  end

  local function variation(list)
    local mean, count = average(list)
    if mean == nil or count < 2 or mean == 0 then return nil end
    local sum = 0
    for _, value in ipairs(values(list)) do sum = sum + (value - mean) ^ 2 end
    return math.sqrt(sum / count) / math.abs(mean)
  end

  local function confidence(samples, spread, freshness_s)
    if samples >= 5 and (spread == nil or spread <= 0.08) and (freshness_s == nil or freshness_s <= 5) then return "high" end
    if samples >= 2 and (spread == nil or spread <= 0.20) and (freshness_s == nil or freshness_s <= 15) then return "medium" end
    return "low"
  end

  local function age(now_s, observed_s)
    if type(now_s) ~= "number" or type(observed_s) ~= "number" then return nil end
    return math.max(0, now_s - observed_s)
  end

  local function numeric_metric(value, unit, samples, freshness_s, spread, reason)
    return contracts.metric(value, unit, samples, freshness_s, confidence(samples, spread, freshness_s), reason)
  end

  local function unavailable(unit, reason, samples, freshness_s)
    return contracts.unavailable(unit, reason, samples, freshness_s)
  end

  local function tire_state(tyres)
    if type(tyres) ~= "table" then return "UNKNOWN" end
    local core, optimum, wear = tyres.core_c, tyres.optimum_c, tyres.wear
    if type(wear) == "number" and wear >= 0.70 then return "WORN" end
    if type(core) ~= "number" or type(optimum) ~= "number" then return "UNKNOWN" end
    if core < optimum - 15 then return "COLD" end
    if core > optimum + 15 then return "HOT" end
    return "GOOD"
  end

  function calculations.compute(input)
    local snapshot = input.snapshot or {}
    local session = snapshot.session or {}
    local car = snapshot.car or {}
    local tyres = snapshot.tyres or {}
    local store = input.store or { fuel_samples = {}, pace_samples = {}, laps = {} }
    local stint = input.stint or {}
    local config = input.config or { targets = {} }
    local now_s = input.now_s
    local observed_age = age(now_s, snapshot.observed_monotonic_s)
    local fuel_mean, fuel_count = average(store.fuel_samples)
    local pace_mean, pace_count = average(store.pace_samples)
    local fuel_spread = variation(store.fuel_samples)
    local pace_spread = variation(store.pace_samples)
    local calibration = input.calibration
    local distance_to_pit, pit_reason = track_model.distance_to_pit(snapshot, calibration)
    local track_length_m = (calibration and calibration.track_length_m) or session.track_length_m
    local lap_distance_km = track_length_m and track_length_m / 1000 or nil
    local fuel_per_km = nil
    local fuel_per_min = nil
    if fuel_mean and lap_distance_km and lap_distance_km > 0 then fuel_per_km = fuel_mean / lap_distance_km end
    if fuel_mean and pace_mean and pace_mean > 0 then fuel_per_min = fuel_mean / pace_mean * 60 end
    local current_fuel = numeric_metric(car.fuel_l, " L", car.fuel_l and 1 or 0, observed_age, nil, "MEASURED_CURRENT")
    local fuel_used = nil
    if type(stint.start_fuel_l) == "number" and type(car.fuel_l) == "number" and car.fuel_l <= stint.start_fuel_l then
      fuel_used = stint.start_fuel_l - car.fuel_l
    end
    local fuel_laps = nil
    local fuel_time = nil
    local fuel_distance = nil
    if type(car.fuel_l) == "number" and fuel_mean and fuel_mean > 0 then fuel_laps = car.fuel_l / fuel_mean end
    if type(car.fuel_l) == "number" and fuel_per_min and fuel_per_min > 0 then fuel_time = car.fuel_l / fuel_per_min * 60 end
    if type(car.fuel_l) == "number" and fuel_per_km and fuel_per_km > 0 then fuel_distance = car.fuel_l / fuel_per_km end
    local predicted_pit = nil
    if type(car.fuel_l) == "number" and fuel_per_km and distance_to_pit then
      predicted_pit = car.fuel_l - fuel_per_km * ((distance_to_pit + (calibration.pit_route_additional_m or 0)) / 1000)
    end
    local target_fuel = config.targets and config.targets.fuel_at_pit_l
    local fuel_delta = target_fuel and predicted_pit and predicted_pit - target_fuel or nil
    local remaining = {}
    local remaining_reasons = {}
    if type(session.remaining_s) == "number" and session.remaining_s > 0 then
      remaining[#remaining + 1] = session.remaining_s; remaining_reasons[#remaining_reasons + 1] = "session time"
    end
    if type(fuel_time) == "number" and fuel_time > 0 then
      remaining[#remaining + 1] = fuel_time; remaining_reasons[#remaining_reasons + 1] = "fuel range"
    end
    if type(config.targets) == "table" and type(config.targets.stint_minutes) == "number" and type(stint.start_monotonic_s) == "number" then
      local target_remaining = config.targets.stint_minutes * 60 - math.max(0, now_s - stint.start_monotonic_s)
      if target_remaining > 0 then remaining[#remaining + 1] = target_remaining; remaining_reasons[#remaining_reasons + 1] = "stint target" end
    end
    if type(session.lap_limit) == "number" and type(session.current_lap) == "number" and session.lap_limit > session.current_lap and pace_mean then
      remaining[#remaining + 1] = (session.lap_limit - session.current_lap) * pace_mean; remaining_reasons[#remaining_reasons + 1] = "lap limit"
    end
    local remaining_s = nil
    local remaining_reason = "NO_TRUSTWORTHY_CONSTRAINT"
    for index, value in ipairs(remaining) do
      if remaining_s == nil or value < remaining_s then remaining_s = value; remaining_reason = remaining_reasons[index] end
    end
    local elapsed_s = namespace.live.stint_tracker.elapsed(stint, now_s)
    local stint_progress = nil
    if elapsed_s and remaining_s and elapsed_s + remaining_s > 0 then stint_progress = elapsed_s / (elapsed_s + remaining_s) end
    local pace_delta = nil
    local pace_reason = nil
    local pace_target = config.targets and config.targets.pace_s
    if type(car.lap_time_s) == "number" and car.lap_time_s > 0 and pace_target then pace_delta = car.lap_time_s - pace_target; pace_reason = "configured target"
    elseif type(car.lap_time_s) == "number" and car.lap_time_s > 0 and pace_mean then pace_delta = car.lap_time_s - pace_mean; pace_reason = "rolling representative pace" end
    local weather = input.weather or {}
    local weather_trend = input.weather_trend or { label = "UNKNOWN", text = "Measured trend: Unavailable" }
    local fresh_reason = observed_age and observed_age <= 2 and "MEASURED_CURRENT" or "STALE_TELEMETRY"
    local result = {
      stint = {
        elapsed = numeric_metric(elapsed_s, " s", 1, observed_age, nil, elapsed_s and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        completed_laps = numeric_metric(stint.completed_laps, " laps", stint.completed_laps or 0, observed_age, nil, "MEASURED_CURRENT"),
        remaining = numeric_metric(remaining_s, " s", #remaining, observed_age, nil, remaining_s and remaining_reason or "INSUFFICIENT_SAMPLES"),
        endpoint = numeric_metric(elapsed_s and remaining_s and elapsed_s + remaining_s or nil, " s", #remaining, observed_age, nil, remaining_s and remaining_reason or "INSUFFICIENT_SAMPLES"),
        progress = numeric_metric(stint_progress, "", #remaining, observed_age, nil, stint_progress and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
      },
      fuel = {
        current = current_fuel,
        used_stint = numeric_metric(fuel_used, " L", fuel_count, observed_age, fuel_spread, fuel_used and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        per_lap = numeric_metric(fuel_mean, " L/lap", fuel_count, observed_age, fuel_spread, fuel_mean and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        per_km = numeric_metric(fuel_per_km, " L/km", fuel_count, observed_age, fuel_spread, fuel_per_km and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        per_min = numeric_metric(fuel_per_min, " L/min", fuel_count, observed_age, fuel_spread, fuel_per_min and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        laps_remaining = numeric_metric(fuel_laps, " laps", fuel_count, observed_age, fuel_spread, fuel_laps and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        time_remaining = numeric_metric(fuel_time, " s", fuel_count, observed_age, fuel_spread, fuel_time and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        distance_remaining = numeric_metric(fuel_distance, " km", fuel_count, observed_age, fuel_spread, fuel_distance and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        predicted_at_pit = numeric_metric(predicted_pit, " L", fuel_count, observed_age, fuel_spread, predicted_pit and "MEASURED_CURRENT" or pit_reason),
        delta_target = numeric_metric(fuel_delta, " L", fuel_count, observed_age, fuel_spread, fuel_delta and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
      },
      pace = {
        current = numeric_metric(car.lap_time_s, " s", 1, observed_age, nil, car.lap_time_s and fresh_reason or "SOURCE_UNAVAILABLE"),
        previous_representative = numeric_metric(pace_mean, " s", pace_count, observed_age, pace_spread, pace_mean and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        rolling = numeric_metric(pace_mean, " s", pace_count, observed_age, pace_spread, pace_mean and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        delta = numeric_metric(pace_delta, " s", pace_count, observed_age, pace_spread, pace_delta and pace_reason or "INSUFFICIENT_SAMPLES"),
      },
      tyres = {
        compound = tyres and tyres.compound or nil,
        core_c = numeric_metric(tyres and tyres.core_c, " °C", 1, observed_age, nil, "MEASURED_CURRENT"),
        surface_c = numeric_metric(tyres and tyres.surface_c, " °C", 1, observed_age, nil, "MEASURED_CURRENT"),
        wear = numeric_metric(tyres and tyres.wear and tyres.wear * 100 or nil, " %", 1, observed_age, nil, "MEASURED_CURRENT"),
        pressure_kpa = numeric_metric(tyres and tyres.pressure_kpa, " kPa", 1, observed_age, nil, "MEASURED_CURRENT"),
        state = tire_state(tyres),
      },
      weather = {
        current = weather,
        trend = weather_trend,
        future = namespace.live.weather.future(),
      },
      pit = {
        distance = numeric_metric(distance_to_pit, " m", 1, observed_age, nil, pit_reason),
        calibrated = distance_to_pit ~= nil,
        calibration_reason = pit_reason,
      },
      freshness_s = observed_age,
      samples = { fuel = fuel_count, pace = pace_count, laps = #store.laps },
    }
    result.alerts = {}
    local threshold = config.targets and config.targets.fuel_delta_threshold_l or 1.0
    if fuel_delta and fuel_delta < -threshold and fuel_count >= 2 and result.fuel.delta_target.confidence_band ~= "low" then
      result.alerts[#result.alerts + 1] = { kind = "SAVE_FUEL", label = "SAVE FUEL", priority = 2, reason = "Fuel target is not reachable at the representative rate" }
    elseif fuel_delta and fuel_delta > threshold and fuel_count >= 3 and result.fuel.delta_target.confidence_band == "high" then
      result.alerts[#result.alerts + 1] = { kind = "PUSH", label = "PUSH", priority = 4, reason = "Measured fuel margin is available" }
    end
    if type(config.targets and config.targets.planned_pit_lap) == "number" and type(session.current_lap) == "number" and session.current_lap >= config.targets.planned_pit_lap then
      result.alerts[#result.alerts + 1] = { kind = "BOX", label = "BOX THIS LAP", priority = 2, reason = "Configured pit lap reached" }
    end
    if fuel_count < 2 or pace_count < 2 then
      result.alerts[#result.alerts + 1] = { kind = "LOW_CONFIDENCE", label = "LOW CONFIDENCE", priority = 4, reason = "INSUFFICIENT_SAMPLES" }
    end
    if distance_to_pit == nil then
      result.alerts[#result.alerts + 1] = { kind = "PIT_ENTRY_NOT_CALIBRATED", label = "PIT ENTRY NOT CALIBRATED", priority = 4, reason = "PIT_ENTRY_NOT_CALIBRATED" }
    end
    return result
  end

  namespace.live.calculations = calculations
end
