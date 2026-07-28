"""Deterministic current and historical stint calculations.

This module consumes immutable completed laps, immutable race events, and
purpose-specific eligibility decisions. It produces current calculated values
only; future endpoint estimation and operator actions belong to later layers.
"""

from __future__ import annotations

import copy
import json
import math
from dataclasses import dataclass, field
from statistics import median
from types import MappingProxyType
from typing import Any, Iterable, Mapping, Sequence

from tools.race_engine_core import calculated_value, to_plain


CALCULATION_VERSION = "stint-calculation-v1"
ESTIMATOR_VERSION = "median-v1"
WHEELS = ("FL", "FR", "RL", "RR")
REGIME_ALIASES = {
    "WETTING": "MIXED",
    "DAMP": "MIXED",
    "FUEL_SAVING": "FUEL_SAVE",
    "FUEL_SAVE_RUNNING": "FUEL_SAVE",
    "PUSH_RUNNING": "PUSH",
    "GREEN": "NORMAL",
    "GREEN_VALID": "NORMAL",
}


def _copy(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {key: _copy(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [_copy(child) for child in value]
    return copy.deepcopy(value)


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(child) for key, child in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(child) for child in value)
    return value


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _number(value: Any) -> int | float | None:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)) else None


def _first(mapping: Mapping[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in mapping:
            return mapping[key]
    return None


def _token(value: Any) -> str:
    return str(value or "").strip().upper().replace("-", "_").replace(" ", "_")


def _regime(value: Any) -> str | None:
    token = REGIME_ALIASES.get(_token(value), _token(value))
    return token or None


def _event_type(event: Mapping[str, Any]) -> str:
    return _token(event.get("event_type", event.get("type")))


def _event_time(event: Mapping[str, Any]) -> float | None:
    for key in ("session_time_s", "detection_time_s", "source_time_s", "time_s"):
        value = _number(event.get(key))
        if value is not None:
            return float(value)
    return None


def _lap_time(lap: Mapping[str, Any]) -> float | None:
    return _number(_first(lap, "lap_time_s", "time_s", "duration_s"))


def _fuel_use(lap: Mapping[str, Any]) -> float | None:
    fuel = _mapping(lap.get("fuel"))
    direct = _first(lap, "fuel_use_l", "fuel_used_l", "fuel_delta_l")
    value = _number(direct)
    if value is not None:
        return float(value)
    value = _number(_first(fuel, "use_l", "used_l", "fuel_used_l", "delta_l"))
    if value is not None:
        return float(value)
    start, end = _number(_first(fuel, "start_l", "fuel_start_l")), _number(_first(fuel, "end_l", "fuel_end_l"))
    if start is not None and end is not None:
        return float(start - end)
    return None


def _lap_regime(lap: Mapping[str, Any]) -> str | None:
    value = _first(lap, "regime", "operating_regime", "weather_regime")
    if value is None:
        value = _first(_mapping(lap.get("classification")), "regime")
    return _regime(value)


def _identity(lap: Mapping[str, Any]) -> str:
    return str(lap.get("identity_key") or "unknown")


def _lap_record(value: Mapping[str, Any]) -> Mapping[str, Any]:
    if "lap" in value and isinstance(value.get("lap"), Mapping):
        lap = dict(value["lap"])
        if "eligibility" not in lap and isinstance(value.get("eligibility"), Mapping):
            lap["eligibility"] = value["eligibility"]
        return lap
    return value


def _eligibility(lap: Mapping[str, Any], purpose: str) -> bool:
    eligibility = _mapping(lap.get("eligibility"))
    if not eligibility and isinstance(lap.get("eligibility_result"), Mapping):
        eligibility = _mapping(lap["eligibility_result"].get("eligibility", lap["eligibility_result"]))
        if not eligibility and isinstance(lap["eligibility_result"].get("decisions"), Mapping):
            eligibility = lap["eligibility_result"]["decisions"]
    decisions = _mapping(eligibility.get("decisions"))
    candidate = decisions.get(purpose, eligibility.get(purpose))
    if isinstance(candidate, Mapping):
        candidate = _first(candidate, "eligible", "value")
    return candidate is True


def _reason_codes(lap: Mapping[str, Any], purpose: str) -> list[str]:
    eligibility = _mapping(lap.get("eligibility"))
    result = _mapping(lap.get("eligibility_result"))
    if not eligibility and result:
        eligibility = _mapping(result.get("eligibility", result))
    reasons = _mapping(eligibility.get("reasons")).get(purpose, [])
    if isinstance(reasons, str):
        return [reasons]
    return [str(item) for item in reasons] if isinstance(reasons, (list, tuple)) else []


def _sort_laps(laps: Iterable[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    records = [_lap_record(lap) for lap in laps if isinstance(lap, Mapping)]
    return sorted(enumerate(records), key=lambda item: (
        _number(item[1].get("lap_number")) is None,
        _number(item[1].get("lap_number")) if _number(item[1].get("lap_number")) is not None else item[0],
        _number(item[1].get("completed_at_s")) is None,
        _number(item[1].get("completed_at_s")) if _number(item[1].get("completed_at_s")) is not None else item[0],
        str(item[1].get("lap_id") or ""),
    ))


@dataclass(frozen=True)
class StintCalculationConfig:
    policy: str = "OPERATIONAL"
    active_regime: str | None = None
    representative_method: str = "MEDIAN"
    representative_version: str = ESTIMATOR_VERSION
    max_sample_references: int = 32
    stale_after_s: float = 180.0
    refuel_boundary_l: float = 1.0
    split_on_compound_change: bool = True
    pace_target_s: float | None = None
    fuel_target_l: float | None = None
    tyre_targets: Mapping[str, Any] = field(default_factory=dict)
    now_s: float | None = None

    @classmethod
    def from_value(cls, value: "StintCalculationConfig | Mapping[str, Any] | None") -> "StintCalculationConfig":
        if isinstance(value, cls):
            return value
        raw = dict(value or {})
        return cls(
            policy=str(raw.get("policy", "OPERATIONAL")),
            active_regime=_regime(raw.get("active_regime", raw.get("regime"))),
            representative_method=str(raw.get("representative_method", "MEDIAN")).upper(),
            representative_version=str(raw.get("representative_version", ESTIMATOR_VERSION)),
            max_sample_references=max(1, int(raw.get("max_sample_references", 32))),
            stale_after_s=max(0.0, float(raw.get("stale_after_s", 180.0))),
            refuel_boundary_l=float(raw.get("refuel_boundary_l", 1.0)),
            split_on_compound_change=bool(raw.get("split_on_compound_change", True)),
            pace_target_s=_number(raw.get("pace_target_s", raw.get("target_pace_s"))),
            fuel_target_l=_number(raw.get("fuel_target_l", raw.get("target_fuel_l"))),
            tyre_targets=_copy(raw.get("tyre_targets", {})) if isinstance(raw.get("tyre_targets", {}), Mapping) else {},
            now_s=_number(raw.get("now_s")),
        )


@dataclass(frozen=True)
class _Boundary:
    sort_key: tuple[Any, ...]
    reason: str
    event_id: str | None
    lap_number: float | None
    event_time_s: float | None


def _boundary_reason(event: Mapping[str, Any], config: StintCalculationConfig) -> str | None:
    kind = _event_type(event)
    payload = _mapping(event.get("payload"))
    if kind in {"STINT_STARTED", "DRIVER_DEFINED_STINT_START", "STINT_BOUNDARY", "SESSION_RESTART", "RESTART"}:
        return "EXPLICIT_STINT_BOUNDARY"
    if kind in {"PIT_EXIT_CANDIDATE", "PIT_EXIT_CONFIRMED", "PIT_LANE_EXITED", "PIT_EXITED", "PIT_BOX_DEPARTURE"}:
        return "PIT_CYCLE_EXIT"
    if kind == "REFUEL" and (_number(_first(payload, "delta_l", "refuel_l", "amount_l")) or 0.0) >= config.refuel_boundary_l:
        return "MATERIAL_REFUEL"
    if kind in {"COMPOUND_CHANGED", "TYRE_COMPOUND_CHANGED", "TYRE_SET_CHANGED"}:
        return "TYRE_CHANGE"
    return None


def _boundaries(events: Iterable[Mapping[str, Any]], config: StintCalculationConfig) -> list[_Boundary]:
    result: list[_Boundary] = []
    for index, event in enumerate(events):
        if not isinstance(event, Mapping):
            continue
        reason = _boundary_reason(event, config)
        if reason is None:
            continue
        payload = _mapping(event.get("payload"))
        lap_number = _number(_first(payload, "lap_number", "completed_lap_number"))
        event_time = _event_time(event)
        sequence = _number(event.get("sequence"))
        result.append(_Boundary(
            (sequence is None, sequence if sequence is not None else index, event_time is None, event_time if event_time is not None else index, str(event.get("event_id") or "")),
            reason,
            str(event.get("event_id")) if event.get("event_id") is not None else None,
            lap_number,
            event_time,
        ))
    result.sort(key=lambda boundary: boundary.sort_key)
    pit_exit_times = [boundary.event_time_s for boundary in result if boundary.reason == "PIT_CYCLE_EXIT" and boundary.event_time_s is not None]
    # A material refuel observed during a pit cycle and its later pit exit are
    # one stint boundary, unless the producer supplied an explicit boundary
    # event. Refuel-only evidence still creates a boundary.
    return [
        boundary
        for boundary in result
        if not (
            boundary.reason == "MATERIAL_REFUEL"
            and boundary.event_time_s is not None
            and any(exit_time >= boundary.event_time_s for exit_time in pit_exit_times)
        )
    ]


def _compound(lap: Mapping[str, Any]) -> str | None:
    value = _first(lap, "compound", "tyre_compound")
    return str(value).upper() if value is not None else None


def _current_snapshot_value(snapshot: Mapping[str, Any] | None, *keys: str) -> Any:
    snapshot = snapshot or {}
    value = _first(snapshot, *keys)
    if value is not None:
        return value
    car = _mapping(snapshot.get("car"))
    value = _first(car, *keys)
    if value is not None:
        return value
    return _first(_mapping(snapshot.get("session")), *keys)


def _wheel_records(value: Any) -> dict[str, Mapping[str, Any]]:
    source = _mapping(value)
    wheels = source.get("wheels", source)
    result: dict[str, Mapping[str, Any]] = {}
    aliases = {"FRONT_LEFT": "FL", "FRONT_RIGHT": "FR", "REAR_LEFT": "RL", "REAR_RIGHT": "RR", "LF": "FL", "RF": "FR", "LR": "RL", "RR": "RR"}
    for key, record in wheels.items():
        normalized = aliases.get(_token(key), _token(key))
        if normalized in WHEELS and isinstance(record, Mapping):
            result[normalized] = record
    return result


def _wheel_value(record: Mapping[str, Any], metric: str) -> float | None:
    aliases = {
        "temperature_c": ("temperature_c", "temp_c", "temperature"),
        "pressure": ("pressure", "pressure_psi", "pressure_kpa"),
        "wear": ("wear", "wear_pct", "life"),
    }
    return _number(_first(record, *aliases.get(metric, (metric,))))


def _sample_refs(laps: Sequence[Mapping[str, Any]], config: StintCalculationConfig) -> list[str]:
    return [str(lap.get("lap_id")) for lap in laps[-config.max_sample_references:] if lap.get("lap_id") is not None]


def _confidence(samples: Sequence[float], *, fresh: bool = True) -> tuple[str, list[str]]:
    if not samples:
        return "UNAVAILABLE", ["NO_ELIGIBLE_SAMPLES"]
    reasons = [f"SAMPLE_COUNT_{'HIGH' if len(samples) >= 5 else 'MEDIUM' if len(samples) >= 2 else 'LOW'}"]
    if len(samples) >= 2:
        center = float(median(samples))
        spread = max(samples) - min(samples)
        if center and spread / abs(center) <= 0.03:
            reasons.append("LOW_DISPERSION")
        else:
            reasons.append("MEASURED_DISPERSION")
    reasons.append("FRESH_SAMPLE" if fresh else "STALE_SAMPLE")
    return ("HIGH" if len(samples) >= 5 and reasons[-2] == "LOW_DISPERSION" else "MEDIUM" if len(samples) >= 2 else "LOW"), reasons


def _freshness(latest: Mapping[str, Any] | None, config: StintCalculationConfig) -> float | None:
    now = config.now_s
    completed = _number((latest or {}).get("completed_at_s"))
    if now is None or completed is None:
        return None
    return max(0.0, float(now) - float(completed))


def _calculated(
    value: Any,
    *,
    unit: str,
    samples: Sequence[Mapping[str, Any]],
    rejected: Sequence[Mapping[str, Any]],
    regime: str | None,
    config: StintCalculationConfig,
    unavailable_reason: str | None = None,
    method: str = "ARITHMETIC_MEAN",
    latest: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    numeric = [float(item["value"]) for item in samples if _number(item.get("value")) is not None]
    age = _freshness(latest, config)
    fresh = age is None or age <= config.stale_after_s
    confidence, confidence_reasons = _confidence(numeric, fresh=fresh)
    if unavailable_reason is not None:
        confidence = "UNAVAILABLE"
    accepted_refs = [str(item.get("lap_id")) for item in samples if item.get("lap_id") is not None]
    rejected_refs = [str(item.get("lap_id")) for item in rejected if item.get("lap_id") is not None]
    return {
        **calculated_value(
            value=value,
            unit=unit,
            calculation_version=f"{CALCULATION_VERSION}:{method.lower()}",
            source_fields=["completed-lap-v1", "eligibility-v1"],
            source_events=[],
            accepted_samples=accepted_refs[-32:],
            rejected_samples=rejected_refs[-32:],
            sample_count=len(numeric),
            regime=regime,
            policy=config.policy,
            freshness_s=age,
            confidence=confidence,
            uncertainty={"method": method, "confidence_reason_codes": confidence_reasons},
            binding_constraint=None,
            unavailable_reason=unavailable_reason,
        ),
    }


def _empty_value(unit: str, *, regime: str | None, config: StintCalculationConfig, reason: str = "NO_ELIGIBLE_SAMPLES") -> dict[str, Any]:
    return _calculated(None, unit=unit, samples=[], rejected=[], regime=regime, config=config, unavailable_reason=reason)


def _metric_samples(laps: Sequence[Mapping[str, Any]], purpose: str, extractor, active_regime: str | None) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    accepted: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    for lap in laps:
        value = extractor(lap)
        compatible = active_regime is None or _lap_regime(lap) is None or _lap_regime(lap) == active_regime
        record = {"lap_id": lap.get("lap_id"), "value": value, "regime": _lap_regime(lap), "completed_at_s": lap.get("completed_at_s")}
        if _eligibility(lap, purpose) and value is not None and compatible:
            accepted.append(record)
        elif lap.get("lap_id") is not None:
            rejected.append({**record, "reason_codes": _reason_codes(lap, purpose) or (["REGIME_MISMATCH"] if not compatible else ["INELIGIBLE_OR_MISSING_MEASUREMENT"])})
    return accepted, rejected


def _mean(samples: Sequence[Mapping[str, Any]]) -> float | None:
    values = [float(item["value"]) for item in samples if _number(item.get("value")) is not None]
    return sum(values) / len(values) if values else None


def _representative(samples: Sequence[Mapping[str, Any]], config: StintCalculationConfig) -> float | None:
    values = [float(item["value"]) for item in samples if _number(item.get("value")) is not None]
    if not values:
        return None
    if config.representative_method != "MEDIAN":
        raise ValueError(f"unsupported representative estimator: {config.representative_method}")
    return float(median(values))


def _delta(value: Mapping[str, Any], target: float | None, *, reference: str, unit: str) -> dict[str, Any]:
    measured = _number(value.get("value"))
    return {"value": measured, "target": target, "delta": measured - target if measured is not None and target is not None else None, "unit": unit, "reference": reference, "unavailable_reason": None if target is not None and measured is not None else "TARGET_NOT_CONFIGURED" if target is None else value.get("unavailable_reason")}


def _latest_completed(laps: Sequence[Mapping[str, Any]], purpose: str | None = None) -> Mapping[str, Any] | None:
    candidates = [lap for lap in laps if purpose is None or _eligibility(lap, purpose)]
    return candidates[-1] if candidates else None


def _latest_summary(lap: Mapping[str, Any] | None, purpose: str, value: float | None, unit: str, config: StintCalculationConfig, regime: str | None) -> dict[str, Any]:
    if lap is None or value is None:
        return _empty_value(unit, regime=regime, config=config, reason="NO_ELIGIBLE_SAMPLES")
    return _calculated(value, unit=unit, samples=[{"lap_id": lap.get("lap_id"), "value": value}], rejected=[], regime=regime, config=config, latest=lap, method="LATEST_ACCEPTED")


def _lap_status(lap: Mapping[str, Any], purpose: str, value: float | None) -> dict[str, Any]:
    eligible = _eligibility(lap, purpose)
    return {"lap_id": lap.get("lap_id"), "value": value, "unit": "L", "status": "ELIGIBLE" if eligible and value is not None else "EXCLUDED" if not eligible else "UNAVAILABLE", "official_validity": lap.get("official_validity"), "classification": lap.get("classification"), "reason_codes": _reason_codes(lap, purpose)}


def _tyre_summary(laps: Sequence[Mapping[str, Any]], current_snapshot: Mapping[str, Any] | None, active_regime: str | None, config: StintCalculationConfig) -> dict[str, Any]:
    current_tyre_source = _mapping((current_snapshot or {}).get("tyres"))
    if not current_tyre_source:
        current_tyre_source = _mapping(_mapping((current_snapshot or {}).get("car")).get("tyres"))
    current_wheels = _wheel_records(current_tyre_source)
    current: dict[str, Any] = {"temperature_c": {}, "pressure": {}, "wear": {}, "flat_spot": {}}
    for wheel in WHEELS:
        record = current_wheels.get(wheel, {})
        for metric in ("temperature_c", "pressure", "wear"):
            value = _wheel_value(record, metric)
            if value is not None:
                current[metric][wheel] = value
        flat = _first(record, "flat_spot", "flat_spot_state")
        if flat is not None:
            current["flat_spot"][wheel] = flat

    accepted = [lap for lap in laps if _eligibility(lap, "useForTyres") and isinstance(lap.get("tyres", lap.get("tyre_measurements", lap.get("tyre"))), Mapping) and (active_regime is None or _lap_regime(lap) is None or _lap_regime(lap) == active_regime)]
    accepted = [lap for lap in accepted if _wheel_records(lap.get("tyres", lap.get("tyre_measurements", lap.get("tyre"))))]
    if accepted:
        first_wheels = _wheel_records(accepted[0].get("tyres", accepted[0].get("tyre_measurements", accepted[0].get("tyre"))))
        last_wheels = _wheel_records(accepted[-1].get("tyres", accepted[-1].get("tyre_measurements", accepted[-1].get("tyre"))))
    else:
        first_wheels = last_wheels = {}
    trends: dict[str, Any] = {}
    for wheel in WHEELS:
        per_wheel: dict[str, Any] = {}
        for metric in ("temperature_c", "pressure", "wear"):
            values = []
            for lap in accepted:
                wheels = _wheel_records(lap.get("tyres", lap.get("tyre_measurements", lap.get("tyre"))))
                value = _wheel_value(wheels.get(wheel, {}), metric)
                if value is not None:
                    values.append(value)
            if values:
                per_wheel[metric] = {"first": values[0], "latest": values[-1], "delta": values[-1] - values[0], "sample_count": len(values)}
        if per_wheel:
            trends[wheel] = per_wheel
    min_max = None
    source_wheels = last_wheels or current_wheels
    temperatures = [_wheel_value(source_wheels.get(wheel, {}), "temperature_c") for wheel in WHEELS]
    temperatures = [value for value in temperatures if value is not None]
    if temperatures:
        min_max = {"min_c": min(temperatures), "max_c": max(temperatures)}
    unsupported = {metric: _empty_value("", regime=active_regime, config=config, reason="UNSUPPORTED_MEASUREMENT") for metric in ("graining", "blistering")}
    warning = _first(current_tyre_source, "strongest_warning", "warning", "warning_level", "flat_spot_warning")
    target_deltas: dict[str, Any] = {}
    for metric, target in config.tyre_targets.items():
        if isinstance(target, Mapping):
            target_value = _number(_first(target, "target", "value"))
        else:
            target_value = _number(target)
        measured = _number(_first(current_tyre_source, metric))
        target_deltas[metric] = {"value": measured, "target": target_value, "delta": measured - target_value if measured is not None and target_value is not None else None, "unavailable_reason": None if measured is not None and target_value is not None else "TARGET_NOT_CONFIGURED" if target_value is None else "MEASUREMENT_UNAVAILABLE"}
    return {
        "current": current,
        "current_lap_min_max_temperature_c": min_max,
        "trend": trends,
        "stint_start_to_current_change": trends,
        "strongest_verified_warning": warning,
        "unsupported": unsupported,
        "targets": _copy(dict(config.tyre_targets)),
        "target_deltas": target_deltas,
        "accepted_sample_count": len(accepted),
        "accepted_sample_references": _sample_refs(accepted, config),
    }


class StintCalculationEngine:
    """Calculate the current stint without mutating inputs or projecting endpoints."""

    def __init__(self, config: StintCalculationConfig | Mapping[str, Any] | None = None) -> None:
        self.config = StintCalculationConfig.from_value(config)

    def _assign_stints(self, laps: Sequence[Mapping[str, Any]], events: Iterable[Mapping[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
        config = self.config
        boundaries = _boundaries(events, config)
        boundary_index = 0
        assigned: list[dict[str, Any]] = []
        stints: dict[str, dict[str, Any]] = {}
        current_identity: str | None = None
        stint_number = 0
        current_stint_id: str | None = None
        previous_compound: str | None = None
        lap_counts: dict[str, int] = {}
        used_boundary_keys: set[tuple[Any, ...]] = set()
        for lap in laps:
            identity = _identity(lap)
            if current_identity is None or identity != current_identity:
                current_identity = identity
                stint_number = 1
                current_stint_id = f"stint:{identity}:{stint_number}"
                previous_compound = None
            else:
                compound = _compound(lap)
                if config.split_on_compound_change and previous_compound and compound and compound != previous_compound:
                    stint_number += 1
                    current_stint_id = f"stint:{identity}:{stint_number}"
            lap_time = _number(lap.get("completed_at_s"))
            lap_number = _number(lap.get("lap_number"))
            while boundary_index < len(boundaries):
                boundary = boundaries[boundary_index]
                qualifies_by_lap = boundary.lap_number is not None and lap_number is not None and lap_number >= boundary.lap_number
                qualifies_by_time = boundary.event_time_s is not None and lap_time is not None and lap_time >= boundary.event_time_s
                qualifies_unpositioned = boundary.lap_number is None and boundary.event_time_s is None and bool(assigned)
                if not (qualifies_by_lap or qualifies_by_time or qualifies_unpositioned):
                    break
                boundary_index += 1
                dedupe = (boundary.event_time_s, boundary.lap_number) if boundary.event_time_s is not None or boundary.lap_number is not None else (boundary.reason,)
                if dedupe in used_boundary_keys:
                    continue
                used_boundary_keys.add(dedupe)
                if current_stint_id is not None and assigned:
                    stint_number += 1
                    current_stint_id = f"stint:{identity}:{stint_number}"
            assert current_stint_id is not None
            lap_counts[current_stint_id] = lap_counts.get(current_stint_id, 0) + 1
            stint_lap_number = lap_counts[current_stint_id]
            enriched = _copy(dict(lap))
            enriched["stint_id"] = current_stint_id
            enriched["stint_number"] = stint_number
            enriched["stint_lap_number"] = stint_lap_number
            assigned.append(enriched)
            state = stints.setdefault(current_stint_id, {"stint_id": current_stint_id, "stint_number": stint_number, "identity_key": identity, "lap_ids": [], "stint_lap_numbers": [], "start_time_s": lap.get("started_at_s", lap.get("completed_at_s")), "end_time_s": None})
            state["lap_ids"].append(lap.get("lap_id"))
            state["stint_lap_numbers"].append(stint_lap_number)
            state["end_time_s"] = lap.get("completed_at_s", state["end_time_s"])
            previous_compound = _compound(lap) or previous_compound
        return assigned, stints

    def calculate(self, laps: Iterable[Mapping[str, Any]], events: Iterable[Mapping[str, Any]] = (), *, current_snapshot: Mapping[str, Any] | None = None) -> Mapping[str, Any]:
        event_list = [event for event in events if isinstance(event, Mapping)]
        ordered_pairs = _sort_laps(laps)
        ordered = [record for _, record in ordered_pairs]
        assigned, stints = self._assign_stints(ordered, event_list)
        for stint_id, state in stints.items():
            historical_laps = [lap for lap in assigned if lap.get("stint_id") == stint_id]
            historical_regime = _lap_regime(historical_laps[-1]) if historical_laps else None
            historical_pace, _ = _metric_samples(historical_laps, "useForPace", _lap_time, historical_regime)
            historical_fuel, _ = _metric_samples(historical_laps, "useForFuel", _fuel_use, historical_regime)
            state["completed_laps"] = len(historical_laps)
            state["regime"] = historical_regime
            state["operational_pace_average_s"] = _mean(historical_pace)
            state["representative_pace_s"] = _representative(historical_pace, self.config)
            state["operational_fuel_average_l"] = _mean(historical_fuel)
            state["representative_fuel_use_l"] = _representative(historical_fuel, self.config)
            state["accepted_sample_counts"] = {"pace": len(historical_pace), "fuel": len(historical_fuel)}
        current_stint_id = assigned[-1]["stint_id"] if assigned else None
        current_laps = [lap for lap in assigned if lap.get("stint_id") == current_stint_id]
        active_regime = self.config.active_regime
        if active_regime is None:
            active_regime = _regime(_first(_mapping((current_snapshot or {}).get("environment")), "weather_regime", "regime"))
        if active_regime is None and current_laps:
            active_regime = _lap_regime(current_laps[-1])

        latest_completed = current_laps[-1] if current_laps else None
        latest_completed_status = None
        if latest_completed is not None:
            latest_completed_status = {
                "lap_id": latest_completed.get("lap_id"),
                "lap_time_s": _lap_time(latest_completed),
                "official_validity": latest_completed.get("official_validity"),
                "classification": latest_completed.get("classification"),
                "eligibility": _copy(_mapping(latest_completed.get("eligibility"))),
                "exclusion_reasons": {purpose: _reason_codes(latest_completed, purpose) for purpose in ("useForPace", "useForFuel", "useForTyres", "useForProjection", "useForOfficialAverage") if not _eligibility(latest_completed, purpose)},
                "stint_id": current_stint_id,
                "stint_lap_number": latest_completed.get("stint_lap_number"),
            }

        pace_accepted, pace_rejected = _metric_samples(current_laps, "useForPace", _lap_time, active_regime)
        official_accepted, official_rejected = _metric_samples(current_laps, "useForOfficialAverage", _lap_time, active_regime=None)
        fuel_accepted, fuel_rejected = _metric_samples(current_laps, "useForFuel", _fuel_use, active_regime)
        latest_pace_lap = current_laps[max((index for index, lap in enumerate(current_laps) if any(sample.get("lap_id") == lap.get("lap_id") for sample in pace_accepted)), default=-1)] if pace_accepted else None
        latest_fuel_lap = current_laps[max((index for index, lap in enumerate(current_laps) if any(sample.get("lap_id") == lap.get("lap_id") for sample in fuel_accepted)), default=-1)] if fuel_accepted else None

        official_avg = _calculated(_mean(official_accepted), unit="s", samples=official_accepted, rejected=official_rejected, regime=None, config=self.config, unavailable_reason=None if official_accepted else "NO_OFFICIAL_VALID_SAMPLES", latest=official_accepted[-1] if official_accepted else None)
        stint_avg = _calculated(_mean(pace_accepted), unit="s", samples=pace_accepted, rejected=pace_rejected, regime=active_regime, config=self.config, unavailable_reason=None if pace_accepted else "NO_PACE_ELIGIBLE_SAMPLES", latest=pace_accepted[-1] if pace_accepted else None)
        representative = _calculated(_representative(pace_accepted, self.config), unit="s", samples=pace_accepted, rejected=pace_rejected, regime=active_regime, config=self.config, unavailable_reason=None if pace_accepted else "NO_PACE_ELIGIBLE_SAMPLES", method=self.config.representative_version, latest=pace_accepted[-1] if pace_accepted else None)
        latest_pace = _latest_summary(latest_pace_lap, "useForPace", _lap_time(latest_pace_lap) if latest_pace_lap else None, "s", self.config, active_regime)
        pace = {
            "latest_completed": latest_completed_status,
            "latest_accepted": latest_pace,
            "official_average": official_avg,
            "operational_stint_average": stint_avg,
            "representative_pace": representative,
            "target_deltas": {
                "latest_accepted": _delta(latest_pace, self.config.pace_target_s, reference="configured_pace_target_s", unit="s"),
                "operational_stint_average": _delta(stint_avg, self.config.pace_target_s, reference="configured_pace_target_s", unit="s"),
                "representative_pace": _delta(representative, self.config.pace_target_s, reference="configured_pace_target_s", unit="s"),
                "latest_vs_operational_stint_average": _delta(latest_pace, _number(stint_avg.get("value")), reference="operational_stint_average", unit="s"),
                "latest_vs_representative_pace": _delta(latest_pace, _number(representative.get("value")), reference="representative_pace", unit="s"),
            },
        }

        latest_completed_fuel = _lap_status(latest_completed, "useForFuel", _fuel_use(latest_completed)) if latest_completed else None
        latest_fuel = _latest_summary(latest_fuel_lap, "useForFuel", _fuel_use(latest_fuel_lap) if latest_fuel_lap else None, "L/lap", self.config, active_regime)
        fuel_avg = _calculated(_mean(fuel_accepted), unit="L/lap", samples=fuel_accepted, rejected=fuel_rejected, regime=active_regime, config=self.config, unavailable_reason=None if fuel_accepted else "NO_FUEL_ELIGIBLE_SAMPLES", latest=fuel_accepted[-1] if fuel_accepted else None)
        representative_fuel = _calculated(_representative(fuel_accepted, self.config), unit="L/lap", samples=fuel_accepted, rejected=fuel_rejected, regime=active_regime, config=self.config, unavailable_reason=None if fuel_accepted else "NO_FUEL_ELIGIBLE_SAMPLES", method=self.config.representative_version, latest=fuel_accepted[-1] if fuel_accepted else None)
        current_fuel = _number(_current_snapshot_value(current_snapshot, "fuel_l", "current_fuel_l"))
        fuel = {
            "current": _calculated(current_fuel, unit="L", samples=[], rejected=[], regime=active_regime, config=self.config, unavailable_reason=None if current_fuel is not None else "MEASUREMENT_UNAVAILABLE", latest=latest_completed),
            "latest_completed_lap_use": latest_completed_fuel,
            "latest_accepted": latest_fuel,
            "operational_stint_average": fuel_avg,
            "representative_use": representative_fuel,
            "target_deltas": {
                "latest_accepted": _delta(latest_fuel, self.config.fuel_target_l, reference="configured_fuel_target_l_per_lap", unit="L/lap"),
                "operational_stint_average": _delta(fuel_avg, self.config.fuel_target_l, reference="configured_fuel_target_l_per_lap", unit="L/lap"),
                "representative_use": _delta(representative_fuel, self.config.fuel_target_l, reference="configured_fuel_target_l_per_lap", unit="L/lap"),
                "latest_vs_operational_stint_average": _delta(latest_fuel, _number(fuel_avg.get("value")), reference="operational_stint_average", unit="L/lap"),
                "latest_vs_representative_use": _delta(latest_fuel, _number(representative_fuel.get("value")), reference="representative_use", unit="L/lap"),
            },
        }

        first_state = stints.get(current_stint_id or "", {})
        current_time = _number(_first(current_snapshot or {}, "observed_monotonic_s", "session_time_s"))
        end_time = current_time if current_time is not None else (latest_completed.get("completed_at_s") if latest_completed else None)
        start_time = first_state.get("start_time_s")
        elapsed = float(end_time) - float(start_time) if _number(end_time) is not None and _number(start_time) is not None else None
        current_lap_number = _number(_current_snapshot_value(current_snapshot, "current_lap"))
        if current_lap_number is not None and current_laps and _number(current_laps[0].get("lap_number")) is not None:
            current_stint_lap = int(current_lap_number - float(current_laps[0].get("lap_number")) + 1)
        else:
            current_stint_lap = len(current_laps) + 1 if current_laps else None
        progress = {
            "current_stint_id": current_stint_id,
            "stint_number": first_state.get("stint_number"),
            "current_stint_lap": current_stint_lap,
            "completed_stint_laps": len(current_laps),
            "stint_start_time_s": start_time,
            "elapsed_stint_time_s": elapsed,
            "current_regime": active_regime,
            "calculation_paused": _mapping((current_snapshot or {}).get("session")).get("paused") is True,
            "accepted_sample_counts": {"pace": len(pace_accepted), "fuel": len(fuel_accepted), "tyres": _tyre_summary(current_laps, current_snapshot, active_regime, self.config)["accepted_sample_count"], "projection": sum(1 for lap in current_laps if _eligibility(lap, "useForProjection")), "official_average": len(official_accepted)},
            "latest_completed_status": latest_completed_status,
        }
        tyres = _tyre_summary(current_laps, current_snapshot, active_regime, self.config)
        boundary_event_ids = [str(event.get("event_id")) for event in event_list if _boundary_reason(event, self.config) is not None and event.get("event_id") is not None]
        result = {
            "schema_version": "stint-calculation-v1",
            "calculation_version": CALCULATION_VERSION,
            "policy": self.config.policy,
            "representative_estimator": {"method": self.config.representative_method, "version": self.config.representative_version},
            "progress": progress,
            "pace": pace,
            "fuel": fuel,
            "tyres": tyres,
            "stints": list(stints.values()),
            "boundary_event_references": boundary_event_ids[-self.config.max_sample_references :],
            "accepted_sample_references": {"pace": _sample_refs(pace_accepted, self.config), "fuel": _sample_refs(fuel_accepted, self.config), "official_average": _sample_refs(official_accepted, self.config)},
            "confidence_reasons": {"pace": representative["uncertainty"]["confidence_reason_codes"], "fuel": representative_fuel["uncertainty"]["confidence_reason_codes"]},
        }
        return _freeze(result)

    def calculate_stint(self, laps: Iterable[Mapping[str, Any]], events: Iterable[Mapping[str, Any]] = (), *, current_snapshot: Mapping[str, Any] | None = None) -> Mapping[str, Any]:
        return self.calculate(laps, events, current_snapshot=current_snapshot)


StintCalculator = StintCalculationEngine


def calculate_stint(laps: Iterable[Mapping[str, Any]], events: Iterable[Mapping[str, Any]] = (), *, config: StintCalculationConfig | Mapping[str, Any] | None = None, current_snapshot: Mapping[str, Any] | None = None) -> Mapping[str, Any]:
    return StintCalculationEngine(config).calculate(laps, events, current_snapshot=current_snapshot)


def serialize_calculations(result: Mapping[str, Any]) -> bytes:
    return (json.dumps(to_plain(result), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


__all__ = [
    "CALCULATION_VERSION",
    "ESTIMATOR_VERSION",
    "StintCalculationConfig",
    "StintCalculationEngine",
    "StintCalculator",
    "calculate_stint",
    "serialize_calculations",
]
