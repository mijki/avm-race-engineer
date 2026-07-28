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
        self.assertEqual(exited["last_visit"]["classification"], "STOP_GO")
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

    def test_service_classifications_require_evidence_not_pit_box_dwell(self) -> None:
        def run(sequence: list[dict]) -> dict:
            learner = PitLearner(debounce_s=0)
            for item in sequence:
                result = learner.update(item, item["observed_monotonic_s"])
            return result

        entry = snapshot(0, spline=0.89)
        lane = snapshot(1, lane=True, spline=0.91)
        box = snapshot(2, lane=True, box=True, spline=0.94)
        departed = snapshot(3, lane=True, box=False, spline=0.95)
        exit_snapshot = snapshot(4, lane=False, spline=0.02)
        for item in (entry, lane, box, departed, exit_snapshot):
            item["tyres"] = {"compound": "medium"}
        self.assertEqual(run([entry, lane, exit_snapshot])["last_visit"]["classification"], "DRIVE_THROUGH")
        self.assertEqual(run([entry, lane, box, departed, exit_snapshot])["last_visit"]["classification"], "STOP_GO")

        fuel_exit = snapshot(4, lane=False, spline=0.02, fuel=50)
        fuel_box = snapshot(2, lane=True, box=True, spline=0.94, fuel=20)
        result = run([snapshot(0, fuel=20), snapshot(1, lane=True, spline=0.91, fuel=20), fuel_box, snapshot(3, lane=True, box=False, spline=0.95, fuel=50), fuel_exit])
        self.assertEqual(result["last_visit"]["classification"], "SERVICE_STOP")
        self.assertEqual(result["last_confirmed_exit"]["event_type"], "PIT_SERVICE_STOP_CONFIRMED")

    def test_tyre_repair_and_combined_service_evidence(self) -> None:
        def run(items: list[dict]) -> dict:
            learner = PitLearner(debounce_s=0)
            for item in items:
                result = learner.update(item, item["observed_monotonic_s"])
            return result["last_visit"]

        entry = snapshot(0, spline=0.89)
        lane = snapshot(1, lane=True, spline=0.91)
        box = snapshot(2, lane=True, box=True, spline=0.94)
        departed = snapshot(3, lane=True, box=False, spline=0.95)
        exit_snapshot = snapshot(4, lane=False, spline=0.02)
        for item in (entry, lane, box, departed, exit_snapshot):
            item["tyres"] = {"compound": "medium"}

        tyre_box = copy.deepcopy(box)
        tyre_box["tyres"] = {"compound": "hard"}
        tyre_exit = copy.deepcopy(exit_snapshot)
        tyre_exit["tyres"] = {"compound": "hard"}
        self.assertEqual(run([entry, lane, box, tyre_box, departed, tyre_exit])["classification"], "SERVICE_STOP")

        damaged_box = copy.deepcopy(box)
        damaged_box["car"]["damage"] = {"engine": 0.6}
        repair_box = copy.deepcopy(damaged_box)
        repair_box["car"]["damage"] = {"engine": 0.0}
        repair_exit = copy.deepcopy(exit_snapshot)
        repair_exit["car"]["damage"] = {"engine": 0.0}
        damaged_entry = copy.deepcopy(entry)
        damaged_entry["car"]["damage"] = {"engine": 0.6}
        damaged_lane = copy.deepcopy(lane)
        damaged_lane["car"]["damage"] = {"engine": 0.6}
        self.assertEqual(run([damaged_entry, damaged_lane, damaged_box, repair_box, departed, repair_exit])["classification"], "SERVICE_STOP")

        combined_box = copy.deepcopy(box)
        combined_box["car"]["fuel_l"] = 20
        combined_box["car"]["damage"] = {"engine": 0.0}
        combined_box["tyres"] = {"compound": "hard"}
        combined_exit = copy.deepcopy(exit_snapshot)
        combined_exit["car"]["fuel_l"] = 50
        combined_exit["car"]["damage"] = {"engine": 0.0}
        combined_exit["tyres"] = {"compound": "hard"}
        combined_entry = copy.deepcopy(entry)
        combined_entry["car"]["damage"] = {"engine": 0.6}
        combined_lane = copy.deepcopy(lane)
        combined_lane["car"]["damage"] = {"engine": 0.6}
        visit = run([combined_entry, combined_lane, combined_box, departed, combined_exit])
        self.assertEqual(visit["classification"], "SERVICE_STOP")
        self.assertGreaterEqual(len(visit["service_evidence"]), 3)

        planned = copy.deepcopy(box)
        planned["service_confirmed"] = True
        planned_exit = copy.deepcopy(exit_snapshot)
        planned_exit["service_confirmed"] = True
        self.assertEqual(run([entry, lane, planned, departed, planned_exit])["classification"], "SERVICE_STOP")

        manual = PitLearner(debounce_s=0)
        manual.update(entry, 0)
        manual.update(lane, 1)
        self.assertTrue(manual.confirm_new_stint())
        manual.update(exit_snapshot, 2)
        manual.update(copy.deepcopy(exit_snapshot) | {"snapshot_id": "manual-exit-2"}, 2.1)
        self.assertEqual(manual.last_visit["classification"], "SERVICE_STOP")

    def test_repeated_incomplete_and_reset_visits_are_unknown_without_stint_implication(self) -> None:
        learner = PitLearner(debounce_s=0)
        learner.update(snapshot(0), 0)
        learner.update(snapshot(1, lane=True, box=True), 1)
        learner.update(snapshot(2, lane=False, box=True), 2)
        self.assertEqual(learner.last_visit["classification"], "UNKNOWN_STOP")

        learner.update(snapshot(3), 3)
        learner.update(snapshot(4, lane=True), 4)
        reset = snapshot(5, lane=True, reset=1)
        learner.update(reset, 5)
        learner.update(snapshot(6, lane=False, spline=0.03), 6)
        self.assertEqual(learner.last_visit["classification"], "UNKNOWN_STOP")

        learner.update(snapshot(7), 7)
        learner.update(snapshot(8, lane=True), 8)
        learner.update(snapshot(9, lane=False), 9)
        self.assertEqual(learner.last_visit["classification"], "DRIVE_THROUGH")

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
