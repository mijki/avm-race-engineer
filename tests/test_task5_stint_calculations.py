from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.lap_eligibility import EligibilityEngine
from tools.stint_calculations import StintCalculationEngine, calculate_stint, serialize_calculations


def raw_lap(number: int, *, time: float = 90.0, fuel: float = 2.5, regime: str = "DRY", official: bool = True, pace: bool = True, fuel_ok: bool = True, tyres_ok: bool = True, projection: bool = True, official_average: bool = True, **fields):
    reasons = {}
    if not pace:
        reasons["useForPace"] = ["TEST_EXCLUDED"]
    if not fuel_ok:
        reasons["useForFuel"] = ["TEST_EXCLUDED"]
    if not tyres_ok:
        reasons["useForTyres"] = ["TEST_EXCLUDED"]
    if not projection:
        reasons["useForProjection"] = ["TEST_EXCLUDED"]
    if not official_average:
        reasons["useForOfficialAverage"] = ["TEST_EXCLUDED"]
    value = {
        "schema_version": "completed-lap-v1",
        "lap_id": f"lap-{number}",
        "identity_key": "car|track|main|session|setup",
        "lap_number": number,
        "started_at_s": (number - 1) * 100,
        "completed_at_s": number * 100,
        "lap_time_s": time,
        "official_validity": official,
        "classification": "NORMAL",
        "weather_regime": regime,
        "fuel": {"use_l": fuel, "measurement_complete": True},
        "tyres": {"measurement_complete": True, "wheels": {
            "FL": {"temperature_c": 90 + number, "pressure_psi": 27 + number / 10, "wear": 0.9 - number / 100},
            "FR": {"temperature_c": 91 + number, "pressure_psi": 27 + number / 10, "wear": 0.9 - number / 100},
            "RL": {"temperature_c": 88 + number, "pressure_psi": 26 + number / 10, "wear": 0.9 - number / 100},
            "RR": {"temperature_c": 89 + number, "pressure_psi": 26 + number / 10, "wear": 0.9 - number / 100},
        }},
        "eligibility": {
            "useForPace": pace,
            "useForFuel": fuel_ok,
            "useForTyres": tyres_ok,
            "useForProjection": projection,
            "useForOfficialAverage": official_average,
            "policy": "OPERATIONAL",
            "reasons": reasons,
        },
    }
    value.update(fields)
    return value


def completed_with_task4(lap):
    result = EligibilityEngine().evaluate(lap)
    value = copy.deepcopy(lap)
    value["eligibility"] = {
        **{purpose: decision["eligible"] for purpose, decision in result["decisions"].items()},
        "policy": result["policy_id"],
        "reasons": {purpose: list(decision["reason_codes"]) for purpose, decision in result["decisions"].items()},
    }
    return value


class StintCalculationTests(unittest.TestCase):
    def test_stint_start_ids_and_lap_numbering_are_stable(self):
        laps = [raw_lap(1), raw_lap(2)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps)
        self.assertEqual(result["progress"]["current_stint_id"], "stint:car|track|main|session|setup:1")
        self.assertEqual(result["progress"]["completed_stint_laps"], 2)
        self.assertEqual(result["progress"]["current_stint_lap"], 3)
        self.assertEqual(result["stints"][0]["stint_lap_numbers"], (1, 2))

    def test_pit_cycle_and_refuel_boundaries(self):
        laps = [raw_lap(1), raw_lap(2), raw_lap(3)]
        events = [
            {"event_id": "refuel", "event_type": "REFUEL", "detection_time_s": 150, "payload": {"delta_l": 20}},
            {"event_id": "pit-exit", "event_type": "PIT_SERVICE_STOP_CONFIRMED", "detection_time_s": 250, "payload": {"classification": "SERVICE_STOP"}},
        ]
        result = StintCalculationEngine().calculate(laps, events)
        self.assertEqual([item["stint_id"] for item in result["stints"]], ["stint:car|track|main|session|setup:1", "stint:car|track|main|session|setup:2"])
        self.assertEqual(result["stints"][1]["lap_ids"], ("lap-3",))

    def test_unconfirmed_pit_exit_does_not_start_a_new_stint(self):
        laps = [raw_lap(1), raw_lap(2), raw_lap(3)]
        candidate = [{"event_id": "pit-exit", "event_type": "PIT_EXIT_CANDIDATE", "detection_time_s": 250}]
        confirmed = [{"event_id": "pit-exit", "event_type": "PIT_EXIT_CONFIRMED", "detection_time_s": 250}]
        service = [{"event_id": "service-exit", "event_type": "PIT_SERVICE_STOP_CONFIRMED", "detection_time_s": 250, "payload": {"classification": "SERVICE_STOP"}}]
        self.assertEqual(len(StintCalculationEngine().calculate(laps, candidate)["stints"]), 1)
        self.assertEqual(len(StintCalculationEngine().calculate(laps, confirmed)["stints"]), 1)
        self.assertEqual(len(StintCalculationEngine().calculate(laps, service)["stints"]), 2)

    def test_refuel_only_boundary_and_reset_does_not_boundary(self):
        laps = [raw_lap(1), raw_lap(2), raw_lap(3)]
        refuel = [{"event_id": "refuel", "event_type": "REFUEL", "payload": {"lap_number": 2, "delta_l": 5}}]
        result = StintCalculationEngine().calculate(laps, refuel)
        self.assertEqual(len(result["stints"]), 1)
        service = [{"event_id": "service", "event_type": "PIT_SERVICE_STOP_CONFIRMED", "payload": {"lap_number": 2, "classification": "SERVICE_STOP"}}]
        result = StintCalculationEngine().calculate(laps, service)
        self.assertEqual(len(result["stints"]), 2)
        reset = [{"event_id": "reset", "event_type": "RESET", "payload": {"lap_number": 2}}]
        result = StintCalculationEngine().calculate(laps, reset)
        self.assertEqual(len(result["stints"]), 1)

    def test_explicit_boundary_and_compound_change(self):
        laps = [raw_lap(1, compound="SOFT"), raw_lap(2, compound="MEDIUM"), raw_lap(3, compound="MEDIUM")]
        result = StintCalculationEngine().calculate(laps)
        self.assertEqual(len(result["stints"]), 2)
        explicit = StintCalculationEngine().calculate([raw_lap(1), raw_lap(2), raw_lap(3)], [{"event_id": "start-2", "event_type": "STINT_STARTED", "payload": {"lap_number": 2}}])
        self.assertEqual(explicit["stints"][1]["lap_ids"], ("lap-2", "lap-3"))

    def test_latest_completed_and_latest_accepted_are_distinct(self):
        laps = [raw_lap(1), raw_lap(2, pace=False, fuel_ok=False, official=False)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps)
        self.assertEqual(result["pace"]["latest_completed"]["lap_id"], "lap-2")
        self.assertEqual(result["pace"]["latest_accepted"]["accepted_samples"], ("lap-1",))
        self.assertIn("TEST_EXCLUDED", result["pace"]["latest_completed"]["exclusion_reasons"]["useForPace"])

    def test_official_and_operational_averages_are_distinct(self):
        laps = [raw_lap(1, time=90), raw_lap(2, time=100, official=False, pace=True, official_average=False)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps)
        self.assertEqual(result["pace"]["official_average"]["value"], 90.0)
        self.assertEqual(result["pace"]["operational_stint_average"]["value"], 95.0)
        self.assertEqual(result["pace"]["representative_pace"]["value"], 95.0)

    def test_representative_median_handles_outlier_without_renaming_average(self):
        laps = [raw_lap(i, time=value) for i, value in enumerate((90, 91, 92, 180), 1)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps)
        self.assertEqual(result["pace"]["operational_stint_average"]["value"], 113.25)
        self.assertEqual(result["pace"]["representative_pace"]["value"], 91.5)
        self.assertEqual(result["representative_estimator"]["method"], "MEDIAN")

    def test_target_deltas_and_missing_targets(self):
        result = StintCalculationEngine({"active_regime": "DRY", "pace_target_s": 92, "fuel_target_l": 2.0}).calculate([raw_lap(1, time=90, fuel=2.5)])
        self.assertEqual(result["pace"]["target_deltas"]["latest_accepted"]["delta"], -2.0)
        self.assertEqual(result["fuel"]["target_deltas"]["latest_accepted"]["delta"], 0.5)
        missing = StintCalculationEngine().calculate([raw_lap(1)])
        self.assertIsNone(missing["pace"]["target_deltas"]["latest_accepted"]["delta"])
        self.assertEqual(missing["pace"]["target_deltas"]["latest_accepted"]["unavailable_reason"], "TARGET_NOT_CONFIGURED")

    def test_fuel_current_latest_completed_latest_accepted_and_estimators(self):
        laps = [raw_lap(1, fuel=2), raw_lap(2, fuel=3, fuel_ok=False)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps, current_snapshot={"observed_monotonic_s": 250, "car": {"fuel_l": 40}})
        self.assertEqual(result["fuel"]["current"]["value"], 40)
        self.assertEqual(result["fuel"]["latest_completed_lap_use"]["lap_id"], "lap-2")
        self.assertEqual(result["fuel"]["latest_completed_lap_use"]["status"], "EXCLUDED")
        self.assertEqual(result["fuel"]["latest_accepted"]["value"], 2)
        self.assertEqual(result["fuel"]["operational_stint_average"]["value"], 2)
        self.assertEqual(result["fuel"]["representative_use"]["value"], 2)

    def test_excluded_latest_laps_preserve_previous_statistics_and_counts(self):
        laps = [raw_lap(1, time=90, fuel=2), raw_lap(2, time=200, fuel=20, pace=False, fuel_ok=False, official=False)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps)
        self.assertEqual(result["pace"]["operational_stint_average"]["value"], 90)
        self.assertEqual(result["fuel"]["operational_stint_average"]["value"], 2)
        self.assertEqual(result["progress"]["accepted_sample_counts"]["pace"], 1)
        self.assertEqual(result["progress"]["accepted_sample_counts"]["fuel"], 1)
        self.assertEqual(result["pace"]["latest_completed"]["lap_id"], "lap-2")

    def test_same_lap_can_be_accepted_for_fuel_but_not_pace(self):
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate([raw_lap(1, official=False, pace=False, fuel_ok=True, official_average=False)])
        self.assertIsNone(result["pace"]["operational_stint_average"]["value"])
        self.assertEqual(result["fuel"]["operational_stint_average"]["value"], 2.5)

    def test_regime_separation_and_traffic(self):
        laps = [raw_lap(1, regime="DRY", time=90), raw_lap(2, regime="WET", time=110), raw_lap(3, regime="DRY", time=91), raw_lap(4, regime="DRY", classification="TRAFFIC", pace=False, fuel_ok=True)]
        result = StintCalculationEngine({"active_regime": "DRY"}).calculate(laps)
        self.assertEqual(result["pace"]["operational_stint_average"]["value"], 90.5)
        self.assertEqual(result["fuel"]["operational_stint_average"]["value"], 2.5)
        push = StintCalculationEngine({"active_regime": "PUSH"}).calculate([raw_lap(1, regime="PUSH", classification="PUSH"), raw_lap(2, regime="FUEL_SAVE", classification="FUEL_SAVE", pace=False)])
        self.assertEqual(push["progress"]["current_regime"], "PUSH")
        self.assertEqual(push["pace"]["operational_stint_average"]["value"], 90.0)

    def test_confidence_reasons_and_bounded_references(self):
        laps = [raw_lap(i) for i in range(1, 40)]
        result = StintCalculationEngine({"active_regime": "DRY", "max_sample_references": 4}).calculate(laps)
        self.assertLessEqual(len(result["pace"]["operational_stint_average"]["accepted_samples"]), 32)
        self.assertLessEqual(len(result["accepted_sample_references"]["pace"]), 4)
        self.assertIn("SAMPLE_COUNT_HIGH", result["confidence_reasons"]["pace"])

    def test_tyre_summary_and_unsupported_damage(self):
        snapshot = {"observed_monotonic_s": 250, "tyres": {"wheels": {"FL": {"temperature_c": 100, "pressure_psi": 28, "wear": 0.7, "flat_spot_state": "NONE"}, "FR": {"temperature_c": 101, "pressure_psi": 28, "wear": 0.7}, "RL": {"temperature_c": 98, "pressure_psi": 27, "wear": 0.8}, "RR": {"temperature_c": 99, "pressure_psi": 27, "wear": 0.8}}, "strongest_warning": "FR_PRESSURE"}}
        result = StintCalculationEngine({"active_regime": "DRY", "tyre_targets": {"temperature_c": 100}}).calculate([raw_lap(1), raw_lap(2)], current_snapshot=snapshot)
        self.assertEqual(result["tyres"]["current"]["temperature_c"]["FL"], 100)
        self.assertEqual(result["tyres"]["current_lap_min_max_temperature_c"], {"min_c": 90, "max_c": 93})
        self.assertEqual(result["tyres"]["strongest_verified_warning"], "FR_PRESSURE")
        self.assertEqual(result["tyres"]["unsupported"]["graining"]["unavailable_reason"], "UNSUPPORTED_MEASUREMENT")
        self.assertEqual(result["tyres"]["target_deltas"]["temperature_c"]["target"], 100)

    def test_missing_tyres_do_not_invent_physics_or_targets(self):
        result = StintCalculationEngine().calculate([raw_lap(1, tyres={"measurement_complete": False, "wheels": {}})])
        self.assertEqual(result["tyres"]["accepted_sample_count"], 0)
        self.assertIsNone(result["tyres"]["current_lap_min_max_temperature_c"])
        self.assertEqual(result["tyres"]["unsupported"]["blistering"]["value"], None)
        self.assertEqual(result["tyres"]["target_deltas"], {})

    def test_calculated_value_metadata_and_deterministic_replay(self):
        laps = [completed_with_task4(raw_lap(1)), completed_with_task4(raw_lap(2, official=False, pace=False, official_average=False))]
        first = StintCalculationEngine({"active_regime": "DRY", "now_s": 250}).calculate(laps)
        second = StintCalculationEngine({"active_regime": "DRY", "now_s": 250}).calculate(copy.deepcopy(laps))
        self.assertEqual(serialize_calculations(first), serialize_calculations(second))
        value = first["pace"]["representative_pace"]
        for key in ("value", "unit", "calculation_version", "accepted_samples", "rejected_samples", "sample_count", "regime", "policy", "freshness_s", "confidence", "unavailable_reason"):
            self.assertIn(key, value)

    def test_no_future_engine_recommendation_renderer_networking_or_runtime_loaders(self):
        source = Path("tools/stint_calculations.py").read_text(encoding="utf-8").lower()
        self.assertNotIn("forecast", source)
        self.assertNotIn("recommendation", source)
        self.assertNotIn("socket", source)
        self.assertNotIn("requests", source)
        self.assertNotIn("require(", source)
        self.assertNotIn("dofile(", source)

    def test_convenience_api_is_deterministic(self):
        result = calculate_stint([raw_lap(1), raw_lap(2)], config={"active_regime": "DRY"})
        self.assertEqual(result["progress"]["completed_stint_laps"], 2)


if __name__ == "__main__":
    unittest.main()
