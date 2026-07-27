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
      fuel_samples = {},
      pace_samples = {},
      weather = {},
      count = 0,
      last_reset_reason = nil,
    }
  end

  function sample_store.reset(store, reason)
    store.laps = {}
    store.fuel_samples = {}
    store.pace_samples = {}
    store.weather = {}
    store.count = 0
    store.last_reset_reason = reason
  end

  function sample_store.add_lap(store, lap)
    if type(lap) ~= "table" or lap.accepted ~= true then return false end
    push_bounded(store.laps, lap, store.max_count)
    if type(lap.fuel_used_l) == "number" and lap.fuel_used_l > 0 then
      push_bounded(store.fuel_samples, lap.fuel_used_l, store.max_count)
    end
    if type(lap.lap_time_s) == "number" and lap.lap_time_s > 0 then
      push_bounded(store.pace_samples, lap.lap_time_s, store.max_count)
    end
    store.count = #store.laps
    return true
  end

  function sample_store.add_weather(store, sample)
    if type(sample) ~= "table" then return end
    push_bounded(store.weather, sample, store.weather_count)
  end

  function sample_store.summary(store)
    return {
      laps = #store.laps,
      fuel = #store.fuel_samples,
      pace = #store.pace_samples,
      weather = #store.weather,
      max = store.max_count,
    }
  end

  namespace.live.sample_store = sample_store
end
