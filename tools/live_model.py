"""Host oracle for the bounded Lua live slice.

The real runtime implementation is Lua. This small, dependency-free oracle
keeps the same normalized field names and equations available to Python tests
when no Lua interpreter is installed on the validation host.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from statistics import mean, pstdev
from typing import Any


def normalize_csp(raw: dict[str, Any], now_s: float, source_mode: str = "live") -> dict[str, Any]:
    def section(name: str) -> dict[str, Any]:
        value = raw.get(name, {})
        return value if isinstance(value, dict) else {}

    identity = section("identity")
    session = section("session")
    car = section("car")
    tyres = section("tyres")
    environment = section("environment")
    return {
        "source_mode": source_mode,
        "observed_monotonic_s": now_s,
        "identity": {key: identity.get(key) for key in ("car_id", "track_id", "layout_id", "driver_name", "session_id", "configuration_id")},
        "session": {key: session.get(key) for key in ("type", "elapsed_s", "remaining_s", "lap_limit", "completed_laps", "current_lap", "position", "total_cars", "track_length_m", "paused", "replay", "active", "finished")},
        "car": {key: car.get(key) for key in ("speed_kmh", "fuel_l", "fuel_capacity_l", "spline", "distance_session_km", "pit_lane", "pit_box", "lap_time_s", "previous_lap_time_s", "best_lap_time_s", "lap_valid", "previous_lap_valid", "last_lap_cuts", "reset_counter")},
        "tyres": {key: tyres.get(key) for key in ("compound", "core_c", "surface_c", "wear", "pressure_kpa", "optimum_c")},
        "environment": {key: environment.get(key) for key in ("ambient_c", "road_c", "wind_kmh", "weather_type", "rain_intensity", "track_wetness", "standing_water", "grip")},
    }


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
    fuel_samples: list[float] = field(default_factory=list)
    pace_samples: list[float] = field(default_factory=list)

    def add_lap(self, lap: dict[str, Any]) -> bool:
        if not lap.get("accepted"):
            return False
        self.laps.append(lap)
        if isinstance(lap.get("fuel_used_l"), (int, float)) and lap["fuel_used_l"] > 0:
            self.fuel_samples.append(float(lap["fuel_used_l"]))
        if isinstance(lap.get("lap_time_s"), (int, float)) and lap["lap_time_s"] > 0:
            self.pace_samples.append(float(lap["lap_time_s"]))
        self.laps = self.laps[-self.max_count :]
        self.fuel_samples = self.fuel_samples[-self.max_count :]
        self.pace_samples = self.pace_samples[-self.max_count :]
        return True


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
            event = {"lap_number": previous_count, "lap_time_s": car.get("previous_lap_time_s"), "fuel_used_l": fuel_used, "distance_km": distance, "accepted": reason is None, "reason": reason, "regime": reason or "green_valid"}
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
    completed_laps: int = 0
    identity: str | None = None
    previous: dict[str, Any] | None = None
    end_reason: str | None = None

    def update(self, snapshot: dict[str, Any], now_s: float, fuel_jump_l: float = 1.0) -> None:
        key = identity_key(snapshot)
        session = snapshot["session"]
        car = snapshot["car"]
        if self.identity is not None and key != self.identity:
            self.__init__()
        self.identity = key
        previous = self.previous
        if previous and session.get("completed_laps") is not None and previous["session"].get("completed_laps") is not None and session["completed_laps"] < previous["session"]["completed_laps"]:
            self.__init__(); self.identity = key
        if previous and previous["session"].get("replay") != session.get("replay"):
            self.__init__(); self.identity = key
        if previous and isinstance(previous["car"].get("fuel_l"), (int, float)) and isinstance(car.get("fuel_l"), (int, float)) and car["fuel_l"] - previous["car"]["fuel_l"] > fuel_jump_l and not car.get("pit_lane"):
            self.__init__(); self.identity = key
        on_track = not car.get("pit_lane") and not car.get("pit_box")
        if self.active and not on_track:
            self.active = False; self.end_reason = "PIT_ENTRY"
        if not self.active and on_track and session.get("active", True) and not session.get("finished"):
            self.active = True
            self.start_monotonic_s = now_s
            self.start_fuel_l = car.get("fuel_l")
            self.completed_laps = 0
            self.end_reason = None
        if session.get("finished"):
            self.active = False; self.end_reason = "SESSION_END"
        self.previous = snapshot

    def elapsed(self, now_s: float) -> float | None:
        return max(0, now_s - self.start_monotonic_s) if self.active and self.start_monotonic_s is not None else None


def metric(value: float | None, unit: str, samples: int, reason: str, freshness_s: float | None = 0, confidence: str | None = None) -> dict[str, Any]:
    if confidence is None:
        confidence = "high" if samples >= 5 else ("medium" if samples >= 2 else "low")
    return {"value": value, "unit": unit, "sample_count": samples, "reason": reason, "freshness_s": freshness_s, "confidence_band": confidence}


def calculate(snapshot: dict[str, Any], stint: StintTracker, samples: SampleStore, calibration: dict[str, Any] | None, now_s: float) -> dict[str, Any]:
    car, session = snapshot["car"], snapshot["session"]
    fuel_mean = mean(samples.fuel_samples) if samples.fuel_samples else None
    pace_mean = mean(samples.pace_samples) if samples.pace_samples else None
    length_m = (calibration or {}).get("track_length_m") or session.get("track_length_m")
    lap_km = length_m / 1000 if length_m else None
    fuel_per_km = fuel_mean / lap_km if fuel_mean and lap_km else None
    fuel_per_min = fuel_mean / pace_mean * 60 if fuel_mean and pace_mean else None
    distance, pit_reason = forward_distance(car.get("spline"), (calibration or {}).get("pit_entry_spline"), (calibration or {}).get("track_length_m"))
    fuel_at_pit = None
    if car.get("fuel_l") is not None and fuel_per_km is not None and distance is not None:
        fuel_at_pit = car["fuel_l"] - fuel_per_km * (distance + (calibration or {}).get("pit_route_additional_m", 0)) / 1000
    fuel_used = stint.start_fuel_l - car["fuel_l"] if stint.start_fuel_l is not None and car.get("fuel_l") is not None and car["fuel_l"] <= stint.start_fuel_l else None
    fuel_laps = car["fuel_l"] / fuel_mean if car.get("fuel_l") is not None and fuel_mean else None
    fuel_time = car["fuel_l"] / fuel_per_min * 60 if car.get("fuel_l") is not None and fuel_per_min else None
    return {
        "fuel": {"current": metric(car.get("fuel_l"), " L", 1, "MEASURED_CURRENT"), "used": metric(fuel_used, " L", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_used is not None else "INSUFFICIENT_SAMPLES"), "per_lap": metric(fuel_mean, " L/lap", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_mean is not None else "INSUFFICIENT_SAMPLES"), "per_km": metric(fuel_per_km, " L/km", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_per_km is not None else "INSUFFICIENT_SAMPLES"), "per_min": metric(fuel_per_min, " L/min", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_per_min is not None else "INSUFFICIENT_SAMPLES"), "laps": metric(fuel_laps, " laps", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_laps is not None else "INSUFFICIENT_SAMPLES"), "time": metric(fuel_time, " s", len(samples.fuel_samples), "MEASURED_CURRENT" if fuel_time is not None else "INSUFFICIENT_SAMPLES"), "at_pit": metric(fuel_at_pit, " L", len(samples.fuel_samples), pit_reason)},
        "pace": {"current": metric(car.get("lap_time_s"), " s", 1, "MEASURED_CURRENT"), "rolling": metric(pace_mean, " s", len(samples.pace_samples), "MEASURED_CURRENT" if pace_mean is not None else "INSUFFICIENT_SAMPLES")},
        "pit": {"distance": metric(distance, " m", 1, pit_reason)},
        "stint_elapsed_s": stint.elapsed(now_s),
    }


def visible_projection(snapshot: dict[str, Any], calculated: dict[str, Any]) -> tuple[str, ...]:
    """A stable host assertion that visible values are data-bound."""
    return (f"fuel={calculated['fuel']['current']['value']}", f"lap={snapshot['session'].get('current_lap')}", f"pace={calculated['pace']['current']['value']}", f"weather={snapshot['environment'].get('weather_type')}")


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
    margin = 14 if mode == "garage" else 10
    gap = 10 if mode == "garage" else 8
    header_h = 42 if mode == "garage" else max(32, min(40, height * 0.14))
    header = (margin, margin, width - margin * 2, header_h)
    if mode == "compact":
        timing_y = margin + header_h + gap
        timing_h = max(42, min(58, height * 0.19))
        primary_y = timing_y + timing_h + gap
        primary_h = max(72, min(94, height * 0.31))
        support_y = primary_y + primary_h + gap
        support_h = max(32, height - support_y - margin)
        main_w = width - margin * 2
        fuel_w = max(250, main_w * 0.58)
        return {"header": header, "timing": (margin, timing_y, main_w, timing_h), "fuel": (margin, primary_y, fuel_w - gap / 2, primary_h), "pace": (margin + fuel_w + gap / 2, primary_y, main_w - fuel_w - gap / 2, primary_h), "weather": (margin, support_y, main_w * 0.57, support_h), "engineer": (margin + main_w * 0.57 + gap, support_y, main_w * 0.43 - gap, support_h)}
    if mode == "expanded":
        body_y = margin + header_h + gap
        main_w = width - margin * 2
        left_w = main_w * 0.43
        right_x = margin + left_w + gap
        right_w = main_w - left_w - gap
        row_h = (height - body_y - margin - gap * 3) / 4
        return {"header": header, "fuel": (margin, body_y, left_w, row_h * 2 + gap), "pit": (margin, body_y + row_h * 2 + gap * 2, left_w, row_h * 2 + gap), "timing": (right_x, body_y, right_w, row_h), "pace": (right_x, body_y + row_h + gap, right_w, row_h), "tyres": (right_x, body_y + (row_h + gap) * 2, right_w, row_h), "weather": (right_x, body_y + (row_h + gap) * 3, right_w, row_h)}
    return {"header": header, "diagnostics": (margin, margin + header_h + gap, width - margin * 2, height * 4)}


def layout_valid(boxes: dict[str, tuple[float, float, float, float]], width: float, height: float, mode: str) -> bool:
    values = list(boxes.items())
    for name, (x, y, box_width, box_height) in values:
        if name == "header":
            continue
        if x < 0 or y < 0 or x + box_width > width + 0.5 or (mode != "garage" and y + box_height > height + 0.5):
            return False
    for index, (_, left) in enumerate(values):
        if values[index][0] == "header":
            continue
        lx, ly, lw, lh = left
        for other_name, right in values[index + 1 :]:
            if other_name == "header":
                continue
            rx, ry, rw, rh = right
            if lx < rx + rw and rx < lx + lw and ly < ry + rh and ry < ly + lh:
                return False
    return True
