"""Host oracle for the bounded Lua live slice.

The real runtime implementation is Lua. This small, dependency-free oracle
keeps the same normalized field names and equations available to Python tests
when no Lua interpreter is installed on the validation host.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from statistics import mean, pstdev
from typing import Any

from tools.race_engine_core import SCHEMA_VERSIONS, identity_key as race_identity_key, snapshot_id as race_snapshot_id, track_layout_key


CORE_FIELDS = (
    "session.elapsed_s",
    "session.current_lap",
    "car.speed_kmh",
    "car.fuel_l",
    "car.spline",
    "car.lap_time_s",
)

OPTIONAL_FIELDS = (
    "identity.track_id",
    "identity.layout_id",
    "identity.car_id",
    "session.remaining_s",
    "session.lap_limit",
    "session.position",
    "session.total_cars",
    "session.track_length_m",
    "car.previous_lap_time_s",
    "car.best_lap_time_s",
    "car.pit_lane",
    "car.pit_box",
    "tyres.compound",
    "tyres.core_c",
    "tyres.surface_c",
    "tyres.pressure_kpa",
    "tyres.wear",
    "environment.ambient_c",
    "environment.road_c",
    "environment.weather_type",
    "environment.rain_intensity",
    "environment.track_wetness",
    "environment.standing_water",
)

TASK2_OPTIONAL_FIELDS = ("car.reset_counter", "car.world_position")


@dataclass
class SourceHealthTracker:
    """Bounded LIVE/PARTIAL/STALE/OFFLINE transition oracle."""

    stale_after_s: float = 2.0
    transition_confirmations: int = 2
    state: str = "OFFLINE"
    previous_state: str | None = None
    last_usable_s: float | None = None
    last_current_s: float | None = None
    healthy_streak: int = 0
    failure_streak: int = 0
    transitions: list[dict[str, Any]] = field(default_factory=list)
    max_transitions: int = 16

    def _transition(self, next_state: str, reason: str, now_s: float) -> None:
        if self.state == next_state and self.transitions and self.transitions[-1].get("reason") == reason:
            return
        self.previous_state = self.state
        self.state = next_state
        self.transitions.append({"from": self.previous_state, "to": next_state, "reason": reason, "at_s": now_s})
        self.transitions = self.transitions[-self.max_transitions :]

    def update(self, now_s: float, *, usable_core: bool, optional_degraded: bool = False, read_ok: bool = True, reason: str | None = None) -> str:
        self.last_current_s = now_s
        if usable_core and read_ok:
            self.healthy_streak += 1
            self.failure_streak = 0
            self.last_usable_s = now_s
            self._transition("PARTIAL" if optional_degraded else "LIVE", "OPTIONAL_FIELDS_DEGRADED" if optional_degraded else "CORE_FIELDS_RECOVERED", now_s)
            return self.state
        self.healthy_streak = 0
        self.failure_streak += 1
        age = now_s - self.last_usable_s if self.last_usable_s is not None else None
        if self.last_usable_s is None:
            self._transition("OFFLINE", reason or "NO_USABLE_CORE", now_s)
        elif age is not None and age > self.stale_after_s:
            self._transition("STALE", reason or "SOURCE_STALE", now_s)
        elif self.failure_streak >= self.transition_confirmations:
            self._transition("PARTIAL", reason or "CORE_READ_DEGRADED", now_s)
        return self.state

    def diagnostics(self) -> dict[str, Any]:
        return {
            "state": self.state,
            "previous_state": self.previous_state,
            "last_usable_s": self.last_usable_s,
            "current_age_s": self.last_current_s - self.last_usable_s if self.last_current_s is not None and self.last_usable_s is not None else None,
            "healthy_streak": self.healthy_streak,
            "failure_streak": self.failure_streak,
            "transitions": list(self.transitions),
        }


@dataclass
class SnapshotHistory:
    max_count: int = 48
    snapshots: list[dict[str, Any]] = field(default_factory=list)

    def append(self, snapshot: dict[str, Any]) -> None:
        self.snapshots.append(snapshot)
        self.snapshots = self.snapshots[-self.max_count :]

    def recent(self) -> list[dict[str, Any]]:
        return [dict(snapshot) for snapshot in self.snapshots]


def classify_source_health(snapshot: dict[str, Any], *, read_ok: bool = True, stale: bool = False) -> dict[str, Any]:
    """Task 2 health semantics; legacy ``classify_source`` remains compatible."""
    result = classify_source(snapshot, stale=stale)
    result["runtime_optional_missing"] = [field for field in TASK2_OPTIONAL_FIELDS if not _present(_path(snapshot, field))]
    if not read_ok:
        result["source_health"] = "STALE" if stale else "OFFLINE"
    elif result["core_valid"]:
        result["source_health"] = "PARTIAL" if result["optional_missing"] or result["runtime_optional_missing"] else "LIVE"
    else:
        result["source_health"] = "OFFLINE"
    return result


def _path(snapshot: dict[str, Any], field: str) -> Any:
    value: Any = snapshot
    for part in field.split("."):
        if not isinstance(value, dict):
            return None
        value = value.get(part)
    return value


def _present(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == value and value not in (float("inf"), float("-inf"))
    if isinstance(value, str):
        return value != ""
    return True


def classify_source(snapshot: dict[str, Any], *, stale: bool = False) -> dict[str, Any]:
    missing_core = [field for field in CORE_FIELDS if not _present(_path(snapshot, field))]
    optional_missing = [field for field in OPTIONAL_FIELDS if not _present(_path(snapshot, field))]
    availability = "stale" if stale else ("live" if not missing_core and not optional_missing else "partial")
    return {"availability": availability, "core_valid": not missing_core, "missing_core": missing_core, "optional_missing": optional_missing}


def live_source_from_api(*, ac_available: bool, sim: Any, car: Any, snapshot: dict[str, Any] | None = None, stale: bool = False) -> dict[str, Any]:
    """Classify the adapter boundary before UI projection or mock selection."""
    if not ac_available or sim is None or car is None:
        return {"availability": "unavailable", "core_valid": False, "missing_core": [], "optional_missing": []}
    result = classify_source(snapshot or {}, stale=stale)
    return result


def normalize_csp(raw: dict[str, Any], now_s: float, source_mode: str = "live") -> dict[str, Any]:
    def section(name: str) -> dict[str, Any]:
        value = raw.get(name, {})
        return value if isinstance(value, dict) else {}

    identity = section("identity")
    session = section("session")
    car = section("car")
    tyres = section("tyres")
    environment = section("environment")
    normalized_session = {key: session.get(key) for key in ("type", "elapsed_s", "remaining_s", "lap_limit", "completed_laps", "race_lap", "current_lap", "position", "total_cars", "track_length_m", "paused", "replay", "active", "finished")}
    if normalized_session["race_lap"] is None:
        normalized_session["race_lap"] = normalized_session["completed_laps"]
    snapshot = {
        "schema_version": SCHEMA_VERSIONS["telemetry_snapshot"],
        "snapshot_id": raw.get("snapshot_id") or race_snapshot_id(identity, int(raw.get("sequence") or 0)),
        "source_mode": source_mode,
        "observed_monotonic_s": now_s,
        "source_timestamp_s": raw.get("source_timestamp_s", now_s),
        "sequence": int(raw.get("sequence") or 0),
        "identity": {key: identity.get(key) for key in ("car_id", "track_id", "layout_id", "driver_name", "session_id", "configuration_id")},
        "session": normalized_session,
        "car": {key: car.get(key) for key in ("speed_kmh", "fuel_l", "fuel_capacity_l", "spline", "distance_session_km", "pit_lane", "pit_box", "lap_time_s", "previous_lap_time_s", "best_lap_time_s", "lap_valid", "previous_lap_valid", "last_lap_cuts", "reset_counter")},
        "tyres": {key: tyres.get(key) for key in ("compound", "core_c", "surface_c", "wear", "pressure_kpa", "optimum_c", "wheels")},
        "environment": {key: environment.get(key) for key in ("ambient_c", "road_c", "wind_kmh", "weather_type", "rain_intensity", "track_wetness", "standing_water", "grip")},
    }
    snapshot["source_availability"] = "mock" if source_mode == "mock" else classify_source(snapshot)["availability"]
    source = classify_source(snapshot)
    snapshot["source_health"] = "LIVE" if source_mode == "mock" else ("PARTIAL" if source["core_valid"] and source["optional_missing"] else "LIVE" if source["core_valid"] else "OFFLINE")
    snapshot["track_layout_key"] = track_layout_key(snapshot["identity"])
    snapshot["missing_core"] = source["missing_core"]
    snapshot["optional_missing"] = source["optional_missing"]
    snapshot["availability"] = {field: {"available": _present(_path(snapshot, field)), "provenance": "fixture" if _present(_path(snapshot, field)) else None, "reason": "MEASURED_CURRENT" if _present(_path(snapshot, field)) else "SOURCE_UNAVAILABLE"} for field in CORE_FIELDS + OPTIONAL_FIELDS + TASK2_OPTIONAL_FIELDS}
    snapshot["failures"] = {"missing_core": source["missing_core"], "missing_optional": source["optional_missing"]}
    return snapshot


def identity_key(snapshot: dict[str, Any]) -> str:
    value = snapshot.get("identity", {})
    return "|".join(str(value.get(key) or "") for key in ("car_id", "track_id", "layout_id", "session_id", "configuration_id"))


def forward_distance(current_spline: float | None, pit_entry_spline: float | None, track_length_m: float | None) -> tuple[float | None, str]:
    if not all(isinstance(value, (int, float)) for value in (current_spline, pit_entry_spline, track_length_m)):
        return None, "PIT_ENTRY_NOT_CALIBRATED"
    if not (0 <= current_spline < 1 and 0 <= pit_entry_spline < 1 and track_length_m > 0):
        return None, "PIT_ENTRY_NOT_CALIBRATED"
    delta = pit_entry_spline - current_spline
    if delta < 0:
        return (delta + 1) * track_length_m, "PIT_ENTRY_WRAPAROUND_APPLIED"
    return delta * track_length_m, "MEASURED_CURRENT"


@dataclass
class SampleStore:
    max_count: int = 12
    laps: list[dict[str, Any]] = field(default_factory=list)
    excluded_laps: list[dict[str, Any]] = field(default_factory=list)
    stint_history: list[dict[str, Any]] = field(default_factory=list)
    fuel_samples: list[float] = field(default_factory=list)
    pace_samples: list[float] = field(default_factory=list)
    latest_valid_fuel_l: float | None = None
    latest_valid_pace_s: float | None = None
    latest_completed: dict[str, Any] | None = None
    latest_excluded: dict[str, Any] | None = None
    tyre_lap_number: int | None = None
    tyre_lap_min_c: dict[int, float] = field(default_factory=dict)
    tyre_lap_max_c: dict[int, float] = field(default_factory=dict)
    last_reset_reason: str | None = None

    def record_lap(self, lap: dict[str, Any]) -> bool:
        self.latest_completed = lap
        if not lap.get("accepted"):
            self.excluded_laps.append(lap)
            self.excluded_laps = self.excluded_laps[-self.max_count :]
            self.latest_excluded = lap
            return False
        self.laps.append(lap)
        if isinstance(lap.get("fuel_used_l"), (int, float)) and lap["fuel_used_l"] > 0:
            self.fuel_samples.append(float(lap["fuel_used_l"]))
            self.latest_valid_fuel_l = float(lap["fuel_used_l"])
        if isinstance(lap.get("lap_time_s"), (int, float)) and lap["lap_time_s"] > 0:
            self.pace_samples.append(float(lap["lap_time_s"]))
            self.latest_valid_pace_s = float(lap["lap_time_s"])
        self.laps = self.laps[-self.max_count :]
        self.fuel_samples = self.fuel_samples[-self.max_count :]
        self.pace_samples = self.pace_samples[-self.max_count :]
        return True

    add_lap = record_lap

    def reset(self, reason: str | None = None) -> None:
        self.laps.clear()
        self.excluded_laps.clear()
        self.stint_history.clear()
        self.fuel_samples.clear()
        self.pace_samples.clear()
        self.latest_valid_fuel_l = None
        self.latest_valid_pace_s = None
        self.latest_completed = None
        self.latest_excluded = None
        self.tyre_lap_number = None
        self.tyre_lap_min_c.clear()
        self.tyre_lap_max_c.clear()
        self.last_reset_reason = reason

    def reset_stint(self, reason: str) -> None:
        if self.fuel_samples or self.pace_samples:
            self.stint_history.append({"reason": reason, "fuel_samples": self.fuel_samples[:], "pace_samples": self.pace_samples[:]})
            self.stint_history = self.stint_history[-4:]
        self.laps.clear()
        self.fuel_samples.clear()
        self.pace_samples.clear()
        self.latest_valid_fuel_l = None
        self.latest_valid_pace_s = None
        self.latest_completed = None
        self.latest_excluded = None
        self.tyre_lap_number = None
        self.tyre_lap_min_c.clear()
        self.tyre_lap_max_c.clear()
        self.last_reset_reason = reason

    def update_tyre_lap(self, snapshot: dict[str, Any]) -> None:
        lap_number = snapshot.get("session", {}).get("current_lap")
        if not isinstance(lap_number, int):
            return
        if self.tyre_lap_number != lap_number:
            self.tyre_lap_number = lap_number
            self.tyre_lap_min_c.clear()
            self.tyre_lap_max_c.clear()
        for index, wheel in enumerate(snapshot.get("tyres", {}).get("wheels") or [], start=1):
            value = wheel.get("core_c") if isinstance(wheel, dict) else None
            if isinstance(value, (int, float)):
                self.tyre_lap_min_c[index] = min(value, self.tyre_lap_min_c.get(index, value))
                self.tyre_lap_max_c[index] = max(value, self.tyre_lap_max_c.get(index, value))


@dataclass
class LapTracker:
    previous: dict[str, Any] | None = None
    lap_start_fuel_l: float | None = None
    lap_start_distance_km: float | None = None
    out_lap_pending: bool = False
    identity: str | None = None

    def update(self, snapshot: dict[str, Any]) -> dict[str, Any] | None:
        current_identity = identity_key(snapshot)
        if self.identity is not None and current_identity != self.identity:
            self.__init__()
        self.identity = current_identity
        car = snapshot["car"]
        previous = self.previous
        if self.lap_start_fuel_l is None:
            self.lap_start_fuel_l = car.get("fuel_l")
        if self.lap_start_distance_km is None:
            self.lap_start_distance_km = car.get("distance_session_km")
        event = None
        current_count = snapshot["session"].get("completed_laps")
        previous_count = previous and previous["session"].get("completed_laps")
        if previous_count is not None and current_count is not None and current_count > previous_count:
            previous_car = previous["car"]
            reason = None
            in_lap = bool(previous_car.get("pit_lane")) or bool(car.get("pit_lane"))
            if current_count - previous_count != 1:
                reason = "INCOMPLETE_LAP"
            elif in_lap:
                reason = "PIT_LAP_EXCLUDED"
            elif self.out_lap_pending:
                reason = "OUT_LAP_EXCLUDED"
            elif car.get("previous_lap_valid") is not True or (car.get("last_lap_cuts") or 0) > 0:
                reason = "INVALID_LAP"
            fuel_used = None
            if isinstance(self.lap_start_fuel_l, (int, float)) and isinstance(car.get("fuel_l"), (int, float)):
                delta = self.lap_start_fuel_l - car["fuel_l"]
                if 0 <= delta < 0.8 * max(self.lap_start_fuel_l, 1):
                    fuel_used = delta
            if fuel_used is None and reason is None:
                reason = "REFUEL_TRANSITION"
            distance = None
            if isinstance(self.lap_start_distance_km, (int, float)) and isinstance(car.get("distance_session_km"), (int, float)):
                delta = car["distance_session_km"] - self.lap_start_distance_km
                if 0 < delta < 100:
                    distance = delta
            event = {"lap_number": previous_count, "lap_time_s": car.get("previous_lap_time_s"), "fuel_used_l": fuel_used, "distance_km": distance, "accepted": reason is None, "reason": reason, "regime": reason or "green_valid", "incomplete": current_count - previous_count != 1}
            self.out_lap_pending = False
            self.lap_start_fuel_l = car.get("fuel_l")
            self.lap_start_distance_km = car.get("distance_session_km")
        if previous and previous["car"].get("pit_lane") and not car.get("pit_lane"):
            self.out_lap_pending = True
        self.previous = snapshot
        return event


@dataclass
class StintTracker:
    active: bool = False
    start_monotonic_s: float | None = None
    start_fuel_l: float | None = None
    start_lap: int | None = None
    stint_id: str | None = None
    stint_number: int = 0
    completed_laps: int = 0
    current_stint_lap: int = 0
    identity: str | None = None
    previous: dict[str, Any] | None = None
    previous_stint: dict[str, Any] | None = None
    stint_history: list[dict[str, Any]] = field(default_factory=list)
    awaiting_boundary: bool = False
    end_reason: str | None = None

    def reset(self, reason: str | None = None) -> None:
        identity = self.identity
        self.__init__()
        self.identity = identity
        self.end_reason = reason

    def _archive_current(self, now_s: float, reason: str) -> None:
        if self.stint_number <= 0 or self.stint_id is None:
            return
        previous = {
            "stint_id": self.stint_id,
            "stint_number": self.stint_number,
            "identity_key": self.identity,
            "start_monotonic_s": self.start_monotonic_s,
            "end_monotonic_s": now_s,
            "start_lap": self.start_lap,
            "completed_laps": self.current_stint_lap,
            "end_reason": reason,
        }
        self.previous_stint = previous
        self.stint_history.append(previous)
        self.stint_history = self.stint_history[-4:]

    def _begin(self, snapshot: dict[str, Any], now_s: float, boundary_confirmed: bool) -> None:
        session = snapshot["session"]
        car = snapshot["car"]
        if boundary_confirmed:
            self._archive_current(now_s, "PIT_EXIT_CONFIRMED")
            self.stint_number += 1
        elif self.stint_number == 0:
            self.stint_number = 1
        self.stint_id = f"stint:{self.identity or 'unknown'}:{self.stint_number}"
        self.active = True
        self.awaiting_boundary = False
        self.start_monotonic_s = now_s
        self.start_fuel_l = car.get("fuel_l")
        self.start_lap = session.get("current_lap") or ((session.get("completed_laps") or 0) + 1)
        self.completed_laps = 0
        self.current_stint_lap = 0
        self.end_reason = None

    def update(self, snapshot: dict[str, Any], now_s: float, fuel_jump_l: float = 1.0, boundary_event: dict[str, Any] | None = None) -> None:
        key = identity_key(snapshot)
        session = snapshot["session"]
        car = snapshot["car"]
        if self.identity is not None and key != self.identity:
            self.__init__()
        self.identity = key
        previous = self.previous
        if previous and session.get("completed_laps") is not None and previous["session"].get("completed_laps") is not None and session["completed_laps"] < previous["session"]["completed_laps"]:
            self.reset("SESSION_RESTART"); self.identity = key
        if previous and previous["session"].get("replay") != session.get("replay"):
            self.reset("REPLAY_STATE_CHANGED"); self.identity = key
        on_track = not car.get("pit_lane") and not car.get("pit_box")
        if self.active and not on_track:
            self.active = False; self.awaiting_boundary = True; self.end_reason = "PIT_ENTRY"
        if not self.active and on_track and session.get("active", True) and not session.get("finished"):
            confirmed_exit = isinstance(boundary_event, dict) and boundary_event.get("event_type") == "PIT_EXIT_CONFIRMED"
            if self.stint_number == 0 or (self.awaiting_boundary and confirmed_exit):
                self._begin(snapshot, now_s, self.stint_number > 0 and confirmed_exit)
        if session.get("finished"):
            self.active = False; self.awaiting_boundary = False; self.end_reason = "SESSION_END"
        self.previous = snapshot

    def record_lap(self, event: dict[str, Any]) -> None:
        """Count a completed lap for stint progress, including out-laps."""
        if self.active and event.get("incomplete") is not True:
            self.current_stint_lap += 1
            self.completed_laps = self.current_stint_lap

    def elapsed(self, now_s: float) -> float | None:
        return max(0, now_s - self.start_monotonic_s) if self.active and self.start_monotonic_s is not None else None


def metric(value: float | None, unit: str, samples: int, reason: str, freshness_s: float | None = 0, confidence: str | None = None) -> dict[str, Any]:
    if confidence is None:
        confidence = "high" if samples >= 5 else ("medium" if samples >= 2 else "low")
    return {"value": value, "unit": unit, "sample_count": samples, "reason": reason, "freshness_s": freshness_s, "confidence_band": confidence}


def _difference(left: float | None, right: float | None) -> float | None:
    return left - right if isinstance(left, (int, float)) and isinstance(right, (int, float)) else None


def _flat_spot_percent(value: Any) -> float | None:
    return float(value) * 100 if isinstance(value, (int, float)) and 0 <= value <= 1 else None


def _cardinal(degrees: float | None) -> str | None:
    if not isinstance(degrees, (int, float)):
        return None
    return ("N", "NE", "E", "SE", "S", "SW", "W", "NW")[int((degrees % 360 + 22.5) // 45) % 8]


def _tyre_state(wheel: dict[str, Any]) -> str:
    if (_flat_spot_percent(wheel.get("flat_spot")) or -1) >= 10:
        return "FLAT_SPOTTED"
    if isinstance(wheel.get("wear"), (int, float)) and wheel["wear"] >= 0.7:
        return "WORN"
    core, optimum = wheel.get("core_c"), wheel.get("optimum_c")
    if not isinstance(core, (int, float)) or not isinstance(optimum, (int, float)):
        return "UNKNOWN"
    if core < optimum - 15:
        return "COLD"
    if core > optimum + 15:
        return "HOT"
    return "OPTIMAL"


def _wheel_cells(snapshot: dict[str, Any], samples: SampleStore, targets: dict[str, Any]) -> list[dict[str, Any]]:
    tyres = snapshot.get("tyres", {})
    source = tyres.get("wheels") or []
    labels = ("FL", "FR", "RL", "RR")
    result: list[dict[str, Any]] = []
    pressure_targets = targets.get("pressure_targets_psi") or {}
    compound = tyres.get("compound")
    selected_target = pressure_targets.get(compound) or pressure_targets.get("default") or pressure_targets
    temperature_targets = targets.get("temperature_targets_c") or {}
    selected_temperature = temperature_targets.get(compound) or temperature_targets.get("default") or temperature_targets
    for index, label in enumerate(labels, start=1):
        wheel = source[index - 1] if index - 1 < len(source) and isinstance(source[index - 1], dict) else {
            "label": label,
            "core_c": tyres.get("core_c"),
            "middle_c": tyres.get("surface_c"),
            "optimum_c": tyres.get("optimum_c"),
            "pressure_kpa": tyres.get("pressure_kpa"),
            "wear": tyres.get("wear"),
        }
        pressure_psi = wheel.get("pressure_psi")
        if pressure_psi is None and isinstance(wheel.get("pressure_kpa"), (int, float)):
            pressure_psi = wheel["pressure_kpa"] / 6.894757293
        target = selected_target.get(label) if isinstance(selected_target, dict) else selected_target if isinstance(selected_target, (int, float)) else None
        temperature_target = selected_temperature.get(label) if isinstance(selected_temperature, dict) else selected_temperature if isinstance(selected_temperature, (int, float)) else None
        result.append({
            "label": wheel.get("label", label),
            "core_c": wheel.get("core_c"),
            "temperature_target_c": temperature_target,
            "temperature_delta_c": _difference(wheel.get("core_c"), temperature_target),
            "lap_min_c": samples.tyre_lap_min_c.get(index),
            "lap_max_c": samples.tyre_lap_max_c.get(index),
            "pressure_psi": pressure_psi,
            "pressure_target_psi": target,
            "pressure_delta_psi": _difference(pressure_psi, target),
            "pressure_kpa": wheel.get("pressure_kpa") if isinstance(wheel.get("pressure_kpa"), (int, float)) else pressure_psi * 6.894757293 if isinstance(pressure_psi, (int, float)) else None,
            "pressure_target_kpa": target * 6.894757293 if isinstance(target, (int, float)) else None,
            "pressure_delta_kpa": _difference(wheel.get("pressure_kpa") if isinstance(wheel.get("pressure_kpa"), (int, float)) else pressure_psi * 6.894757293 if isinstance(pressure_psi, (int, float)) else None, target * 6.894757293 if isinstance(target, (int, float)) else None),
            "wear": wheel.get("wear"),
            "wear_percent": wheel["wear"] * 100 if isinstance(wheel.get("wear"), (int, float)) and 0 <= wheel["wear"] <= 1 else None,
            "life": (1 - wheel["wear"]) * 100 if isinstance(wheel.get("wear"), (int, float)) and 0 <= wheel["wear"] <= 1 else None,
            "grain": None,
            "blister": None,
            "flat_spot": _flat_spot_percent(wheel.get("flat_spot")),
            "damage_reasons": {"grain": "UNSUPPORTED", "blister": "UNSUPPORTED", "flat_spot": "CSP_REFERENCE_0_TO_1"},
            "state": _tyre_state(wheel),
        })
    return result


def calculate(
    snapshot: dict[str, Any],
    stint: StintTracker,
    samples: SampleStore,
    calibration: dict[str, Any] | None,
    now_s: float,
    targets: dict[str, Any] | None = None,
) -> dict[str, Any]:
    targets = targets or {}
    car, session = snapshot["car"], snapshot["session"]
    fuel_mean = mean(samples.fuel_samples) if samples.fuel_samples else None
    pace_mean = mean(samples.pace_samples) if samples.pace_samples else None
    latest_valid_fuel = samples.latest_valid_fuel_l
    latest_valid_pace = samples.latest_valid_pace_s
    latest_completed = samples.latest_completed or {}
    target_fuel = targets.get("fuel_per_lap_l")
    target_pace = targets.get("pace_s")
    length_m = (calibration or {}).get("track_length_m") or session.get("track_length_m")
    lap_km = length_m / 1000 if length_m else None
    fuel_per_km = fuel_mean / lap_km if fuel_mean and lap_km else None
    fuel_per_min = fuel_mean / pace_mean * 60 if fuel_mean and pace_mean else None
    distance, pit_reason = forward_distance(car.get("spline"), (calibration or {}).get("pit_entry_spline"), (calibration or {}).get("track_length_m"))
    route_known = isinstance(calibration, dict) and isinstance(calibration.get("pit_route_additional_m"), (int, float))
    fuel_at_pit = None
    observed_age = snapshot.get("observed_monotonic_s")
    age_s = max(0.0, now_s - observed_age) if isinstance(observed_age, (int, float)) else None
    fresh_enough = age_s is None or age_s <= 2.0
    if car.get("fuel_l") is not None and fuel_per_km is not None and distance is not None and route_known and fresh_enough:
        fuel_at_pit = car["fuel_l"] - fuel_per_km * (distance + calibration["pit_route_additional_m"]) / 1000
    elif distance is not None and not route_known:
        pit_reason = "PIT_ROUTE_NOT_CONFIGURED"
    elif distance is not None and route_known and not fresh_enough:
        pit_reason = "STALE_TELEMETRY"
    fuel_used = stint.start_fuel_l - car["fuel_l"] if stint.start_fuel_l is not None and car.get("fuel_l") is not None and car["fuel_l"] <= stint.start_fuel_l else None
    fuel_laps = car["fuel_l"] / fuel_mean if car.get("fuel_l") is not None and fuel_mean else None
    fuel_time = car["fuel_l"] / fuel_per_min * 60 if car.get("fuel_l") is not None and fuel_per_min else None
    pace_delta_target = _difference(latest_valid_pace, target_pace)
    pace_delta_average = _difference(latest_valid_pace, pace_mean)
    fuel_delta_target = _difference(latest_valid_fuel, target_fuel)
    fuel_delta_average = _difference(latest_valid_fuel, fuel_mean)
    return {
        "fuel": {
            "current": metric(car.get("fuel_l"), " L", 1, "MEASURED_CURRENT"),
            "used": metric(fuel_used, " L", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_used is not None else "INSUFFICIENT_SAMPLES"),
            "target_per_lap": metric(target_fuel, " L/lap", len(samples.fuel_samples), "USER_CONFIG" if target_fuel is not None else "TARGET_NOT_CONFIGURED"),
            "per_lap": metric(fuel_mean, " L/lap", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_mean is not None else "INSUFFICIENT_SAMPLES"),
            "latest_valid": metric(latest_valid_fuel, " L/lap", len(samples.fuel_samples), "MEASURED_CURRENT" if latest_valid_fuel is not None else "INSUFFICIENT_SAMPLES"),
            "latest_completed": metric(latest_completed.get("fuel_used_l"), " L/lap", len(samples.fuel_samples), "MEASURED_CURRENT" if latest_completed.get("accepted") else latest_completed.get("reason", "INSUFFICIENT_SAMPLES")),
            "per_km": metric(fuel_per_km, " L/km", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_per_km is not None else "INSUFFICIENT_SAMPLES"),
            "per_min": metric(fuel_per_min, " L/min", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_per_min is not None else "INSUFFICIENT_SAMPLES"),
            "laps": metric(fuel_laps, " laps", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_laps is not None else "INSUFFICIENT_SAMPLES"),
            "time": metric(fuel_time, " s", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_time is not None else "INSUFFICIENT_SAMPLES"),
            "at_pit": metric(fuel_at_pit, " L", len(samples.fuel_samples), pit_reason),
            "delta_target": metric(fuel_delta_target, " L/lap", len(samples.fuel_samples), "USER_CONFIG" if fuel_delta_target is not None else "TARGET_NOT_CONFIGURED"),
            "delta_average": metric(fuel_delta_average, " L/lap", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_delta_average is not None else "INSUFFICIENT_SAMPLES"),
            "average_vs_target": metric(_difference(fuel_mean, target_fuel), " L/lap", len(samples.fuel_samples), "USER_CONFIG" if fuel_mean is not None and target_fuel is not None else "TARGET_NOT_CONFIGURED"),
        },
        "pace": {
            "current": metric(car.get("lap_time_s"), " s", 1, "MEASURED_CURRENT"),
            "target": metric(target_pace, " s", len(samples.pace_samples), "USER_CONFIG" if target_pace is not None else "TARGET_NOT_CONFIGURED"),
            "latest_valid": metric(latest_valid_pace, " s", len(samples.pace_samples), "MEASURED_CURRENT" if latest_valid_pace is not None else "INSUFFICIENT_SAMPLES"),
            "latest_completed": metric(latest_completed.get("lap_time_s"), " s", len(samples.pace_samples), "MEASURED_CURRENT" if latest_completed.get("accepted") else latest_completed.get("reason", "INSUFFICIENT_SAMPLES")),
            "rolling": metric(pace_mean, " s", len(samples.pace_samples), "MEASURED_CURRENT" if pace_mean is not None else "INSUFFICIENT_SAMPLES"),
            "delta_to_target": metric(pace_delta_target, " s", len(samples.pace_samples), "USER_CONFIG" if pace_delta_target is not None else "TARGET_NOT_CONFIGURED"),
            "delta_to_average": metric(pace_delta_average, " s", len(samples.pace_samples), "MEASURED_CURRENT" if pace_delta_average is not None else "INSUFFICIENT_SAMPLES"),
            "average_vs_target": metric(_difference(pace_mean, target_pace), " s", len(samples.pace_samples), "USER_CONFIG" if pace_mean is not None and target_pace is not None else "TARGET_NOT_CONFIGURED"),
        },
        "tyres": {"wheels": _wheel_cells(snapshot, samples, targets)},
        "pit": {"distance": metric(distance, " m", 1, pit_reason)},
        "stint": {
            "stint_id": stint.stint_id,
            "stint_number": metric(stint.stint_number, "", 0, "MEASURED_CURRENT" if stint.stint_number else "SOURCE_UNAVAILABLE"),
            "current_stint_lap": metric(stint.current_stint_lap, " lap", stint.current_stint_lap, "MEASURED_CURRENT"),
            "race_lap": metric(session.get("race_lap", session.get("completed_laps")), " lap", 1, "AC_COMPLETED_LAP_COUNT" if session.get("race_lap", session.get("completed_laps")) is not None else "SOURCE_UNAVAILABLE"),
            "current_lap": metric(session.get("current_lap"), " lap", 1, "AC_CURRENT_LAP_IN_PROGRESS" if session.get("current_lap") is not None else "SOURCE_UNAVAILABLE"),
            "previous_stint": stint.previous_stint,
            "stint_history": list(stint.stint_history),
        },
        "stint_elapsed_s": stint.elapsed(now_s),
        "latest_excluded": samples.latest_excluded,
        "configuration": {
            "target_pace_s": target_pace,
            "target_fuel_per_lap_l": target_fuel,
            "target_stint_minutes": targets.get("stint_minutes"),
            "planned_pit_lap": targets.get("planned_pit_lap"),
            "pressure_unit": targets.get("pressure_unit", "psi"),
            "pressure_targets_psi": targets.get("pressure_targets_psi", {}),
            "pace_delta_threshold_s": targets.get("pace_delta_threshold_s", 0.50),
            "fuel_comparison_threshold_l": targets.get("fuel_comparison_threshold_l", 0.05),
            "pressure_delta_threshold_psi": targets.get("pressure_delta_threshold_psi", 0.50),
            "temperature_delta_threshold_c": targets.get("temperature_delta_threshold_c", 15),
            "temperature_targets_c": targets.get("temperature_targets_c", {}),
            "strategy_profile": targets.get("strategy_profile"),
            "endurance_rules": targets.get("endurance_rules", {}),
        },
    }


def visible_projection(snapshot: dict[str, Any], calculated: dict[str, Any]) -> tuple[str, ...]:
    """A stable host assertion that visible values are data-bound."""
    return (f"fuel={calculated['fuel']['current']['value']}", f"speed={snapshot['car'].get('speed_kmh')}", f"lap={snapshot['session'].get('current_lap')}", f"pace={calculated['pace']['current']['value']}", f"weather={snapshot['environment'].get('weather_type')}")


def weather_trend(history: list[dict[str, Any]]) -> str:
    if len(history) < 3:
        return "UNKNOWN"
    first = history[0].get("track_wetness")
    last = history[-1].get("track_wetness")
    if not isinstance(first, (int, float)) or not isinstance(last, (int, float)):
        return "UNKNOWN"
    if last - first > 0.03:
        return "WETTING"
    if last - first < -0.03:
        return "DRYING"
    return "STABLE"


def future_weather() -> dict[str, Any]:
    return {"label": "UNKNOWN", "text": "No reliable future forecast", "probability": None, "eta_s": None}


def layout_boxes(width: float, height: float, mode: str) -> dict[str, tuple[float, float, float, float]]:
    margin = 8
    gap = 6
    outer_h = max(1.0, height - 12.0)
    header_h = 32.0 if mode == "garage" else max(28.0, min(34.0, height * 0.09))
    outer_w = max(1.0, width - margin * 2)
    header = (margin, 6.0, outer_w, header_h)
    content = (0.0, 0.0, width, height)
    if mode == "compact":
        footer_h = max(42.0, min(54.0, height * 0.13))
        body_y = 6.0 + header_h + gap
        footer_y = 6.0 + outer_h - footer_h
        body_h = max(1.0, footer_y - gap - body_y)
        large = width >= 850
        primary_h = max(76.0, min(128.0, body_h * 0.50)) if large else max(62.0, min(112.0, body_h * 0.32))
        pit_h = primary_h if large else max(50.0, min(78.0, body_h * 0.23))
        secondary_h = body_h - primary_h - (gap if large else gap * 2) - (0 if large else pit_h)
        primary_w = (outer_w - gap * 2) / 3 if large else (outer_w - gap) / 2
        secondary_w = (outer_w - gap) / 2
        secondary_y = body_y + primary_h + gap if large else body_y + primary_h + gap + pit_h + gap
        return {
            "content": content,
            "header": header,
            "timing": header,
            "fuel": (margin, body_y, primary_w, primary_h),
            "pace": (margin + primary_w + gap, body_y, primary_w, primary_h),
            "pit": (margin + (primary_w + gap) * 2, body_y, primary_w, primary_h) if large else (margin, body_y + primary_h + gap, outer_w, pit_h),
            "tyres": (margin, secondary_y, secondary_w, secondary_h),
            "weather": (margin + secondary_w + gap, secondary_y, secondary_w, secondary_h),
            "engineer": (margin, footer_y, outer_w, footer_h),
        }
    if mode == "expanded":
        body_y = 6.0 + header_h + gap
        body_h = max(1.0, 6.0 + outer_h - body_y)
        main_w = outer_w
        left_w = main_w * 0.43
        right_x = margin + left_w + gap
        right_w = main_w - left_w - gap
        row_h = max(24.0, (body_h - gap * 4) / 5)
        left_card_h = max(24.0, (body_h - gap * 2) / 3)
        return {
            "content": content,
            "header": header,
            "timing": (right_x, body_y, right_w, row_h),
            "message": (right_x, body_y + row_h + gap, right_w, row_h),
            "tyres": (right_x, body_y + (row_h + gap) * 2, right_w, row_h),
            "weather": (right_x, body_y + (row_h + gap) * 3, right_w, row_h),
            "connections": (right_x, body_y + (row_h + gap) * 4, right_w, row_h),
            "fuel": (margin, body_y, left_w, left_card_h),
            "pace": (margin, body_y + left_card_h + gap, left_w, left_card_h),
            "pit": (margin, body_y + (left_card_h + gap) * 2, left_w, left_card_h),
        }
    body_y = 6.0 + header_h + gap
    overview_h = 50.0
    controls_y = body_y + overview_h + gap
    controls_h = min(160.0, max(86.0, 6.0 + outer_h - controls_y - gap - 1.0))
    diagnostics_y = controls_y + controls_h + gap
    diagnostics_h = max(1.0, 6.0 + outer_h - diagnostics_y)
    main_w = outer_w
    return {
        "content": content,
        "header": header,
        "overview": (margin, body_y, main_w, overview_h),
        "scenarios": (margin, controls_y, main_w * 0.58, controls_h),
        "settings": (margin + main_w * 0.58 + gap, controls_y, main_w * 0.42 - gap, controls_h),
        "diagnostics": (margin, diagnostics_y, main_w, diagnostics_h),
    }


def layout_valid(boxes: dict[str, tuple[float, float, float, float]], width: float, height: float, mode: str) -> bool:
    values = list(boxes.items())
    for name, (x, y, box_width, box_height) in values:
        if name in {"header", "content"}:
            continue
        if x < 0 or y < 0 or x + box_width > width + 0.5 or (mode != "garage" and y + box_height > height + 0.5):
            return False
    for index, (_, left) in enumerate(values):
        if values[index][0] in {"header", "content"}:
            continue
        lx, ly, lw, lh = left
        for other_name, right in values[index + 1 :]:
            if other_name in {"header", "content"}:
                continue
            rx, ry, rw, rh = right
            if lx < rx + rw and rx < lx + lw and ly < ry + rh and ry < ly + lh:
                return False
    return True
