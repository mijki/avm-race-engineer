do
  local namespace = _G.AVM_PITWALL_F1
  local sample_store = {}

  local function push_bounded(list, value, max_count)
    if value == nil then return end
    list[#list + 1] = value
    while #list > max_count do table.remove(list, 1) end
  end

  function sample_store.new(max_count, weather_count)
    return {
      max_count = max_count or 12,
      weather_count = weather_count or 20,
      laps = {},
      excluded_laps = {},
      stint_history = {},
      fuel_samples = {},
      pace_samples = {},
      weather = {},
      tyre_lap = { lap_number = nil, min_c = {}, max_c = {} },
      latest_valid_fuel_l = nil,
      latest_valid_pace_s = nil,
      latest_completed = nil,
      latest_excluded = nil,
      count = 0,
      last_reset_reason = nil,
    }
  end

  function sample_store.reset(store, reason)
    store.laps = {}
    store.excluded_laps = {}
    store.stint_history = {}
    store.fuel_samples = {}
    store.pace_samples = {}
    store.weather = {}
    store.tyre_lap = { lap_number = nil, min_c = {}, max_c = {} }
    store.latest_valid_fuel_l = nil
    store.latest_valid_pace_s = nil
    store.latest_completed = nil
    store.latest_excluded = nil
    store.count = 0
    store.last_reset_reason = reason
  end

  function sample_store.reset_stint(store, reason)
    if #store.fuel_samples > 0 or #store.pace_samples > 0 then
      push_bounded(store.stint_history, {
        reason = reason,
        fuel_samples = store.fuel_samples,
        pace_samples = store.pace_samples,
      }, 4)
    end
    store.laps = {}
    store.fuel_samples = {}
    store.pace_samples = {}
    store.tyre_lap = { lap_number = nil, min_c = {}, max_c = {} }
    store.latest_valid_fuel_l = nil
    store.latest_valid_pace_s = nil
    store.latest_completed = nil
    store.latest_excluded = nil
    store.count = 0
    store.last_reset_reason = reason
  end

  function sample_store.record_lap(store, lap)
    if type(lap) ~= "table" then return false end
    store.latest_completed = lap
    if lap.accepted ~= true then
      push_bounded(store.excluded_laps, lap, store.max_count)
      store.latest_excluded = lap
      return false
    end
    push_bounded(store.laps, lap, store.max_count)
    if type(lap.fuel_used_l) == "number" and lap.fuel_used_l > 0 then
      push_bounded(store.fuel_samples, lap.fuel_used_l, store.max_count)
      store.latest_valid_fuel_l = lap.fuel_used_l
    end
    if type(lap.lap_time_s) == "number" and lap.lap_time_s > 0 then
      push_bounded(store.pace_samples, lap.lap_time_s, store.max_count)
      store.latest_valid_pace_s = lap.lap_time_s
    end
    store.count = #store.laps
    return true
  end

  sample_store.add_lap = sample_store.record_lap

  function sample_store.update_tyre_lap(store, snapshot)
    local session = snapshot and snapshot.session or {}
    local lap_number = session.current_lap
    if type(lap_number) ~= "number" then return end
    if store.tyre_lap.lap_number ~= lap_number then
      store.tyre_lap = { lap_number = lap_number, min_c = {}, max_c = {} }
    end
    local wheels = snapshot.tyres and snapshot.tyres.wheels or {}
    for index = 1, 4 do
      local wheel = wheels[index] or {}
      local value = wheel.core_c
      if type(value) == "number" then
        if store.tyre_lap.min_c[index] == nil or value < store.tyre_lap.min_c[index] then store.tyre_lap.min_c[index] = value end
        if store.tyre_lap.max_c[index] == nil or value > store.tyre_lap.max_c[index] then store.tyre_lap.max_c[index] = value end
      end
    end
  end

  function sample_store.add_weather(store, sample)
    if type(sample) ~= "table" then return end
    push_bounded(store.weather, sample, store.weather_count)
  end

  function sample_store.summary(store)
    return {
      laps = #store.laps,
      excluded = #store.excluded_laps,
      fuel = #store.fuel_samples,
      pace = #store.pace_samples,
      weather = #store.weather,
      stint_history = #store.stint_history,
      latest_excluded_reason = store.latest_excluded and store.latest_excluded.reason or nil,
      max = store.max_count,
    }
  end

  namespace.live.sample_store = sample_store
end
