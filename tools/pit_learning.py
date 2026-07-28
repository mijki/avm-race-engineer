"""Pure host oracle for automatic pit-lane marker learning."""

from __future__ import annotations

import copy
import math
from dataclasses import dataclass, field
from typing import Any, Mapping

from tools.race_engine_core import SCHEMA_VERSIONS, identity_key, pit_marker, pit_observation, track_layout_key


STATES = ("ON_TRACK", "ENTRY_CANDIDATE", "IN_PIT_LANE", "AT_PIT_BOX", "LEAVING_PIT_BOX", "EXIT_CANDIDATE", "BACK_ON_TRACK", "RESET_SUPPRESSED")
PIT_VISIT_CLASSIFICATIONS = frozenset(("DRIVE_THROUGH", "STOP_GO", "SERVICE_STOP", "UNKNOWN_STOP"))
_CONFIRMED_VALUES = frozenset(("CONFIRMED", "COMPLETE", "COMPLETED", "DONE", "APPLIED", "VERIFIED", "TRUE"))


def _car(snapshot: Mapping[str, Any] | None) -> Mapping[str, Any]:
    value = snapshot.get("car", {}) if isinstance(snapshot, Mapping) else {}
    return value if isinstance(value, Mapping) else {}


def _session(snapshot: Mapping[str, Any] | None) -> Mapping[str, Any]:
    value = snapshot.get("session", {}) if isinstance(snapshot, Mapping) else {}
    return value if isinstance(value, Mapping) else {}


def _pit_lane(snapshot: Mapping[str, Any] | None) -> bool:
    car = _car(snapshot)
    return car.get("pit_lane") is True or car.get("isInPitlane") is True


def _pit_box(snapshot: Mapping[str, Any] | None) -> bool:
    car = _car(snapshot)
    return car.get("pit_box") is True or car.get("isInPit") is True


def _number(value: Any) -> float | None:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)) else None


def _service_sections(snapshot: Mapping[str, Any] | None) -> list[Mapping[str, Any]]:
    if not isinstance(snapshot, Mapping):
        return []
    sections: list[Mapping[str, Any]] = [snapshot]
    for name in ("service", "pit_service", "planned_service", "strategy", "session", "car", "tyres"):
        value = snapshot.get(name)
        if isinstance(value, Mapping):
            sections.append(value)
    return sections


def _confirmed_signal(snapshot: Mapping[str, Any] | None, names: tuple[str, ...]) -> str | None:
    for section in _service_sections(snapshot):
        for name in names:
            value = section.get(name)
            if value is True:
                return name
            if isinstance(value, str) and value.strip().upper() in _CONFIRMED_VALUES:
                return name
            if isinstance(value, Mapping):
                for child_name in ("confirmed", "complete", "completed", "done", "applied", "verified"):
                    child = value.get(child_name)
                    if child is True or isinstance(child, str) and child.strip().upper() in _CONFIRMED_VALUES:
                        return name
    return None


def _service_number(snapshot: Mapping[str, Any] | None, names: tuple[str, ...]) -> float | None:
    for section in _service_sections(snapshot):
        for name in names:
            value = _numeric_total(section.get(name))
            if value is not None:
                return value
    return None


def _numeric_total(value: Any) -> float | None:
    if isinstance(value, Mapping):
        values = [_numeric_total(child) for child in value.values()]
        numeric = [item for item in values if item is not None]
        return sum(numeric) if numeric else None
    return _number(value)


def _service_evidence(previous: Mapping[str, Any] | None, snapshot: Mapping[str, Any] | None, fuel_jump_l: float) -> list[dict[str, Any]]:
    evidence: list[dict[str, Any]] = []
    current_car, previous_car = _car(snapshot), _car(previous)
    current_fuel, previous_fuel = _number(current_car.get("fuel_l")), _number(previous_car.get("fuel_l"))
    fuel_delta = None if current_fuel is None or previous_fuel is None else current_fuel - previous_fuel
    if fuel_delta is not None and fuel_delta >= fuel_jump_l:
        evidence.append({"kind": "FUEL_INCREASE", "delta_l": fuel_delta})
    if _confirmed_signal(snapshot, ("tyre_replacement_confirmed", "tyres_replaced", "tyre_change_confirmed", "tyre_reset_verified", "tyres_reset", "tyre_reset")):
        evidence.append({"kind": "TYRE_REPLACEMENT"})
    previous_tyres, current_tyres = (previous or {}).get("tyres", {}), (snapshot or {}).get("tyres", {})
    if isinstance(previous_tyres, Mapping) and isinstance(current_tyres, Mapping):
        for key in ("compound", "set_id", "tyre_set_id", "tyre_set"):
            if previous_tyres.get(key) is not None and current_tyres.get(key) is not None and previous_tyres.get(key) != current_tyres.get(key):
                evidence.append({"kind": "TYRE_REPLACEMENT", "field": key, "from": previous_tyres.get(key), "to": current_tyres.get(key)})
                break
        previous_reset = _number(previous_tyres.get("reset_counter"))
        current_reset = _number(current_tyres.get("reset_counter"))
        if previous_reset is not None and current_reset is not None and current_reset > previous_reset:
            evidence.append({"kind": "TYRE_RESET", "from": previous_reset, "to": current_reset})
    previous_damage = _service_number(previous, ("damage", "damage_level", "damage_percent", "repair_damage"))
    current_damage = _service_number(snapshot, ("damage", "damage_level", "damage_percent", "repair_damage"))
    if previous_damage is not None and current_damage is not None and current_damage < previous_damage:
        evidence.append({"kind": "REPAIR_COMPLETION", "from": previous_damage, "to": current_damage})
    if _confirmed_signal(snapshot, ("repair_complete", "repairs_complete", "repair_completed", "repair_confirmed", "repairs_confirmed")):
        evidence.append({"kind": "REPAIR_COMPLETION"})
    if _confirmed_signal(snapshot, ("driver_change_confirmed", "driver_change_completed", "planned_driver_change", "service_confirmed", "planned_service_confirmed", "service_completed")):
        evidence.append({"kind": "PLANNED_SERVICE"})
    if _confirmed_signal(snapshot, ("manual_new_stint_confirmation", "new_stint_confirmed", "manual_service_confirmation")):
        evidence.append({"kind": "MANUAL_NEW_STINT"})
    return evidence


def _world_distance(left: Any, right: Any) -> float | None:
    if not isinstance(left, Mapping) or not isinstance(right, Mapping):
        return None
    if not all(isinstance(left.get(key), (int, float)) and isinstance(right.get(key), (int, float)) for key in ("x", "y", "z")):
        return None
    return math.sqrt(sum((float(left[key]) - float(right[key])) ** 2 for key in ("x", "y", "z")))


def _circular_delta(left: float, right: float) -> float:
    delta = abs(left - right)
    return min(delta, 1.0 - delta)


def _circular_center(values: list[float]) -> float | None:
    if not values:
        return None
    reference = values[0]
    adjusted = [value - 1 if value - reference > 0.5 else value + 1 if value - reference < -0.5 else value for value in values]
    return sum(adjusted) / len(adjusted) % 1.0


def forward_distance(current_spline: float | None, target_spline: float | None, track_length_m: float | None) -> tuple[float | None, str]:
    if not all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in (current_spline, target_spline, track_length_m)):
        return None, "PIT_ENTRY_NOT_CALIBRATED"
    if not (0 <= current_spline < 1 and 0 <= target_spline < 1 and track_length_m > 0):
        return None, "PIT_ENTRY_NOT_CALIBRATED"
    raw_delta = target_spline - current_spline
    delta = (raw_delta + 1) % 1
    return delta * track_length_m, "PIT_ENTRY_WRAPAROUND_APPLIED" if raw_delta < 0 else "MEASURED_CURRENT"


@dataclass
class PitLearner:
    debounce_s: float = 0.10
    spline_tolerance: float = 0.025
    movement_limit_m: float = 250.0
    world_jump_threshold_m: float = 1000.0
    max_observations: int = 24
    max_events: int = 64
    state: str = "ON_TRACK"
    live_pit_lane: bool = False
    live_pit_box: bool = False
    previous: dict[str, Any] | None = None
    candidate: dict[str, Any] | None = None
    visit: dict[str, Any] | None = None
    last_visit: dict[str, Any] | None = None
    marker: dict[str, Any] | None = None
    suppress_reason: str | None = None
    events: list[dict[str, Any]] = field(default_factory=list)
    latest_observation: dict[str, Any] | None = None
    latest_rejection: dict[str, Any] | None = None
    sequence: int = 0
    service_fuel_jump_l: float = 1.0
    manual_new_stint_confirmation: bool = False
    last_confirmed_exit: dict[str, Any] | None = None

    def set_marker(self, marker: Mapping[str, Any] | None, snapshot: Mapping[str, Any] | None = None) -> dict[str, Any]:
        identity = snapshot.get("identity", {}) if isinstance(snapshot, Mapping) else {}
        if not isinstance(identity, Mapping):
            identity = {}
        if marker is None:
            marker = pit_marker(track_layout_key=track_layout_key(identity), track_id=identity.get("track_id"), layout_id=identity.get("layout_id"), accepted_observations=[], rejected_observations=[])
        self.marker = copy.deepcopy(dict(marker))
        self.marker.setdefault("accepted_observations", [])
        self.marker.setdefault("rejected_observations", [])
        self.marker.setdefault("timing", {})
        return self.marker

    def _emit(self, snapshot: Mapping[str, Any], event_type: str, payload: Mapping[str, Any] | None = None, *, confidence: str = "medium", rejection: str | None = None, suppression: str | None = None) -> dict[str, Any]:
        self.sequence += 1
        event = {"schema_version": SCHEMA_VERSIONS["race_event"], "event_id": f"pit-event:{self.sequence}:{event_type}", "sequence": self.sequence, "event_type": event_type, "source_snapshot_id": snapshot.get("snapshot_id", "snapshot:unavailable"), "detection_time_s": snapshot.get("observed_monotonic_s"), "source_time_s": snapshot.get("source_timestamp_s"), "session_time_s": _session(snapshot).get("elapsed_s"), "identity_key": identity_key(snapshot.get("identity", {})), "confidence": confidence, "provenance": {"source": "CSP", "detector": "pit-learning-v1"}, "payload": copy.deepcopy(dict(payload or {})), "rejection_reason": rejection, "suppression_reason": suppression}
        self.events.append(event)
        self.events = self.events[-self.max_events :]
        return event

    def _discontinuity(self, snapshot: Mapping[str, Any]) -> str | None:
        if self.previous is None:
            return None
        old_car, current_car = _car(self.previous), _car(snapshot)
        old_session, current_session = _session(self.previous), _session(snapshot)
        if identity_key(self.previous.get("identity", {})) != identity_key(snapshot.get("identity", {})):
            return "IDENTITY_CHANGED"
        if old_session.get("replay") != current_session.get("replay"):
            return "REPLAY_TRANSITION"
        if isinstance(old_session.get("completed_laps"), (int, float)) and isinstance(current_session.get("completed_laps"), (int, float)) and current_session["completed_laps"] < old_session["completed_laps"]:
            return "LAP_COUNTER_DECREASE"
        if isinstance(old_car.get("reset_counter"), (int, float)) and isinstance(current_car.get("reset_counter"), (int, float)) and old_car["reset_counter"] != current_car["reset_counter"]:
            return "RESET_COUNTER_CHANGED"
        if isinstance(old_car.get("spline"), (int, float)) and isinstance(current_car.get("spline"), (int, float)):
            delta = abs(float(old_car["spline"]) - float(current_car["spline"]))
            if 0.20 < delta < 0.80:
                return "SPLINE_JUMP"
        spline_delta = abs(float(old_car["spline"]) - float(current_car["spline"])) if isinstance(old_car.get("spline"), (int, float)) and isinstance(current_car.get("spline"), (int, float)) else None
        movement = _world_distance(old_car.get("world_position"), current_car.get("world_position"))
        if movement is not None and movement > self.world_jump_threshold_m and (spline_delta is None or spline_delta < 0.80):
            return "WORLD_POSITION_JUMP"
        return None

    def _new_visit(self, snapshot: Mapping[str, Any], now_s: float, started_in_pit: bool) -> dict[str, Any]:
        car = _car(snapshot)
        evidence = _service_evidence(None, snapshot, self.service_fuel_jump_l)
        if self.manual_new_stint_confirmation:
            evidence.append({"kind": "MANUAL_NEW_STINT"})
            self.manual_new_stint_confirmation = False
        return {
            "started_at_s": now_s,
            "started_in_pit": started_in_pit,
            "entry_snapshot_id": None if started_in_pit else snapshot.get("snapshot_id"),
            "entry_snapshot": None if started_in_pit else copy.deepcopy(dict(snapshot)),
            "entry_spline": None if started_in_pit else car.get("spline"),
            "entry_world_position": None if started_in_pit else copy.deepcopy(car.get("world_position")),
            "box_arrival_s": None,
            "box_departure_s": None,
            "exit_s": None,
            "exit_snapshot": None,
            "reset_suppressed": False,
            "service_evidence": evidence,
            "classification": "UNKNOWN_STOP" if started_in_pit else None,
        }

    def _observation(self, snapshot: Mapping[str, Any], kind: str, now_s: float) -> dict[str, Any]:
        candidate = self.candidate or {"snapshot": snapshot, "at_s": now_s}
        source = candidate["snapshot"]
        source_car, current_car = _car(source), _car(snapshot)
        return pit_observation(observation_id=f"pit-observation:{self.sequence + 1}:{kind}", transition_type=kind, source_snapshot_id=source.get("snapshot_id"), old_state=kind == "ENTRY" and False or True, new_state=kind == "ENTRY" and True or False, entry_classification="PIT_LANE_ENTRY" if kind == "ENTRY" else None, exit_classification="PIT_LANE_EXIT" if kind == "EXIT" else None, spline=source_car.get("spline"), world_position=source_car.get("world_position"), reset_counter=source_car.get("reset_counter"), speed_kmh=source_car.get("speed_kmh"), source_time_s=source.get("source_timestamp_s"), detection_time_s=source.get("observed_monotonic_s"), stability_duration_s=max(0.0, now_s - float(candidate["at_s"])), movement_m=_world_distance(source_car.get("world_position"), current_car.get("world_position")), confidence="high", confirmation_state="CONFIRMED", rejection_reasons=[])

    def _accept(self, snapshot: Mapping[str, Any], kind: str, now_s: float) -> bool:
        if self.suppress_reason is not None:
            self.latest_rejection = {"reason": self.suppress_reason}
            return False
        if self.marker is None:
            self.set_marker(None, snapshot)
        marker = self.marker
        if marker.get("manual_override") is True:
            self.latest_rejection = {"reason": "MANUAL_OVERRIDE"}
            return False
        observation = self._observation(snapshot, kind, now_s)
        values = [item.get("spline") for item in marker["accepted_observations"] if item.get("kind") == kind and isinstance(item.get("spline"), (int, float))]
        center = _circular_center(values)
        if center is not None and isinstance(observation.get("spline"), (int, float)) and _circular_delta(center, observation["spline"]) > self.spline_tolerance:
            rejected = copy.deepcopy(observation)
            rejected.update({"reason": "OUTLIER", "kind": kind})
            marker["rejected_observations"].append(rejected)
            marker["rejected_observations"] = marker["rejected_observations"][-self.max_observations :]
            self.latest_rejection = rejected
            if len(marker["rejected_observations"]) >= 2 and len(values) >= 2:
                marker["state"] = "CONFLICTED"
            return False
        observation["kind"] = kind
        marker["accepted_observations"].append(copy.deepcopy(observation))
        marker["accepted_observations"] = marker["accepted_observations"][-self.max_observations :]
        values.append(observation.get("spline")) if isinstance(observation.get("spline"), (int, float)) else None
        updated = _circular_center(values)
        if kind == "ENTRY":
            marker["entry_spline"], marker["entry_world_position"] = updated, copy.deepcopy(observation.get("world_position"))
        else:
            marker["exit_spline"], marker["exit_world_position"] = updated, copy.deepcopy(observation.get("world_position"))
        count = len(marker["accepted_observations"])
        marker["confidence"] = min(1.0, count / 3.0)
        marker["state"] = "CONFIRMED" if count >= 3 else "LEARNED" if count == 2 else "PROVISIONAL"
        marker["first_observed_at_s"] = marker.get("first_observed_at_s", now_s)
        marker["last_observed_at_s"] = now_s
        marker["source"] = "AUTOMATIC"
        self.latest_observation = observation
        self.latest_rejection = None
        return True

    def _finish_visit(self, snapshot: Mapping[str, Any], now_s: float) -> None:
        if self.visit is None:
            return
        self.visit["exit_snapshot"] = copy.deepcopy(dict(snapshot))
        self.visit["exit_s"] = now_s
        if self.visit.get("reset_suppressed") or self.visit.get("started_in_pit") or self.visit.get("entry_snapshot") is None:
            classification, classification_reason = "UNKNOWN_STOP", "ENTRY_OR_RESET_UNTRUSTWORTHY"
        elif self.visit.get("service_evidence"):
            classification, classification_reason = "SERVICE_STOP", "CONFIRMED_SERVICE_EVIDENCE"
        elif self.visit.get("box_arrival_s") is None:
            classification, classification_reason = "DRIVE_THROUGH", "NO_PIT_BOX_ARRIVAL"
        elif self.visit.get("box_departure_s") is None:
            classification, classification_reason = "UNKNOWN_STOP", "PIT_BOX_STATE_INCOMPLETE"
        else:
            classification, classification_reason = "STOP_GO", "PIT_BOX_WITHOUT_SERVICE_EVIDENCE"
        self.visit["classification"] = classification
        self.visit["classification_reason"] = classification_reason
        self.visit["total_lane_duration_s"] = max(0.0, now_s - self.visit["started_at_s"])
        if self.visit.get("box_arrival_s") is not None and self.visit.get("box_departure_s") is not None:
            self.visit["service_duration_s"] = max(0.0, self.visit["box_departure_s"] - self.visit["box_arrival_s"])
        if self.marker is not None:
            timing = self.marker.setdefault("timing", {})
            timing.update({"last_classification": classification, "last_total_lane_duration_s": self.visit["total_lane_duration_s"], "last_service_duration_s": self.visit.get("service_duration_s"), "last_entry_to_box_s": self.visit["box_arrival_s"] - self.visit["started_at_s"] if self.visit.get("box_arrival_s") is not None else None, "last_box_to_exit_s": self.visit["exit_s"] - self.visit["box_departure_s"] if self.visit.get("box_departure_s") is not None else None})
        self.last_visit = copy.deepcopy(self.visit)
        self.visit = None

    def confirm_new_stint(self) -> bool:
        """Record an explicit operator confirmation for the active pit visit."""
        if self.visit is None:
            self.manual_new_stint_confirmation = True
            return False
        self.visit.setdefault("service_evidence", []).append({"kind": "MANUAL_NEW_STINT"})
        return True

    def update(self, snapshot: Mapping[str, Any], now_s: float) -> dict[str, Any]:
        snapshot = copy.deepcopy(dict(snapshot))
        current_lane, current_box = _pit_lane(snapshot), _pit_box(snapshot)
        was_lane, was_box = _pit_lane(self.previous), _pit_box(self.previous)
        self.last_confirmed_exit = None
        discontinuity = self._discontinuity(snapshot)
        if discontinuity:
            self.suppress_reason = discontinuity
            self.state = "RESET_SUPPRESSED"
            if self.visit is not None:
                self.visit["reset_suppressed"] = True
            self.candidate = None
            self._emit(snapshot, "PIT_LEARNING_SUPPRESSED", {"reason": discontinuity}, confidence="high", suppression=discontinuity)
        if self.previous is None:
            self.live_pit_lane, self.live_pit_box = current_lane, current_box
            self.visit = self._new_visit(snapshot, now_s, started_in_pit=True) if current_lane else None
            self.state = "AT_PIT_BOX" if current_lane and current_box else "IN_PIT_LANE" if current_lane else "ON_TRACK"
            self.set_marker(self.marker, snapshot)
            self.previous = snapshot
            return self.diagnostics(snapshot)
        if current_lane != was_lane:
            self.live_pit_lane = current_lane
            if current_lane:
                self.candidate = {"kind": "ENTRY", "snapshot": snapshot, "at_s": now_s}
                self.visit = self._new_visit(snapshot, now_s, started_in_pit=False)
                self.state = "ENTRY_CANDIDATE"
                self._emit(snapshot, "PIT_ENTRY_CANDIDATE", {"original_snapshot_id": snapshot.get("snapshot_id")}, confidence="low")
                self.state = "IN_PIT_LANE"
            else:
                self.candidate = {"kind": "EXIT", "snapshot": snapshot, "at_s": now_s}
                self.live_pit_lane = False
                self.state = "EXIT_CANDIDATE"
                self._emit(snapshot, "PIT_EXIT_CANDIDATE", {"original_snapshot_id": snapshot.get("snapshot_id")}, confidence="low")
        if current_box != was_box:
            if current_box:
                self.visit = self.visit or self._new_visit(snapshot, now_s, started_in_pit=True)
                self.visit["box_arrival_s"] = now_s
                self.state = "AT_PIT_BOX"
                self._emit(snapshot, "PIT_BOX_ARRIVAL", {"service_start_s": now_s})
            else:
                if self.visit is not None:
                    self.visit["box_departure_s"] = now_s
                if current_lane:
                    self.state = "LEAVING_PIT_BOX"
                self._emit(snapshot, "PIT_BOX_DEPARTURE", {"service_end_s": now_s})
        if self.visit is not None:
            evidence = _service_evidence(self.previous, snapshot, self.service_fuel_jump_l)
            if evidence:
                self.visit.setdefault("service_evidence", []).extend(evidence)
        if self.candidate:
            kind, candidate = self.candidate["kind"], self.candidate
            stable = now_s - candidate["at_s"] >= self.debounce_s
            same_state = current_lane if kind == "ENTRY" else not current_lane
            old_car, current_car = _car(candidate["snapshot"]), _car(snapshot)
            old_reset, new_reset = old_car.get("reset_counter"), current_car.get("reset_counter")
            movement = _world_distance(old_car.get("world_position"), current_car.get("world_position"))
            candidate_reason = self.suppress_reason if self.suppress_reason is not None else None if stable and same_state else "STABILITY_PENDING" if not stable else "CANDIDATE_INTERRUPTED"
            if isinstance(old_reset, (int, float)) and isinstance(new_reset, (int, float)) and old_reset != new_reset:
                candidate_reason = "RESET_COUNTER_CHANGED"
            if movement is not None and movement > self.movement_limit_m:
                candidate_reason = "WORLD_POSITION_JUMP"
            if candidate_reason is None and same_state:
                accepted = self._accept(snapshot, kind, now_s)
                self.candidate = None
                if kind == "ENTRY":
                    self._emit(snapshot, "PIT_ENTRY_CONFIRMED" if accepted else "PIT_ENTRY_REJECTED", {"marker_state": self.marker.get("state") if self.marker else "UNAVAILABLE"}, confidence="high" if accepted else "low", rejection=None if accepted else self.latest_rejection.get("reason") if self.latest_rejection else "REJECTED", suppression=self.suppress_reason)
                else:
                    self._finish_visit(snapshot, now_s)
                    classification = self.last_visit.get("classification") if self.last_visit else "UNKNOWN_STOP"
                    exit_event = self._emit(snapshot, "PIT_EXIT_CONFIRMED" if accepted else "PIT_EXIT_REJECTED", {"marker_state": self.marker.get("state") if self.marker else "UNAVAILABLE", "classification": classification}, confidence="high" if accepted else "low", rejection=None if accepted else self.latest_rejection.get("reason") if self.latest_rejection else "REJECTED", suppression=self.suppress_reason)
                    if classification == "SERVICE_STOP":
                        self.last_confirmed_exit = self._emit(snapshot, "PIT_SERVICE_STOP_CONFIRMED", {"classification": classification, "exit_event_id": exit_event["event_id"], "visit": copy.deepcopy(self.last_visit)}, confidence="high")
                    self.state = "BACK_ON_TRACK"
                    self.suppress_reason = None
            elif candidate_reason != "STABILITY_PENDING":
                rejection = self._observation(snapshot, kind, now_s)
                rejection["rejection_reasons"] = [candidate_reason]
                if self.marker is not None:
                    self.marker["rejected_observations"].append(rejection)
                    self.marker["rejected_observations"] = self.marker["rejected_observations"][-self.max_observations :]
                self.latest_rejection = rejection
                self.candidate = None
                if kind == "ENTRY":
                    self.visit = None
                    self.state = "BACK_ON_TRACK"
                    self._emit(snapshot, "PIT_ENTRY_REJECTED", {"reason": candidate_reason}, confidence="low", rejection=candidate_reason)
                else:
                    self._finish_visit(snapshot, now_s)
                    classification = self.last_visit.get("classification") if self.last_visit else "UNKNOWN_STOP"
                    self.state = "BACK_ON_TRACK"
                    self._emit(snapshot, "PIT_EXIT_REJECTED", {"reason": candidate_reason, "classification": classification}, confidence="low", rejection=candidate_reason, suppression=self.suppress_reason)
                    self.suppress_reason = None
        elif not current_lane:
            if was_lane and self.visit is not None:
                self._finish_visit(snapshot, now_s)
            self.state = "RESET_SUPPRESSED" if self.suppress_reason else "ON_TRACK"
            self.suppress_reason = None
        elif current_box:
            self.state = "AT_PIT_BOX"
        else:
            self.state = "RESET_SUPPRESSED" if self.suppress_reason else "IN_PIT_LANE"
        self.live_pit_lane, self.live_pit_box = current_lane, current_box
        self.previous = snapshot
        return self.diagnostics(snapshot)

    def manual_override(self, *, entry_spline: float, exit_spline: float | None = None, snapshot: Mapping[str, Any] | None = None) -> dict[str, Any]:
        identity = snapshot.get("identity", {}) if isinstance(snapshot, Mapping) else {}
        self.marker = pit_marker(track_layout_key=track_layout_key(identity), track_id=identity.get("track_id"), layout_id=identity.get("layout_id"), state="MANUAL_OVERRIDE", entry_spline=entry_spline, exit_spline=exit_spline, accepted_observations=[], rejected_observations=[], confidence=1.0, source="MANUAL_OVERRIDE", manual_override=True)
        return self.marker

    def clear_override(self) -> bool:
        if self.marker is None or not self.marker.get("manual_override"):
            return False
        self.marker["manual_override"] = False
        self.marker["source"] = "AUTOMATIC"
        self.marker["state"] = "PROVISIONAL" if self.marker.get("entry_spline") is not None else "UNAVAILABLE"
        return True

    def distance_to_entry(self, snapshot: Mapping[str, Any]) -> tuple[float | None, str]:
        return forward_distance(_car(snapshot).get("spline"), self.marker.get("entry_spline") if self.marker else None, _session(snapshot).get("track_length_m"))

    def diagnostics(self, snapshot: Mapping[str, Any] | None = None) -> dict[str, Any]:
        distance, reason = self.distance_to_entry(snapshot or {})
        return {"state": self.state, "live_pit_lane": self.live_pit_lane, "live_pit_box": self.live_pit_box, "marker": copy.deepcopy(self.marker), "marker_state": self.marker.get("state", "UNAVAILABLE") if self.marker else "UNAVAILABLE", "confidence": self.marker.get("confidence", 0) if self.marker else 0, "accepted_observations": len(self.marker.get("accepted_observations", [])) if self.marker else 0, "rejected_observations": len(self.marker.get("rejected_observations", [])) if self.marker else 0, "distance_to_entry_m": distance, "distance_reason": reason, "latest_observation": copy.deepcopy(self.latest_observation), "latest_rejection": copy.deepcopy(self.latest_rejection), "current_visit": copy.deepcopy(self.visit), "last_visit": copy.deepcopy(self.last_visit), "last_confirmed_exit": copy.deepcopy(self.last_confirmed_exit), "suppress_reason": self.suppress_reason}
