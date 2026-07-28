from __future__ import annotations

import copy
import unittest
from pathlib import Path

from tools.driver_status import (
    DriverStatusViewModel,
    build_driver_status,
    format_delta,
    format_lap_time,
    wind_cardinal,
)
from tools.forecast_engine import ForecastEngine
from tools.stint_calculations import StintCalculationEngine


def lap(number: int, *, pace: bool = True, fuel_ok: bool = True) -> dict:
    return {
        "schema_version": "completed-lap-v1",
        "lap_id": f"lap-{number}",
        "identity_key": "car|track|main|session|cfg",
        "lap_number": number,
        "started_at_s": (number - 1) * 100,
        "completed_at_s": number * 100,
        "lap_time_s": 90 + number / 100,
        "official_validity": pace,
        "classification": "NORMAL" if pace else "INVALID",
        "weather_regime": "DRY",
        "fuel": {"use_l": 2.5, "measurement_complete": True},
        "tyres": {"measurement_complete": True, "wheels": {
            "FL": {"temperature_c": 100, "pressure_psi": 27.5, "wear": 0.8},
            "FR": {"temperature_c": 101, "pressure_psi": 27.6, "wear": 0.8},
            "RL": {"temperature_c": 98, "pressure_psi": 26.8, "wear": 0.85},
            "RR": {"temperature_c": 99, "pressure_psi": 26.9, "wear": 0.85},
        }},
        "eligibility": {
            "useForPace": pace,
            "useForFuel": fuel_ok,
            "useForTyres": True,
            "useForProjection": True,
            "useForOfficialAverage": pace,
            "reasons": {"useForPace": [] if pace else ["INVALID_LAP"], "useForFuel": [] if fuel_ok else ["PIT_LAP"]},
        },
    }


def snapshot(*, current_lap: int = 3, completed_laps: int | None = None, pit_lane: bool = False) -> dict:
    return {
        "schema_version": "telemetry-snapshot-v1",
        "snapshot_id": "snapshot-3",
        "identity": {"car_id": "car", "track_id": "track", "layout_id": "main", "session_id": "session", "driver_id": "driver", "configuration_id": "cfg"},
        "session": {"current_lap": current_lap, "completed_laps": current_lap if completed_laps is None else completed_laps, "lap_limit": 40},
        "car": {"fuel_l": 30, "pit_lane": pit_lane, "pit_box": False, "compound": "MEDIUM", "tyres": {"wheels": {
            "FL": {"temperature_c": 105, "pressure_psi": 27.7, "wear": 0.75},
            "FR": {"temperature_c": 106, "pressure_psi": 27.8, "wear": 0.75},
            "RL": {"temperature_c": 100, "pressure_psi": 27.0, "wear": 0.80},
            "RR": {"temperature_c": 101, "pressure_psi": 27.1, "wear": 0.80},
        }}, "spline": 0.2},
        "environment": {"weather_type": "DRY", "track_condition": "dry", "air_temperature_c": 22, "road_temperature_c": 30, "wind_speed_kmh": 12, "wind_direction_deg": 90},
    }


def state(*, target: bool = True, excluded_latest: bool = False, empty_post_pit: bool = False):
    laps = [lap(1), lap(2, pace=not excluded_latest, fuel_ok=not excluded_latest)]
    events = [{"event_type": "PIT_EXIT_CONFIRMED", "event_id": "pit-exit", "detection_time_s": 250}] if empty_post_pit else []
    snap = snapshot(current_lap=3)
    calc = StintCalculationEngine({"active_regime": "DRY", "pace_target_s": 92 if target else None, "fuel_target_l": 2.4, "now_s": 300}).calculate(laps, events, current_snapshot=snap)
    forecast = ForecastEngine({"race_lap_limit": 40, "track_length_m": 5000, "reserve_fuel_l": 2, "planned_pit_lap": 10, "now_s": 300, "pit_marker": {"state": "CONFIRMED", "entry_spline": 0.1}}).calculate(calc, current_snapshot=snap, pit_diagnostics={"marker": {"state": "CONFIRMED", "entry_spline": 0.1}})
    return calc, forecast, snap


class DriverStatusTests(unittest.TestCase):
    def test_formatting_is_lap_and_delta_specific(self):
        self.assertEqual(format_lap_time(78.010), "1:18.010")
        self.assertEqual(format_lap_time(522.322), "8:42.322")
        self.assertEqual(format_delta(2.322), "+2.322 s")
        self.assertEqual(format_delta(-0.452), "−0.452 s")
        self.assertEqual(wind_cardinal(90), "E")

    def test_common_metadata_and_source_trace(self):
        calc, forecast, snap = state()
        result = build_driver_status(calc, forecast, snapshot=snap)
        field = result["fields"]["pace.latest"]
        for key in ("field_id", "label", "raw_value", "formatted_value", "unit", "availability", "semantic_state", "severity", "confidence", "freshness_s", "source_layer", "comparison_reference", "unavailable_reason", "supporting_detail", "trace_id"):
            self.assertIn(key, field)
        self.assertEqual(field["source_layer"], "calculation")

    def test_pace_target_last_and_stint_average_have_explicit_references(self):
        calc, forecast, snap = state(target=True)
        result = DriverStatusViewModel({"targets": {}}).build(calc, forecast, snapshot=snap)
        self.assertEqual(result["fields"]["pace.target"]["formatted_value"], "1:32.000")
        self.assertIn("VS TARGET", result["fields"]["pace.latest_vs_target"]["label"])
        self.assertIn("VS TARGET", result["fields"]["pace.stint_average_vs_target"]["label"])
        self.assertNotIn("DELTA", result["fields"])

    def test_missing_pace_target_suppresses_target_rows_and_repeats_one_warning(self):
        calc, forecast, snap = state(target=False)
        result = build_driver_status(calc, forecast, snapshot=snap, mode="compact")
        self.assertNotIn("pace.target", result["display_fields"]["pace"])
        self.assertNotIn("pace.latest_vs_target", result["display_fields"]["pace"])
        self.assertEqual([item for item in result["fields"].values() if item["unavailable_reason"] == "TARGET_NOT_CONFIGURED" and item["source_layer"] == "configuration"].__len__(), 1)

    def test_excluded_latest_lap_remains_expanded_diagnostic(self):
        calc, forecast, snap = state(excluded_latest=True)
        result = build_driver_status(calc, forecast, snapshot=snap, mode="expanded")
        self.assertIn("pace.latest_exclusion", result["display_fields"]["pace"])
        self.assertEqual(result["fields"]["pace.latest_exclusion"]["raw_value"], "INVALID_LAP")
        self.assertEqual(result["fields"]["pace.stint_average"]["raw_value"], 90.01)

    def test_fuel_current_latest_average_and_required_are_separate(self):
        calc, forecast, snap = state()
        result = build_driver_status(calc, forecast, snapshot=snap)
        self.assertEqual(result["fields"]["fuel.current"]["raw_value"], 30)
        self.assertEqual(result["fields"]["fuel.latest"]["raw_value"], 2.5)
        self.assertEqual(result["fields"]["fuel.required_per_lap_now"]["raw_value"], 2.5)
        self.assertIn("fuel.current", result["display_fields"]["fuel"])

    def test_stint_strip_uses_engine_owned_identity_and_zero_based_live_lap(self):
        calc, forecast, snap = state(empty_post_pit=True)
        result = build_driver_status(calc, forecast, snapshot=snap)
        self.assertEqual(result["stint"]["stint_id"], "stint:car|track|main|session|cfg:2")
        self.assertEqual(result["stint"]["stint_number"], 2)
        self.assertEqual(result["stint"]["current_stint_lap"], 0)
        self.assertEqual(result["stint"]["strip_label"], "STINT 2 · LAP 0")
        self.assertIsNotNone(result["stint"]["previous_summary"])

    def test_race_lap_uses_completed_ac_count_not_active_current_lap(self):
        calc, forecast, _ = state()
        snap = snapshot(current_lap=4, completed_laps=3)
        result = build_driver_status(calc, forecast, snapshot=snap)
        self.assertEqual(result["stint"]["race_lap"], 3)
        self.assertEqual(result["stint"]["current_race_lap"], 3)
        self.assertEqual(result["fields"]["stint.current_race_lap"]["raw_value"], 3)

    def test_four_independent_tyres_and_unsupported_damage(self):
        calc, forecast, snap = state()
        result = build_driver_status(calc, forecast, snapshot=snap)
        self.assertEqual(set(result["tyres"]["wheels"]), {"FL", "FR", "RL", "RR"})
        self.assertEqual(result["fields"]["tyres.graining"]["unavailable_reason"], "UNSUPPORTED_MEASUREMENT")
        self.assertEqual(result["fields"]["tyres.blistering"]["unavailable_reason"], "UNSUPPORTED_MEASUREMENT")
        self.assertNotIn("pressure_delta", result["tyres"]["wheels"]["FL"])
        self.assertEqual(len([field for field in result["fields"].values() if field["unavailable_reason"] == "TARGETS_NOT_CONFIGURED"]), 1)

    def test_weather_is_readable_and_future_is_explicitly_unavailable(self):
        calc, forecast, snap = state()
        result = build_driver_status(calc, forecast, snapshot=snap)
        self.assertEqual(result["weather"]["condition"], "Dry")
        self.assertEqual(result["weather"]["wind_cardinal"], "E")
        self.assertEqual(result["fields"]["weather.future"]["unavailable_reason"], "FUTURE_WEATHER_SOURCE_UNAVAILABLE")
        self.assertNotIn("CURRENT 100", result["fields"]["weather.condition"]["formatted_value"])

    def test_live_pit_state_survives_missing_calibration_without_repeated_warning(self):
        calc, forecast, snap = state()
        forecast = copy.deepcopy(forecast)
        forecast["pit"]["marker"] = {"state": "UNAVAILABLE"}
        forecast["pit"]["live"] = {"state": "IN_PIT_LANE", "pit_lane": True, "pit_box": False}
        result = build_driver_status(calc, forecast, snapshot=snapshot(pit_lane=True), pit_diagnostics={"state": "IN_PIT_LANE"})
        self.assertEqual(result["pit"]["live"]["state"], "IN_PIT_LANE")
        self.assertTrue(result["pit"]["live"]["pit_lane"])
        self.assertEqual(len([field_id for field_id in result["display_fields"]["pit"] if result["fields"][field_id]["unavailable_reason"] == "PIT_ENTRY_NOT_CALIBRATED"]), 1)
        self.assertIn("pit.calibration", result["display_fields"]["pit"])

    def test_trust_states_are_independent_and_neutral_for_local_unused_sources(self):
        calc, forecast, snap = state()
        result = build_driver_status(calc, forecast, snapshot=snap, source_status={"TEL": "PARTIAL"})
        self.assertEqual(result["trust"]["TEL"]["state"], "PARTIAL")
        self.assertEqual(result["trust"]["BRG"]["state"], "NOT USED")
        self.assertEqual(result["trust"]["BRG"]["semantic_state"], "neutral")
        self.assertEqual(result["trust"]["ENG"]["state"], "NOT ASSIGNED")
        self.assertEqual(result["trust"]["ENG"]["semantic_state"], "neutral")
        self.assertIn("shape", result["trust"]["TEL"])

    def test_engineer_is_separate_from_source_health(self):
        calc, forecast, snap = state()
        result = build_driver_status(calc, forecast, snapshot=snap, source_status={"TEL": "STALE"}, engineer={"active": {"instruction": "save_fuel", "source": "engineer", "priority": "high", "detail": "Save one tenth per lap"}})
        self.assertEqual(result["engineer"]["source"], "engineer")
        self.assertEqual(result["fields"]["engineer.primary"]["semantic_state"], "caution")
        self.assertEqual(result["trust"]["TEL"]["state"], "STALE")
        self.assertNotIn("STALE", result["engineer"]["detail"])

    def test_mode_allocation_and_priority(self):
        calc, forecast, snap = state()
        compact = build_driver_status(calc, forecast, snapshot=snap, mode="compact")
        expanded_calc, expanded_forecast, expanded_snapshot = state(excluded_latest=True)
        expanded = build_driver_status(expanded_calc, expanded_forecast, snapshot=expanded_snapshot, mode="expanded")
        garage = build_driver_status(calc, forecast, snapshot=snap, mode="garage")
        self.assertIn("engineer.primary", compact["display_fields"]["engineer"])
        self.assertIn("pace.latest_exclusion", expanded["display_fields"]["pace"])
        self.assertIn("diagnostics", garage["display_fields"])
        self.assertLess(compact["priority"].index("engineer.primary"), compact["priority"].index("stint.current_stint_number"))
        self.assertEqual(compact["semantic_states"], ["neutral", "informational", "good", "caution", "critical", "unavailable"])

    def test_deterministic_serialization_and_source_boundaries(self):
        from tools.driver_status import serialize_driver_status

        calc, forecast, snap = state()
        first = build_driver_status(calc, forecast, snapshot=snap)
        second = build_driver_status(calc, forecast, snapshot=copy.deepcopy(snap))
        self.assertEqual(serialize_driver_status(first), serialize_driver_status(second))
        source = Path("tools/driver_status.py").read_text(encoding="utf-8").lower()
        for forbidden in ("getcarstate", "socket", "requests", "require(", "dofile(", "forecast rain eta"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
