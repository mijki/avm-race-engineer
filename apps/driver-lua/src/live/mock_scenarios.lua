do
  local namespace = _G.AVM_PITWALL_F1
  local mock = {}

  -- Mock values are intentionally isolated from renderers and are selectable only in Garage.
  mock.scenarios = {
    baseline = {
      identity = { car_id = "mock-car-a", track_id = "mock-track", layout_id = "main", driver_name = "Mock driver", session_id = "mock-session-a", configuration_id = "mock-car-a@mock-track" },
      session = { type = "PRACTICE", elapsed_s = 184, remaining_s = 900, lap_limit = nil, completed_laps = 3, current_lap = 4, position = 4, total_cars = 12, paused = false, replay = false, active = true, finished = false },
      car = { speed_kmh = 214, fuel_l = 37.4, fuel_capacity_l = 60, spline = 0.81, distance_session_km = 76.1, pit_lane = false, pit_box = false, lap_time_s = 92.4, previous_lap_time_s = 91.8, best_lap_time_s = 90.9, lap_valid = true, previous_lap_valid = true, last_lap_cuts = 0 },
      tyres = { compound = "medium", core_c = 87, surface_c = 82, wear = 0.18, pressure_kpa = 178, optimum_c = 92 },
      environment = { ambient_c = 22, road_c = 31, wind_kmh = 8, weather_type = "clear", rain_intensity = 0, track_wetness = 0, standing_water = 0, grip = 0.98 },
    },
    alternate = {
      identity = { car_id = "mock-car-b", track_id = "mock-track", layout_id = "main", driver_name = "Mock driver", session_id = "mock-session-b", configuration_id = "mock-car-b@mock-track" },
      session = { type = "RACE", elapsed_s = 642, remaining_s = 1200, lap_limit = 30, completed_laps = 7, current_lap = 8, position = 11, total_cars = 18, paused = false, replay = false, active = true, finished = false },
      car = { speed_kmh = 118, fuel_l = 19.2, fuel_capacity_l = 60, spline = 0.97, distance_session_km = 179.3, pit_lane = false, pit_box = false, lap_time_s = 104.7, previous_lap_time_s = 106.1, best_lap_time_s = 98.2, lap_valid = true, previous_lap_valid = true, last_lap_cuts = 0 },
      tyres = { compound = "hard", core_c = 113, surface_c = 120, wear = 0.76, pressure_kpa = 185, optimum_c = 96 },
      environment = { ambient_c = 27, road_c = 43, wind_kmh = 16, weather_type = "light rain", rain_intensity = 0.18, track_wetness = 0.24, standing_water = 0.03, grip = 0.89 },
    },
  }

  function mock.get(name)
    return mock.scenarios[name or "baseline"]
  end

  namespace.live.mock_scenarios = mock
end
