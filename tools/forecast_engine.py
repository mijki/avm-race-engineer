"""Deterministic race, fuel, stint, and pit forecasts.

The forecast engine consumes the immutable outputs of the telemetry, event,
eligibility, stint, and pit-learning layers.  It never reads runtime APIs and
never turns a missing measurement into a zero.  Forecast records retain the
selected model, source references, freshness, confidence, uncertainty, and a
specific unavailable reason when a prediction is not defensible.
"""

from __future__ import annotations

import copy
import json
import math
from dataclasses import dataclass, field
from statistics import median
from typing import Any, Iterable, Mapping, Sequence

from tools.pit_learning import forward_distance
from tools.race_engine_core import forecast as forecast_envelope
from tools.race_engine_core import to_plain


FORECAST_VERSION = "race-pit-forecast-v1"
MODEL_ID = "race-pit-forecast"
MODEL_VERSION = "race-pit-forecast-v1"


def _copy(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {key: _copy(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [_copy(child) for child in value]
    return copy.deepcopy(value)


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(float(value)) else None


def _first(mapping: Mapping[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in mapping:
            return mapping[key]
    return None


def _token(value: Any) -> str:
    return str(value or "").strip().upper().replace("-", "_").replace(" ", "_")


def _value(metric: Any) -> float | None:
    return _number(_mapping(metric).get("value"))


def _metric_reason(metric: Any, default: str) -> str:
    return str(_mapping(metric).get("unavailable_reason") or default)


def _snapshot_value(snapshot: Mapping[str, Any] | None, *keys: str) -> Any:
    snapshot = snapshot or {}
    value = _first(snapshot, *keys)
    if value is not None:
        return value
    for section_name in ("session", "car", "track", "environment"):
        value = _first(_mapping(snapshot.get(section_name)), *keys)
        if value is not None:
            return value
    return None


def _identity(snapshot: Mapping[str, Any] | None, calculation: Mapping[str, Any]) -> str:
    identity = _mapping((snapshot or {}).get("identity"))
    if identity:
        return "|".join(str(identity.get(key) or "") for key in ("car_id", "track_id", "layout_id", "session_id", "configuration_id"))
    progress = _mapping(calculation.get("progress"))
    stint_id = progress.get("current_stint_id")
    return str(stint_id or "identity:unknown")


def _sample_refs(metric: Mapping[str, Any] | None) -> list[str]:
    refs = _mapping(metric).get("accepted_samples", [])
    return [str(item) for item in refs if item is not None]


def _confidence_value(metric: Mapping[str, Any] | None) -> str:
    value = str(_mapping(metric).get("confidence") or "UNAVAILABLE").upper()
    return value if value in {"HIGH", "MEDIUM", "LOW", "UNAVAILABLE"} else "LOW"


def _confidence_score(band: str) -> float:
    return {"HIGH": 0.90, "MEDIUM": 0.65, "LOW": 0.35, "UNAVAILABLE": 0.0}.get(band, 0.0)


def _freshness(metrics: Sequence[Mapping[str, Any] | None]) -> float | None:
    ages = [_number(_mapping(metric).get("freshness_s")) for metric in metrics if metric]
    ages = [age for age in ages if age is not None]
    return max(ages) if ages else None


def _selected_metric(calculation: Mapping[str, Any], section: str, names: Sequence[str]) -> tuple[Mapping[str, Any] | None, str | None]:
    values = _mapping(calculation.get(section))
    for name in names:
        metric = _mapping(values.get(name))
        if _value(metric) is not None:
            return metric, name
    return None, None


def _range_from_metric(metric: Mapping[str, Any] | None, value: float | None, unit: str) -> dict[str, Any] | None:
    if value is None:
        return None
    uncertainty = _mapping(_mapping(metric).get("uncertainty"))
    raw_range = uncertainty.get("range") or uncertainty.get("observed_range")
    if isinstance(raw_range, Mapping):
        lower = _number(_first(raw_range, "lower_bound", "lower"))
        upper = _number(_first(raw_range, "upper_bound", "upper"))
        if lower is not None and upper is not None and upper >= lower:
            return {"lower_bound": lower, "upper_bound": upper, "unit": unit}
    return None


def _uncertainty(value: float | None, unit: str, sources: Sequence[Mapping[str, Any] | None]) -> dict[str, Any]:
    ranges = [_range_from_metric(source, _value(source), unit) for source in sources if source]
    ranges = [item for item in ranges if item is not None]
    if ranges:
        return {"range": {"lower_bound": min(item["lower_bound"] for item in ranges), "upper_bound": max(item["upper_bound"] for item in ranges), "unit": unit}, "reason_codes": ["OBSERVED_SAMPLE_RANGE"]}
    return {"range": None, "reason_codes": ["RANGE_UNAVAILABLE"]}


def _record(
    forecast_id: str,
    *,
    value: Any,
    unit: str,
    generated_at_s: float | None,
    target_at_s: float | None = None,
    measured_inputs: Sequence[str] = (),
    calculated_inputs: Sequence[str] = (),
    samples: Sequence[str] = (),
    regime: str | None = None,
    freshness_s: float | None = None,
    confidence: str = "UNAVAILABLE",
    uncertainty: Mapping[str, Any] | None = None,
    binding_constraint: str | None = None,
    unavailable_reason: str | None = None,
    supersedes: str | None = None,
) -> dict[str, Any]:
    result = forecast_envelope(
        forecast_id=forecast_id,
        model_id=MODEL_ID,
        model_version=MODEL_VERSION,
        generated_at_s=generated_at_s,
        target_at_s=target_at_s,
        value=value,
        unit=unit,
        measured_inputs=list(measured_inputs),
        calculated_inputs=list(calculated_inputs),
        samples=list(samples),
        regime=regime,
        freshness_s=freshness_s,
        confidence=confidence,
        uncertainty=_copy(uncertainty or {"range": None, "reason_codes": ["RANGE_UNAVAILABLE"]}),
        binding_constraint=binding_constraint,
        unavailable_reason=unavailable_reason,
        supersedes=supersedes,
    )
    result["sample_count"] = len(samples)
    result["source_layer"] = "forecast"
    return result


def _unavailable(
    forecast_id: str,
    *,
    unit: str,
    generated_at_s: float | None,
    reason: str,
    measured_inputs: Sequence[str] = (),
    calculated_inputs: Sequence[str] = (),
    samples: Sequence[str] = (),
    regime: str | None = None,
    freshness_s: float | None = None,
    supersedes: str | None = None,
) -> dict[str, Any]:
    return _record(
        forecast_id,
        value=None,
        unit=unit,
        generated_at_s=generated_at_s,
        measured_inputs=measured_inputs,
        calculated_inputs=calculated_inputs,
        samples=samples,
        regime=regime,
        freshness_s=freshness_s,
        confidence="UNAVAILABLE",
        unavailable_reason=reason,
        supersedes=supersedes,
    )


def _identity_fields(snapshot: Mapping[str, Any] | None) -> dict[str, Any]:
    identity = _mapping((snapshot or {}).get("identity"))
    return {
        "session_id": str(identity.get("session_id") or "session:unknown"),
        "car_id": str(identity.get("car_id") or "car:unknown"),
        "driver_id": identity.get("driver_id"),
        "track_id": str(identity.get("track_id") or "track:unknown"),
        "layout_id": identity.get("layout_id"),
    }


def _event_token(event: Mapping[str, Any]) -> str:
    return _token(event.get("event_type", event.get("type")))


def _invalidation_reasons(events: Iterable[Mapping[str, Any]], previous: Mapping[str, Any] | None, strategy_revision: str | None, target_key: str | None) -> list[str]:
    reasons: list[str] = []
    for event in events:
        token = _event_token(event)
        if token in {"RESET", "TELEPORT", "IDENTITY_CHANGED", "SESSION_RESTART", "REPLAY_TRANSITION"}:
            reasons.append(token)
        elif token == "LAP_COMPLETED":
            reasons.append("NEW_COMPLETED_LAP")
        elif token in {"PIT_ENTRY_CANDIDATE", "PIT_ENTRY_CONFIRMED", "REFUEL", "PIT_EXIT_CONFIRMED", "PIT_SERVICE_STOP_CONFIRMED", "MANUAL_NEW_STINT_CONFIRMED"}:
            reasons.append("PIT_STATE_CHANGED")
        elif token in {"PIT_MARKER_UPDATED", "MARKER_UPDATED"}:
            reasons.append("MARKER_UPDATED")
    previous_strategy = _mapping(previous).get("strategy_revision") if previous else None
    if previous_strategy is not None and strategy_revision is not None and previous_strategy != strategy_revision:
        reasons.append("STRATEGY_CHANGED")
    previous_target = _mapping(previous).get("target_key") if previous else None
    if previous_target is not None and target_key is not None and previous_target != target_key:
        reasons.append("TARGET_CHANGED")
    return list(dict.fromkeys(reasons))


def _pit_marker(pit_diagnostics: Mapping[str, Any], config: "ForecastConfig") -> Mapping[str, Any]:
    marker = pit_diagnostics.get("marker")
    if isinstance(marker, Mapping):
        return marker
    if isinstance(config.pit_marker, Mapping):
        return config.pit_marker
    return {}


def _normal_stop_visits(marker: Mapping[str, Any], pit_diagnostics: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    values: list[Mapping[str, Any]] = []
    timing = _mapping(marker.get("timing"))
    for key in ("normal_stops", "observations", "timing_observations"):
        candidate = timing.get(key)
        if isinstance(candidate, (list, tuple)):
            values.extend(item for item in candidate if isinstance(item, Mapping) and _token(item.get("classification", item.get("kind"))) in {"NORMAL_STOP", "NORMAL"})
    visits = pit_diagnostics.get("normal_stops")
    if isinstance(visits, (list, tuple)):
        values.extend(item for item in visits if isinstance(item, Mapping))
    last_visit = pit_diagnostics.get("last_visit")
    if isinstance(last_visit, Mapping) and _token(last_visit.get("classification")) == "NORMAL_STOP":
        values.append(last_visit)
    return values


def _median_field(values: Sequence[Mapping[str, Any]], *keys: str) -> float | None:
    numbers = [_number(_first(value, *keys)) for value in values]
    numbers = [number for number in numbers if number is not None]
    return float(median(numbers)) if numbers else None


@dataclass(frozen=True)
class ForecastConfig:
    """Explicit strategy and session inputs for the forecast engine."""

    session_type: str = "UNKNOWN"
    race_lap_limit: float | None = None
    session_remaining_s: float | None = None
    stint_lap_limit: float | None = None
    stint_time_limit_s: float | None = None
    driver_rule_laps: float | None = None
    tyre_rule_laps: float | None = None
    planned_stint_laps: float | None = None
    planned_stint_time_s: float | None = None
    planned_pit_lap: float | None = None
    planned_pit_time_s: float | None = None
    pit_window_open_lap: float | None = None
    pit_window_close_lap: float | None = None
    reserve_fuel_l: float = 0.0
    tank_capacity_l: float | None = None
    target_fuel_l: float | None = None
    target_fuel_at_pit_l: float | None = None
    target_finish_fuel_l: float | None = None
    pace_target_s: float | None = None
    fuel_target_l: float | None = None
    track_length_m: float | None = None
    pit_route_additional_m: float = 0.0
    pit_marker: Mapping[str, Any] | None = None
    pit_loss_s: float | None = None
    planned_service_duration_s: float | None = None
    strategy_id: str = "strategy:local"
    strategy_revision: str = "revision:local"
    baseline_strategy_revision: str = "revision:local"
    now_s: float | None = None
    stale_after_s: float = 180.0
    future_weather: Mapping[str, Any] | None = None
    explicit_regime: str | None = None
    target_key: str | None = None
    extra: Mapping[str, Any] = field(default_factory=dict)

    @classmethod
    def from_value(cls, value: "ForecastConfig | Mapping[str, Any] | None") -> "ForecastConfig":
        if isinstance(value, cls):
            return value
        raw = dict(value or {})
        aliases = {
            "race_lap_limit": ("race_lap_limit", "lap_limit", "session_lap_limit"),
            "session_remaining_s": ("session_remaining_s", "remaining_s"),
            "stint_lap_limit": ("stint_lap_limit", "max_stint_laps"),
            "stint_time_limit_s": ("stint_time_limit_s", "max_stint_time_s"),
            "planned_pit_lap": ("planned_pit_lap", "pit_lap", "target_pit_lap"),
            "track_length_m": ("track_length_m",),
        }

        def number(name: str, default: float | None = None) -> float | None:
            keys = aliases.get(name, (name,))
            return _number(_first(raw, *keys)) if _first(raw, *keys) is not None else default

        marker = raw.get("pit_marker") or raw.get("marker")
        return cls(
            session_type=str(raw.get("session_type", raw.get("type", "UNKNOWN"))).upper(),
            race_lap_limit=number("race_lap_limit"),
            session_remaining_s=number("session_remaining_s"),
            stint_lap_limit=number("stint_lap_limit"),
            stint_time_limit_s=number("stint_time_limit_s"),
            driver_rule_laps=number("driver_rule_laps"),
            tyre_rule_laps=number("tyre_rule_laps"),
            planned_stint_laps=number("planned_stint_laps"),
            planned_stint_time_s=number("planned_stint_time_s"),
            planned_pit_lap=number("planned_pit_lap"),
            planned_pit_time_s=number("planned_pit_time_s"),
            pit_window_open_lap=number("pit_window_open_lap"),
            pit_window_close_lap=number("pit_window_close_lap"),
            reserve_fuel_l=number("reserve_fuel_l", 0.0) or 0.0,
            tank_capacity_l=number("tank_capacity_l"),
            target_fuel_l=number("target_fuel_l"),
            target_fuel_at_pit_l=number("target_fuel_at_pit_l"),
            target_finish_fuel_l=number("target_finish_fuel_l"),
            pace_target_s=number("pace_target_s", number("target_pace_s")),
            fuel_target_l=number("fuel_target_l", number("target_fuel_per_lap_l")),
            track_length_m=number("track_length_m"),
            pit_route_additional_m=number("pit_route_additional_m", 0.0) or 0.0,
            pit_marker=_copy(marker) if isinstance(marker, Mapping) else None,
            pit_loss_s=number("pit_loss_s"),
            planned_service_duration_s=number("planned_service_duration_s", number("service_duration_s")),
            strategy_id=str(raw.get("strategy_id", "strategy:local")),
            strategy_revision=str(raw.get("strategy_revision", raw.get("accepted_strategy_revision", "revision:local"))),
            baseline_strategy_revision=str(raw.get("baseline_strategy_revision", raw.get("strategy_revision", "revision:local"))),
            now_s=number("now_s"),
            stale_after_s=max(0.0, number("stale_after_s", 180.0) or 0.0),
            future_weather=_copy(raw.get("future_weather")) if isinstance(raw.get("future_weather"), Mapping) else None,
            explicit_regime=str(raw.get("regime")).upper() if raw.get("regime") is not None else None,
            target_key=str(raw.get("target_key")) if raw.get("target_key") is not None else None,
            extra=_copy(raw),
        )


class ForecastEngine:
    """Pure forecast producer for one deterministic input state."""

    def __init__(self, config: ForecastConfig | Mapping[str, Any] | None = None) -> None:
        self.config = ForecastConfig.from_value(config)

    def _time(self, snapshot: Mapping[str, Any] | None) -> float | None:
        return self.config.now_s if self.config.now_s is not None else _number(_snapshot_value(snapshot, "observed_monotonic_s", "session_time_s", "elapsed_s"))

    def _prepare_metric(self, metric: Mapping[str, Any] | None) -> Mapping[str, Any] | None:
        if metric is None:
            return None
        age = _number(metric.get("freshness_s"))
        if age is None or age <= self.config.stale_after_s:
            return metric
        degraded = _copy(metric)
        degraded["confidence"] = "LOW"
        degraded["unavailable_reason"] = "STALE_SOURCE"
        return degraded

    def _pace(self, calculation: Mapping[str, Any]) -> tuple[float | None, Mapping[str, Any] | None, str | None]:
        metric, name = _selected_metric(calculation, "pace", ("representative_pace", "operational_stint_average", "latest_accepted"))
        metric = self._prepare_metric(metric)
        return _value(metric), metric, name

    def _fuel_rate(self, calculation: Mapping[str, Any]) -> tuple[float | None, Mapping[str, Any] | None, str | None]:
        metric, name = _selected_metric(calculation, "fuel", ("representative_use", "operational_stint_average", "latest_accepted"))
        metric = self._prepare_metric(metric)
        return _value(metric), metric, name

    def _current_lap(self, calculation: Mapping[str, Any], snapshot: Mapping[str, Any] | None) -> float | None:
        value = _number(_snapshot_value(snapshot, "current_lap", "lap_number"))
        if value is not None:
            return value
        return _number(_mapping(calculation.get("progress")).get("current_race_lap"))

    def _current_fuel(self, calculation: Mapping[str, Any], snapshot: Mapping[str, Any] | None) -> tuple[float | None, Mapping[str, Any] | None]:
        live_value = _number(_snapshot_value(snapshot, "fuel_l", "current_fuel_l"))
        metric = _mapping(_mapping(calculation.get("fuel")).get("current"))
        value = live_value if live_value is not None else _value(metric)
        if live_value is not None:
            metric = {**metric, "value": live_value, "source": "measured_current_snapshot"}
        return value, metric

    def _base_id(self, calculation: Mapping[str, Any], snapshot: Mapping[str, Any] | None, generated_at_s: float | None) -> str:
        identity = _identity(snapshot, calculation)
        stint_id = str(_mapping(calculation.get("progress")).get("current_stint_id") or "stint:unknown")
        time_token = "unknown" if generated_at_s is None else f"{generated_at_s:.3f}"
        return f"forecast:{identity}:{self.config.strategy_revision}:{stint_id}:{time_token}"

    def _constraints(
        self,
        calculation: Mapping[str, Any],
        snapshot: Mapping[str, Any] | None,
        base_id: str,
        generated_at_s: float | None,
        pace_s: float | None,
        pace_metric: Mapping[str, Any] | None,
        fuel_l: float | None,
        fuel_rate_l: float | None,
        fuel_metric: Mapping[str, Any] | None,
        supersedes: str | None,
    ) -> dict[str, Any]:
        progress = _mapping(calculation.get("progress"))
        completed_laps = _number(progress.get("completed_stint_laps"))
        if completed_laps is None:
            completed_laps = _number(progress.get("current_stint_lap_zero_based"))
        completed_laps = completed_laps if completed_laps is not None else 0.0
        current_lap = self._current_lap(calculation, snapshot)
        now_s = generated_at_s
        start_s = _number(progress.get("stint_start_time_s"))
        elapsed_s = _number(progress.get("elapsed_stint_time_s"))
        if elapsed_s is None and start_s is not None and now_s is not None:
            elapsed_s = max(0.0, now_s - start_s)

        constraints: dict[str, dict[str, Any]] = {}

        def add(name: str, remaining_time_s: float | None, remaining_laps: float | None, *, reason: str | None = None, direct: bool = False) -> None:
            if remaining_time_s is None and remaining_laps is not None and pace_s is not None:
                remaining_time_s = max(0.0, remaining_laps * pace_s)
            if remaining_laps is None and remaining_time_s is not None and pace_s is not None and pace_s > 0:
                remaining_laps = max(0.0, remaining_time_s / pace_s)
            endpoint_lap = current_lap + remaining_laps if current_lap is not None and remaining_laps is not None else None
            endpoint_time = now_s + remaining_time_s if now_s is not None and remaining_time_s is not None else None
            record = _record(
                f"{base_id}:stint:{name}",
                value=remaining_laps if remaining_laps is not None else remaining_time_s,
                unit="laps" if remaining_laps is not None else "s",
                generated_at_s=generated_at_s,
                target_at_s=endpoint_time,
                measured_inputs=["session.current_lap"] if current_lap is not None else [],
                calculated_inputs=["pace.selected"] if pace_s is not None else [],
                samples=_sample_refs(pace_metric),
                regime=_mapping(pace_metric).get("regime"),
                freshness_s=_freshness([pace_metric]),
                confidence=_confidence_value(pace_metric) if remaining_laps is not None or pace_s is not None else "LOW",
                uncertainty=_uncertainty(pace_metric, "laps" if remaining_laps is not None else "s", [pace_metric]),
                unavailable_reason=reason,
                supersedes=supersedes,
            )
            constraints[name] = {
                "forecast": record,
                "remaining_time_s": remaining_time_s,
                "remaining_laps": remaining_laps,
                "predicted_endpoint_lap": endpoint_lap,
                "predicted_endpoint_time_s": endpoint_time,
                "direct_configured_limit": direct,
                "unavailable_reason": reason,
            }

        if self.config.stint_time_limit_s is not None:
            add("time_limited", max(0.0, self.config.stint_time_limit_s - (elapsed_s or 0.0)), None, direct=True)
        if self.config.stint_lap_limit is not None:
            add("lap_limited", None, max(0.0, self.config.stint_lap_limit - completed_laps), direct=True)
        if self.config.driver_rule_laps is not None:
            add("driver_rule_limited", None, max(0.0, self.config.driver_rule_laps - completed_laps), direct=True)
        if self.config.tyre_rule_laps is not None:
            add("tyre_rule_limited", None, max(0.0, self.config.tyre_rule_laps - completed_laps), direct=True)
        if self.config.planned_stint_laps is not None:
            add("planned", None, max(0.0, self.config.planned_stint_laps - completed_laps), direct=True)
        elif self.config.planned_stint_time_s is not None:
            add("planned", max(0.0, self.config.planned_stint_time_s - (elapsed_s or 0.0)), None, direct=True)
        if fuel_l is not None and fuel_rate_l is not None and fuel_rate_l > 0:
            remaining_fuel_l = max(0.0, fuel_l - self.config.reserve_fuel_l)
            add("fuel_limited", None, remaining_fuel_l / fuel_rate_l)
            constraints["fuel_limited"]["remaining_fuel_l"] = remaining_fuel_l
        else:
            constraints["fuel_limited"] = {"forecast": _unavailable(f"{base_id}:stint:fuel_limited", unit="laps", generated_at_s=generated_at_s, reason="CURRENT_FUEL_OR_FUEL_MODEL_UNAVAILABLE", samples=_sample_refs(fuel_metric), regime=_mapping(fuel_metric).get("regime"), freshness_s=_freshness([fuel_metric]), supersedes=supersedes), "remaining_time_s": None, "remaining_laps": None, "predicted_endpoint_lap": None, "predicted_endpoint_time_s": None, "direct_configured_limit": False, "unavailable_reason": "CURRENT_FUEL_OR_FUEL_MODEL_UNAVAILABLE"}

        available = [item for item in constraints.values() if item.get("remaining_laps") is not None]
        binding = min(available, key=lambda item: (float(item["remaining_laps"]), str(item["forecast"].get("forecast_id")))) if available else None
        binding_name = None
        if binding is not None:
            binding_name = next(name for name, item in constraints.items() if item is binding)
        remaining_laps = binding.get("remaining_laps") if binding else None
        remaining_time = binding.get("remaining_time_s") if binding else None
        if remaining_time is None and remaining_laps is not None and pace_s is not None:
            remaining_time = remaining_laps * pace_s
        endpoint_lap = current_lap + remaining_laps if current_lap is not None and remaining_laps is not None else None
        endpoint_time = now_s + remaining_time if now_s is not None and remaining_time is not None else None
        actual = _record(
            f"{base_id}:stint:predicted_actual",
            value=endpoint_lap,
            unit="lap",
            generated_at_s=generated_at_s,
            target_at_s=endpoint_time,
            measured_inputs=["session.current_lap"] if current_lap is not None else [],
            calculated_inputs=["stint.constraints", "pace.selected"],
            samples=_sample_refs(pace_metric) + _sample_refs(fuel_metric),
            regime=_mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime"),
            freshness_s=_freshness([pace_metric, fuel_metric]),
            confidence=min((_confidence_value(pace_metric), _confidence_value(fuel_metric)), key=lambda item: _confidence_score(item)) if pace_metric or fuel_metric else "UNAVAILABLE",
            uncertainty=_uncertainty(pace_metric, "lap", [pace_metric]),
            binding_constraint=binding_name,
            unavailable_reason=None if binding is not None else "NO_DEFENSIBLE_STINT_ENDPOINT",
            supersedes=supersedes,
        )
        return {
            "constraints": constraints,
            "remaining_stint_time": _record(f"{base_id}:stint:remaining_time", value=remaining_time, unit="s", generated_at_s=generated_at_s, calculated_inputs=["stint.constraints"], samples=_sample_refs(pace_metric) + _sample_refs(fuel_metric), regime=_mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime"), freshness_s=_freshness([pace_metric, fuel_metric]), confidence=_confidence_value(pace_metric) if remaining_time is not None else "UNAVAILABLE", unavailable_reason=None if remaining_time is not None else "NO_DEFENSIBLE_STINT_ENDPOINT", supersedes=supersedes),
            "remaining_stint_laps": _record(f"{base_id}:stint:remaining_laps", value=remaining_laps, unit="laps", generated_at_s=generated_at_s, calculated_inputs=["stint.constraints"], samples=_sample_refs(pace_metric) + _sample_refs(fuel_metric), regime=_mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime"), freshness_s=_freshness([pace_metric, fuel_metric]), confidence=_confidence_value(pace_metric) if remaining_laps is not None else "UNAVAILABLE", unavailable_reason=None if remaining_laps is not None else "NO_DEFENSIBLE_STINT_ENDPOINT", supersedes=supersedes),
            "predicted_actual": actual,
            "predicted_endpoint_lap": endpoint_lap,
            "predicted_endpoint_time_s": endpoint_time,
            "binding_constraint": binding_name,
            "limiting_factor": binding_name,
            "planned": constraints.get("planned"),
        }

    def _race(
        self,
        calculation: Mapping[str, Any],
        snapshot: Mapping[str, Any] | None,
        base_id: str,
        generated_at_s: float | None,
        pace_s: float | None,
        pace_metric: Mapping[str, Any] | None,
        fuel_rate_l: float | None,
        fuel_metric: Mapping[str, Any] | None,
        fuel_l: float | None,
        supersedes: str | None,
    ) -> dict[str, Any]:
        current_lap = self._current_lap(calculation, snapshot)
        session = _mapping((snapshot or {}).get("session"))
        lap_limit = self.config.race_lap_limit if self.config.race_lap_limit is not None else _number(_first(session, "lap_limit", "race_lap_limit"))
        remaining_time = self.config.session_remaining_s if self.config.session_remaining_s is not None else _number(_first(session, "remaining_s", "remaining_time_s"))
        remaining_laps = max(0.0, lap_limit - current_lap) if lap_limit is not None and current_lap is not None else remaining_time / pace_s if remaining_time is not None and pace_s and pace_s > 0 else None
        if remaining_time is None and remaining_laps is not None and pace_s is not None:
            remaining_time = remaining_laps * pace_s
        finish_lap = math.floor(current_lap + remaining_laps) if current_lap is not None and remaining_laps is not None else None
        finish_time = generated_at_s + remaining_time if generated_at_s is not None and remaining_time is not None else None
        samples = _sample_refs(pace_metric) + _sample_refs(fuel_metric)
        race_laps = _record(f"{base_id}:race:remaining_laps", value=remaining_laps, unit="laps", generated_at_s=generated_at_s, calculated_inputs=["session.lap_limit", "pace.selected"], samples=samples, regime=_mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime"), freshness_s=_freshness([pace_metric, fuel_metric]), confidence=_confidence_value(pace_metric) if remaining_laps is not None else "UNAVAILABLE", unavailable_reason=None if remaining_laps is not None else "RACE_DISTANCE_OR_TIME_UNAVAILABLE", supersedes=supersedes)
        race_time = _record(f"{base_id}:race:remaining_time", value=remaining_time, unit="s", generated_at_s=generated_at_s, calculated_inputs=["session.remaining_time", "pace.selected"], samples=samples, regime=_mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime"), freshness_s=_freshness([pace_metric, fuel_metric]), confidence=_confidence_value(pace_metric) if remaining_time is not None else "UNAVAILABLE", unavailable_reason=None if remaining_time is not None else "RACE_TIME_UNAVAILABLE", supersedes=supersedes)
        finish_lap_record = _record(f"{base_id}:race:finish_lap", value=finish_lap, unit="lap", generated_at_s=generated_at_s, target_at_s=finish_time, calculated_inputs=["race.remaining_laps"], samples=samples, regime=_mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime"), freshness_s=_freshness([pace_metric, fuel_metric]), confidence=_confidence_value(pace_metric) if finish_lap is not None else "UNAVAILABLE", unavailable_reason=None if finish_lap is not None else "RACE_FINISH_LAP_UNAVAILABLE", supersedes=supersedes)
        fuel_required = remaining_laps * fuel_rate_l if remaining_laps is not None and fuel_rate_l is not None else None
        target_finish = self.config.target_finish_fuel_l if self.config.target_finish_fuel_l is not None else self.config.reserve_fuel_l
        required_total = fuel_required + target_finish if fuel_required is not None else None
        expected_finish = fuel_l - fuel_required if fuel_l is not None and fuel_required is not None else None
        margin = expected_finish - target_finish if expected_finish is not None else None
        fuel_record = _record(f"{base_id}:race:fuel_required_to_finish", value=required_total, unit="L", generated_at_s=generated_at_s, calculated_inputs=["race.remaining_laps", "fuel.selected", "strategy.reserve"], samples=_sample_refs(fuel_metric), regime=_mapping(fuel_metric).get("regime"), freshness_s=_freshness([fuel_metric]), confidence=_confidence_value(fuel_metric) if required_total is not None else "UNAVAILABLE", uncertainty=_uncertainty(fuel_metric, "L", [fuel_metric]), unavailable_reason=None if required_total is not None else "RACE_FUEL_REQUIREMENT_UNAVAILABLE", supersedes=supersedes)
        expected_record = _record(f"{base_id}:race:expected_fuel_at_finish", value=expected_finish, unit="L", generated_at_s=generated_at_s, calculated_inputs=["race.remaining_laps", "fuel.selected"], samples=_sample_refs(fuel_metric), regime=_mapping(fuel_metric).get("regime"), freshness_s=_freshness([fuel_metric]), confidence=_confidence_value(fuel_metric) if expected_finish is not None else "UNAVAILABLE", uncertainty=_uncertainty(fuel_metric, "L", [fuel_metric]), unavailable_reason=None if expected_finish is not None else "RACE_FUEL_REQUIREMENT_UNAVAILABLE", supersedes=supersedes)
        margin_record = _record(f"{base_id}:race:fuel_margin", value=margin, unit="L", generated_at_s=generated_at_s, calculated_inputs=["race.expected_fuel_at_finish", "strategy.reserve"], samples=_sample_refs(fuel_metric), regime=_mapping(fuel_metric).get("regime"), freshness_s=_freshness([fuel_metric]), confidence=_confidence_value(fuel_metric) if margin is not None else "UNAVAILABLE", unavailable_reason=None if margin is not None else "RACE_FUEL_MARGIN_UNAVAILABLE", supersedes=supersedes)
        return {"remaining_laps": race_laps, "remaining_time": race_time, "predicted_finish_lap": finish_lap_record, "predicted_finish_time": _record(f"{base_id}:race:finish_time", value=finish_time, unit="s", generated_at_s=generated_at_s, target_at_s=finish_time, calculated_inputs=["race.remaining_time"], samples=samples, regime=_mapping(pace_metric).get("regime"), freshness_s=_freshness([pace_metric]), confidence=_confidence_value(pace_metric) if finish_time is not None else "UNAVAILABLE", unavailable_reason=None if finish_time is not None else "RACE_FINISH_TIME_UNAVAILABLE", supersedes=supersedes), "fuel_required_to_finish": fuel_record, "expected_fuel_at_finish": expected_record, "fuel_margin": margin_record, "planned_stops_remaining": self._planned_stops_remaining(current_lap, calculation, snapshot), "strategy_feasibility": "feasible" if margin is not None and margin >= 0 else "infeasible" if margin is not None else "unknown"}

    def _planned_stops_remaining(self, current_lap: float | None, calculation: Mapping[str, Any], snapshot: Mapping[str, Any] | None) -> dict[str, Any]:
        plan = self.config.extra.get("planned_stops")
        if not isinstance(plan, (list, tuple)):
            return {"value": None, "unit": "stops", "unavailable_reason": "PLANNED_STOPS_NOT_CONFIGURED"}
        count = sum(1 for item in plan if _number(item) is not None and (current_lap is None or float(item) > current_lap))
        return {"value": count, "unit": "stops", "unavailable_reason": None}

    def _fuel(
        self,
        calculation: Mapping[str, Any],
        snapshot: Mapping[str, Any] | None,
        race: Mapping[str, Any],
        base_id: str,
        generated_at_s: float | None,
        fuel_l: float | None,
        fuel_metric: Mapping[str, Any] | None,
        fuel_rate_l: float | None,
        pace_metric: Mapping[str, Any] | None,
        supersedes: str | None,
    ) -> dict[str, Any]:
        current_lap = self._current_lap(calculation, snapshot)
        planned_laps = max(0.0, self.config.planned_pit_lap - current_lap) if self.config.planned_pit_lap is not None and current_lap is not None else None
        required_pit = planned_laps * fuel_rate_l + self.config.reserve_fuel_l if planned_laps is not None and fuel_rate_l is not None else None
        expected_pit = fuel_l - planned_laps * fuel_rate_l if fuel_l is not None and planned_laps is not None and fuel_rate_l is not None else None
        race_remaining = _value(race.get("remaining_laps"))
        required_finish = race_remaining * fuel_rate_l + self.config.reserve_fuel_l if race_remaining is not None and fuel_rate_l is not None else None
        expected_finish = fuel_l - race_remaining * fuel_rate_l if fuel_l is not None and race_remaining is not None and fuel_rate_l is not None else None
        required_now = fuel_rate_l
        required_pit_per_lap = required_pit / planned_laps if required_pit is not None and planned_laps and planned_laps > 0 else None
        save = max(0.0, (required_finish - fuel_l) / race_remaining) if required_finish is not None and fuel_l is not None and race_remaining and race_remaining > 0 else None
        common = {"samples": _sample_refs(fuel_metric), "regime": _mapping(fuel_metric).get("regime"), "freshness_s": _freshness([fuel_metric]), "confidence": _confidence_value(fuel_metric), "supersedes": supersedes}

        def make(name: str, value: float | None, unit: str, reason: str, *, inputs: Sequence[str] = (), uncertainty: bool = False) -> dict[str, Any]:
            return _record(f"{base_id}:fuel:{name}", value=value, unit=unit, generated_at_s=generated_at_s, calculated_inputs=list(inputs), samples=common["samples"], regime=common["regime"], freshness_s=common["freshness_s"], confidence=common["confidence"] if value is not None else "UNAVAILABLE", uncertainty=_uncertainty(fuel_metric, unit, [fuel_metric]) if uncertainty else None, unavailable_reason=None if value is not None else reason, supersedes=supersedes)

        target_delta = None
        if self.config.fuel_target_l is not None and fuel_rate_l is not None:
            target_delta = make("current_rate_vs_target", fuel_rate_l - self.config.fuel_target_l, "L/lap", "", inputs=["fuel.selected", "strategy.fuel_target_l"])
            target_delta["reference"] = "configured_fuel_target_l_per_lap"
        else:
            target_delta = _unavailable(f"{base_id}:fuel:current_rate_vs_target", unit="L/lap", generated_at_s=generated_at_s, reason="TARGET_NOT_CONFIGURED", samples=common["samples"], regime=common["regime"], freshness_s=common["freshness_s"], supersedes=supersedes)
            target_delta["reference"] = "configured_fuel_target_l_per_lap"
        current = make("current", fuel_l, "L", "CURRENT_FUEL_UNAVAILABLE", inputs=["fuel.current"], uncertainty=False)
        range_laps = make("range_laps", max(0.0, fuel_l - self.config.reserve_fuel_l) / fuel_rate_l if fuel_l is not None and fuel_rate_l and fuel_rate_l > 0 else None, "laps", "CURRENT_FUEL_OR_FUEL_MODEL_UNAVAILABLE", inputs=["fuel.current", "fuel.selected"], uncertainty=True)
        range_time = make("range_time", _value(range_laps) * _value(pace_metric) if _value(range_laps) is not None and _value(pace_metric) is not None else None, "s", "CURRENT_FUEL_OR_FUEL_MODEL_UNAVAILABLE", inputs=["fuel.range_laps", "pace.selected"], uncertainty=True)
        result = {
            "current": current,
            "range_laps": range_laps,
            "range_time": range_time,
            "range_distance_m": make("range_distance", _value(range_laps) * self.config.track_length_m if _value(range_laps) is not None and self.config.track_length_m is not None else None, "m", "TRACK_LENGTH_UNAVAILABLE", inputs=["fuel.range_laps", "track.length"], uncertainty=True),
            "required_fuel_per_lap_now": make("required_per_lap_now", required_now, "L/lap", "FUEL_MODEL_UNAVAILABLE", inputs=["fuel.selected"]),
            "required_fuel_per_lap_to_planned_pit": make("required_per_lap_to_planned_pit", required_pit_per_lap, "L/lap", "PLANNED_PIT_TARGET_UNAVAILABLE", inputs=["fuel.required_to_planned_pit", "strategy.planned_pit_lap"]),
            "required_to_planned_pit": make("required_to_planned_pit", required_pit, "L", "PLANNED_PIT_TARGET_UNAVAILABLE", inputs=["fuel.selected", "strategy.planned_pit_lap"], uncertainty=True),
            "required_to_finish": make("required_to_finish", required_finish, "L", "RACE_FUEL_REQUIREMENT_UNAVAILABLE", inputs=["race.remaining_laps", "fuel.selected"], uncertainty=True),
            "expected_at_planned_pit": make("expected_at_planned_pit", expected_pit, "L", "PLANNED_PIT_TARGET_UNAVAILABLE", inputs=["fuel.current", "fuel.selected", "strategy.planned_pit_lap"], uncertainty=True),
            "expected_at_finish": make("expected_at_finish", expected_finish, "L", "RACE_FUEL_REQUIREMENT_UNAVAILABLE", inputs=["fuel.current", "race.remaining_laps", "fuel.selected"], uncertainty=True),
            "margin_vs_required": make("margin_vs_required", expected_finish - self.config.reserve_fuel_l if expected_finish is not None else None, "L", "RACE_FUEL_MARGIN_UNAVAILABLE", inputs=["fuel.expected_at_finish", "strategy.reserve"]),
            "fuel_save_requirement": make("fuel_save_requirement", save, "L/lap", "RACE_FUEL_REQUIREMENT_UNAVAILABLE", inputs=["fuel.required_to_finish", "fuel.current", "race.remaining_laps"]),
            "target_delta": target_delta,
            "configured_target_fuel_per_lap_l": self.config.fuel_target_l,
            "selected_model": {"name": "representative_fuel_use" if fuel_rate_l is not None else None, "value": fuel_rate_l, "source": "calculated" if fuel_rate_l is not None else None},
        }
        return result

    def _pit(
        self,
        calculation: Mapping[str, Any],
        snapshot: Mapping[str, Any] | None,
        pit_diagnostics: Mapping[str, Any],
        base_id: str,
        generated_at_s: float | None,
        pace_s: float | None,
        pace_metric: Mapping[str, Any] | None,
        fuel_l: float | None,
        fuel_rate_l: float | None,
        fuel_metric: Mapping[str, Any] | None,
        supersedes: str | None,
    ) -> dict[str, Any]:
        marker = _pit_marker(pit_diagnostics, self.config)
        current_spline = _number(_snapshot_value(snapshot, "spline"))
        track_length = self.config.track_length_m if self.config.track_length_m is not None else _number(_snapshot_value(snapshot, "track_length_m"))
        entry_spline = _number(marker.get("entry_spline"))
        distance, distance_reason = forward_distance(current_spline, entry_spline, track_length)
        if marker.get("state") in {"CONFLICTED", "UNAVAILABLE"}:
            distance, distance_reason = None, "PIT_ENTRY_MARKER_UNTRUSTWORTHY"
        live_lane = bool(pit_diagnostics.get("live_pit_lane", _snapshot_value(snapshot, "pit_lane") is True))
        live_box = bool(pit_diagnostics.get("live_pit_box", _snapshot_value(snapshot, "pit_box") is True))
        current_lap = self._current_lap(calculation, snapshot)
        planned_passed = self.config.planned_pit_lap is not None and current_lap is not None and current_lap >= self.config.planned_pit_lap
        raw_passed = current_spline is not None and entry_spline is not None and current_spline > entry_spline and current_spline - entry_spline < 0.5
        entry_passed = bool(planned_passed or raw_passed)
        speed_mps = None
        current_speed = _number(_snapshot_value(snapshot, "speed_kmh"))
        if current_speed is not None and current_speed > 1.0:
            speed_mps = current_speed / 3.6
        elif distance is not None and pace_s is not None and track_length and track_length > 0:
            speed_mps = track_length / pace_s
        eta = distance / speed_mps if distance is not None and speed_mps and speed_mps > 0 else None
        expected_lap = None
        if current_lap is not None:
            expected_lap = current_lap + (1 if entry_passed else 0)
            if self.config.planned_pit_lap is not None and not entry_passed:
                expected_lap = self.config.planned_pit_lap
        marker_state = str(marker.get("state") or pit_diagnostics.get("marker_state") or "UNAVAILABLE").upper()
        marker_confidence = _number(marker.get("confidence"))
        if marker_confidence is None:
            marker_confidence = _number(pit_diagnostics.get("confidence")) or 0.0
        confidence = "HIGH" if marker_state == "MANUAL_OVERRIDE" or marker_state == "CONFIRMED" else "MEDIUM" if marker_state == "LEARNED" else "LOW" if marker_state == "PROVISIONAL" else "UNAVAILABLE"
        common_samples = _sample_refs(pace_metric) + _sample_refs(fuel_metric)
        timing = _mapping(marker.get("timing"))
        visits = _normal_stop_visits(marker, pit_diagnostics)
        entry_box = self.config.extra.get("entry_to_box_s") or _number(timing.get("last_entry_to_box_s")) or _median_field(visits, "entry_to_box_s", "last_entry_to_box_s")
        box_exit = self.config.extra.get("box_to_exit_s") or _number(timing.get("last_box_to_exit_s")) or _median_field(visits, "box_to_exit_s", "last_box_to_exit_s")
        service = self.config.planned_service_duration_s
        if service is None:
            service = _median_field(visits, "service_duration_s", "last_service_duration_s")
        drive_through_only = bool(not visits and _token(timing.get("last_classification")) == "DRIVE_THROUGH") or bool(timing.get("drive_through_only"))
        timing_reason = "NO_RECENT_PIT_TIMING" if not visits and entry_box is None and box_exit is None else "DRIVE_THROUGH_ONLY_EVIDENCE" if drive_through_only and service is None else None
        if drive_through_only:
            service = None
        total_duration = self.config.extra.get("total_pit_lane_duration_s") or _number(timing.get("last_total_lane_duration_s")) or _median_field(visits, "total_lane_duration_s", "last_total_lane_duration_s")
        if total_duration is None and entry_box is not None and box_exit is not None and service is not None:
            total_duration = entry_box + service + box_exit
        loss = self.config.pit_loss_s if self.config.pit_loss_s is not None else total_duration
        entry_record = _record(f"{base_id}:pit:distance_to_entry", value=distance, unit="m", generated_at_s=generated_at_s, measured_inputs=["car.spline", "track.length"], calculated_inputs=["pit.marker.entry_spline"], samples=common_samples, regime=_mapping(pace_metric).get("regime"), freshness_s=_freshness([pace_metric, fuel_metric]), confidence=confidence if distance is not None else "UNAVAILABLE", unavailable_reason=None if distance is not None else distance_reason, supersedes=supersedes)
        eta_record = _record(f"{base_id}:pit:eta_to_entry", value=eta, unit="s", generated_at_s=generated_at_s, calculated_inputs=["pit.distance_to_entry", "pace.selected"], samples=common_samples, regime=_mapping(pace_metric).get("regime"), freshness_s=_freshness([pace_metric]), confidence=confidence if eta is not None else "UNAVAILABLE", uncertainty=_uncertainty(pace_metric, "s", [pace_metric]), unavailable_reason=None if eta is not None else "PIT_ENTRY_ETA_UNAVAILABLE", supersedes=supersedes)
        expected_fuel = fuel_l - fuel_rate_l * (distance / track_length) if fuel_l is not None and fuel_rate_l is not None and distance is not None and track_length and track_length > 0 else None
        entry_fuel_record = _record(f"{base_id}:pit:expected_fuel_at_entry", value=expected_fuel, unit="L", generated_at_s=generated_at_s, calculated_inputs=["fuel.current", "fuel.selected", "pit.distance_to_entry"], samples=_sample_refs(fuel_metric), regime=_mapping(fuel_metric).get("regime"), freshness_s=_freshness([fuel_metric]), confidence=_confidence_value(fuel_metric) if expected_fuel is not None else "UNAVAILABLE", uncertainty=_uncertainty(fuel_metric, "L", [fuel_metric]), unavailable_reason=None if expected_fuel is not None else "PIT_ENTRY_FUEL_UNAVAILABLE", supersedes=supersedes)
        def timing_record(name: str, value: float | None, reason: str, inputs: Sequence[str]) -> dict[str, Any]:
            return _record(f"{base_id}:pit:{name}", value=value, unit="s", generated_at_s=generated_at_s, calculated_inputs=inputs, samples=[str(item.get("visit_id")) for item in visits if item.get("visit_id") is not None], confidence=confidence if value is not None else "UNAVAILABLE", unavailable_reason=None if value is not None else reason, supersedes=supersedes)
        cycle = {
            "entry_to_box": timing_record("entry_to_box", entry_box, timing_reason or "ENTRY_TO_BOX_UNAVAILABLE", ["pit.marker.timing"]),
            "service_duration": timing_record("service_duration", service, "SERVICE_DURATION_NOT_CONFIGURED_OR_CALIBRATED" if not drive_through_only else "DRIVE_THROUGH_ONLY_EVIDENCE", ["strategy.service_duration", "pit.marker.timing"]),
            "box_to_exit": timing_record("box_to_exit", box_exit, timing_reason or "BOX_TO_EXIT_UNAVAILABLE", ["pit.marker.timing"]),
            "total_lane_duration": timing_record("total_lane_duration", total_duration, timing_reason or "PIT_CYCLE_DURATION_UNAVAILABLE", ["pit.marker.timing", "pit.cycle.components"]),
            "total_pit_loss": timing_record("total_pit_loss", loss, "PIT_LOSS_UNAVAILABLE", ["strategy.pit_loss", "pit.cycle.total_lane_duration"]),
        }
        rejoin_time = generated_at_s + total_duration if generated_at_s is not None and total_duration is not None else None
        rejoin_lap = expected_lap + 1 if expected_lap is not None and total_duration is not None else None
        if entry_passed:
            window_state = "OVERDUE"
        elif self.config.planned_pit_lap is None:
            window_state = "UNKNOWN"
        elif current_lap is None:
            window_state = "UNKNOWN"
        elif self.config.pit_window_open_lap is not None and current_lap < self.config.pit_window_open_lap:
            window_state = "CLOSED"
        elif self.config.pit_window_close_lap is not None and current_lap > self.config.pit_window_close_lap:
            window_state = "OVERDUE"
        else:
            window_state = "OPEN"
        return {
            "live": {"state": pit_diagnostics.get("state", "ON_TRACK"), "pit_lane": live_lane, "pit_box": live_box, "available": True},
            "marker": {"state": marker_state, "confidence": marker_confidence, "source": marker.get("source"), "manual_override": marker.get("manual_override") is True, "entry_spline": entry_spline, "exit_spline": _number(marker.get("exit_spline"))},
            "distance_to_entry": entry_record,
            "route_distance_to_entry": _record(f"{base_id}:pit:route_distance_to_entry", value=distance + self.config.pit_route_additional_m if distance is not None else None, unit="m", generated_at_s=generated_at_s, calculated_inputs=["pit.distance_to_entry", "strategy.pit_route_additional_m"], samples=common_samples, confidence=confidence if distance is not None else "UNAVAILABLE", unavailable_reason=None if distance is not None else distance_reason, supersedes=supersedes),
            "eta_to_entry": eta_record,
            "expected_entry_lap": _record(f"{base_id}:pit:expected_entry_lap", value=expected_lap, unit="lap", generated_at_s=generated_at_s, calculated_inputs=["pit.distance_to_entry", "session.current_lap"], samples=common_samples, confidence=confidence if expected_lap is not None else "UNAVAILABLE", unavailable_reason=None if expected_lap is not None else "PIT_ENTRY_LAP_UNAVAILABLE", supersedes=supersedes),
            "expected_fuel_at_entry": entry_fuel_record,
            "entry_already_passed": entry_passed,
            "entry_window_state": window_state,
            "cycle": cycle,
            "expected_box_arrival_time_s": generated_at_s + eta + entry_box if generated_at_s is not None and eta is not None and entry_box is not None else None,
            "expected_box_departure_time_s": generated_at_s + eta + entry_box + service if generated_at_s is not None and eta is not None and entry_box is not None and service is not None else None,
            "expected_pit_exit_time_s": rejoin_time,
            "expected_rejoin_lap": rejoin_lap,
            "expected_rejoin_time_s": rejoin_time,
            "timing_confidence": confidence if visits or self.config.planned_service_duration_s is not None else "LOW",
            "timing_reason": timing_reason,
            "calibration_status": marker_state,
            "states": ["PLANNED_ENTRY_PASSED"] if entry_passed else ["PIT_WINDOW_OPEN"] if window_state == "OPEN" else [],
        }

    def calculate(
        self,
        calculation: Mapping[str, Any],
        *,
        current_snapshot: Mapping[str, Any] | None = None,
        pit_diagnostics: Mapping[str, Any] | None = None,
        events: Iterable[Mapping[str, Any]] = (),
        previous_forecast: Mapping[str, Any] | None = None,
    ) -> Mapping[str, Any]:
        calculation = _mapping(calculation)
        pit_diagnostics = _mapping(pit_diagnostics)
        generated_at_s = self._time(current_snapshot)
        pace_s, pace_metric, pace_name = self._pace(calculation)
        fuel_rate_l, fuel_metric, fuel_name = self._fuel_rate(calculation)
        fuel_l, current_fuel_metric = self._current_fuel(calculation, current_snapshot)
        if current_fuel_metric and _value(current_fuel_metric) is None and fuel_l is not None:
            current_fuel_metric = {"value": fuel_l, "confidence": "HIGH", "accepted_samples": [], "regime": None}
        base_id = self._base_id(calculation, current_snapshot, generated_at_s)
        identity_fields = _identity_fields(current_snapshot)
        invalidation = _invalidation_reasons(events, previous_forecast, self.config.strategy_revision, self.config.target_key)
        supersedes = str(previous_forecast.get("forecast_id")) if isinstance(previous_forecast, Mapping) and previous_forecast.get("forecast_id") is not None else None
        constraints = self._constraints(calculation, current_snapshot, base_id, generated_at_s, pace_s, pace_metric, fuel_l, fuel_rate_l, fuel_metric, supersedes)
        race = self._race(calculation, current_snapshot, base_id, generated_at_s, pace_s, pace_metric, fuel_rate_l, fuel_metric, fuel_l, supersedes)
        fuel = self._fuel(calculation, current_snapshot, race, base_id, generated_at_s, fuel_l, fuel_metric, fuel_rate_l, pace_metric, supersedes)
        pit = self._pit(calculation, current_snapshot, pit_diagnostics, base_id, generated_at_s, pace_s, pace_metric, fuel_l, fuel_rate_l, fuel_metric, supersedes)
        current_regime = self.config.explicit_regime or _mapping(pace_metric).get("regime") or _mapping(fuel_metric).get("regime")
        future_weather = self.config.future_weather
        if future_weather is None:
            future_weather_record = _unavailable(f"{base_id}:weather:future", unit="", generated_at_s=generated_at_s, reason="FUTURE_WEATHER_SOURCE_UNAVAILABLE", regime=current_regime, supersedes=supersedes)
        else:
            future_weather_record = _record(f"{base_id}:weather:future", value=_copy(future_weather), unit="state", generated_at_s=generated_at_s, measured_inputs=["weather.future_source"], confidence="HIGH", unavailable_reason=None, supersedes=supersedes)
        states = ["FORECAST_UNAVAILABLE"] if constraints["predicted_actual"].get("unavailable_reason") else []
        states.extend(pit.get("states", []))
        if _value(fuel.get("margin_vs_required")) is not None and _value(fuel.get("margin_vs_required")) < 0:
            states.append("FUEL_MARGIN_LOW")
        if not states:
            states.append("ON_PLAN")
        result = {
            "schema_version": "forecast-engine-v1",
            "forecast_version": FORECAST_VERSION,
            "forecast_id": base_id,
            **identity_fields,
            "strategy_id": self.config.strategy_id,
            "strategy_revision": self.config.strategy_revision,
            "baseline_strategy_revision": self.config.baseline_strategy_revision,
            "stint_id": _mapping(calculation.get("progress")).get("current_stint_id"),
            "calculated_at_s": generated_at_s,
            "model": {"model_id": MODEL_ID, "model_version": MODEL_VERSION},
            "pace_input": {"value": pace_s, "source": pace_name, "regime": current_regime, "sample_count": len(_sample_refs(pace_metric)), "unavailable_reason": None if pace_s is not None else "NO_COMPATIBLE_PACE_MODEL"},
            "fuel_input": {"value": fuel_rate_l, "source": fuel_name, "regime": current_regime, "sample_count": len(_sample_refs(fuel_metric)), "unavailable_reason": None if fuel_rate_l is not None else "NO_COMPATIBLE_FUEL_MODEL"},
            "stint": constraints,
            "race": race,
            "fuel": fuel,
            "pit": pit,
            "weather": {"current_regime": current_regime, "future": future_weather_record, "future_authoritative": future_weather is not None},
            "recommendation_states": list(dict.fromkeys(states)),
            "invalidation": {"invalidated": bool(invalidation), "reason_codes": invalidation, "supersedes": supersedes},
            "strategy_feasibility": race.get("strategy_feasibility", "unknown"),
            "target_key": self.config.target_key,
        }
        return _copy(result)

    forecast = calculate
    build = calculate


RacePitForecastEngine = ForecastEngine


def calculate_forecasts(
    calculation: Mapping[str, Any],
    *,
    config: ForecastConfig | Mapping[str, Any] | None = None,
    current_snapshot: Mapping[str, Any] | None = None,
    pit_diagnostics: Mapping[str, Any] | None = None,
    events: Iterable[Mapping[str, Any]] = (),
    previous_forecast: Mapping[str, Any] | None = None,
) -> Mapping[str, Any]:
    return ForecastEngine(config).calculate(calculation, current_snapshot=current_snapshot, pit_diagnostics=pit_diagnostics, events=events, previous_forecast=previous_forecast)


def serialize_forecasts(result: Mapping[str, Any]) -> bytes:
    return (json.dumps(to_plain(result), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


__all__ = [
    "FORECAST_VERSION",
    "MODEL_ID",
    "MODEL_VERSION",
    "ForecastConfig",
    "ForecastEngine",
    "RacePitForecastEngine",
    "calculate_forecasts",
    "serialize_forecasts",
]
