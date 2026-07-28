from __future__ import annotations

import copy
import unittest

from tools.forecast_engine import ForecastEngine, calculate_forecasts, serialize_forecasts
from tools.race_engine_core import to_plain
from tools.stint_calculations import StintCalculationEngine


def lap(number: int, *, time: float = 90.0, fuel: float = 2.5, completed: float | None = None) -> dict:
    completed = number * 100 if completed is None else completed
    return {
        "schema_version": "completed-lap-v1",
        "lap_id": f"lap-{number}",
        "identity_key": "car|track|main|session|cfg",
        "lap_number": number,
        "started_at_s": completed - 90,
        "completed_at_s": completed,
        "lap_time_s": time,
        "official_validity": True,
        "classification": "NORMAL",
        "weather_regime": "DRY",
        "fuel": {"use_l": fuel, "measurement_complete": True},
        "eligibility": {
            "useForPace": True,
            "useForFuel": True,
            "useForTyres": True,
            "useForProjection": True,
            "useForOfficialAverage": True,
        },
    }


def snapshot(*, current_lap: float = 10, fuel: float = 30, spline: float = 0.20, pit_lane: bool = False) -> dict:
    return {
        "schema_version": "telemetry-snapshot-v1",
        "snapshot_id": f"snapshot-{current_lap}",
        "observed_monotonic_s": 1000,
        "identity": {"car_id": "car", "track_id": "track", "layout_id": "main", "session_id": "session", "configuration_id": "cfg"},
        "session": {"current_lap": current_lap, "lap_limit": 40, "track_length_m": 5000},
        "car": {"fuel_l": fuel, "spline": spline, "speed_kmh": 200, "pit_lane": pit_lane, "pit_box": False},
    }


def calculated(laps: list[dict] | None = None, *, snapshot_value: dict | None = None, events=()):
    return StintCalculationEngine({"active_regime": "DRY", "now_s": 1000}).calculate(laps or [lap(i) for i in range(1, 11)], events, current_snapshot=snapshot_value or snapshot())


class ForecastEngineTests(unittest.TestCase):
    def test_time_lap_fuel_constraints_and_binding_constraint(self):
        result = ForecastEngine({"stint_time_limit_s": 2000, "stint_lap_limit": 20, "driver_rule_laps": 25, "tyre_rule_laps": 30, "reserve_fuel_l": 2, "race_lap_limit": 40, "track_length_m": 5000}).calculate(calculated(), current_snapshot=snapshot(fuel=20))
        self.assertEqual(result["stint"]["constraints"]["time_limited"]["remaining_time_s"], 1010)
        self.assertEqual(result["stint"]["constraints"]["lap_limited"]["remaining_laps"], 10)
        self.assertEqual(result["stint"]["constraints"]["fuel_limited"]["remaining_laps"], 7.2)
        self.assertEqual(result["stint"]["binding_constraint"], "fuel_limited")
        self.assertEqual(result["stint"]["remaining_stint_laps"]["value"], 7.2)

    def test_race_finish_and_fuel_requirements_are_separate_from_measurements(self):
        result = ForecastEngine({"race_lap_limit": 40, "reserve_fuel_l": 2, "track_length_m": 5000}).calculate(calculated(), current_snapshot=snapshot(current_lap=10, fuel=60))
        self.assertEqual(result["race"]["remaining_laps"]["value"], 30)
        self.assertEqual(result["race"]["predicted_finish_lap"]["value"], 40)
        self.assertEqual(result["race"]["fuel_required_to_finish"]["value"], 77)
        self.assertEqual(result["fuel"]["required_to_finish"]["value"], 77)
        self.assertEqual(result["fuel"]["expected_at_finish"]["value"], -15)
        self.assertEqual(result["fuel"]["margin_vs_required"]["value"], -17)

    def test_planned_pit_fuel_metrics_and_no_target_comparison(self):
        result = ForecastEngine({"race_lap_limit": 40, "planned_pit_lap": 15, "reserve_fuel_l": 2, "fuel_target_l": None}).calculate(calculated(), current_snapshot=snapshot(current_lap=10, fuel=30))
        self.assertEqual(result["fuel"]["required_to_planned_pit"]["value"], 14.5)
        self.assertEqual(result["fuel"]["required_fuel_per_lap_to_planned_pit"]["value"], 2.9)
        self.assertEqual(result["fuel"]["expected_at_planned_pit"]["value"], 17.5)
        self.assertEqual(result["fuel"]["required_fuel_per_lap_now"]["value"], 2.5)
        self.assertEqual(result["fuel"]["target_delta"]["unavailable_reason"], "TARGET_NOT_CONFIGURED")

    def test_pit_entry_wraparound_and_already_passed(self):
        config = {"track_length_m": 5000, "planned_pit_lap": 11, "pit_marker": {"state": "PROVISIONAL", "entry_spline": 0.10}}
        wrap = ForecastEngine(config).calculate(calculated(), current_snapshot=snapshot(current_lap=10, spline=0.97), pit_diagnostics={"marker": config["pit_marker"]})
        self.assertAlmostEqual(wrap["pit"]["distance_to_entry"]["value"], 650)
        self.assertFalse(wrap["pit"]["entry_already_passed"])
        self.assertEqual(wrap["pit"]["marker"]["state"], "PROVISIONAL")
        passed = ForecastEngine({**config, "planned_pit_lap": 10}).calculate(calculated(), current_snapshot=snapshot(current_lap=10, spline=0.20), pit_diagnostics={"marker": config["pit_marker"]})
        self.assertTrue(passed["pit"]["entry_already_passed"])
        self.assertIn("PLANNED_ENTRY_PASSED", passed["recommendation_states"])

    def test_marker_unavailable_does_not_hide_live_pit_state(self):
        result = calculate_forecasts(calculated(), config={"track_length_m": 5000}, current_snapshot=snapshot(pit_lane=True), pit_diagnostics={"state": "IN_PIT_LANE", "live_pit_lane": True, "live_pit_box": False})
        self.assertTrue(result["pit"]["live"]["pit_lane"])
        self.assertIsNone(result["pit"]["distance_to_entry"]["value"])
        self.assertEqual(result["pit"]["distance_to_entry"]["unavailable_reason"], "PIT_ENTRY_NOT_CALIBRATED")

    def test_pit_confidence_service_and_drive_through_boundary(self):
        marker = {"state": "CONFIRMED", "confidence": 1.0, "entry_spline": 0.10, "timing": {"normal_stops": [{"classification": "NORMAL_STOP", "entry_to_box_s": 8, "service_duration_s": 22, "box_to_exit_s": 7, "total_lane_duration_s": 37}]}}
        result = ForecastEngine({"track_length_m": 5000, "planned_pit_lap": 12, "planned_service_duration_s": 24, "pit_marker": marker}).calculate(calculated(), current_snapshot=snapshot(current_lap=10), pit_diagnostics={"marker": marker})
        self.assertEqual(result["pit"]["timing_confidence"], "HIGH")
        self.assertEqual(result["pit"]["cycle"]["service_duration"]["value"], 24)
        self.assertEqual(result["pit"]["cycle"]["total_pit_loss"]["value"], 37)
        drive = {"state": "LEARNED", "entry_spline": 0.1, "timing": {"last_classification": "DRIVE_THROUGH"}}
        drive_result = ForecastEngine({"track_length_m": 5000, "pit_marker": drive}).calculate(calculated(), current_snapshot=snapshot(), pit_diagnostics={"marker": drive})
        self.assertEqual(drive_result["pit"]["cycle"]["service_duration"]["unavailable_reason"], "DRIVE_THROUGH_ONLY_EVIDENCE")

    def test_stale_inputs_degrade_and_future_weather_is_not_fabricated(self):
        calc = calculated()
        calc = to_plain(calc)
        calc["pace"]["representative_pace"]["freshness_s"] = 999
        result = ForecastEngine({"stale_after_s": 180}).calculate(calc, current_snapshot=snapshot())
        self.assertEqual(result["pace_input"]["unavailable_reason"], "NO_COMPATIBLE_PACE_MODEL") if result["pace_input"]["value"] is None else self.assertEqual(result["pace_input"]["value"], 90)
        self.assertEqual(result["pace_input"]["sample_count"], 10)
        self.assertIsNone(result["weather"]["future"]["value"])
        self.assertEqual(result["weather"]["future"]["unavailable_reason"], "FUTURE_WEATHER_SOURCE_UNAVAILABLE")

    def test_invalidation_supersession_and_deterministic_serialization(self):
        engine = ForecastEngine({"race_lap_limit": 40, "now_s": 1000})
        first = engine.calculate(calculated())
        second = engine.calculate(calculated(), events=[{"event_type": "RESET"}], previous_forecast=first)
        self.assertTrue(second["invalidation"]["invalidated"])
        self.assertIn("RESET", second["invalidation"]["reason_codes"])
        self.assertEqual(second["invalidation"]["supersedes"], first["forecast_id"])
        self.assertEqual(serialize_forecasts(first), serialize_forecasts(engine.calculate(calculated())))

    def test_post_pit_empty_stint_is_engine_owned_and_retains_previous_stint(self):
        events = [{"event_id": "pit-exit", "event_type": "PIT_EXIT_CONFIRMED", "detection_time_s": 250}]
        before = calculated([lap(1), lap(2)], snapshot_value=snapshot(current_lap=3), events=events)
        self.assertEqual(before["progress"]["current_stint_id"], "stint:car|track|main|session|cfg:2")
        self.assertEqual(before["progress"]["current_stint_lap"], 0)
        self.assertEqual(before["progress"]["current_stint_lap_zero_based"], 0)
        self.assertEqual(before["progress"]["previous_stint"]["stint_number"], 1)
        after = calculated([lap(1), lap(2), lap(3, completed=300)], snapshot_value=snapshot(current_lap=3), events=events)
        self.assertEqual(after["progress"]["current_stint_id"], "stint:car|track|main|session|cfg:2")
        self.assertEqual(after["progress"]["current_stint_lap_zero_based"], 1)

    def test_no_network_or_runtime_loader_boundary(self):
        from pathlib import Path

        source = Path("tools/forecast_engine.py").read_text(encoding="utf-8").lower()
        for forbidden in ("socket", "requests", "require(", "dofile(", "getcarstate", "forecast rain eta"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
