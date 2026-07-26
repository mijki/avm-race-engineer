local namespace = _G.AVM_PITWALL_F1

namespace.config = {
  product_name = "AVM PitWall",
  build_name = "F1 DEV",
  default_mode = "compact",
  modes = { "compact", "expanded", "garage" },
  default_scenario = "NORMAL_ON_PLAN_DRY",
  max_alert_repeats = 3,
  alert_repeat_seconds = { critical = 8, high = 14, normal = 24, low = 40 },
  alert_expiry_seconds = { critical = 120, high = 90, normal = 55, low = 35 },
  max_text_length = 96,
  max_scenario_history = 4,
  sound_volume = 0.7,
  ui_scale = 1.0,
}
