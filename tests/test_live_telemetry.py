from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.live_model import (
    LapTracker,
    SampleStore,
    StintTracker,
    calculate,
    classify_source,
    forward_distance,
    future_weather,
    identity_key,
    live_source_from_api,
    normalize_csp,
    visible_projection,
    weather_trend,
)


ROOT = Path(__file__).resolve().parents[1]


def fixture(name: str, now: float = 10.0) -> dict:
    raw = json.loads((ROOT / "tests" / "fixtures" / name).read_text(encoding="utf-8"))
    return normalize_csp(raw, now)


class LiveTelemetryTests(unittest.TestCase):
    def test_stint_ordinal_current_stint_lap_and_race_lap_follow_confirmed_boundary(self) -> None:
        def snapshot(completed_laps: int, *, pit_lane: bool = False, now: float = 0.0) -> dict:
            result = fixture("live_telemetry_a.json", now)
            result["session"]["completed_laps"] = completed_laps
            result["session"]["race_lap"] = completed_laps
            result["session"]["current_lap"] = completed_laps + 1
            result["car"]["pit_lane"] = pit_lane
            result["car"]["pit_box"] = pit_lane
            return result

        def progress(current: dict, tracker: StintTracker, now: float) -> tuple[int, int, int]:
            calculated = calculate(current, tracker, SampleStore(), None, now)
            return tuple(calculated["stint"][name]["value"] for name in ("stint_number", "current_stint_lap", "race_lap"))

        tracker = StintTracker()
        first = snapshot(0)
        tracker.update(first, 0)
        for completed_laps in (1, 2, 3):
            current = snapshot(completed_laps, now=completed_laps * 10)
            tracker.update(current, completed_laps * 10)
            tracker.record_lap({"incomplete": False, "accepted": True})
        self.assertEqual(progress(current, tracker, 30), (1, 3, 3))

        pit_entry = snapshot(3, pit_lane=True, now=31)
        tracker.update(pit_entry, 31)
        self.assertEqual(progress(pit_entry, tracker, 31), (1, 3, 3))

        unconfirmed_exit = snapshot(3, now=32)
        tracker.update(unconfirmed_exit, 32)
        self.assertFalse(tracker.active)
        self.assertEqual(progress(unconfirmed_exit, tracker, 32), (1, 3, 3))

        confirmed_exit = snapshot(3, now=32.2)
        tracker.update(confirmed_exit, 32.2, boundary_event={"event_type": "PIT_EXIT_CONFIRMED"})
        self.assertEqual(progress(confirmed_exit, tracker, 32.2), (2, 0, 3))
        self.assertEqual(tracker.previous_stint["stint_number"], 1)
        self.assertEqual(tracker.previous_stint["completed_laps"], 3)
        self.assertEqual(len(tracker.stint_history), 1)

        for completed_laps in (4, 5):
            current = snapshot(completed_laps, now=completed_laps * 10)
            tracker.update(current, completed_laps * 10)
            tracker.record_lap({"incomplete": False, "accepted": completed_laps == 5, "reason": None if completed_laps == 5 else "OUT_LAP_EXCLUDED"})
            self.assertEqual(progress(current, tracker, completed_laps * 10), (2, completed_laps - 3, completed_laps))

    def test_ac_current_lap_is_not_used_as_completed_race_lap(self) -> None:
        snapshot = fixture("live_telemetry_a.json")
        snapshot["session"]["completed_laps"] = 3
        snapshot["session"]["race_lap"] = 3
        snapshot["session"]["current_lap"] = 4
        normalized = normalize_csp(snapshot, 10.0)
        self.assertEqual(normalized["session"]["race_lap"], 3)
        self.assertEqual(normalized["session"]["current_lap"], 4)

        view_model = (ROOT / "apps" / "driver-lua" / "src" / "view_model.lua").read_text(encoding="utf-8")
        self.assertIn("stint = live_metric(stint_number, 0)", view_model)
        self.assertNotIn("stint = live_metric(status.stint and status.stint.completed_laps", view_model)
        self.assertIn('"RACE LAP "', view_model)

    def test_normalization_preserves_unavailable_as_none(self) -> None:
        snap = normalize_csp({"identity": {}, "session": {}, "car": {}, "tyres": {}, "environment": {}}, 1.0)
        self.assertIsNone(snap["car"]["fuel_l"])
        self.assertIsNone(snap["session"]["remaining_s"])
        self.assertIsNone(snap["environment"]["rain_intensity"])

    def test_valid_minimal_live_core_is_live(self) -> None:
        snap = fixture("live_telemetry_a.json")
        snap["session"]["lap_limit"] = 30
        result = live_source_from_api(ac_available=True, sim={}, car={}, snapshot=snap)
        self.assertEqual(result["availability"], "live")
        self.assertTrue(result["core_valid"])

    def test_optional_missing_fields_remain_live_and_are_field_level(self) -> None:
        snap = fixture("live_telemetry_a.json")
        snap["tyres"]["core_c"] = None
        snap["environment"]["track_wetness"] = None
        result = classify_source(snap)
        self.assertEqual(result["availability"], "partial")
        self.assertTrue(result["core_valid"])
        self.assertIn("tyres.core_c", result["optional_missing"])
        self.assertIn("environment.track_wetness", result["optional_missing"])

    def test_missing_core_is_partial_but_missing_car_or_sim_is_unavailable(self) -> None:
        snap = fixture("live_telemetry_a.json")
        snap["car"]["fuel_l"] = None
        partial = live_source_from_api(ac_available=True, sim={}, car={}, snapshot=snap)
        self.assertEqual(partial["availability"], "partial")
        self.assertIn("car.fuel_l", partial["missing_core"])
        self.assertEqual(live_source_from_api(ac_available=True, sim={}, car=None, snapshot=snap)["availability"], "unavailable")
        self.assertEqual(live_source_from_api(ac_available=False, sim={}, car={}, snapshot=snap)["availability"], "unavailable")

    def test_last_valid_sample_can_be_classified_stale_without_mock_substitution(self) -> None:
        snap = fixture("live_telemetry_a.json")
        result = live_source_from_api(ac_available=True, sim={}, car={}, snapshot=snap, stale=True)
        self.assertEqual(result["availability"], "stale")
        self.assertTrue(result["core_valid"])

    def test_two_fixtures_change_visible_data_binding(self) -> None:
        first = fixture("live_telemetry_a.json")
        second = fixture("live_telemetry_b.json")
        store = SampleStore()
        calc_a = calculate(first, StintTracker(), store, None, 10)
        calc_b = calculate(second, StintTracker(), store, None, 10)
        self.assertNotEqual(visible_projection(first, calc_a), visible_projection(second, calc_b))

    def test_identity_key_changes_for_car_and_session(self) -> None:
        first = fixture("live_telemetry_a.json")
        second = fixture("live_telemetry_b.json")
        self.assertNotEqual(identity_key(first), identity_key(second))

    def test_completed_valid_lap_produces_fuel_and_pace_samples(self) -> None:
        first = fixture("live_telemetry_a.json")
        first["session"]["completed_laps"] = 2
        tracker = LapTracker()
        self.assertIsNone(tracker.update(first))
        second = fixture("live_telemetry_a.json", 110)
        second["session"]["completed_laps"] = 3
        second["car"]["fuel_l"] = 35
        second["car"]["distance_session_km"] = 17
        event = tracker.update(second)
        self.assertIsNotNone(event)
        self.assertTrue(event["accepted"])
        self.assertEqual(event["fuel_used_l"], 5)
        self.assertEqual(event["distance_km"], 5)
        self.assertEqual(event["lap_time_s"], 99)

    def test_refuel_transition_is_not_a_negative_consumption_sample(self) -> None:
        first = fixture("live_telemetry_a.json")
        tracker = LapTracker()
        tracker.update(first)
        second = fixture("live_telemetry_a.json", 110)
        second["session"]["completed_laps"] = 3
        second["car"]["fuel_l"] = 55
        event = tracker.update(second)
        self.assertIsNotNone(event)
        self.assertFalse(event["accepted"])
        self.assertIsNone(event["fuel_used_l"])

    def test_pit_laps_are_excluded(self) -> None:
        first = fixture("live_telemetry_a.json")
        first["car"]["pit_lane"] = True
        tracker = LapTracker()
        tracker.update(first)
        second = fixture("live_telemetry_a.json", 110)
        second["session"]["completed_laps"] = 3
        second["car"]["pit_lane"] = True
        event = tracker.update(second)
        self.assertFalse(event["accepted"])
        self.assertEqual(event["reason"], "PIT_LAP_EXCLUDED")

    def test_stint_starts_on_track_and_ends_on_pit_entry(self) -> None:
        first = fixture("live_telemetry_a.json")
        tracker = StintTracker()
        tracker.update(first, 10)
        self.assertTrue(tracker.active)
        self.assertEqual(tracker.start_fuel_l, 40)
        second = fixture("live_telemetry_a.json", 20)
        second["car"]["pit_lane"] = True
        tracker.update(second, 20)
        self.assertFalse(tracker.active)
        self.assertEqual(tracker.end_reason, "PIT_ENTRY")

    def test_identity_and_session_restart_reset_stint(self) -> None:
        tracker = StintTracker()
        first = fixture("live_telemetry_a.json")
        tracker.update(first, 10)
        restart = fixture("live_telemetry_a.json", 20)
        restart["session"]["completed_laps"] = 0
        tracker.update(restart, 20)
        self.assertTrue(tracker.active)
        self.assertEqual(tracker.start_monotonic_s, 20)
        changed = fixture("live_telemetry_b.json", 30)
        tracker.update(changed, 30)
        self.assertEqual(tracker.start_monotonic_s, 30)


class CalculationTests(unittest.TestCase):
    def test_fuel_rates_range_and_pit_prediction(self) -> None:
        snap = fixture("live_telemetry_a.json")
        stint = StintTracker(active=True, start_monotonic_s=0, start_fuel_l=50)
        store = SampleStore()
        for used, pace in ((5, 100), (5, 100), (5, 100)):
            store.add_lap({"accepted": True, "fuel_used_l": used, "lap_time_s": pace})
        calibration = {"track_id": "fixture-track", "layout_id": "main", "track_length_m": 5000, "pit_entry_spline": 0.93, "pit_route_additional_m": 200}
        result = calculate(snap, stint, store, calibration, 10)
        self.assertAlmostEqual(result["fuel"]["per_lap"]["value"], 5)
        self.assertAlmostEqual(result["fuel"]["per_km"]["value"], 1)
        self.assertAlmostEqual(result["fuel"]["per_min"]["value"], 3)
        self.assertAlmostEqual(result["fuel"]["laps"]["value"], 8)
        self.assertAlmostEqual(result["fuel"]["time"]["value"], 800)
        self.assertAlmostEqual(result["pit"]["distance"]["value"], 600)
        self.assertAlmostEqual(result["fuel"]["at_pit"]["value"], 39.2)

    def test_pit_entry_wraparound_and_missing_calibration(self) -> None:
        distance, reason = forward_distance(0.97, 0.10, 25378)
        self.assertAlmostEqual(distance, (1 - 0.97 + 0.10) * 25378)
        self.assertEqual(reason, "PIT_ENTRY_WRAPAROUND_APPLIED")
        self.assertEqual(forward_distance(0.81, None, 25378)[1], "PIT_ENTRY_NOT_CALIBRATED")
        self.assertIsNone(forward_distance(0.81, None, 25378)[0])

    def test_insufficient_samples_are_low_confidence_and_unavailable(self) -> None:
        snap = fixture("live_telemetry_a.json")
        result = calculate(snap, StintTracker(), SampleStore(), None, 10)
        self.assertIsNone(result["fuel"]["per_lap"]["value"])
        self.assertEqual(result["fuel"]["per_lap"]["confidence_band"], "low")
        self.assertEqual(result["pit"]["distance"]["reason"], "PIT_ENTRY_NOT_CALIBRATED")

    def test_sample_store_is_bounded(self) -> None:
        store = SampleStore(max_count=3)
        for index in range(8):
            store.add_lap({"accepted": True, "fuel_used_l": index + 1, "lap_time_s": index + 90})
        self.assertEqual(len(store.laps), 3)
        self.assertEqual(len(store.fuel_samples), 3)
        self.assertEqual(len(store.pace_samples), 3)


class WeatherTests(unittest.TestCase):
    def test_measured_trend_and_future_weather_honesty(self) -> None:
        history = [{"track_wetness": 0.0}, {"track_wetness": 0.05}, {"track_wetness": 0.12}]
        self.assertEqual(weather_trend(history), "WETTING")
        future = future_weather()
        self.assertEqual(future["text"], "No reliable future forecast")
        self.assertIsNone(future["probability"])
        self.assertIsNone(future["eta_s"])


if __name__ == "__main__":
    unittest.main()
