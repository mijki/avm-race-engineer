from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.lap_eligibility import EligibilityEngine, PURPOSES, evaluate_completed_lap, serialize_eligibility


def lap(number: int = 1, **fields):
    result = {
        "schema_version": "completed-lap-v1",
        "lap_id": f"lap-{number}",
        "identity_key": "car|track|main|session|setup",
        "lap_number": number,
        "completed_at_s": number * 100,
        "lap_time_s": 90.0,
        "official_validity": True,
        "classification": "NORMAL",
        "weather_regime": "DRY",
        "fuel": {"use_l": 2.5, "measurement_complete": True},
        "tyres": {"measurement_complete": True, "wheels": {"FL": {"temperature_c": 90.0}}},
        "pit_reset_interaction": {},
    }
    result.update(fields)
    return result


def decision(result, purpose):
    return result["decisions"][purpose]


class EligibilityTests(unittest.TestCase):
    def test_normal_valid_lap_has_independent_complete_decisions(self):
        result = EligibilityEngine().evaluate(lap())
        self.assertTrue(all(decision(result, purpose)["eligible"] for purpose in PURPOSES))
        self.assertEqual(result["event"]["event_type"], "LAP_ELIGIBILITY_DECIDED")
        self.assertEqual(result["event"]["schema_version"], "race-event-v1")

    def test_invalid_track_limit_is_useful_for_fuel_and_tyres_but_not_official(self):
        invalid = lap(2, official_validity=False, invalidation_reason="TRACK_LIMIT")
        result = EligibilityEngine().evaluate(invalid)
        self.assertFalse(decision(result, "useForOfficialAverage")["eligible"])
        self.assertTrue(decision(result, "useForFuel")["eligible"])
        self.assertTrue(decision(result, "useForTyres")["eligible"])

    def test_strict_rejects_invalid_track_limit(self):
        result = EligibilityEngine("STRICT").evaluate(lap(2, official_validity=False, invalidation_reason="TRACK_LIMIT"))
        self.assertFalse(any(decision(result, purpose)["eligible"] for purpose in PURPOSES))

    def test_operational_pace_track_limit_requires_explicit_option(self):
        invalid = lap(2, official_validity=False, invalidation_reason="TRACK_LIMIT")
        self.assertFalse(decision(EligibilityEngine().evaluate(invalid), "useForPace")["eligible"])
        configured = EligibilityEngine({"policy": "OPERATIONAL", "allow_track_limit_invalid_pace": True}).evaluate(invalid)
        self.assertTrue(decision(configured, "useForPace")["eligible"])

    def test_shortcut_and_implausible_laps_are_not_estimator_samples(self):
        shortcut = EligibilityEngine().evaluate(lap(2, official_validity=False, invalidation_reason="TRACK_LIMIT", shortcut_detected=True, implausibly_fast=True))
        for purpose in ("useForPace", "useForFuel", "useForProjection", "useForOfficialAverage"):
            self.assertFalse(decision(shortcut, purpose)["eligible"])
        self.assertTrue(decision(shortcut, "useForTyres")["eligible"])

    def test_traffic_fuel_save_and_push_are_regime_specific(self):
        traffic = EligibilityEngine().evaluate(lap(2, traffic_affected=True, classification="TRAFFIC"))
        self.assertFalse(decision(traffic, "useForPace")["eligible"])
        self.assertTrue(decision(traffic, "useForFuel")["eligible"])
        fuel_save = EligibilityEngine().evaluate(lap(3, fuel_save=True, classification="FUEL_SAVE"))
        self.assertFalse(decision(fuel_save, "useForPace")["eligible"])
        self.assertTrue(decision(fuel_save, "useForFuel")["eligible"])
        push = EligibilityEngine({"active_regime": "PUSH"}).evaluate(lap(4, push_lap=True, classification="PUSH", regime="PUSH"))
        self.assertTrue(decision(push, "useForPace")["eligible"])
        self.assertTrue(decision(push, "useForProjection")["eligible"])

    def test_weather_and_mixed_regimes_do_not_cross_contaminate_active_set(self):
        engine = EligibilityEngine({"active_regime": "DRY"})
        wet = engine.evaluate(lap(2, weather_regime="WET"))
        mixed = engine.evaluate(lap(3, weather_regime="MIXED"))
        self.assertFalse(decision(wet, "useForPace")["eligible"])
        self.assertFalse(decision(mixed, "useForFuel")["eligible"])
        self.assertTrue(decision(wet, "useForTyres")["eligible"])

    def test_pit_in_out_box_reset_teleport_incident_and_incomplete(self):
        pit = EligibilityEngine().evaluate(lap(2, classification="IN_LAP", pit_reset_interaction={"pit_box": True}))
        self.assertFalse(decision(pit, "useForPace")["eligible"])
        self.assertTrue(decision(pit, "useForTyres")["eligible"])
        for field in ({"reset": True}, {"teleport": True}, {"incident": True}):
            result = EligibilityEngine().evaluate(lap(3, pit_reset_interaction=field))
            self.assertFalse(decision(result, "useForPace")["eligible"])
            self.assertFalse(decision(result, "useForFuel")["eligible"])
        incomplete = EligibilityEngine().evaluate(lap(4, complete=False))
        self.assertFalse(decision(incomplete, "useForOfficialAverage")["eligible"])

    def test_missing_measurements_are_not_zero(self):
        result = EligibilityEngine().evaluate(lap(2, fuel={}, tyres={}))
        self.assertFalse(decision(result, "useForFuel")["eligible"])
        self.assertIn("MISSING_FUEL_MEASUREMENTS", decision(result, "useForFuel")["reason_codes"])
        self.assertFalse(decision(result, "useForTyres")["eligible"])
        self.assertIn("MISSING_TYRE_MEASUREMENTS", decision(result, "useForTyres")["reason_codes"])

    def test_official_average_follows_official_validity(self):
        invalid = EligibilityEngine().evaluate(lap(2, official_validity=False, invalidation_reason="TRACK_LIMIT"))
        self.assertFalse(decision(invalid, "useForOfficialAverage")["eligible"])
        unknown = EligibilityEngine().evaluate(lap(3, official_validity=None))
        self.assertFalse(decision(unknown, "useForOfficialAverage")["eligible"])
        self.assertIn("OFFICIAL_VALIDITY_UNKNOWN", decision(unknown, "useForOfficialAverage")["reason_codes"])

    def test_manual_include_exclude_and_restore_are_auditable(self):
        engine = EligibilityEngine(max_override_history=8)
        original = engine.evaluate(lap())
        engine.set_override("lap-1", "useForPace", "EXCLUDE", "driver marked compromised", timestamp_s=12, source="driver")
        excluded = engine.evaluate(lap())
        self.assertFalse(decision(excluded, "useForPace")["eligible"])
        self.assertEqual(decision(excluded, "useForPace")["manual_override_state"], "EXCLUDE")
        engine.set_override("lap-1", "useForFuel", "INCLUDE", "fuel measurement reviewed")
        included = engine.evaluate(lap())
        self.assertTrue(decision(included, "useForFuel")["eligible"])
        engine.restore_automatic("lap-1", "useForPace", "restore automatic policy")
        restored = engine.evaluate(lap())
        self.assertEqual(decision(restored, "useForPace")["eligible"], decision(original, "useForPace")["eligible"])
        self.assertEqual(len(engine.override_history), 3)
        self.assertEqual(engine.override_history[0]["source"], "driver")

    def test_override_history_is_bounded_and_identity_scoped(self):
        engine = EligibilityEngine(max_override_history=2)
        engine.set_override("lap-1", "useForPace", "EXCLUDE", "one", identity_key="identity-a")
        engine.set_override("lap-2", "useForPace", "EXCLUDE", "two", identity_key="identity-a")
        engine.set_override("lap-3", "useForPace", "EXCLUDE", "three", identity_key="identity-a")
        self.assertEqual(len(engine.override_history), 2)
        self.assertFalse(decision(engine.evaluate(lap(1, identity_key="identity-a")), "useForPace")["eligible"])
        self.assertTrue(decision(engine.evaluate(lap(1, identity_key="identity-b")), "useForPace")["eligible"])

    def test_evidence_and_original_lap_are_not_mutated(self):
        original = lap(2)
        before = copy.deepcopy(original)
        result = EligibilityEngine().evaluate(original, [{"event_id": "event-1", "event_type": "LAP_COMPLETED", "payload": {"lap_id": "lap-2"}, "sequence": 1}])
        self.assertEqual(original, before)
        self.assertEqual(result["decisions"]["useForPace"]["source_evidence"]["event_sources"][0]["event_id"], "event-1")
        with self.assertRaises(TypeError):
            result["decisions"]["useForPace"]["eligible"] = False

    def test_custom_policy_is_explicit_per_purpose(self):
        result = EligibilityEngine({"policy": "CUSTOM", "disabled_purposes": ["useForProjection"]}).evaluate(lap())
        self.assertTrue(decision(result, "useForPace")["eligible"])
        self.assertFalse(decision(result, "useForProjection")["eligible"])
        self.assertIn("CUSTOM_PURPOSE_DISABLED", decision(result, "useForProjection")["reason_codes"])

    def test_deterministic_replay_and_serialization(self):
        laps = [lap(1), lap(2, official_validity=False, invalidation_reason="TRACK_LIMIT"), lap(3, traffic_affected=True, classification="TRAFFIC")]
        first = EligibilityEngine().evaluate_laps(laps)
        second = EligibilityEngine().evaluate_laps(copy.deepcopy(laps))
        self.assertEqual(serialize_eligibility(first), serialize_eligibility(second))
        self.assertEqual(json.loads(serialize_eligibility(first)), json.loads(serialize_eligibility(second)))

    def test_no_stint_forecast_recommendation_renderer_or_networking_in_module(self):
        source = Path("tools/lap_eligibility.py").read_text(encoding="utf-8")
        self.assertNotIn("forecast", source.lower())
        self.assertNotIn("recommend", source.lower())
        self.assertNotIn("require(", source)
        self.assertNotIn("dofile(", source)

    def test_convenience_function_replays_explicit_overrides(self):
        result = evaluate_completed_lap(lap(), overrides=[{"lap_id": "lap-1", "purposes": ["useForPace"], "action": "EXCLUDE", "reason": "manual"}])
        self.assertFalse(decision(result, "useForPace")["eligible"])


if __name__ == "__main__":
    unittest.main()
