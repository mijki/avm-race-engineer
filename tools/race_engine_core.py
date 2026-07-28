"""Pure Race Engine Core V1 contracts and deterministic replay helpers.

This module deliberately contains no simulator, UI, or network code.  It is
the host-side oracle for the additive Lua contracts in ``contracts.lua`` and
is also useful to bridge-side tests before a full race engine exists.
"""

from __future__ import annotations

import copy
import json
import math
from pathlib import Path
from types import MappingProxyType
from typing import Any, Iterable, Mapping


SCHEMA_VERSIONS = {
    "telemetry_snapshot": "telemetry-snapshot-v1",
    "race_event": "race-event-v1",
    "completed_lap": "completed-lap-v1",
    "pit_observation": "pit-transition-observation-v1",
    "pit_marker": "pit-marker-record-v1",
    "calculated_value": "calculated-value-v1",
    "forecast": "forecast-envelope-v1",
}
SOURCE_HEALTH = frozenset(("LIVE", "PARTIAL", "STALE", "OFFLINE"))
MARKER_STATES = frozenset(("UNAVAILABLE", "PROVISIONAL", "LEARNED", "CONFIRMED", "CONFLICTED", "MANUAL_OVERRIDE"))
ELIGIBILITY_POLICIES = frozenset(("STRICT", "OPERATIONAL", "CUSTOM"))


def _copy(value: Any) -> Any:
    return copy.deepcopy(value)


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(child) for key, child in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(child) for child in value)
    return value


def to_plain(value: Any) -> Any:
    """Convert immutable replay results into JSON-compatible plain values."""
    if isinstance(value, Mapping):
        return {key: to_plain(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_plain(child) for child in value]
    return value


def identity_key(identity: Mapping[str, Any] | None) -> str:
    identity = identity or {}
    return "|".join(str(identity.get(key) or "") for key in ("car_id", "track_id", "layout_id", "session_id", "configuration_id"))


def track_layout_key(identity: Mapping[str, Any] | None) -> str:
    identity = identity or {}
    return f"{identity.get('track_id') or ''}::{identity.get('layout_id') or ''}"


def snapshot_id(identity: Mapping[str, Any] | None, sequence: int) -> str:
    return f"snapshot:{identity_key(identity)}:{sequence}"


def telemetry_snapshot(**fields: Any) -> dict[str, Any]:
    identity = _copy(fields.get("identity") or {})
    sequence = int(fields.get("sequence") or 0)
    return {
        "schema_version": SCHEMA_VERSIONS["telemetry_snapshot"],
        "snapshot_id": fields.get("snapshot_id") or snapshot_id(identity, sequence),
        "source_mode": fields.get("source_mode", "live"),
        "source_timestamp_s": fields.get("source_timestamp_s"),
        "observed_monotonic_s": fields.get("observed_monotonic_s"),
        "sequence": sequence,
        "source_health": fields.get("source_health", "OFFLINE"),
        "identity": identity,
        "track_layout_key": fields.get("track_layout_key") or track_layout_key(identity),
        "session": _copy(fields.get("session") or {}),
        "car": _copy(fields.get("car") or {}),
        "tyres": _copy(fields.get("tyres") or {}),
        "environment": _copy(fields.get("environment") or {}),
        "provenance": _copy(fields.get("provenance") or {}),
        "availability": _copy(fields.get("availability") or {}),
        "failures": _copy(fields.get("failures") or {}),
    }


def _event(stream: "EventStream", snapshot: Mapping[str, Any], event_type: str, payload: Mapping[str, Any] | None = None, *, confidence: str = "medium", rejection_reason: str | None = None, suppression_reason: str | None = None) -> Mapping[str, Any]:
    stream.sequence += 1
    identity = snapshot.get("identity") if isinstance(snapshot.get("identity"), Mapping) else {}
    event = {
        "schema_version": SCHEMA_VERSIONS["race_event"],
        "event_id": f"event:{stream.sequence}:{event_type}",
        "sequence": stream.sequence,
        "event_type": event_type,
        "source_snapshot_id": snapshot.get("snapshot_id", "snapshot:unavailable"),
        "detection_time_s": snapshot.get("observed_monotonic_s"),
        "source_time_s": snapshot.get("source_timestamp_s"),
        "session_time_s": (snapshot.get("session") or {}).get("elapsed_s"),
        "identity_key": identity_key(identity),
        "confidence": confidence,
        "provenance": {"source": snapshot.get("source_mode", "unknown"), "detector": "race-events-v1"},
        "payload": _copy(payload or {}),
        "suppression_reason": suppression_reason,
        "rejection_reason": rejection_reason,
    }
    frozen = _freeze(event)
    stream.events.append(frozen)
    del stream.events[: max(0, len(stream.events) - stream.max_events)]
    return frozen


class EventStream:
    """Deterministic bounded event detector for normalized snapshots."""

    def __init__(self, max_events: int = 128, *, spline_jump_threshold: float = 0.20, world_jump_threshold_m: float = 1000.0, refuel_jump_l: float = 1.0) -> None:
        self.max_events = max(1, max_events)
        self.spline_jump_threshold = spline_jump_threshold
        self.world_jump_threshold_m = world_jump_threshold_m
        self.refuel_jump_l = refuel_jump_l
        self.sequence = 0
        self.events: list[Mapping[str, Any]] = []
        self.previous: Mapping[str, Any] | None = None
        self.identity = ""
        self.weather_regime: Any = None

    @staticmethod
    def _world_distance(left: Any, right: Any) -> float | None:
        if not isinstance(left, Mapping) or not isinstance(right, Mapping):
            return None
        coords = ("x", "y", "z")
        if not all(isinstance(left.get(key), (int, float)) and isinstance(right.get(key), (int, float)) for key in coords):
            return None
        return math.sqrt(sum((float(left[key]) - float(right[key])) ** 2 for key in coords))

    def update(self, snapshot: Mapping[str, Any]) -> list[Mapping[str, Any]]:
        if not isinstance(snapshot, Mapping):
            return []
        previous = self.previous
        current_identity = identity_key(snapshot.get("identity") if isinstance(snapshot.get("identity"), Mapping) else {})
        current_session = snapshot.get("session") if isinstance(snapshot.get("session"), Mapping) else {}
        current_car = snapshot.get("car") if isinstance(snapshot.get("car"), Mapping) else {}
        current_environment = snapshot.get("environment") if isinstance(snapshot.get("environment"), Mapping) else {}
        emitted: list[Mapping[str, Any]] = []
        if previous is None:
            emitted.append(_event(self, snapshot, "SESSION_STARTED", {"initial": True}, confidence="high"))
        else:
            previous_identity = self.identity
            previous_session = previous.get("session") if isinstance(previous.get("session"), Mapping) else {}
            previous_car = previous.get("car") if isinstance(previous.get("car"), Mapping) else {}
            previous_environment = previous.get("environment") if isinstance(previous.get("environment"), Mapping) else {}
            if previous_identity != current_identity:
                emitted.append(_event(self, snapshot, "IDENTITY_CHANGED", {"previous_key": previous_identity, "current_key": current_identity}, confidence="high"))
            if previous_session.get("replay") != current_session.get("replay"):
                emitted.append(_event(self, snapshot, "REPLAY_TRANSITION", {"from": previous_session.get("replay"), "to": current_session.get("replay")}, confidence="high"))
            previous_laps, current_laps = previous_session.get("completed_laps"), current_session.get("completed_laps")
            if isinstance(previous_laps, (int, float)) and isinstance(current_laps, (int, float)):
                if current_laps < previous_laps:
                    emitted.extend((_event(self, snapshot, "SESSION_RESTART", {"previous_laps": previous_laps, "current_laps": current_laps}, confidence="high"), _event(self, snapshot, "LAP_COUNTER_DECREASE", {}, confidence="high")))
                elif current_laps > previous_laps:
                    emitted.append(_event(self, snapshot, "LAP_COMPLETED", {"lap_number": previous_laps, "count": current_laps - previous_laps}, confidence="high"))
            old_reset, new_reset = previous_car.get("reset_counter"), current_car.get("reset_counter")
            if isinstance(old_reset, (int, float)) and isinstance(new_reset, (int, float)) and old_reset != new_reset:
                emitted.append(_event(self, snapshot, "RESET", {"from": old_reset, "to": new_reset}, confidence="high"))
            old_fuel, new_fuel = previous_car.get("fuel_l"), current_car.get("fuel_l")
            if isinstance(old_fuel, (int, float)) and isinstance(new_fuel, (int, float)) and new_fuel - old_fuel > self.refuel_jump_l:
                emitted.append(_event(self, snapshot, "REFUEL", {"delta_l": new_fuel - old_fuel}, confidence="medium"))
            old_spline, new_spline = previous_car.get("spline"), current_car.get("spline")
            if isinstance(old_spline, (int, float)) and isinstance(new_spline, (int, float)):
                delta = abs(float(new_spline) - float(old_spline))
                if self.spline_jump_threshold < delta < 1.0 - self.spline_jump_threshold:
                    emitted.append(_event(self, snapshot, "SPLINE_JUMP", {"delta": delta}, confidence="medium", rejection_reason="SPLINE_JUMP"))
            world_m = self._world_distance(previous_car.get("world_position"), current_car.get("world_position"))
            if world_m is not None and world_m > self.world_jump_threshold_m:
                emitted.append(_event(self, snapshot, "TELEPORT", {"movement_m": world_m}, confidence="high", rejection_reason="WORLD_POSITION_JUMP"))
            old_lane, new_lane = previous_car.get("pit_lane") is True, current_car.get("pit_lane") is True
            if not old_lane and new_lane:
                emitted.append(_event(self, snapshot, "PIT_ENTRY_CANDIDATE", {"old_state": False, "new_state": True}, confidence="low"))
            elif old_lane and not new_lane:
                emitted.append(_event(self, snapshot, "PIT_EXIT_CANDIDATE", {"old_state": True, "new_state": False}, confidence="low"))
            old_box, new_box = previous_car.get("pit_box") is True, current_car.get("pit_box") is True
            if not old_box and new_box:
                emitted.append(_event(self, snapshot, "PIT_BOX_ARRIVAL", {"old_state": False, "new_state": True}, confidence="medium"))
            elif old_box and not new_box:
                emitted.append(_event(self, snapshot, "PIT_BOX_DEPARTURE", {"old_state": True, "new_state": False}, confidence="medium"))
            if current_session.get("finished") is True and previous_session.get("finished") is not True:
                emitted.append(_event(self, snapshot, "SESSION_ENDED", {}, confidence="high"))
            regime = current_environment.get("weather_regime")
            if regime is not None and self.weather_regime is not None and regime != self.weather_regime:
                emitted.append(_event(self, snapshot, "WEATHER_REGIME_CHANGED", {"from": self.weather_regime, "to": regime}, confidence="medium"))
            self.weather_regime = regime if regime is not None else self.weather_regime
        self.identity = current_identity
        if self.weather_regime is None:
            self.weather_regime = current_environment.get("weather_regime")
        self.previous = _copy(snapshot)
        return emitted


def replay_snapshots(snapshots: Iterable[Mapping[str, Any]], *, max_events: int = 128) -> list[Mapping[str, Any]]:
    stream = EventStream(max_events=max_events)
    result: list[Mapping[str, Any]] = []
    for snapshot in snapshots:
        result.extend(stream.update(snapshot))
    return result


def serialize_replay(events: Iterable[Mapping[str, Any]]) -> bytes:
    return (json.dumps(to_plain(list(events)), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def completed_lap(**fields: Any) -> dict[str, Any]:
    eligibility = _copy(fields.get("eligibility") or {})
    return {
        "schema_version": SCHEMA_VERSIONS["completed_lap"],
        "lap_id": fields.get("lap_id"),
        "identity_key": fields.get("identity_key", ""),
        "lap_number": fields.get("lap_number"),
        "started_at_s": fields.get("started_at_s"),
        "completed_at_s": fields.get("completed_at_s"),
        "lap_time_s": fields.get("lap_time_s"),
        "sectors": _copy(fields.get("sectors") or {}),
        "official_validity": fields.get("official_validity"),
        "invalidation_reason": fields.get("invalidation_reason"),
        "classification": fields.get("classification"),
        "fuel": _copy(fields.get("fuel") or {}),
        "weather_regime": fields.get("weather_regime"),
        "compound": fields.get("compound"),
        "pit_reset_interaction": _copy(fields.get("pit_reset_interaction") or {}),
        "eligibility": {
            "useForPace": eligibility.get("useForPace"),
            "useForFuel": eligibility.get("useForFuel"),
            "useForTyres": eligibility.get("useForTyres"),
            "useForProjection": eligibility.get("useForProjection"),
            "useForOfficialAverage": eligibility.get("useForOfficialAverage"),
            "policy": eligibility.get("policy", "OPERATIONAL"),
            "reasons": _copy(eligibility.get("reasons") or {}),
            "manual_override": eligibility.get("manual_override"),
        },
    }


def pit_observation(**fields: Any) -> dict[str, Any]:
    return {"schema_version": SCHEMA_VERSIONS["pit_observation"], "observation_id": fields.get("observation_id"), "transition_type": fields.get("transition_type"), "source_snapshot_id": fields.get("source_snapshot_id"), "old_state": fields.get("old_state"), "new_state": fields.get("new_state"), "entry_classification": fields.get("entry_classification"), "exit_classification": fields.get("exit_classification"), "spline": fields.get("spline"), "world_position": _copy(fields.get("world_position")), "reset_counter": fields.get("reset_counter"), "speed_kmh": fields.get("speed_kmh"), "source_time_s": fields.get("source_time_s"), "detection_time_s": fields.get("detection_time_s"), "stability_duration_s": fields.get("stability_duration_s"), "movement_m": fields.get("movement_m"), "confidence": fields.get("confidence", "low"), "confirmation_state": fields.get("confirmation_state", "PROVISIONAL"), "rejection_reasons": _copy(fields.get("rejection_reasons") or [])}


def pit_marker(**fields: Any) -> dict[str, Any]:
    return {"schema_version": SCHEMA_VERSIONS["pit_marker"], "track_layout_key": fields.get("track_layout_key", ""), "track_id": fields.get("track_id"), "layout_id": fields.get("layout_id"), "state": fields.get("state", "UNAVAILABLE"), "entry_spline": fields.get("entry_spline"), "exit_spline": fields.get("exit_spline"), "entry_world_position": _copy(fields.get("entry_world_position")), "exit_world_position": _copy(fields.get("exit_world_position")), "accepted_observations": _copy(fields.get("accepted_observations") or []), "rejected_observations": _copy(fields.get("rejected_observations") or []), "confidence": fields.get("confidence", 0.0), "source": fields.get("source", "AUTOMATIC"), "first_observed_at_s": fields.get("first_observed_at_s"), "last_observed_at_s": fields.get("last_observed_at_s"), "manual_override": fields.get("manual_override", False), "timing": _copy(fields.get("timing") or {})}


def calculated_value(**fields: Any) -> dict[str, Any]:
    return {"schema_version": SCHEMA_VERSIONS["calculated_value"], "value": fields.get("value"), "unit": fields.get("unit", ""), "calculation_version": fields.get("calculation_version", "unknown"), "source_fields": _copy(fields.get("source_fields") or []), "source_events": _copy(fields.get("source_events") or []), "accepted_samples": _copy(fields.get("accepted_samples") or []), "rejected_samples": _copy(fields.get("rejected_samples") or []), "sample_count": fields.get("sample_count", 0), "regime": fields.get("regime"), "policy": fields.get("policy"), "freshness_s": fields.get("freshness_s"), "confidence": fields.get("confidence"), "uncertainty": _copy(fields.get("uncertainty")), "binding_constraint": fields.get("binding_constraint"), "unavailable_reason": fields.get("unavailable_reason")}


def forecast(**fields: Any) -> dict[str, Any]:
    return {"schema_version": SCHEMA_VERSIONS["forecast"], "forecast_id": fields.get("forecast_id"), "model_id": fields.get("model_id"), "model_version": fields.get("model_version"), "generated_at_s": fields.get("generated_at_s"), "target_at_s": fields.get("target_at_s"), "value": fields.get("value"), "unit": fields.get("unit", ""), "measured_inputs": _copy(fields.get("measured_inputs") or []), "calculated_inputs": _copy(fields.get("calculated_inputs") or []), "samples": _copy(fields.get("samples") or []), "regime": fields.get("regime"), "freshness_s": fields.get("freshness_s"), "confidence": fields.get("confidence"), "uncertainty": _copy(fields.get("uncertainty")), "binding_constraint": fields.get("binding_constraint"), "unavailable_reason": fields.get("unavailable_reason"), "supersedes": fields.get("supersedes")}


def load_replay_fixture(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def replay_fixture(path: Path) -> dict[str, bytes]:
    catalog = load_replay_fixture(path)
    return {scenario["id"]: serialize_replay(replay_snapshots(scenario["snapshots"])) for scenario in catalog["scenarios"]}
