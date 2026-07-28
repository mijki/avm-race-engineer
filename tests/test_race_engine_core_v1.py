from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.race_engine_core import (
    ELIGIBILITY_POLICIES,
    MARKER_STATES,
    SCHEMA_VERSIONS,
    SOURCE_HEALTH,
    EventStream,
    calculated_value,
    completed_lap,
    forecast,
    identity_key,
    load_replay_fixture,
    pit_marker,
    pit_observation,
    replay_fixture,
    replay_snapshots,
    serialize_replay,
    telemetry_snapshot,
    to_plain,
)


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "race_engine_core_v1_replay.json"


class ContractTests(unittest.TestCase):
    def test_versions_and_unavailable_values_are_explicit(self) -> None:
        snapshot = telemetry_snapshot(identity={"track_id": "track", "layout_id": "main"}, sequence=1)
        self.assertEqual(snapshot["schema_version"], SCHEMA_VERSIONS["telemetry_snapshot"])
        self.assertIsNone(snapshot["car"].get("fuel_l"))
        self.assertEqual(SOURCE_HEALTH, frozenset(("LIVE", "PARTIAL", "STALE", "OFFLINE")))
        self.assertEqual(MARKER_STATES, frozenset(("UNAVAILABLE", "PROVISIONAL", "LEARNED", "CONFIRMED", "CONFLICTED", "MANUAL_OVERRIDE")))
        self.assertEqual(ELIGIBILITY_POLICIES, frozenset(("STRICT", "OPERATIONAL", "CUSTOM")))

    def test_identity_is_deterministic(self) -> None:
        identity = {"car_id": "car", "track_id": "track", "layout_id": "main", "session_id": "s", "configuration_id": "c"}
        self.assertEqual(identity_key(identity), identity_key(dict(reversed(list(identity.items())))))

    def test_completed_lap_has_independent_eligibility(self) -> None:
        lap = completed_lap(lap_id="lap-1", identity_key="key", lap_number=1, eligibility={"useForPace": True, "useForFuel": False, "useForTyres": True, "useForProjection": False, "useForOfficialAverage": False, "policy": "CUSTOM", "reasons": {"useForFuel": "PIT_LAP"}})
        self.assertEqual(lap["schema_version"], "completed-lap-v1")
        self.assertTrue(lap["eligibility"]["useForPace"])
        self.assertFalse(lap["eligibility"]["useForFuel"])
        self.assertEqual(lap["eligibility"]["policy"], "CUSTOM")

    def test_envelopes_keep_forecasts_separate_from_calculations(self) -> None:
        calculated = calculated_value(value=None, unit="L", calculation_version="calc-v1", unavailable_reason="INSUFFICIENT_SAMPLES")
        predicted = forecast(forecast_id="f-1", model_id="none", model_version="0", value=None, unit="L", unavailable_reason="NO_MODEL")
        self.assertEqual(calculated["schema_version"], "calculated-value-v1")
        self.assertEqual(predicted["schema_version"], "forecast-envelope-v1")
        self.assertNotIn("model_id", calculated)

    def test_pit_contracts_include_bounded_observation_slots(self) -> None:
        observation = pit_observation(observation_id="o-1", transition_type="ENTRY", source_snapshot_id="s-1", rejection_reasons=[])
        marker = pit_marker(track_layout_key="track::main", accepted_observations=[], rejected_observations=[])
        self.assertEqual(observation["schema_version"], "pit-transition-observation-v1")
        self.assertEqual(marker["schema_version"], "pit-marker-record-v1")


class ReplayTests(unittest.TestCase):
    def test_all_required_replay_scenarios_exist(self) -> None:
        catalog = load_replay_fixture(FIXTURE)
        self.assertEqual(len(catalog["scenarios"]), 12)
        self.assertEqual({item["id"] for item in catalog["scenarios"]}, {"session-start", "completed-lap", "invalidated-lap", "reset-teleport", "pit-entry", "pit-box-arrival", "pit-box-departure", "pit-exit", "start-in-pit", "track-layout-change", "refuel", "weather-regime-change"})

    def test_replay_is_byte_identical(self) -> None:
        catalog = load_replay_fixture(FIXTURE)
        for scenario in catalog["scenarios"]:
            first = serialize_replay(replay_snapshots(scenario["snapshots"]))
            second = serialize_replay(replay_snapshots(scenario["snapshots"]))
            self.assertEqual(first, second, scenario["id"])

    def test_replay_detects_boundaries_and_bounded_retention(self) -> None:
        catalog = load_replay_fixture(FIXTURE)
        by_id = {item["id"]: item for item in catalog["scenarios"]}
        self.assertEqual(to_plain(replay_snapshots(by_id["pit-entry"]["snapshots"]))[1]["event_type"], "PIT_ENTRY_CANDIDATE")
        events = replay_snapshots(by_id["reset-teleport"]["snapshots"])
        self.assertIn("RESET", {event["event_type"] for event in events})
        self.assertIn("TELEPORT", {event["event_type"] for event in events})
        stream = EventStream(max_events=2)
        for scenario in catalog["scenarios"]:
            for snapshot in scenario["snapshots"]:
                stream.update(snapshot)
        self.assertLessEqual(len(stream.events), 2)

    def test_event_is_immutable(self) -> None:
        snapshot = telemetry_snapshot(identity={"session_id": "s"}, sequence=1)
        event = replay_snapshots([snapshot])[0]
        with self.assertRaises(TypeError):
            event["event_type"] = "MUTATED"  # type: ignore[index]
        self.assertEqual(event["schema_version"], "race-event-v1")

    def test_fixture_replay_map_is_stable(self) -> None:
        outputs = replay_fixture(FIXTURE)
        self.assertEqual(set(outputs), {item["id"] for item in load_replay_fixture(FIXTURE)["scenarios"]})
        json.loads(outputs["session-start"].decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
