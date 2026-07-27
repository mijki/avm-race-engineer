from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.live_model import (
    LapTracker,
    SampleStore,
    StintTracker,
    calculate,
    forward_distance,
    future_weather,
    identity_key,
    normalize_csp,
    visible_projection,
    weather_trend,
)


ROOT = Path(__file__).resolve().parents[1]


def fixture(name: str, now: float = 10.0) -> dict:
    raw = json.loads((ROOT / "tests" / "fixtures" / name).read_text(encoding="utf-8"))
    return normalize_csp(raw, now)


class LiveTelemetryTests(unittest.TestCase):
    def test_normalization_preserves_unavailable_as_none(self) -> None:
        snap = normalize_csp({"identity": {}, "session": {}, "car": {}, "tyres": {}, "environment": {}}, 1.0)
        self.assertIsNone(snap["car"]["fuel_l"])
        self.assertIsNone(snap["session"]["remaining_s"])
        self.assertIsNone(snap["environment"]["rain_intensity"])

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
