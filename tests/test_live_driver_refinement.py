from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.live_model import (
    SampleStore,
    StintTracker,
    calculate,
    forward_distance,
    layout_boxes,
    layout_valid,
    normalize_csp,
)


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps" / "driver-lua" / "src"


def fixture(name: str = "live_telemetry_a.json", now: float = 10.0) -> dict:
    raw = json.loads((ROOT / "tests" / "fixtures" / name).read_text(encoding="utf-8"))
    return normalize_csp(raw, now)


class ShellAndLayoutRefinementTests(unittest.TestCase):
    def test_supported_compact_sizes_keep_shell_cards_valid(self) -> None:
        for width, height in ((500, 425), (700, 300), (800, 408), (900, 450), (1600, 370)):
            boxes = layout_boxes(width, height, "compact")
            self.assertTrue(layout_valid(boxes, width, height, "compact"))
            self.assertEqual(boxes["content"], (0.0, 0.0, width, height))
            self.assertGreater(boxes["header"][1], boxes["content"][1])
            self.assertLessEqual(boxes["engineer"][1] + boxes["engineer"][3], height)

    def test_compact_breakpoint_changes_primary_composition(self) -> None:
        narrow = layout_boxes(500, 425, "compact")
        medium = layout_boxes(800, 408, "compact")
        large = layout_boxes(900, 450, "compact")
        self.assertEqual(narrow["pit"][0], narrow["fuel"][0])
        self.assertEqual(narrow["pit"][2], narrow["weather"][0] + narrow["weather"][2] - narrow["fuel"][0])
        self.assertEqual(medium["pit"][0], medium["fuel"][0])
        self.assertEqual(large["pit"][1], large["fuel"][1])
        self.assertLess(large["pace"][0] + large["pace"][2], large["pit"][0])

    def test_manifest_owns_opaque_shell_without_forcing_scrollbar_off(self) -> None:
        manifest = (ROOT / "apps" / "driver-lua" / "manifest" / "manifest.ini").read_text(encoding="utf-8")
        self.assertIn("NAME = AVM PitWall F1 Dev", manifest)
        self.assertIn("PADDING = 0,0", manifest)
        self.assertIn("NO_BACKGROUND", manifest)
        self.assertNotIn("NO_SCROLLBAR", manifest)
        self.assertIn("MIN_SIZE = 500, 240", manifest)

        app = (SOURCE / "app.lua").read_text(encoding="utf-8")
        bootstrap = (SOURCE / "bootstrap.lua").read_text(encoding="utf-8")
        self.assertIn("function render_content_surface", app)
        self.assertIn('theme.color("background")', app)
        self.assertIn('components.header(vm, header)', (SOURCE / "ui" / "compact_mode.lua").read_text(encoding="utf-8"))
        self.assertIn("runtime.app_entry == nil", bootstrap)


class SamplePersistenceRefinementTests(unittest.TestCase):
    def _store_with_history(self) -> tuple[dict, StintTracker, SampleStore]:
        snap = fixture()
        stint = StintTracker(active=True, start_monotonic_s=0, start_fuel_l=55)
        store = SampleStore()
        for lap_time, fuel_used in ((116.2, 2.7), (116.5, 2.8), (116.4, 2.75), (116.6, 2.72), (116.3, 2.74)):
            store.add_lap({"accepted": True, "lap_time_s": lap_time, "fuel_used_l": fuel_used})
        return snap, stint, store

    def test_invalid_lap_preserves_valid_representatives_and_is_diagnostic(self) -> None:
        snap, stint, store = self._store_with_history()
        before = calculate(snap, stint, store, None, 10)
        store.add_lap({"accepted": False, "reason": "INVALID_LAP", "lap_time_s": 150, "fuel_used_l": None})
        after = calculate(snap, stint, store, None, 10)
        self.assertEqual(after["fuel"]["per_lap"]["value"], before["fuel"]["per_lap"]["value"])
        self.assertEqual(after["pace"]["rolling"]["value"], before["pace"]["rolling"]["value"])
        self.assertEqual(after["pace"]["latest_valid"]["value"], before["pace"]["latest_valid"]["value"])
        self.assertEqual(after["latest_excluded"]["reason"], "INVALID_LAP")
        self.assertEqual(len(store.excluded_laps), 1)

    def test_refuel_archives_stint_samples_without_negative_consumption(self) -> None:
        _, _, store = self._store_with_history()
        store.reset_stint("REFUEL_TRANSITION")
        self.assertEqual(store.fuel_samples, [])
        self.assertEqual(store.pace_samples, [])
        self.assertIsNone(store.latest_valid_fuel_l)
        self.assertEqual(store.stint_history[0]["reason"], "REFUEL_TRANSITION")
        store.add_lap({"accepted": False, "reason": "REFUEL_TRANSITION", "fuel_used_l": None})
        self.assertEqual(store.fuel_samples, [])


class PaceFuelComparisonTests(unittest.TestCase):
    def test_pace_target_and_three_comparisons_are_distinct(self) -> None:
        snap, stint, store = SamplePersistenceRefinementTests()._store_with_history()
        result = calculate(snap, stint, store, None, 10, {"pace_s": 116.0})
        self.assertEqual(result["pace"]["target"]["value"], 116.0)
        self.assertAlmostEqual(result["pace"]["delta_to_target"]["value"], 0.3)
        self.assertAlmostEqual(result["pace"]["delta_to_average"]["value"], -0.1)
        self.assertAlmostEqual(result["pace"]["average_vs_target"]["value"], 0.4)

    def test_missing_target_is_neutral_and_not_fabricated(self) -> None:
        snap, stint, store = SamplePersistenceRefinementTests()._store_with_history()
        result = calculate(snap, stint, store, None, 10)
        self.assertIsNone(result["pace"]["target"]["value"])
        self.assertEqual(result["pace"]["delta_to_target"]["reason"], "TARGET_NOT_CONFIGURED")
        self.assertIsNone(result["fuel"]["target_per_lap"]["value"])

    def test_fuel_target_and_three_comparisons_are_distinct(self) -> None:
        snap, stint, store = SamplePersistenceRefinementTests()._store_with_history()
        result = calculate(snap, stint, store, None, 10, {"fuel_per_lap_l": 2.70})
        self.assertEqual(result["fuel"]["target_per_lap"]["value"], 2.70)
        self.assertAlmostEqual(result["fuel"]["delta_target"]["value"], 0.04)
        self.assertAlmostEqual(result["fuel"]["delta_average"]["value"], -0.002)
        self.assertAlmostEqual(result["fuel"]["average_vs_target"]["value"], 0.042)

    def test_pit_prediction_requires_route_and_fresh_data(self) -> None:
        snap, stint, store = SamplePersistenceRefinementTests()._store_with_history()
        calibration = {"track_length_m": 5000, "pit_entry_spline": 0.93}
        missing_route = calculate(snap, stint, store, calibration, 10)
        self.assertIsNone(missing_route["fuel"]["at_pit"]["value"])
        self.assertEqual(missing_route["fuel"]["at_pit"]["reason"], "PIT_ROUTE_NOT_CONFIGURED")
        fresh_route = dict(calibration, pit_route_additional_m=0)
        snap["observed_monotonic_s"] = 0
        stale = calculate(snap, stint, store, fresh_route, 10)
        self.assertIsNone(stale["fuel"]["at_pit"]["value"])
        self.assertEqual(stale["fuel"]["at_pit"]["reason"], "STALE_TELEMETRY")


class FourTyreAndWeatherTests(unittest.TestCase):
    def _wheel_snapshot(self) -> dict:
        snap = fixture()
        snap["tyres"]["wheels"] = [
            {"label": "FL", "core_c": 84, "pressure_psi": 26.0, "wear": 0.03, "optimum_c": 92, "grain": 0.0, "blister": 0.0, "flat_spot": 0.0},
            {"label": "FR", "core_c": 88, "pressure_psi": 26.4, "wear": 0.04, "optimum_c": 92, "flat_spot": 0.12},
            {"label": "RL", "core_c": 92, "pressure_psi": 27.0, "wear": 0.05, "optimum_c": 92, "grain": 0.4},
            {"label": "RR", "core_c": 106, "pressure_psi": 27.2, "wear": 0.06, "optimum_c": 92, "blister": 0.4},
        ]
        return snap

    def test_four_wheels_keep_independent_values_and_lap_min_max(self) -> None:
        snap = self._wheel_snapshot()
        store = SampleStore()
        store.update_tyre_lap(snap)
        next_sample = copy.deepcopy(snap)
        next_sample["tyres"]["wheels"][0]["core_c"] = 80
        next_sample["tyres"]["wheels"][1]["core_c"] = 95
        store.update_tyre_lap(next_sample)
        result = calculate(snap, StintTracker(), store, None, 10, {"pressure_targets_psi": {"medium": {"FL": 26.5, "FR": 26.5}}})
        wheels = result["tyres"]["wheels"]
        self.assertEqual([wheel["label"] for wheel in wheels], ["FL", "FR", "RL", "RR"])
        self.assertEqual(wheels[0]["core_c"], 84)
        self.assertEqual(wheels[1]["core_c"], 88)
        self.assertEqual(wheels[0]["lap_min_c"], 80)
        self.assertEqual(wheels[1]["lap_max_c"], 95)
        self.assertAlmostEqual(wheels[0]["pressure_delta_psi"], -0.5)
        self.assertAlmostEqual(wheels[0]["life"], 97)
        self.assertEqual(wheels[1]["state"], "FLAT_SPOTTED")
        self.assertEqual(wheels[2]["grain"], None)
        self.assertEqual(wheels[3]["blister"], None)

    def test_tyre_lap_min_max_resets_on_lap_boundary(self) -> None:
        snap = self._wheel_snapshot()
        store = SampleStore()
        store.update_tyre_lap(snap)
        boundary = copy.deepcopy(snap)
        boundary["session"]["current_lap"] += 1
        boundary["tyres"]["wheels"][0]["core_c"] = 100
        store.update_tyre_lap(boundary)
        self.assertEqual(store.tyre_lap_min_c[1], 100)
        self.assertEqual(store.tyre_lap_max_c[1], 100)

    def test_damage_without_verified_scale_is_not_rendered_as_zero(self) -> None:
        source = (SOURCE / "live" / "calculations.lua").read_text(encoding="utf-8")
        self.assertIn('grain = numeric_metric(nil, " %"', source)
        self.assertIn('blister = numeric_metric(nil, " %"', source)
        self.assertIn('flat_spot and "CSP_TYRE_FLATSPOT_UNIT_SCALE"', source)

    def test_weather_and_wind_labels_are_explicit_and_forecast_honest(self) -> None:
        formatting = (SOURCE / "formatting.lua").read_text(encoding="utf-8")
        weather = (SOURCE / "live" / "weather.lua").read_text(encoding="utf-8")
        compact = (SOURCE / "ui" / "compact_mode.lua").read_text(encoding="utf-8")
        components = (SOURCE / "ui" / "components.lua").read_text(encoding="utf-8")
        self.assertIn('raw:match("^CURRENT%s+%d+")', formatting)
        self.assertIn('function formatting.grip', formatting)
        self.assertIn('function formatting.cardinal_direction', formatting)
        self.assertIn("wind_direction_deg", weather)
        self.assertIn('"No reliable future forecast"', weather)
        self.assertIn('"WIND  " .. vm.weather.wind', compact)


class CalibrationIndicatorDocumentationTests(unittest.TestCase):
    def test_wraparound_and_calibration_safety_contract(self) -> None:
        distance, reason = forward_distance(0.97, 0.10, 25378)
        self.assertAlmostEqual(distance, (0.13) * 25378)
        self.assertEqual(reason, "PIT_ENTRY_WRAPAROUND_APPLIED")
        state = (SOURCE / "app_state.lua").read_text(encoding="utf-8")
        self.assertIn("ARM PIT ENTRY", (SOURCE / "ui" / "garage_mode.lua").read_text(encoding="utf-8"))
        self.assertIn("calibration_capture_armed_until", state)
        self.assertIn("self.mode ~= \"garage\"", state)
        self.assertIn("track_id", state)
        self.assertIn("layout_id", state)

    def test_health_and_engineer_models_are_separate(self) -> None:
        status = (SOURCE / "live" / "status_builder.lua").read_text(encoding="utf-8")
        telemetry = (SOURCE / "live" / "telemetry.lua").read_text(encoding="utf-8")
        compact = (SOURCE / "ui" / "compact_mode.lua").read_text(encoding="utf-8")
        components = (SOURCE / "ui" / "components.lua").read_text(encoding="utf-8")
        self.assertIn('bridge = "NOT_USED"', status)
        self.assertIn('engineer = "NOT_ASSIGNED"', status)
        self.assertIn("message_id", telemetry)
        self.assertIn("requires_acknowledgement", telemetry)
        self.assertIn('components.card(status, "ENGINEER"', compact)
        self.assertIn("components.header(vm, header)", compact)
        self.assertIn('function components.header(vm, box)', components)
        self.assertIn('components.indicator(indicators.telemetry', components)
        self.assertIn('components.indicator(indicators.bridge', components)
        self.assertIn('components.indicator(indicators.engineer', components)

    def test_thresholds_and_unsupported_states_are_explicit(self) -> None:
        config = (SOURCE / "config.lua").read_text(encoding="utf-8")
        view_model = (SOURCE / "view_model.lua").read_text(encoding="utf-8")
        self.assertIn("pace_delta_threshold_s", config)
        self.assertIn("fuel_comparison_threshold_l", config)
        self.assertIn("pressure_delta_threshold_psi", config)
        self.assertIn("temperature_delta_threshold_c", config)
        self.assertIn("local function metric_tone", view_model)
        self.assertIn('"LAP " .. tostring(session.current_lap)', view_model)
        self.assertIn('return "neutral"', view_model)
        self.assertIn('return "critical"', view_model)


if __name__ == "__main__":
    unittest.main()
