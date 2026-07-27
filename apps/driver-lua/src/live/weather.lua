do
  local namespace = _G.AVM_PITWALL_F1
  local weather = {}

  local function clamp(value)
    if type(value) ~= "number" then return nil end
    return math.max(0, math.min(1, value))
  end

  function weather.new(max_samples)
    return { history = {}, max_samples = max_samples or 20, last_update_s = nil }
  end

  function weather.normalize(environment)
    environment = environment or {}
    return {
      ambient_c = environment.ambient_c,
      road_c = environment.road_c,
      wind_kmh = environment.wind_kmh,
      weather_type = environment.weather_type,
      rain_intensity = clamp(environment.rain_intensity),
      track_wetness = clamp(environment.track_wetness),
      standing_water = clamp(environment.standing_water),
      grip = environment.grip,
      source = "Measured now",
      freshness_s = 0,
    }
  end

  function weather.update(state, environment, now_s)
    local current = weather.normalize(environment)
    current.observed_s = now_s
    state.history[#state.history + 1] = current
    while #state.history > state.max_samples do table.remove(state.history, 1) end
    state.last_update_s = now_s
    return current
  end

  function weather.trend(state)
    if #state.history < 3 then return { label = "UNKNOWN", text = "Measured trend: Waiting for more readings" } end
    local first = state.history[1]
    local last = state.history[#state.history]
    if type(first.track_wetness) ~= "number" or type(last.track_wetness) ~= "number" then
      return { label = "UNKNOWN", text = "Measured trend: Unavailable" }
    end
    local delta = last.track_wetness - first.track_wetness
    if delta > 0.03 then return { label = "WETTING", text = "Measured trend: Wetting" } end
    if delta < -0.03 then return { label = "DRYING", text = "Measured trend: Drying" } end
    return { label = "STABLE", text = "Measured trend: Stable" }
  end

  function weather.future()
    return {
      label = "UNKNOWN",
      text = "No reliable future forecast",
      source = "No authoritative future source",
      authoritative = false,
      probability = nil,
      eta_s = nil,
    }
  end

  namespace.live.weather = weather
end
