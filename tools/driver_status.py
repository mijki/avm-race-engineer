"""Stable driver-facing view model for the Race Engine Core V1.

This module reduces normalized snapshot data, immutable calculation output,
forecast output, pit diagnostics, and explicit configuration into stable field
metadata.  It selects, formats, allocates, and traces values; race math and
forecast math stay in their owning layers.
"""

from __future__ import annotations

import copy
import json
import math
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from tools.race_engine_core import to_plain


VIEW_MODEL_VERSION = "driver-status-view-model-v1"
UNAVAILABLE = "UNAVAILABLE"
WHEELS = ("FL", "FR", "RL", "RR")
SEMANTIC_STATES = ("neutral", "informational", "good", "caution", "critical", "unavailable")


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


def _value(metric: Any) -> Any:
    if isinstance(metric, Mapping) and "value" in metric:
        return metric.get("value")
    return metric


def _metric(metric: Any) -> Mapping[str, Any]:
    return metric if isinstance(metric, Mapping) else {"value": metric}


def _confidence(metric: Mapping[str, Any] | None) -> str:
    value = str(_mapping(metric).get("confidence") or "UNAVAILABLE").lower()
    return value if value in {"high", "medium", "low", "unavailable", "blocked"} else "low"


def _availability(value: Any, metric: Mapping[str, Any] | None = None) -> str:
    if value is None:
        return "unavailable"
    if _mapping(metric).get("unavailable_reason"):
        return "degraded"
    return "available"


def _semantic(value: Any, metric: Mapping[str, Any] | None = None, *, default: str = "neutral") -> str:
    explicit = str(_mapping(metric).get("semantic_state") or "").lower()
    if explicit in SEMANTIC_STATES:
        return explicit
    if value is None or _mapping(metric).get("unavailable_reason"):
        return "unavailable"
    return default if default in SEMANTIC_STATES else "neutral"


def _source_layer(metric: Mapping[str, Any] | None, default: str) -> str:
    if _mapping(metric).get("source_layer"):
        return str(metric["source_layer"])
    if _mapping(metric).get("forecast_id") or _mapping(metric).get("model_id"):
        return "forecast"
    if _mapping(metric).get("calculation_version"):
        return "calculation"
    return default


def _trace_id(metric: Mapping[str, Any] | None, fallback: str) -> str:
    value = _mapping(metric).get("forecast_id") or _mapping(metric).get("calculation_id") or _mapping(metric).get("calculation_version")
    return str(value or fallback)


def format_lap_time(seconds: Any) -> str:
    value = _number(seconds)
    if value is None or value < 0:
        return UNAVAILABLE
    milliseconds = int(round((value - math.floor(value)) * 1000))
    whole_seconds = int(math.floor(value))
    if milliseconds == 1000:
        whole_seconds += 1
        milliseconds = 0
    hours, remainder = divmod(whole_seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{secs:02d}.{milliseconds:03d}"
    return f"{minutes}:{secs:02d}.{milliseconds:03d}"


def format_delta(value: Any, unit: str = "s") -> str:
    number = _number(value)
    if number is None:
        return UNAVAILABLE
    sign = "+" if number > 0 else "−" if number < 0 else ""
    return f"{sign}{abs(number):.3f} {unit}"


def format_duration(seconds: Any) -> str:
    value = _number(seconds)
    if value is None or value < 0:
        return UNAVAILABLE
    whole = int(round(value))
    hours, remainder = divmod(whole, 3600)
    minutes, secs = divmod(remainder, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def format_number(value: Any, unit: str = "", places: int = 1) -> str:
    number = _number(value)
    if number is None:
        return UNAVAILABLE
    suffix = f" {unit}" if unit else ""
    return f"{number:.{places}f}{suffix}"


def format_range(metric: Mapping[str, Any] | None, unit: str, places: int = 1) -> str:
    uncertainty = _mapping(_mapping(metric).get("uncertainty"))
    raw = uncertainty.get("range") or uncertainty.get("observed_range")
    if not isinstance(raw, Mapping):
        return format_number(_value(metric), unit, places)
    lower = _number(_first(raw, "lower_bound", "lower"))
    upper = _number(_first(raw, "upper_bound", "upper"))
    if lower is None or upper is None:
        return format_number(_value(metric), unit, places)
    return f"{lower:.{places}f}–{upper:.{places}f} {unit}".strip()


def wind_cardinal(degrees: Any) -> str:
    value = _number(degrees)
    if value is None:
        return UNAVAILABLE
    directions = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    return directions[int(((value % 360) + 22.5) // 45) % 8]


def _field(
    field_id: str,
    label: str,
    raw_value: Any,
    *,
    metric: Mapping[str, Any] | None = None,
    unit: str = "",
    formatted_value: str | None = None,
    semantic_state: str | None = None,
    severity: str | None = None,
    source_layer: str = "view_model",
    comparison_reference: str | None = None,
    unavailable_reason: str | None = None,
    detail: str | None = None,
    trace_id: str | None = None,
    formatter: Any = None,
) -> dict[str, Any]:
    metric = metric or {}
    if unavailable_reason is None:
        unavailable_reason = metric.get("unavailable_reason")
    value = _value(raw_value)
    if formatter is not None and formatted_value is None:
        formatted_value = formatter(value)
    if formatted_value is None:
        formatted_value = format_number(value, unit) if isinstance(value, (int, float)) and not isinstance(value, bool) else str(value) if value is not None else UNAVAILABLE
    state = semantic_state or _semantic(value, metric)
    if unavailable_reason and value is None:
        state = "unavailable"
    if state not in SEMANTIC_STATES:
        state = "neutral"
    return {
        "field_id": field_id,
        "label": label,
        "raw_value": _copy(value),
        "formatted_value": formatted_value,
        "unit": unit,
        "availability": _availability(value, metric) if unavailable_reason is None else "degraded" if value is not None else "unavailable",
        "semantic_state": state,
        "severity": severity or state,
        "confidence": _confidence(metric),
        "freshness_s": metric.get("freshness_s"),
        "source_layer": source_layer or _source_layer(metric, "view_model"),
        "comparison_reference": comparison_reference,
        "unavailable_reason": unavailable_reason,
        "supporting_detail": detail,
        "trace_id": trace_id or _trace_id(metric, field_id),
    }


def _metric_field(field_id: str, label: str, metric: Any, *, unit: str = "", formatter: Any = None, semantic_state: str | None = None, comparison_reference: str | None = None, source_layer: str = "calculation", detail: str | None = None) -> dict[str, Any]:
    record = _metric(metric)
    return _field(field_id, label, record, metric=record, unit=unit, formatter=formatter, semantic_state=semantic_state, comparison_reference=comparison_reference, source_layer=_source_layer(record, source_layer), detail=detail)


def _snapshot_value(snapshot: Mapping[str, Any], *keys: str) -> Any:
    value = _first(snapshot, *keys)
    if value is not None:
        return value
    for section in ("session", "car", "environment", "weather", "track"):
        value = _first(_mapping(snapshot.get(section)), *keys)
        if value is not None:
            return value
    return None


def _target(calculation: Mapping[str, Any], section: str, name: str, targets: Mapping[str, Any]) -> float | None:
    delta = _mapping(_mapping(calculation.get(section)).get("target_deltas")).get(name)
    value = _number(_mapping(delta).get("target"))
    if value is not None:
        return value
    keys = ("pace_target_s", "target_pace_s", "pace_s") if section == "pace" else ("fuel_target_l", "target_fuel_per_lap_l", "fuel_l")
    return _number(_first(targets, *keys))


def _target_delta(calculation: Mapping[str, Any], section: str, name: str) -> Mapping[str, Any]:
    return _mapping(_mapping(calculation.get(section)).get("target_deltas")).get(name, {})


def _wheel_source(calculation: Mapping[str, Any], snapshot: Mapping[str, Any], wheel: str) -> dict[str, Any]:
    current = _mapping(_mapping(calculation.get("tyres")).get("current"))
    tyre_snapshot = _mapping(_snapshot_value(snapshot, "tyres", "tyre"))
    wheels = _mapping(tyre_snapshot.get("wheels", tyre_snapshot))
    source = _mapping(wheels.get(wheel))
    return {
        "temperature_c": _first(current.get("temperature_c", {}), wheel) if isinstance(current.get("temperature_c"), Mapping) else _first(source, "temperature_c", "temp_c", "temperature"),
        "pressure": _first(current.get("pressure", {}), wheel) if isinstance(current.get("pressure"), Mapping) else _first(source, "pressure", "pressure_psi", "pressure_kpa"),
        "wear": _first(current.get("wear", {}), wheel) if isinstance(current.get("wear"), Mapping) else _first(source, "wear", "wear_pct", "life"),
        "compound": _first(source, "compound", "tyre_compound") or _snapshot_value(snapshot, "compound", "tyre_compound"),
        "flat_spot": _first(source, "flat_spot", "flat_spot_state"),
    }


def _trust_state(value: Any, *, default: str, neutral: bool = False) -> dict[str, Any]:
    state = str(value or default).upper().replace("_", " ")
    if state in {"NOT USED", "NOT ASSIGNED"}:
        return {"state": state, "semantic_state": "neutral", "severity": "neutral", "shape": "hollow", "label": state}
    semantic = "good" if state in {"LIVE", "CONNECTED"} else "caution" if state in {"PARTIAL", "STALE", "DEGRADED"} else "critical" if state in {"OFFLINE", "DISCONNECTED", "LOST"} else "neutral" if neutral else "unavailable"
    shape = "filled" if semantic == "good" else "warning" if semantic == "caution" else "crossed" if semantic == "critical" else "hollow"
    return {"state": state, "semantic_state": semantic, "severity": semantic, "shape": shape, "label": state}


def _tel_state(snapshot: Mapping[str, Any], source_status: Mapping[str, Any]) -> str:
    value = _first(source_status, "TEL", "tel", "telemetry", "source_health")
    if value is not None:
        return str(value).upper()
    value = _first(snapshot, "source_health", "source_availability", "connection_state")
    if value is None:
        return "LIVE" if snapshot else "OFFLINE"
    token = str(value).upper()
    return {"LIVE": "LIVE", "PARTIAL": "PARTIAL", "STALE": "STALE", "OFFLINE": "OFFLINE", "DISCONNECTED": "OFFLINE", "UNAVAILABLE": "OFFLINE"}.get(token, "PARTIAL")


def _condition(value: Any, snapshot: Mapping[str, Any]) -> str | None:
    if value is None:
        value = _snapshot_value(snapshot, "weather_type", "condition", "current_weather_type")
    if value is None:
        return None
    token = str(value).strip().upper()
    labels = {"0": "Dry", "DRY": "Dry", "CLEAR": "Dry", "1": "Damp", "DAMP": "Damp", "2": "Wet", "WET": "Wet", "HEAVY_RAIN": "Heavy rain", "STANDING_WATER": "Standing water"}
    if token.startswith("CURRENT"):
        token = token.split(" ", 1)[0]
    return labels.get(token, token.replace("_", " ").title())


@dataclass(frozen=True)
class DriverStatusConfig:
    mode: str = "compact"
    generated_at_utc: str | None = None
    valid_until_utc: str | None = None
    targets: Mapping[str, Any] = None  # type: ignore[assignment]
    bridge_state: str = "NOT USED"
    engineer_state: str = "NOT ASSIGNED"

    @classmethod
    def from_value(cls, value: "DriverStatusConfig | Mapping[str, Any] | None", mode: str | None = None) -> "DriverStatusConfig":
        if isinstance(value, cls):
            return value if mode is None else cls(mode=mode, generated_at_utc=value.generated_at_utc, valid_until_utc=value.valid_until_utc, targets=value.targets, bridge_state=value.bridge_state, engineer_state=value.engineer_state)
        raw = dict(value or {})
        return cls(mode=str(mode or raw.get("mode", "compact")).lower(), generated_at_utc=raw.get("generated_at_utc"), valid_until_utc=raw.get("valid_until_utc"), targets=_copy(raw.get("targets", {})), bridge_state=str(raw.get("bridge_state", "NOT USED")), engineer_state=str(raw.get("engineer_state", "NOT ASSIGNED")))


class DriverStatusViewModel:
    """Build a stable, traceable status model without owning race math."""

    def __init__(self, config: DriverStatusConfig | Mapping[str, Any] | None = None) -> None:
        self.config = DriverStatusConfig.from_value(config)

    def _pace(self, calculation: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        pace = _mapping(calculation.get("pace"))
        targets = self.config.targets or {}
        target = _target(calculation, "pace", "latest_accepted", targets)
        latest = _mapping(pace.get("latest_accepted"))
        average = _mapping(pace.get("operational_stint_average"))
        representative = _mapping(pace.get("representative_pace"))
        official = _mapping(pace.get("official_average"))
        latest_delta = _target_delta(calculation, "pace", "latest_accepted")
        average_delta = _target_delta(calculation, "pace", "operational_stint_average")
        if target is not None:
            fields["pace.target"] = _field("pace.target", "TARGET", target, metric={"value": target}, unit="s", formatter=format_lap_time, source_layer="configuration", detail="Configured target pace")
        fields["pace.latest"] = _metric_field("pace.latest", "LAST", latest, unit="s", formatter=format_lap_time, detail="Latest completed pace-eligible lap")
        fields["pace.stint_average"] = _metric_field("pace.stint_average", "STINT AVG", average, unit="s", formatter=format_lap_time, detail="Arithmetic current-regime pace average")
        fields["pace.latest_vs_target"] = _field("pace.latest_vs_target", "LAST VS TARGET", latest_delta.get("delta"), metric=latest_delta, unit="s", formatter=format_delta, comparison_reference="configured_pace_target_s", detail="Signed latest accepted pace minus configured target")
        fields["pace.stint_average_vs_target"] = _field("pace.stint_average_vs_target", "STINT AVG VS TARGET", average_delta.get("delta"), metric=average_delta, unit="s", formatter=format_delta, comparison_reference="configured_pace_target_s", detail="Signed operational average minus configured target")
        fields["pace.latest_vs_average"] = _field("pace.latest_vs_average", "LAST VS STINT AVG", _mapping(_target_delta(calculation, "pace", "latest_vs_operational_stint_average")).get("delta"), metric=_target_delta(calculation, "pace", "latest_vs_operational_stint_average"), unit="s", formatter=format_delta, comparison_reference="operational_stint_average")
        fields["pace.representative"] = _metric_field("pace.representative", "REP PACE", representative, unit="s", formatter=format_lap_time, detail="Versioned robust estimator")
        fields["pace.official_average"] = _metric_field("pace.official_average", "OFFICIAL AVG", official, unit="s", formatter=format_lap_time)
        latest_completed = _mapping(pace.get("latest_completed"))
        fields["pace.latest_completed"] = _field("pace.latest_completed", "LATEST COMPLETED", latest_completed.get("lap_time_s"), metric={"value": latest_completed.get("lap_time_s"), "unavailable_reason": None if latest_completed else "NO_COMPLETED_LAP"}, unit="s", formatter=format_lap_time, detail="Includes excluded laps for diagnostics")
        excluded_reason = ", ".join(str(value) for value in _mapping(latest_completed.get("exclusion_reasons")).get("useForPace", [])) or None
        fields["pace.latest_exclusion"] = _field("pace.latest_exclusion", "LATEST EXCLUSION", excluded_reason, metric={"value": excluded_reason, "unavailable_reason": None if excluded_reason else "NO_EXCLUDED_LAP"}, source_layer="eligibility", detail="Latest completed lap exclusion reason")
        if target is None:
            fields["pace.targets"] = _field("pace.targets", "TARGET", None, metric={"unavailable_reason": "TARGET_NOT_CONFIGURED"}, source_layer="configuration", detail="Target not set")
        return {"target": target, "latest": _copy(latest), "stint_average": _copy(average), "representative": _copy(representative), "official_average": _copy(official), "sample_counts": {"latest": 1 if latest.get("value") is not None else 0, "stint_average": average.get("sample_count", 0), "official_average": official.get("sample_count", 0)}, "target_configured": target is not None}

    def _fuel(self, calculation: Mapping[str, Any], forecast: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        fuel = _mapping(calculation.get("fuel"))
        targets = self.config.targets or {}
        target = _target(calculation, "fuel", "latest_accepted", targets)
        current = _mapping(fuel.get("current"))
        latest = _mapping(fuel.get("latest_accepted"))
        average = _mapping(fuel.get("operational_stint_average"))
        required = _mapping(forecast.get("fuel", {})).get("required_fuel_per_lap_now", {})
        fields["fuel.current"] = _metric_field("fuel.current", "FUEL", current, unit="L", formatter=lambda value: format_number(value, "L"), detail="Measured current fuel")
        fields["fuel.range_laps"] = _metric_field("fuel.range_laps", "RANGE", _mapping(forecast.get("fuel", {}).get("range_laps")), unit="laps", formatter=lambda value: format_range(_mapping(forecast.get("fuel", {}).get("range_laps")), "laps", 1))
        fields["fuel.latest"] = _metric_field("fuel.latest", "LAST USE", latest, unit="L/lap", formatter=lambda value: format_number(value, "L/lap"), detail="Latest accepted fuel-eligible use")
        fields["fuel.stint_average"] = _metric_field("fuel.stint_average", "STINT AVG", average, unit="L/lap", formatter=lambda value: format_number(value, "L/lap"), detail="Current-regime fuel average")
        fields["fuel.required_per_lap_now"] = _metric_field("fuel.required_per_lap_now", "REQUIRED NOW", required, unit="L/lap", formatter=lambda value: format_number(value, "L/lap"), source_layer="forecast")
        if target is not None:
            target_metric = {"value": target, "unavailable_reason": None}
            fields["fuel.target"] = _field("fuel.target", "TARGET USE", target, metric=target_metric, unit="L/lap", formatter=lambda value: format_number(value, "L/lap"), source_layer="configuration")
            delta = _mapping(_mapping(fuel.get("target_deltas")).get("latest_accepted"))
            fields["fuel.latest_vs_target"] = _field("fuel.latest_vs_target", "LAST VS TARGET", delta.get("delta"), metric=delta, unit="L/lap", formatter=format_delta, comparison_reference="configured_fuel_target_l_per_lap")
        else:
            fields["fuel.targets"] = _field("fuel.targets", "TARGET USE", None, metric={"unavailable_reason": "TARGET_NOT_CONFIGURED"}, source_layer="configuration", detail="Target not set")
        expected_pit = _mapping(forecast.get("fuel", {}).get("expected_at_planned_pit"))
        expected_finish = _mapping(forecast.get("fuel", {}).get("expected_at_finish"))
        fields["fuel.expected_at_pit"] = _metric_field("fuel.expected_at_pit", "AT PIT", expected_pit, unit="L", formatter=lambda value: format_range(expected_pit, "L", 1), source_layer="forecast")
        fields["fuel.expected_at_finish"] = _metric_field("fuel.expected_at_finish", "AT FINISH", expected_finish, unit="L", formatter=lambda value: format_range(expected_finish, "L", 1), source_layer="forecast")
        return {"current": _copy(current), "latest": _copy(latest), "stint_average": _copy(average), "target": target, "range_laps": _copy(_mapping(forecast.get("fuel", {}).get("range_laps"))), "required_per_lap_now": _copy(required), "expected_at_pit": _copy(expected_pit), "expected_at_finish": _copy(expected_finish)}

    def _stint(self, calculation: Mapping[str, Any], forecast: Mapping[str, Any], snapshot: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        progress = _mapping(calculation.get("progress"))
        stint = _mapping(forecast.get("stint"))
        stint_id = progress.get("current_stint_id")
        stint_number = progress.get("stint_number")
        completed = progress.get("completed_stint_laps")
        current_lap = progress.get("current_stint_lap_zero_based", completed)
        race_lap = _snapshot_value(snapshot, "race_lap", "completed_laps")
        if current_lap is None and completed is not None:
            current_lap = completed
        fields["stint.current_stint_number"] = _field("stint.current_stint_number", "STINT", stint_number, metric={"value": stint_number}, unit="", formatter=lambda value: f"STINT {int(value)}" if _number(value) is not None else UNAVAILABLE, source_layer="calculation")
        fields["stint.current_stint_lap"] = _field("stint.current_stint_lap", "STINT LAP", current_lap, metric={"value": current_lap}, unit="", formatter=lambda value: f"LAP {int(value)}" if _number(value) is not None else UNAVAILABLE, source_layer="calculation")
        fields["stint.completed_laps"] = _field("stint.completed_laps", "COMPLETED STINT LAPS", completed, metric={"value": completed}, unit="laps", formatter=lambda value: format_number(value, "laps", 0), source_layer="calculation")
        fields["stint.current_race_lap"] = _field("stint.current_race_lap", "RACE LAP", race_lap, metric={"value": race_lap}, unit="", formatter=lambda value: f"LAP {int(value)}" if _number(value) is not None else UNAVAILABLE, source_layer="telemetry")
        fields["stint.elapsed_time"] = _field("stint.elapsed_time", "STINT ELAPSED", progress.get("elapsed_stint_time_s"), metric={"value": progress.get("elapsed_stint_time_s")}, formatter=format_duration, source_layer="calculation")
        fields["stint.remaining_time"] = _metric_field("stint.remaining_time", "REMAINING TIME", stint.get("remaining_stint_time"), unit="s", formatter=format_duration, source_layer="forecast")
        fields["stint.remaining_laps"] = _metric_field("stint.remaining_laps", "REMAINING LAPS", stint.get("remaining_stint_laps"), unit="laps", formatter=lambda value: format_number(value, "laps", 1), source_layer="forecast")
        fields["stint.binding_constraint"] = _field("stint.binding_constraint", "LIMITING FACTOR", stint.get("binding_constraint"), metric={"value": stint.get("binding_constraint"), "unavailable_reason": None if stint.get("binding_constraint") else "NO_DEFENSIBLE_STINT_ENDPOINT"}, source_layer="forecast")
        previous = progress.get("previous_stint")
        previous_summary = None
        if isinstance(previous, Mapping):
            previous_summary = {"stint_id": previous.get("stint_id"), "stint_number": previous.get("stint_number"), "completed_laps": previous.get("completed_laps", len(previous.get("lap_ids", []))), "pace_s": previous.get("operational_pace_average_s"), "fuel_l_per_lap": previous.get("operational_fuel_average_l")}
        fields["stint.previous_summary"] = _field("stint.previous_summary", "PREVIOUS STINT", previous_summary, metric={"value": previous_summary, "unavailable_reason": None if previous_summary else "NO_PREVIOUS_STINT"}, source_layer="calculation")
        label = f"STINT {int(stint_number)} · LAP {int(current_lap)}" if _number(stint_number) is not None and _number(current_lap) is not None else None
        return {"stint_id": stint_id, "stint_number": stint_number, "current_stint_lap": current_lap, "completed_laps": completed, "race_lap": race_lap, "current_race_lap": race_lap, "previous_summary": previous_summary, "strip_label": label, "binding_constraint": stint.get("binding_constraint")}

    def _tyres(self, calculation: Mapping[str, Any], snapshot: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        tyres = _mapping(calculation.get("tyres"))
        targets = _mapping(tyres.get("targets")) or _mapping(self.config.targets.get("tyre_targets") if self.config.targets else {})
        wheels: dict[str, Any] = {}
        for wheel in WHEELS:
            source = _wheel_source(calculation, snapshot, wheel)
            item: dict[str, Any] = {}
            if source.get("compound") is not None:
                item["compound"] = _field(f"tyres.{wheel}.compound", wheel, source.get("compound"), source_layer="telemetry")
            if source.get("temperature_c") is not None:
                item["temperature"] = _field(f"tyres.{wheel}.temperature", f"{wheel} TEMP", source.get("temperature_c"), unit="°C", formatter=lambda value: format_number(value, "°C", 1), source_layer="calculation")
            if source.get("pressure") is not None:
                item["pressure"] = _field(f"tyres.{wheel}.pressure", f"{wheel} PRESSURE", source.get("pressure"), unit="psi", formatter=lambda value: format_number(value, "psi", 1), source_layer="calculation")
            if source.get("wear") is not None:
                item["wear"] = _field(f"tyres.{wheel}.wear", f"{wheel} WEAR", source.get("wear"), unit="", formatter=lambda value: format_number(value, "", 1), source_layer="calculation")
            if source.get("flat_spot") is not None:
                item["flat_spot"] = _field(f"tyres.{wheel}.flat_spot", f"{wheel} FLAT SPOT", source.get("flat_spot"), source_layer="calculation")
            if targets:
                target_pressure = _number(_mapping(targets.get("pressure")).get(wheel)) if isinstance(targets.get("pressure"), Mapping) else _number(targets.get("pressure"))
                current_pressure = _number(source.get("pressure"))
                if target_pressure is not None and current_pressure is not None:
                    item["pressure_delta"] = _field(f"tyres.{wheel}.pressure_delta", f"{wheel} PRESSURE VS TARGET", current_pressure - target_pressure, metric={"value": current_pressure - target_pressure}, unit="psi", formatter=format_delta, comparison_reference="configured_tyre_pressure_target")
            wheels[wheel] = item
        if not targets:
            fields["tyres.targets"] = _field("tyres.targets", "TYRE TARGETS", None, metric={"unavailable_reason": "TARGETS_NOT_CONFIGURED"}, source_layer="configuration", detail="Targets not set")
        fields["tyres.graining"] = _field("tyres.graining", "GRAINING", None, metric={"unavailable_reason": "UNSUPPORTED_MEASUREMENT"}, source_layer="calculation")
        fields["tyres.blistering"] = _field("tyres.blistering", "BLISTERING", None, metric={"unavailable_reason": "UNSUPPORTED_MEASUREMENT"}, source_layer="calculation")
        return {"wheels": wheels, "targets_configured": bool(targets), "strongest_verified_warning": tyres.get("strongest_verified_warning"), "current_lap_min_max_temperature_c": _copy(tyres.get("current_lap_min_max_temperature_c"))}

    def _weather(self, calculation: Mapping[str, Any], forecast: Mapping[str, Any], snapshot: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        weather = _mapping(calculation.get("weather"))
        current = _mapping(weather.get("current"))
        condition = _condition(_first(current, "weather_type", "condition", "current_weather_type"), snapshot)
        track_condition = str(_first(current, "track_condition", "track_state", "wetness") or _snapshot_value(snapshot, "track_condition", "track_state") or "unknown").lower().replace("standing water", "standing_water")
        if track_condition not in {"dry", "damp", "wet", "standing_water", "unknown"}:
            track_condition = "unknown"
        fields["weather.condition"] = _field("weather.condition", "CONDITION", condition, metric={"value": condition, "unavailable_reason": None if condition else "CURRENT_WEATHER_UNAVAILABLE"}, source_layer="telemetry")
        fields["weather.track_condition"] = _field("weather.track_condition", "TRACK", track_condition, metric={"value": track_condition}, source_layer="telemetry")
        air = _first(current, "air_temperature_c", "ambient_temperature_c", "air_temp_c") or _snapshot_value(snapshot, "air_temperature_c", "ambient_temperature_c")
        road = _first(current, "road_temperature_c", "track_temperature_c", "road_temp_c") or _snapshot_value(snapshot, "road_temperature_c", "track_temperature_c")
        wind_speed = _first(current, "wind_speed_kmh", "wind_speed") or _snapshot_value(snapshot, "wind_speed_kmh", "wind_speed")
        wind_direction = _first(current, "wind_direction_deg", "wind_direction") or _snapshot_value(snapshot, "wind_direction_deg", "wind_direction")
        fields["weather.air_temperature"] = _field("weather.air_temperature", "AIR", air, unit="°C", formatter=lambda value: format_number(value, "°C", 1), source_layer="telemetry")
        fields["weather.road_temperature"] = _field("weather.road_temperature", "ROAD", road, unit="°C", formatter=lambda value: format_number(value, "°C", 1), source_layer="telemetry")
        fields["weather.wind_speed"] = _field("weather.wind_speed", "WIND", wind_speed, unit="km/h", formatter=lambda value: format_number(value, "km/h", 1), source_layer="telemetry")
        fields["weather.wind_direction"] = _field("weather.wind_direction", "WIND DIR", wind_direction, formatted_value=wind_cardinal(wind_direction), source_layer="telemetry", detail=f"{wind_direction}°" if _number(wind_direction) is not None else None)
        future = _mapping(_mapping(forecast.get("weather")).get("future"))
        fields["weather.future"] = _metric_field("weather.future", "FUTURE WEATHER", future, source_layer="forecast", detail="Future conditions require an explicit source")
        return {"condition": condition, "track_condition": track_condition, "air_temperature_c": air, "road_temperature_c": road, "wind_speed_kmh": wind_speed, "wind_cardinal": wind_cardinal(wind_direction), "future": _copy(future), "future_available": _value(future) is not None}

    def _pit(self, forecast: Mapping[str, Any], pit_diagnostics: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        pit = _mapping(forecast.get("pit"))
        live = _mapping(pit.get("live"))
        marker = _mapping(pit.get("marker"))
        fields["pit.live_state"] = _field("pit.live_state", "PIT STATE", live.get("state", pit_diagnostics.get("state", "ON_TRACK")), metric={"value": live.get("state", pit_diagnostics.get("state", "ON_TRACK"))}, source_layer="telemetry")
        fields["pit.marker_state"] = _field("pit.marker_state", "MARKER", marker.get("state"), metric={"value": marker.get("state"), "unavailable_reason": None if marker.get("state") and marker.get("state") != "UNAVAILABLE" else "PIT_ENTRY_NOT_CALIBRATED"}, source_layer="calculation")
        fields["pit.distance_to_entry"] = _metric_field("pit.distance_to_entry", "ENTRY DISTANCE", pit.get("distance_to_entry"), unit="m", formatter=lambda value: format_number(value, "m", 0), source_layer="forecast")
        fields["pit.eta_to_entry"] = _metric_field("pit.eta_to_entry", "ENTRY ETA", pit.get("eta_to_entry"), unit="s", formatter=format_duration, source_layer="forecast")
        fields["pit.expected_fuel_at_entry"] = _metric_field("pit.expected_fuel_at_entry", "FUEL AT ENTRY", pit.get("expected_fuel_at_entry"), unit="L", formatter=lambda value: format_number(value, "L", 1), source_layer="forecast")
        fields["pit.window_state"] = _field("pit.window_state", "PIT WINDOW", pit.get("entry_window_state"), metric={"value": pit.get("entry_window_state"), "unavailable_reason": None if pit.get("entry_window_state") not in (None, "UNKNOWN") else "PIT_WINDOW_NOT_CONFIGURED"}, source_layer="forecast")
        fields["pit.calibration"] = _field("pit.calibration", "PIT CALIBRATION", None if marker.get("state") not in (None, "UNAVAILABLE") else "Pit entry not calibrated", metric={"value": marker.get("state") if marker.get("state") not in (None, "UNAVAILABLE") else None, "unavailable_reason": None if marker.get("state") not in (None, "UNAVAILABLE") else "PIT_ENTRY_NOT_CALIBRATED"}, source_layer="calculation", detail="One concise calibration state")
        cycle = _mapping(pit.get("cycle"))
        fields["pit.total_loss"] = _metric_field("pit.total_loss", "PIT LOSS", cycle.get("total_pit_loss"), unit="s", formatter=format_duration, source_layer="forecast")
        fields["pit.service_duration"] = _metric_field("pit.service_duration", "SERVICE", cycle.get("service_duration"), unit="s", formatter=format_duration, source_layer="forecast")
        return {"live": _copy(live), "marker": _copy(marker), "distance_to_entry": _copy(pit.get("distance_to_entry")), "eta_to_entry": _copy(pit.get("eta_to_entry")), "window_state": pit.get("entry_window_state"), "calibration_available": marker.get("state") not in (None, "UNAVAILABLE"), "cycle": _copy(cycle)}

    def _engineer(self, engineer: Mapping[str, Any] | None, forecast: Mapping[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
        engineer = _mapping(engineer)
        active = _mapping(engineer.get("active", engineer))
        instruction = _first(active, "instruction", "primary_call", "call")
        if instruction is None:
            states = forecast.get("recommendation_states", [])
            instruction = "none" if not states or states == ["ON_PLAN"] else str(states[0]).lower()
        source = str(active.get("source") or "none")
        title = str(active.get("title") or active.get("message") or instruction or "none")
        detail = active.get("detail") or ("No active instruction" if instruction in (None, "none", "on_plan") else "Forecast state requires operator context")
        priority = str(active.get("priority") or "low").lower()
        semantic = "critical" if priority == "critical" else "caution" if priority == "high" else "informational" if instruction not in (None, "none", "on_plan") else "neutral"
        fields["engineer.primary"] = _field("engineer.primary", "ENGINEER", instruction, metric={"value": instruction}, formatted_value=title, semantic_state=semantic, severity=semantic, source_layer="engineer" if source == "engineer" else "forecast" if source != "none" else "view_model", detail=str(detail), trace_id=str(active.get("message_id") or active.get("alert_id") or "engineer:none"))
        fields["engineer.detail"] = _field("engineer.detail", "ENGINEER DETAIL", detail, metric={"value": detail}, source_layer="engineer" if source == "engineer" else "forecast")
        return {"instruction": instruction, "source": source, "title": title, "detail": detail, "priority": priority, "requires_acknowledgement": active.get("requires_acknowledgement") is True}

    def build(
        self,
        calculation: Mapping[str, Any] | None,
        forecast: Mapping[str, Any] | None,
        *,
        snapshot: Mapping[str, Any] | None = None,
        pit_diagnostics: Mapping[str, Any] | None = None,
        source_status: Mapping[str, Any] | None = None,
        engineer: Mapping[str, Any] | None = None,
        mode: str | None = None,
    ) -> Mapping[str, Any]:
        calculation = _mapping(calculation)
        forecast = _mapping(forecast)
        snapshot = _mapping(snapshot)
        pit_diagnostics = _mapping(pit_diagnostics)
        mode = str(mode or self.config.mode).lower()
        if mode not in {"compact", "expanded", "garage"}:
            mode = "compact"
        fields: dict[str, Any] = {}
        stint = self._stint(calculation, forecast, snapshot, fields)
        pace = self._pace(calculation, fields)
        fuel = self._fuel(calculation, forecast, fields)
        tyres = self._tyres(calculation, snapshot, fields)
        weather = self._weather(calculation, forecast, snapshot, fields)
        pit = self._pit(forecast, pit_diagnostics, fields)
        engineer_model = self._engineer(engineer, forecast, fields)
        tel = _trust_state(_tel_state(snapshot, source_status or {}), default="OFFLINE")
        brg = _trust_state(_first(source_status or {}, "BRG", "brg", "bridge") or self.config.bridge_state, default="NOT USED", neutral=True)
        eng = _trust_state(_first(source_status or {}, "ENG", "eng", "engineer") or self.config.engineer_state, default="NOT ASSIGNED", neutral=True)
        trust = {"TEL": tel, "BRG": brg, "ENG": eng}
        fields["trust.TEL"] = _field("trust.TEL", "TEL", tel["state"], metric={"value": tel["state"]}, formatted_value=tel["label"], semantic_state=tel["semantic_state"], severity=tel["severity"], source_layer="source_health", detail="Telemetry source health")
        fields["trust.BRG"] = _field("trust.BRG", "BRG", brg["state"], metric={"value": brg["state"]}, formatted_value=brg["label"], semantic_state=brg["semantic_state"], severity=brg["severity"], source_layer="source_health", detail="Driver Bridge trust state")
        fields["trust.ENG"] = _field("trust.ENG", "ENG", eng["state"], metric={"value": eng["state"]}, formatted_value=eng["label"], semantic_state=eng["semantic_state"], severity=eng["severity"], source_layer="source_health", detail="Engineer source trust state")

        sections = {
            "engineer": ["engineer.primary", "engineer.detail"],
            "stint": ["stint.current_stint_number", "stint.current_stint_lap", "stint.completed_laps", "stint.current_race_lap", "stint.elapsed_time", "stint.remaining_time", "stint.remaining_laps", "stint.binding_constraint", "stint.previous_summary"],
            "fuel": ["fuel.current", "fuel.range_laps", "fuel.latest", "fuel.stint_average", "fuel.required_per_lap_now", "fuel.target", "fuel.targets", "fuel.latest_vs_target", "fuel.expected_at_pit", "fuel.expected_at_finish"],
            "pace": ["pace.target", "pace.latest", "pace.stint_average", "pace.latest_vs_target", "pace.stint_average_vs_target", "pace.latest_vs_average", "pace.representative", "pace.official_average", "pace.latest_completed", "pace.latest_exclusion", "pace.targets"],
            "tyres": ["tyres.FL.temperature", "tyres.FR.temperature", "tyres.RL.temperature", "tyres.RR.temperature", "tyres.FL.pressure", "tyres.FR.pressure", "tyres.RL.pressure", "tyres.RR.pressure", "tyres.targets", "tyres.graining", "tyres.blistering"],
            "weather": ["weather.condition", "weather.track_condition", "weather.air_temperature", "weather.road_temperature", "weather.wind_speed", "weather.wind_direction", "weather.future"],
            "pit": ["pit.live_state", "pit.marker_state", "pit.distance_to_entry", "pit.eta_to_entry", "pit.expected_fuel_at_entry", "pit.window_state", "pit.calibration", "pit.service_duration", "pit.total_loss"],
            "trust": ["trust.TEL", "trust.BRG", "trust.ENG"],
        }
        compact_sections = {
            "engineer": ["engineer.primary"],
            "stint": ["stint.current_stint_number", "stint.current_stint_lap", "stint.current_race_lap", "stint.remaining_time", "stint.remaining_laps", "stint.binding_constraint"],
            "fuel": ["fuel.current", "fuel.range_laps", "fuel.latest", "fuel.stint_average", "fuel.required_per_lap_now", "fuel.target", "fuel.expected_at_pit"],
            "pace": ["pace.target", "pace.latest", "pace.stint_average"],
            "tyres": ["tyres.FL.temperature", "tyres.FR.temperature", "tyres.RL.temperature", "tyres.RR.temperature", "tyres.FL.pressure", "tyres.FR.pressure", "tyres.RL.pressure", "tyres.RR.pressure"],
            "weather": ["weather.condition", "weather.track_condition", "weather.wind_direction"],
            "pit": ["pit.live_state", "pit.window_state", "pit.distance_to_entry", "pit.eta_to_entry", "pit.calibration"],
            "trust": ["trust.TEL", "trust.BRG", "trust.ENG"],
        }
        expanded_sections = {section: list(ids) for section, ids in sections.items()}
        garage_sections = {section: list(ids) for section, ids in sections.items()}
        garage_sections["diagnostics"] = ["pace.latest_exclusion", "stint.previous_summary", "weather.future", "pit.marker_state", "trust.TEL", "trust.BRG", "trust.ENG"]

        def available(ids: Sequence[str], *, retain_structural: bool = False) -> list[str]:
            result: list[str] = []
            for field_id in ids:
                record = fields.get(field_id)
                if record is None:
                    continue
                if retain_structural or record["availability"] != "unavailable" or field_id in {"engineer.primary", "stint.current_stint_number", "stint.current_stint_lap", "trust.TEL", "trust.BRG", "trust.ENG"}:
                    result.append(field_id)
            return result

        display_sections = compact_sections if mode == "compact" else expanded_sections if mode == "expanded" else garage_sections
        display_fields = {section: available(ids, retain_structural=section in {"engineer", "stint", "trust"}) for section, ids in display_sections.items()}
        priority = ["engineer.primary", "stint.current_stint_number", "stint.current_stint_lap", "fuel.margin_vs_required", "fuel.current", "pace.latest_vs_target", "tyres.FL.temperature", "weather.condition", "pit.live_state", "trust.TEL", "trust.BRG", "trust.ENG"]
        priority = [field_id for field_id in priority if field_id in fields]
        identity = _mapping(snapshot.get("identity"))
        calculated_id = _first(calculation, "calculated_race_state_id", "state_id") or _first(forecast, "calculated_race_state_id", "state_id")
        forecast_id = forecast.get("forecast_id")
        snapshot_id = _first(snapshot, "snapshot_id", "status_snapshot_id") or f"driver-status:{calculated_id or 'state:unknown'}:{forecast_id or 'forecast:unknown'}"
        connection_state = {"LIVE": "live", "PARTIAL": "degraded", "STALE": "stale", "OFFLINE": "disconnected"}.get(tel["state"], "degraded")
        output = {
            "schema_version": VIEW_MODEL_VERSION,
            "view_model_version": VIEW_MODEL_VERSION,
            "snapshot_id": str(snapshot_id),
            "mode": mode,
            "available": connection_state != "disconnected",
            "connection_state": connection_state,
            "session_id": identity.get("session_id"),
            "car_id": identity.get("car_id"),
            "driver_id": identity.get("driver_id"),
            "strategy_revision": forecast.get("strategy_revision"),
            "calculated_race_state_id": calculated_id,
            "forecast_id": forecast_id,
            "generated_at_utc": self.config.generated_at_utc,
            "valid_until_utc": self.config.valid_until_utc,
            "fields": fields,
            "sections": sections,
            "display_fields": display_fields,
            "priority": priority,
            "semantic_states": list(SEMANTIC_STATES),
            "stint": stint,
            "pace": pace,
            "fuel": fuel,
            "tyres": tyres,
            "weather": weather,
            "pit": pit,
            "trust": trust,
            "engineer": engineer_model,
            "trace": {field_id: record["trace_id"] for field_id, record in fields.items()},
            "legacy": {
                "stint_summary": {"current_stint_number": stint["stint_number"], "current_stint_lap": stint["current_stint_lap"], "completed_stint_laps": stint["completed_laps"], "predicted_stint_end_lap": _value(_mapping(forecast.get("stint")).get("predicted_actual"))},
                "fuel_summary": {"fuel_remaining_l": _value(_mapping(fuel.get("current"))), "fuel_laps_remaining": _value(_mapping(fuel.get("range_laps"))), "fuel_delta_to_plan_l": _value(_mapping(forecast.get("fuel", {}).get("margin_vs_required")))},
                "pace_summary": {"pace_delta_to_target_s_per_lap": _mapping(_target_delta(calculation, "pace", "latest_accepted")).get("delta"), "rolling_trend": "unknown"},
                "pit_summary": {"pit_window_state": pit.get("window_state"), "primary_call": engineer_model.get("instruction")},
                "weather_summary": {"label": "CURRENT" if weather.get("condition") else "UNKNOWN", "current_weather_type": weather.get("condition"), "current_track_condition": weather.get("track_condition"), "authoritative": False, "confidence_band": "medium" if weather.get("condition") else "blocked"},
                "primary_instruction": {"instruction": engineer_model.get("instruction", "none"), "instruction_source": engineer_model.get("source", "none"), "priority": engineer_model.get("priority", "low"), "requires_acknowledgement": engineer_model.get("requires_acknowledgement", False)},
            },
        }
        return _copy(output)

    reduce = build


DriverStatusBuilder = DriverStatusViewModel


def build_driver_status(
    calculation: Mapping[str, Any] | None,
    forecast: Mapping[str, Any] | None,
    *,
    snapshot: Mapping[str, Any] | None = None,
    pit_diagnostics: Mapping[str, Any] | None = None,
    source_status: Mapping[str, Any] | None = None,
    engineer: Mapping[str, Any] | None = None,
    config: DriverStatusConfig | Mapping[str, Any] | None = None,
    mode: str | None = None,
) -> Mapping[str, Any]:
    return DriverStatusViewModel(config).build(calculation, forecast, snapshot=snapshot, pit_diagnostics=pit_diagnostics, source_status=source_status, engineer=engineer, mode=mode)


def serialize_driver_status(result: Mapping[str, Any]) -> bytes:
    return (json.dumps(to_plain(result), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


__all__ = [
    "VIEW_MODEL_VERSION",
    "DriverStatusConfig",
    "DriverStatusViewModel",
    "DriverStatusBuilder",
    "build_driver_status",
    "serialize_driver_status",
    "format_lap_time",
    "format_delta",
    "format_duration",
    "format_number",
    "format_range",
    "wind_cardinal",
]
