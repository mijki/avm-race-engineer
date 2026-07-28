from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.pit_learning import PitLearner, forward_distance


ROOT = Path(__file__).resolve().parents[1]


def snapshot(now: float, *, lane: bool = False, box: bool = False, spline: float = 0.90, reset: int = 0, fuel: float = 40, session: str = "session") -> dict:
    return {"schema_version": "telemetry-snapshot-v1", "snapshot_id": f"snapshot-{now}", "observed_monotonic_s": now, "identity": {"car_id": "car", "track_id": "track", "layout_id": "main", "session_id": session, "configuration_id": "car@track"}, "session": {"elapsed_s": now, "completed_laps": 2, "track_length_m": 5000}, "car": {"pit_lane": lane, "pit_box": box, "spline": spline, "reset_counter": reset, "fuel_l": fuel, "speed_kmh": 30, "world_position": {"x": spline * 5000, "y": 0, "z": 0}}}


class PitStateTests(unittest.TestCase):
    def test_normal_entry_stop_exit_is_immediate_and_learns_original_boundaries(self) -> None:
        learner = PitLearner(debounce_s=0.1)
        learner.update(snapshot(0, spline=0.89), 0)
        entered = learner.update(snapshot(1, lane=True, spline=0.91), 1)
        self.assertTrue(entered["live_pit_lane"])
        self.assertEqual(entered["state"], "IN_PIT_LANE")
        learner.update(snapshot(1.2, lane=True, spline=0.92), 1.2)
        learner.update(snapshot(2, lane=True, box=True, spline=0.94), 2)
        learner.update(snapshot(3, lane=True, box=False, spline=0.95), 3)
        learner.update(snapshot(4, lane=False, spline=0.02), 4)
        exited = learner.update(snapshot(4.2, lane=False, spline=0.03), 4.2)
        self.assertFalse(exited["live_pit_lane"])
        self.assertEqual(exited["last_visit"]["classification"], "NORMAL_STOP")
        self.assertAlmostEqual(exited["marker"]["entry_spline"], 0.91)
        self.assertAlmostEqual(exited["marker"]["exit_spline"], 0.02)

    def test_drive_through_and_no_service_remain_valid(self) -> None:
        learner = PitLearner(debounce_s=0)
        learner.update(snapshot(0), 0)
        learner.update(snapshot(1, lane=True, spline=0.90), 1)
        learner.update(snapshot(2, lane=True, spline=0.91), 2)
        learner.update(snapshot(3, lane=False, spline=0.02), 3)
        result = learner.update(snapshot(4, lane=False, spline=0.03), 4)
        self.assertEqual(result["last_visit"]["classification"], "DRIVE_THROUGH")

    def test_start_in_pits_does_not_fabricate_entry_marker(self) -> None:
        learner = PitLearner(debounce_s=0)
        first = learner.update(snapshot(0, lane=True, box=True, spline=0.10), 0)
        learner.update(snapshot(1, lane=True, box=False, spline=0.12), 1)
        result = learner.update(snapshot(2, lane=False, spline=0.15), 2)
        learner.update(snapshot(3, lane=False, spline=0.16), 3)
        self.assertIsNone(first["marker"]["entry_spline"])
        self.assertIsNone(result["marker"]["entry_spline"])
        self.assertEqual(result["marker"]["exit_spline"], 0.15)

    def test_reset_teleport_and_identity_suppress_learning(self) -> None:
        learner = PitLearner(debounce_s=0)
        learner.update(snapshot(0), 0)
        learner.update(snapshot(1, lane=True, reset=1, spline=0.91), 1)
        result = learner.update(snapshot(2, lane=True, reset=2, spline=0.92), 2)
        self.assertEqual(result["state"], "RESET_SUPPRESSED")
        self.assertEqual(result["marker"]["state"], "UNAVAILABLE")

    def test_flicker_and_short_legitimate_visit_preserve_original_candidate(self) -> None:
        learner = PitLearner(debounce_s=0.5)
        learner.update(snapshot(0), 0)
        learner.update(snapshot(1, lane=True, spline=0.91), 1)
        interrupted = learner.update(snapshot(1.1, lane=False, spline=0.91), 1.1)
        self.assertIsNone(interrupted["marker"]["entry_spline"])
        learner.update(snapshot(2, lane=True, spline=0.92), 2)
        learner.update(snapshot(2.6, lane=True, spline=0.93), 2.6)
        self.assertAlmostEqual(learner.marker["entry_spline"], 0.92)

    def test_outliers_do_not_destroy_consistent_cluster(self) -> None:
        learner = PitLearner(debounce_s=0)
        for base, exit_s in ((0, 0.90), (2, 0.91), (4, 0.905)):
            learner.update(snapshot(base, spline=0.80), base)
            learner.update(snapshot(base + 0.1, lane=True, spline=exit_s), base + 0.1)
            learner.update(snapshot(base + 0.2, lane=True, spline=exit_s), base + 0.2)
            learner.update(snapshot(base + 0.3, lane=False, spline=0.10), base + 0.3)
            learner.update(snapshot(base + 0.4, lane=False, spline=0.10), base + 0.4)
        before = learner.marker["entry_spline"]
        self.assertAlmostEqual(before, 0.905, places=2)
        self.assertLessEqual(len(learner.marker["accepted_observations"]), 24)

    def test_manual_override_lifecycle_and_distance_wraparound(self) -> None:
        learner = PitLearner()
        learner.update(snapshot(0), 0)
        marker = learner.manual_override(entry_spline=0.10, exit_spline=0.20, snapshot=snapshot(0))
        self.assertEqual(marker["state"], "MANUAL_OVERRIDE")
        learner.update(snapshot(1, lane=True, spline=0.90), 1)
        self.assertEqual(learner.marker["entry_spline"], 0.10)
        self.assertTrue(learner.clear_override())
        distance, reason = forward_distance(0.97, 0.10, 5000)
        self.assertAlmostEqual(distance, 650)
        self.assertEqual(reason, "PIT_ENTRY_WRAPAROUND_APPLIED")

    def test_unrelated_telemetry_and_determinism(self) -> None:
        first = PitLearner(debounce_s=0)
        second = PitLearner(debounce_s=0)
        snapshots = [snapshot(0), snapshot(1, lane=True), snapshot(2, lane=True), snapshot(3, lane=False), snapshot(4, lane=False)]
        first_result = [first.update(item, item["observed_monotonic_s"]) for item in snapshots]
        second_result = [second.update(copy.deepcopy(item), item["observed_monotonic_s"]) for item in snapshots]
        self.assertEqual(first_result, second_result)
        self.assertEqual(first_result[-1]["marker"]["schema_version"], "pit-marker-record-v1")


if __name__ == "__main__":
    unittest.main()
