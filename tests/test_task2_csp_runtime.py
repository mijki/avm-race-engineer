from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.live_model import SnapshotHistory, SourceHealthTracker, classify_source_health, normalize_csp
from tools.race_engine_core import EventStream


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps" / "driver-lua" / "src"


def fixture() -> dict:
    raw = json.loads((ROOT / "tests" / "fixtures" / "live_telemetry_a.json").read_text(encoding="utf-8"))
    return normalize_csp(raw, 10.0)


class SourceHealthTests(unittest.TestCase):
    def test_core_and_optional_health_states_are_distinct(self) -> None:
        snap = fixture()
        snap["session"]["lap_limit"] = 30
        snap["car"]["reset_counter"] = 0
        snap["car"]["world_position"] = {"x": 0, "y": 0, "z": 0}
        self.assertEqual(classify_source_health(snap)["source_health"], "LIVE")
        snap["environment"]["track_wetness"] = None
        self.assertEqual(classify_source_health(snap)["source_health"], "PARTIAL")
        snap["car"]["fuel_l"] = None
        self.assertEqual(classify_source_health(snap)["source_health"], "OFFLINE")

    def test_stale_and_recovery_transitions_are_bounded(self) -> None:
        health = SourceHealthTracker(stale_after_s=2.0, transition_confirmations=2)
        self.assertEqual(health.update(0, usable_core=True), "LIVE")
        self.assertEqual(health.update(1, usable_core=False, read_ok=False), "LIVE")
        self.assertEqual(health.update(3, usable_core=False, read_ok=False), "STALE")
        self.assertEqual(health.update(4, usable_core=True), "LIVE")
        self.assertLessEqual(len(health.diagnostics()["transitions"]), 16)

    def test_snapshot_history_is_bounded_and_preserves_boundary_samples(self) -> None:
        history = SnapshotHistory(max_count=3)
        for index in range(5):
            snapshot = fixture()
            snapshot["sequence"] = index
            snapshot["car"]["pit_lane"] = index == 3
            history.append(snapshot)
        self.assertEqual([item["sequence"] for item in history.snapshots], [2, 3, 4])
        self.assertTrue(history.snapshots[1]["car"]["pit_lane"])


class CspBoundaryTests(unittest.TestCase):
    def test_normalized_snapshot_has_v1_identity_pit_and_failure_metadata(self) -> None:
        snap = fixture()
        self.assertEqual(snap["schema_version"], "telemetry-snapshot-v1")
        self.assertIn("fixture-track::main", snap["track_layout_key"])
        self.assertIn("car.pit_lane", snap["availability"])
        self.assertIn("car.reset_counter", snap["availability"])
        self.assertIsNone(snap["car"]["reset_counter"])
        self.assertIsNone(snap["car"].get("world_position"))

    def test_source_reader_is_protected_and_raw_csp_stays_outside_ui(self) -> None:
        csp = (SOURCE / "adapters" / "csp.lua").read_text(encoding="utf-8")
        status = (SOURCE / "live" / "status_builder.lua").read_text(encoding="utf-8")
        self.assertIn("pcall", csp)
        self.assertIn("telemetry_invoke", csp)
        self.assertIn("source_health", csp)
        self.assertIn("pit_source", status)
        self.assertNotIn("raw_csp", status)

    def test_identity_reset_and_pit_transitions_are_event_evidence(self) -> None:
        first = fixture()
        first["car"]["reset_counter"] = 1
        stream = EventStream()
        stream.update(first)
        second = fixture()
        second["observed_monotonic_s"] = 11
        second["snapshot_id"] = "snapshot-2"
        second["car"]["reset_counter"] = 2
        second["car"]["pit_lane"] = True
        events = stream.update(second)
        kinds = {event["event_type"] for event in events}
        self.assertIn("RESET", kinds)
        self.assertIn("PIT_ENTRY_CANDIDATE", kinds)


if __name__ == "__main__":
    unittest.main()
