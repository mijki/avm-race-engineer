do
  local namespace = _G.AVM_PITWALL_F1
  local contracts = namespace.contracts
  local track_model = namespace.live.track_model
  local calculations = {}

  local function values(list)
    local result = {}
    for _, value in ipairs(list or {}) do
      if type(value) == "number" and value == value and value < math.huge and value > -math.huge then
        result[#result + 1] = value
      end
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

  local function difference(left, right)
    if type(left) == "number" and type(right) == "number" then return left - right end
    return nil
  end

  local function flat_spot_percent(value)
    -- The inspected reference apps clamp flat spotting to a 0..1 unit scale.
    -- The installed SDK does not establish ranges for grain or blister, so
    -- those fields remain unsupported until a verified range is available.
    if type(value) ~= "number" or value < 0 or value > 1 then return nil end
    return value * 100
  end

  local function unsupported_damage()
    return nil
  end

  local function target_pressure_psi(config, compound, label)
    local targets = config.targets or {}
    local values_by_compound = targets.pressure_targets_psi
    if type(values_by_compound) ~= "table" then return nil, "UNAVAILABLE" end
    local selected = values_by_compound[compound] or values_by_compound.default or values_by_compound
    if type(selected) ~= "table" then
      if type(selected) == "number" then return selected, "USER_CONFIG" end
      return nil, "UNAVAILABLE"
    end
    local value = selected[label] or selected.default
    return type(value) == "number" and value or nil, type(value) == "number" and "USER_CONFIG" or "UNAVAILABLE"
  end

  local function target_temperature_c(config, compound, label)
    local targets = config.targets or {}
    local values_by_compound = targets.temperature_targets_c
    if type(values_by_compound) ~= "table" then return nil, "UNAVAILABLE" end
    local selected = values_by_compound[compound] or values_by_compound.default or values_by_compound
    if type(selected) ~= "table" then
      if type(selected) == "number" then return selected, "USER_CONFIG" end
      return nil, "UNAVAILABLE"
    end
    local value = selected[label] or selected.default
    return type(value) == "number" and value or nil, type(value) == "number" and "USER_CONFIG" or "UNAVAILABLE"
  end

  local function tyre_state(wheel)
    if type(wheel) ~= "table" then return "UNKNOWN" end
    local flat_spot = flat_spot_percent(wheel.flat_spot)
    local grain = unsupported_damage(wheel.grain)
    local blister = unsupported_damage(wheel.blister)
    if flat_spot and flat_spot >= 10 then return "FLAT_SPOTTED" end
    if grain and grain >= 10 then return "GRAINING" end
    if blister and blister >= 10 then return "BLISTERING" end
    if type(wheel.wear) == "number" and wheel.wear >= 0.70 then return "WORN" end
    if type(wheel.core_c) ~= "number" or type(wheel.optimum_c) ~= "number" then return "UNKNOWN" end
    if wheel.core_c < wheel.optimum_c - 15 then return "COLD" end
    if wheel.core_c > wheel.optimum_c + 15 then return "HOT" end
    return "OPTIMAL"
  end

  local function build_wheels(tyres, store, config)
    local source = type(tyres.wheels) == "table" and tyres.wheels or {}
    local result = {}
    local labels = { "FL", "FR", "RL", "RR" }
    for index = 1, 4 do
      local input = source[index]
      if type(input) ~= "table" then
        input = {
          label = labels[index],
          core_c = tyres.core_c,
          middle_c = tyres.surface_c,
          optimum_c = tyres.optimum_c,
          pressure_kpa = tyres.pressure_kpa,
          wear = tyres.wear,
          source = "AGGREGATE_FALLBACK",
        }
      end
      local label = input.label or labels[index]
      local pressure_psi = input.pressure_psi or (type(input.pressure_kpa) == "number" and input.pressure_kpa / 6.894757293 or nil)
      local target_psi, target_source = target_pressure_psi(config, tyres.compound, label)
      local target_c, temperature_source = target_temperature_c(config, tyres.compound, label)
      local lap_min = store.tyre_lap and store.tyre_lap.min_c and store.tyre_lap.min_c[index] or nil
      local lap_max = store.tyre_lap and store.tyre_lap.max_c and store.tyre_lap.max_c[index] or nil
      local life = type(input.wear) == "number" and input.wear >= 0 and input.wear <= 1 and (1 - input.wear) * 100 or nil
      local flat_spot = flat_spot_percent(input.flat_spot)
      result[index] = {
        label = label,
        source = input.source or (source[index] and "CSP_WHEEL" or "AGGREGATE_FALLBACK"),
        core_c = numeric_metric(input.core_c, " C", 1, nil, nil, input.core_c and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        inside_c = input.inside_c,
        middle_c = input.middle_c,
        outside_c = input.outside_c,
        lap_min_c = lap_min,
        lap_max_c = lap_max,
        optimum_c = input.optimum_c,
        temperature_target_c = numeric_metric(target_c, " C", 1, nil, nil, temperature_source == "USER_CONFIG" and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        temperature_delta_c = numeric_metric(difference(input.core_c, target_c), " C", 1, nil, nil, target_c and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        pressure_psi = numeric_metric(pressure_psi, " psi", 1, nil, nil, pressure_psi and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        pressure_kpa = numeric_metric(input.pressure_kpa or (pressure_psi and pressure_psi * 6.894757293 or nil), " kPa", 1, nil, nil, pressure_psi and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        pressure_target_psi = numeric_metric(target_psi, " psi", 1, nil, nil, target_source == "USER_CONFIG" and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        pressure_target_kpa = numeric_metric(target_psi and target_psi * 6.894757293 or nil, " kPa", 1, nil, nil, target_source == "USER_CONFIG" and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        pressure_target_source = target_source == "USER_CONFIG" and "USER_CONFIG" or "UNAVAILABLE",
        pressure_delta_psi = numeric_metric(difference(pressure_psi, target_psi), " psi", 1, nil, nil, target_psi and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        pressure_delta_kpa = numeric_metric(difference(input.pressure_kpa or (pressure_psi and pressure_psi * 6.894757293 or nil), target_psi and target_psi * 6.894757293 or nil), " kPa", 1, nil, nil, target_psi and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        wear = numeric_metric(type(input.wear) == "number" and input.wear * 100 or nil, " % wear", 1, nil, nil, input.wear and "CSP_TYRE_WEAR_0_TO_1" or "SOURCE_UNAVAILABLE"),
        life = numeric_metric(life, " % life", 1, nil, nil, life and "CSP_TYRE_WEAR_0_TO_1" or "SOURCE_UNAVAILABLE"),
        grain = numeric_metric(nil, " %", 1, nil, nil, "UNSUPPORTED"),
        blister = numeric_metric(nil, " %", 1, nil, nil, "UNSUPPORTED"),
        flat_spot = numeric_metric(flat_spot, " %", 1, nil, nil, flat_spot and "CSP_TYRE_FLATSPOT_UNIT_SCALE" or "UNSUPPORTED"),
      }
      result[index].state = tyre_state({
        core_c = input.core_c,
        optimum_c = input.optimum_c,
        wear = input.wear,
        grain = input.grain,
        blister = input.blister,
        flat_spot = input.flat_spot,
      })
    end
    return result
  end

  function calculations.compute(input)
    local snapshot = input.snapshot or {}
    local session = snapshot.session or {}
    local car = snapshot.car or {}
    local tyres = snapshot.tyres or {}
    local store = input.store or { fuel_samples = {}, pace_samples = {}, laps = {}, excluded_laps = {}, tyre_lap = {} }
    local laps = store.laps or {}
    local excluded_laps = store.excluded_laps or {}
    local stint = input.stint or {}
    local config = input.config or { targets = {} }
    local now_s = input.now_s
    local observed_age = age(now_s, snapshot.observed_monotonic_s)
    local fuel_mean, fuel_count = average(store.fuel_samples)
    local pace_mean, pace_count = average(store.pace_samples)
    local fuel_spread = variation(store.fuel_samples)
    local pace_spread = variation(store.pace_samples)
    local target_fuel = config.targets and config.targets.fuel_per_lap_l or nil
    local target_pace = config.targets and config.targets.pace_s or nil
    local latest_valid_fuel = store.latest_valid_fuel_l or (laps[#laps] and laps[#laps].fuel_used_l or nil)
    local latest_valid_pace = store.latest_valid_pace_s or (laps[#laps] and laps[#laps].lap_time_s or nil)
    local latest_completed = store.latest_completed or {}
    local latest_completed_fuel = latest_completed.fuel_used_l
    local latest_completed_pace = latest_completed.lap_time_s
    local calibration = input.calibration
    local distance_to_pit, pit_reason = track_model.distance_to_pit(snapshot, calibration)
    local track_length_m = (calibration and calibration.track_length_m) or session.track_length_m
    local lap_distance_km = track_length_m and track_length_m / 1000 or nil
    local fuel_per_km = fuel_mean and lap_distance_km and lap_distance_km > 0 and fuel_mean / lap_distance_km or nil
    local fuel_per_min = fuel_mean and pace_mean and pace_mean > 0 and fuel_mean / pace_mean * 60 or nil
    local current_fuel = numeric_metric(car.fuel_l, " L", 1, observed_age, nil, car.fuel_l and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE")
    local fuel_used = nil
    if type(stint.start_fuel_l) == "number" and type(car.fuel_l) == "number" and car.fuel_l <= stint.start_fuel_l then
      fuel_used = stint.start_fuel_l - car.fuel_l
    end
    local fuel_laps = type(car.fuel_l) == "number" and fuel_mean and fuel_mean > 0 and car.fuel_l / fuel_mean or nil
    local fuel_time = type(car.fuel_l) == "number" and fuel_per_min and fuel_per_min > 0 and car.fuel_l / fuel_per_min * 60 or nil
    local fuel_distance = type(car.fuel_l) == "number" and fuel_per_km and fuel_per_km > 0 and car.fuel_l / fuel_per_km or nil
    local route_known = calibration ~= nil and type(calibration.pit_route_additional_m) == "number"
    local predicted_pit = nil
    local fresh_enough = observed_age == nil or observed_age <= (config.telemetry_stale_after_s or 2)
    if type(car.fuel_l) == "number" and fuel_per_km and distance_to_pit and route_known and fresh_enough then
      predicted_pit = car.fuel_l - fuel_per_km * ((distance_to_pit + calibration.pit_route_additional_m) / 1000)
    elseif distance_to_pit ~= nil and not route_known then
      pit_reason = "PIT_ROUTE_NOT_CONFIGURED"
    elseif distance_to_pit ~= nil and route_known and not fresh_enough then
      pit_reason = "STALE_TELEMETRY"
    end
    local fuel_delta_target = difference(latest_valid_fuel, target_fuel)
    local fuel_delta_average = difference(latest_valid_fuel, fuel_mean)
    local fuel_average_target = difference(fuel_mean, target_fuel)
    local pace_delta_target = difference(latest_valid_pace, target_pace)
    local pace_delta_average = difference(latest_valid_pace, pace_mean)
    local pace_average_target = difference(pace_mean, target_pace)
    local remaining = {}
    local remaining_reasons = {}
    if type(session.remaining_s) == "number" and session.remaining_s > 0 then
      remaining[#remaining + 1] = session.remaining_s; remaining_reasons[#remaining_reasons + 1] = "session time"
    end
    if type(fuel_time) == "number" and fuel_time > 0 then
      remaining[#remaining + 1] = fuel_time; remaining_reasons[#remaining_reasons + 1] = "fuel range"
    end
    if type(config.targets and config.targets.stint_minutes) == "number" and type(stint.start_monotonic_s) == "number" then
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
    local current_stint_lap = nil
    if type(stint.start_lap) == "number" and type(session.current_lap) == "number" then current_stint_lap = math.max(1, session.current_lap - stint.start_lap + 1) end
    local weather = input.weather or {}
    local weather_trend = input.weather_trend or { label = "UNKNOWN", text = "Measured trend: Unavailable" }
    local fresh_reason = observed_age and observed_age <= 2 and "MEASURED_CURRENT" or "STALE_TELEMETRY"
    local wheels = build_wheels(tyres, store, config)
    local result = {
      stint = {
        elapsed = numeric_metric(elapsed_s, " s", 1, observed_age, nil, elapsed_s and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        completed_laps = numeric_metric(stint.completed_laps, " laps", stint.completed_laps or 0, observed_age, nil, "MEASURED_CURRENT"),
        current_lap = numeric_metric(current_stint_lap, " lap", stint.completed_laps or 0, observed_age, nil, current_stint_lap and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        remaining = numeric_metric(remaining_s, " s", #remaining, observed_age, nil, remaining_s and remaining_reason or "NO_TRUSTWORTHY_CONSTRAINT"),
        endpoint = numeric_metric(elapsed_s and remaining_s and elapsed_s + remaining_s or nil, " s", #remaining, observed_age, nil, remaining_s and remaining_reason or "NO_TRUSTWORTHY_CONSTRAINT"),
        progress = numeric_metric(stint_progress, "", #remaining, observed_age, nil, stint_progress and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
      },
      fuel = {
        current = current_fuel,
        used_stint = numeric_metric(fuel_used, " L", fuel_count, observed_age, fuel_spread, fuel_used and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        target_per_lap = numeric_metric(target_fuel, " L/lap", fuel_count, observed_age, fuel_spread, target_fuel and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        per_lap = numeric_metric(fuel_mean, " L/lap", fuel_count, observed_age, fuel_spread, fuel_mean and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        latest_valid = numeric_metric(latest_valid_fuel, " L/lap", fuel_count, observed_age, fuel_spread, latest_valid_fuel and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        latest_completed = numeric_metric(latest_completed_fuel, " L/lap", fuel_count, observed_age, fuel_spread, latest_completed_fuel and (latest_completed.accepted and "MEASURED_CURRENT" or latest_completed.reason or "LAP_EXCLUDED") or "INSUFFICIENT_SAMPLES"),
        per_km = numeric_metric(fuel_per_km, " L/km", fuel_count, observed_age, fuel_spread, fuel_per_km and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        per_min = numeric_metric(fuel_per_min, " L/min", fuel_count, observed_age, fuel_spread, fuel_per_min and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        laps_remaining = numeric_metric(fuel_laps, " laps", fuel_count, observed_age, fuel_spread, fuel_laps and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        time_remaining = numeric_metric(fuel_time, " s", fuel_count, observed_age, fuel_spread, fuel_time and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        distance_remaining = numeric_metric(fuel_distance, " km", fuel_count, observed_age, fuel_spread, fuel_distance and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        predicted_at_pit = numeric_metric(predicted_pit, " L", fuel_count, observed_age, fuel_spread, predicted_pit and "MEASURED_CURRENT" or pit_reason),
        delta_target = numeric_metric(fuel_delta_target, " L/lap", fuel_count, observed_age, fuel_spread, fuel_delta_target and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        delta_average = numeric_metric(fuel_delta_average, " L/lap", fuel_count, observed_age, fuel_spread, fuel_delta_average and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        average_vs_target = numeric_metric(fuel_average_target, " L/lap", fuel_count, observed_age, fuel_spread, fuel_average_target and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
      },
      pace = {
        current = numeric_metric(car.lap_time_s, " s", 1, observed_age, nil, car.lap_time_s and fresh_reason or "SOURCE_UNAVAILABLE"),
        target = numeric_metric(target_pace, " s", pace_count, observed_age, pace_spread, target_pace and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        latest_valid = numeric_metric(latest_valid_pace, " s", pace_count, observed_age, pace_spread, latest_valid_pace and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        latest_completed = numeric_metric(latest_completed_pace, " s", pace_count, observed_age, pace_spread, latest_completed_pace and (latest_completed.accepted and "MEASURED_CURRENT" or latest_completed.reason or "LAP_EXCLUDED") or "INSUFFICIENT_SAMPLES"),
        previous_representative = numeric_metric(pace_mean, " s", pace_count, observed_age, pace_spread, pace_mean and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        rolling = numeric_metric(pace_mean, " s", pace_count, observed_age, pace_spread, pace_mean and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        delta = numeric_metric(pace_delta_target or pace_delta_average, " s", pace_count, observed_age, pace_spread, (pace_delta_target and "USER_CONFIG" or pace_delta_average and "MEASURED_CURRENT" or "TARGET_NOT_CONFIGURED")),
        delta_to_target = numeric_metric(pace_delta_target, " s", pace_count, observed_age, pace_spread, pace_delta_target and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
        delta_to_average = numeric_metric(pace_delta_average, " s", pace_count, observed_age, pace_spread, pace_delta_average and "MEASURED_CURRENT" or "INSUFFICIENT_SAMPLES"),
        average_vs_target = numeric_metric(pace_average_target, " s", pace_count, observed_age, pace_spread, pace_average_target and "USER_CONFIG" or "TARGET_NOT_CONFIGURED"),
      },
      tyres = {
        compound = tyres.compound,
        core_c = numeric_metric(tyres.core_c, " C", 1, observed_age, nil, tyres.core_c and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        surface_c = numeric_metric(tyres.surface_c, " C", 1, observed_age, nil, tyres.surface_c and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        wear = numeric_metric(type(tyres.wear) == "number" and tyres.wear * 100 or nil, " % wear", 1, observed_age, nil, tyres.wear and "CSP_TYRE_WEAR_0_TO_1" or "SOURCE_UNAVAILABLE"),
        pressure_kpa = numeric_metric(tyres.pressure_kpa, " kPa", 1, observed_age, nil, tyres.pressure_kpa and "MEASURED_CURRENT" or "SOURCE_UNAVAILABLE"),
        state = tyre_state({ core_c = tyres.core_c, optimum_c = tyres.optimum_c, wear = tyres.wear }),
        wheels = wheels,
        temperature_source = "CSP tyreCoreTemperature (lap min/max tracked locally)",
      },
      weather = {
        current = weather,
        trend = weather_trend,
        future = namespace.live.weather.future(),
      },
      pit = {
        distance = numeric_metric(distance_to_pit, " m", 1, observed_age, nil, pit_reason),
        calibrated = distance_to_pit ~= nil and route_known,
        calibration_reason = pit_reason,
        route_additional_m = calibration and calibration.pit_route_additional_m or nil,
      },
      freshness_s = observed_age,
      samples = { fuel = fuel_count, pace = pace_count, laps = #laps, excluded = #excluded_laps },
      latest_excluded = store.latest_excluded,
      configuration = {
        target_pace_s = target_pace,
        target_fuel_per_lap_l = target_fuel,
        target_stint_minutes = config.targets and config.targets.stint_minutes,
        planned_pit_lap = config.targets and config.targets.planned_pit_lap,
        pressure_unit = config.targets and config.targets.pressure_unit or "psi",
        pressure_targets_psi = config.targets and config.targets.pressure_targets_psi or {},
        temperature_targets_c = config.targets and config.targets.temperature_targets_c or {},
        pace_delta_threshold_s = config.targets and config.targets.pace_delta_threshold_s or 0.50,
        fuel_comparison_threshold_l = config.targets and config.targets.fuel_comparison_threshold_l or 0.05,
        pressure_delta_threshold_psi = config.targets and config.targets.pressure_delta_threshold_psi or 0.50,
        temperature_delta_threshold_c = config.targets and config.targets.temperature_delta_threshold_c or 15,
        strategy_profile = config.targets and config.targets.strategy_profile,
        endurance_rules = config.targets and config.targets.endurance_rules or {},
      },
    }
    result.alerts = {}
    local threshold = config.targets and config.targets.fuel_delta_threshold_l or 1.0
    if fuel_delta_target and fuel_delta_target < -threshold and fuel_count >= 2 and result.fuel.delta_target.confidence_band ~= "low" then
      result.alerts[#result.alerts + 1] = { kind = "SAVE_FUEL", label = "SAVE FUEL", priority = 5, reason = "Target fuel per lap is below the representative rate", requires_acknowledgement = false }
    elseif fuel_delta_target and fuel_delta_target > threshold and fuel_count >= 3 and result.fuel.delta_target.confidence_band == "high" then
      result.alerts[#result.alerts + 1] = { kind = "PUSH", label = "PUSH", priority = 5, reason = "Measured fuel margin is available", requires_acknowledgement = false }
    end
    if type(config.targets and config.targets.planned_pit_lap) == "number" and type(session.current_lap) == "number" and session.current_lap >= config.targets.planned_pit_lap then
      result.alerts[#result.alerts + 1] = { kind = "BOX", label = "BOX THIS LAP", priority = 2, reason = "Configured pit lap reached", requires_acknowledgement = true }
    end
    if fuel_count < 2 or pace_count < 2 then
      result.alerts[#result.alerts + 1] = { kind = "LOW_CONFIDENCE", label = "LOW CONFIDENCE", priority = 8, reason = "INSUFFICIENT_SAMPLES", requires_acknowledgement = false }
    end
    if distance_to_pit == nil then
      result.alerts[#result.alerts + 1] = { kind = "PIT_ENTRY_NOT_CALIBRATED", label = "PIT ENTRY NOT CALIBRATED", priority = 9, reason = "PIT_ENTRY_NOT_CALIBRATED", requires_acknowledgement = false }
    end
    table.sort(result.alerts, function(left, right) return (left.priority or 99) < (right.priority or 99) end)
    return result
  end

  namespace.live.calculations = calculations
end
