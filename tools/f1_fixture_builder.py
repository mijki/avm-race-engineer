"""Generate deterministic F1 contract fixtures and the scenario catalog."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = ROOT / "apps" / "driver-lua" / "fixtures"
CONTRACT_ROOT = FIXTURE_ROOT / "contracts"
TIMES = [
    "2026-07-26T18:00:00Z",
    "2026-07-26T18:05:00Z",
    "2026-07-26T18:10:00Z",
    "2026-07-26T18:15:00Z",
    "2026-07-26T18:20:00Z",
    "2026-07-26T18:25:00Z",
    "2026-07-26T18:30:00Z",
]


def _confidence(band: str = "high", score: float = 0.92) -> dict[str, Any]:
    return {"overall_band": band, "overall_score": score}


def driver_status(scenario_id: str = "NORMAL_ON_PLAN_DRY") -> dict[str, Any]:
    data: dict[str, Any] = {
        "schema_version": "0.1.0",
        "snapshot_id": f"driver-f1-{scenario_id.lower()}",
        "session_id": "session-f1-demo",
        "car_id": "car-avm-demo",
        "driver_id": "driver-demo",
        "strategy_revision": "accepted-r3",
        "calculated_race_state_id": "state-f1-normal-001",
        "forecast_snapshot_id": "forecast-f1-normal-001",
        "weather_forecast_id": "weather-f1-estimated-001",
        "generated_at_utc": TIMES[0],
        "valid_until_utc": "2026-07-26T18:00:05Z",
        "connection_state": "live",
        "stint_summary": {
            "current_stint_number": 2,
            "total_planned_stints": 4,
            "stint_progress_ratio": 0.72,
            "predicted_stint_end_lap": 26,
        },
        "fuel_summary": {
            "fuel_remaining_l": 18.7,
            "fuel_laps_remaining": 6.4,
            "fuel_delta_to_plan_l": 1.2,
            "next_stop_fuel_addition_l": 46.0,
        },
        "pace_summary": {
            "pace_delta_to_target_s_per_lap": 0.18,
            "rolling_trend": "stable",
        },
        "pit_summary": {
            "pit_window_state": "prepare",
            "primary_call": "on_plan",
            "box_in_laps": None,
        },
        "weather_summary": {
            "label": "CURRENT",
            "current_weather_type": "Dry",
            "current_track_condition": "dry",
            "next_change_summary": None,
            "change_eta_min_lower": None,
            "change_eta_min_upper": None,
            "authoritative": False,
            "expected_tyre_crossover": None,
            "strategy_implication": "M3 remains the correct dry compound.",
            "source_type": "measured_current",
            "confidence_band": "high",
        },
        "primary_instruction": {
            "instruction": "none",
            "instruction_source": "none",
            "priority": "low",
            "requires_acknowledgement": False,
        },
        "confidence_badge": "high",
        "reason_codes": ["WEATHER_CURRENT_ONLY"],
    }

    if scenario_id == "FUEL_SAVE_REQUIRED":
        data["fuel_summary"].update({"fuel_delta_to_plan_l": -1.8, "fuel_laps_remaining": 4.9})
        data["pace_summary"]["pace_delta_to_target_s_per_lap"] = 0.65
        data["pit_summary"]["primary_call"] = "save_fuel"
        data["primary_instruction"] = {
            "instruction": "save_fuel",
            "instruction_source": "forecast_engine",
            "priority": "high",
            "requires_acknowledgement": False,
        }
        data["confidence_badge"] = "medium"
        data["reason_codes"] = ["FUEL_MODEL_ESTIMATED", "FUEL_RESERVE_BELOW_TARGET"]
    elif scenario_id == "EXCESS_FUEL_PUSH":
        data["fuel_summary"].update({"fuel_delta_to_plan_l": 2.4, "fuel_laps_remaining": 7.1})
        data["pace_summary"].update({"pace_delta_to_target_s_per_lap": -0.35, "rolling_trend": "improving"})
        data["pit_summary"]["primary_call"] = "push"
        data["primary_instruction"] = {
            "instruction": "push",
            "instruction_source": "forecast_engine",
            "priority": "normal",
            "requires_acknowledgement": False,
        }
        data["reason_codes"] = []
    elif scenario_id == "BOX_THIS_LAP":
        data["pit_summary"].update({"pit_window_state": "box_now", "primary_call": "box_this_lap"})
        data["primary_instruction"] = {
            "instruction": "box_this_lap",
            "instruction_source": "engineer",
            "priority": "critical",
            "requires_acknowledgement": True,
        }
        data["reason_codes"] = ["PIT_WINDOW_OPEN"]
    elif scenario_id == "BOX_IN_THREE_LAPS":
        data["pit_summary"].update({"pit_window_state": "prepare", "primary_call": "box_in_n_laps", "box_in_laps": 3})
        data["primary_instruction"] = {
            "instruction": "box_in_n_laps",
            "instruction_source": "forecast_engine",
            "priority": "high",
            "requires_acknowledgement": True,
        }
        data["reason_codes"] = ["PIT_WINDOW_NOT_OPEN"]
    elif scenario_id == "STAY_OUT":
        data["pit_summary"].update({"pit_window_state": "open", "primary_call": "stay_out"})
        data["primary_instruction"] = {
            "instruction": "stay_out",
            "instruction_source": "engineer",
            "priority": "high",
            "requires_acknowledgement": True,
        }
        data["reason_codes"] = ["STRATEGY_REVISION_ACCEPTED"]
    elif scenario_id == "ESTIMATED_RAIN":
        data["weather_summary"].update(
            {
                "label": "ESTIMATED",
                "next_change_summary": "Light rain",
                "change_eta_min_lower": 8,
                "change_eta_min_upper": 12,
                "expected_tyre_crossover": "Crossover likely near lap 24",
                "strategy_implication": "Prepare an intermediate tyre decision.",
                "source_type": "estimated_model",
                "confidence_band": "medium",
            }
        )
        data["weather_forecast_id"] = "weather-f1-estimated-001"
        data["reason_codes"] = ["WEATHER_ESTIMATED_ONLY"]
    elif scenario_id == "SCHEDULED_HEAVY_RAIN":
        data["weather_summary"].update(
            {
                "label": "SCHEDULED",
                "next_change_summary": "Heavy rain",
                "change_eta_min_lower": 10,
                "change_eta_min_upper": 10,
                "authoritative": True,
                "expected_tyre_crossover": "Wet tyre crossover at lap 22",
                "strategy_implication": "Pit for wet tyres before the scheduled cell.",
                "source_type": "controller_schedule",
                "confidence_band": "high",
            }
        )
        data["weather_forecast_id"] = "weather-f1-scheduled-001"
        data["reason_codes"] = ["WEATHER_SCHEDULE_AUTHORITATIVE"]
    elif scenario_id == "UNKNOWN_FUTURE_WEATHER":
        data["weather_summary"].update(
            {
                "label": "UNKNOWN",
                "next_change_summary": None,
                "change_eta_min_lower": None,
                "change_eta_min_upper": None,
                "source_type": "unknown",
                "confidence_band": "blocked",
                "strategy_implication": None,
            }
        )
        data["weather_forecast_id"] = None
        data["confidence_badge"] = "blocked"
        data["reason_codes"] = ["WEATHER_UNKNOWN_FUTURE"]
    elif scenario_id == "STALE_WEATHER":
        data["connection_state"] = "stale"
        data["weather_summary"].update(
            {
                "label": "STALE",
                "next_change_summary": None,
                "change_eta_min_lower": None,
                "change_eta_min_upper": None,
                "source_type": "estimated_model",
                "confidence_band": "low",
                "strategy_implication": None,
            }
        )
        data["confidence_badge"] = "low"
        data["reason_codes"] = ["WEATHER_SOURCE_STALE", "TELEMETRY_STALE"]
    elif scenario_id == "LOW_CONFIDENCE_FORECAST":
        data["confidence_badge"] = "low"
        data["pit_summary"]["primary_call"] = "low_confidence"
        data["primary_instruction"] = {
            "instruction": "low_confidence",
            "instruction_source": "forecast_engine",
            "priority": "normal",
            "requires_acknowledgement": False,
        }
        data["reason_codes"] = ["SAMPLE_SET_TOO_SMALL", "FORECAST_HORIZON_LONG"]
    elif scenario_id == "WAITING_FOR_VALID_DATA":
        data["connection_state"] = "degraded"
        data["stint_summary"].update({"current_stint_number": None, "stint_progress_ratio": None})
        data["fuel_summary"].update({"fuel_remaining_l": None, "fuel_laps_remaining": None, "fuel_delta_to_plan_l": None})
        data["pace_summary"].update({"pace_delta_to_target_s_per_lap": None, "rolling_trend": "unknown"})
        data["pit_summary"].update({"pit_window_state": "unknown", "primary_call": "waiting_for_valid_data"})
        data["weather_summary"].update(
            {
                "label": "UNKNOWN",
                "current_weather_type": None,
                "current_track_condition": "unknown",
                "source_type": None,
                "confidence_band": "blocked",
                "strategy_implication": None,
            }
        )
        data["primary_instruction"] = {
            "instruction": "waiting_for_valid_data",
            "instruction_source": "local_safe_fallback",
            "priority": "normal",
            "requires_acknowledgement": False,
        }
        data["confidence_badge"] = "blocked"
        data["reason_codes"] = ["TELEMETRY_MISSING_REQUIRED_FIELD", "CALCULATION_BLOCKED"]
    elif scenario_id == "BRIDGE_OFFLINE":
        data["connection_state"] = "stale"
        data["reason_codes"] = ["TELEMETRY_STALE"]
    elif scenario_id == "ENGINEER_OFFLINE":
        data["connection_state"] = "degraded"
        data["primary_instruction"] = {
            "instruction": "none",
            "instruction_source": "local_safe_fallback",
            "priority": "normal",
            "requires_acknowledgement": False,
        }
        data["reason_codes"] = ["ENGINEER_CHANNEL_UNAVAILABLE"]
    elif scenario_id == "TRAFFIC_WARNING":
        data["primary_instruction"] = {
            "instruction": "push",
            "instruction_source": "engineer",
            "priority": "normal",
            "requires_acknowledgement": False,
        }
        data["reason_codes"] = ["TRAFFIC_APPROACHING"]
    elif scenario_id == "SETUP_AVAILABLE":
        data["primary_instruction"] = {
            "instruction": "none",
            "instruction_source": "engineer",
            "priority": "low",
            "requires_acknowledgement": False,
        }
        data["reason_codes"] = ["SETUP_AVAILABLE"]
    elif scenario_id == "REPLAN_REQUIRED":
        data["pit_summary"]["primary_call"] = "replan_required"
        data["primary_instruction"] = {
            "instruction": "replan_required",
            "instruction_source": "forecast_engine",
            "priority": "high",
            "requires_acknowledgement": True,
        }
        data["confidence_badge"] = "low"
        data["reason_codes"] = ["STRATEGY_INFEASIBLE", "REPLAN_REQUIRED"]
    return data


def weather_measurement() -> dict[str, Any]:
    return {
        "schema_version": "0.1.0",
        "measurement_id": "measurement-f1-dry-001",
        "session_id": "session-f1-demo",
        "car_id": "car-avm-demo",
        "track_id": "track-f1-demo",
        "layout_id": "layout-f1-demo",
        "capture_time_utc": TIMES[0],
        "capture_time_monotonic_ms": 1080000,
        "sequence": {"stream_id": "weather-f1", "sequence_number": 42},
        "source_attribution": {
            "component": "driver_bridge_fixture",
            "source_type": "shared_memory",
            "origin": "replayed",
            "source_id": "fixture:f1-dry",
        },
        "freshness": {"state": "live", "age_ms": 120, "valid_until_utc": "2026-07-26T18:00:05Z"},
        "conditions": {
            "weather_type": "Dry",
            "precipitation_type": "none",
            "ambient_temperature_c": 24.0,
            "road_temperature_c": 31.0,
            "rain_intensity_0_to_1": 0.0,
            "track_wetness_0_to_1": 0.0,
            "standing_water_0_to_1": 0.0,
            "humidity_0_to_1": 0.46,
            "pressure_pa": 101325.0,
            "wind_speed_mps": 2.4,
            "wind_direction_degrees": 180.0,
            "track_grip_0_to_1": 0.92,
        },
        "current_to_next_transition": None,
        "confidence": _confidence(),
        "reason_codes": ["WEATHER_CURRENT_ONLY"],
    }


def weather_point(index: int, kind: str, source_type: str, source_id: str, authoritative: bool, confidence: str) -> dict[str, Any]:
    is_now = index == 0
    weather_type = "Dry"
    precipitation = "none"
    rain = 0.0
    wetness = 0.0
    if kind == "estimated" and index >= 2:
        weather_type = "Light rain" if index < 4 else "Rain"
        precipitation = "rain"
        rain = 0.25 if index < 4 else 0.55
        wetness = 0.18 if index < 4 else 0.46
    if kind == "scheduled" and index >= 2:
        weather_type = "Heavy rain"
        precipitation = "rain"
        rain = 0.8
        wetness = 0.72
    if kind in {"unknown", "stale"} and not is_now:
        weather_type = None
        precipitation = "unknown"
        rain = None
        wetness = None
    point_conf = _confidence(confidence, {"high": 0.94, "medium": 0.68, "low": 0.32, "blocked": 0.0}[confidence])
    reason_codes = ["WEATHER_CURRENT_ONLY"] if is_now else []
    if kind == "estimated" and not is_now:
        reason_codes = ["WEATHER_ESTIMATED_ONLY"]
    if kind == "scheduled" and not is_now:
        reason_codes = ["WEATHER_SCHEDULE_AUTHORITATIVE"]
    if kind == "unknown" and not is_now:
        reason_codes = ["WEATHER_UNKNOWN_FUTURE"]
    if kind == "stale":
        reason_codes = ["WEATHER_SOURCE_STALE"]
    return {
        "forecast_time_utc": TIMES[index],
        "horizon_minutes": index * 5,
        "bucket_start_utc": TIMES[index],
        "bucket_end_utc": TIMES[index + 1] if index < 6 else "2026-07-26T18:35:00Z",
        "weather_type": weather_type,
        "precipitation_type": "none" if is_now and kind != "stale" else precipitation,
        "rain_intensity_0_to_1": rain,
        "rain_probability_0_to_1": None,
        "ambient_temperature_c": 24.0 if is_now else (23.5 if kind == "estimated" else 22.0),
        "road_temperature_c": 31.0 if is_now else (28.0 if kind == "estimated" else 26.0),
        "track_wetness_0_to_1": wetness,
        "standing_water_0_to_1": 0.0 if is_now else (0.12 if kind == "estimated" else 0.38 if kind == "scheduled" else None),
        "humidity_0_to_1": 0.46 if is_now else None,
        "pressure_pa": 101325.0 if is_now else None,
        "wind_speed_mps": 2.4 if is_now else None,
        "wind_direction_degrees": 180.0 if is_now else None,
        "track_grip_0_to_1": 0.92 if is_now else None,
        "source_type": "measured_current" if is_now else source_type,
        "source_id": source_id,
        "generated_at_utc": TIMES[0],
        "source_age_ms": 120 if is_now else 0,
        "confidence": point_conf,
        "uncertainty": {},
        "reason_codes": reason_codes,
        "authoritative": authoritative if not is_now else False,
        "interpolated": False,
    }


def weather_forecast(kind: str = "estimated") -> dict[str, Any]:
    labels = {
        "estimated": ("estimated_model", "weather-f1-estimated-001", "estimated", False, "medium"),
        "scheduled": ("controller_schedule", "weather-f1-scheduled-001", "scheduled", True, "high"),
        "unknown": ("unknown", "weather-f1-unknown-001", "unknown", False, "blocked"),
        "stale": ("estimated_model", "weather-f1-stale-001", "stale", False, "low"),
        "current": ("unknown", "weather-f1-current-001", "current_only", False, "high"),
    }
    source_type, source_id, timeline_status, authoritative, confidence_band = labels[kind]
    return {
        "schema_version": "0.1.0",
        "forecast_id": source_id,
        "session_id": "session-f1-demo",
        "track_id": "track-f1-demo",
        "layout_id": "layout-f1-demo",
        "generated_at_utc": TIMES[0],
        "source_summary": {"source_type": source_type, "source_id": source_id, "authoritative": authoritative},
        "display_bucket_minutes": 5,
        "timeline_status": timeline_status,
        "points": [weather_point(index, kind, source_type, source_id, authoritative, confidence_band) for index in range(7)],
        "confidence": _confidence(confidence_band, {"high": 0.92, "medium": 0.64, "low": 0.28, "blocked": 0.0}[confidence_band]),
        "reason_codes": [
            "WEATHER_ESTIMATED_ONLY" if kind == "estimated" else
            "WEATHER_SCHEDULE_AUTHORITATIVE" if kind == "scheduled" else
            "WEATHER_UNKNOWN_FUTURE" if kind == "unknown" else
            "WEATHER_SOURCE_STALE" if kind == "stale" else
            "WEATHER_CURRENT_ONLY"
        ],
    }


def calculated_race_state() -> dict[str, Any]:
    return {
        "schema_version": "0.1.0",
        "state_id": "state-f1-normal-001",
        "session_id": "session-f1-demo",
        "car_id": "car-avm-demo",
        "driver_id": "driver-demo",
        "track_id": "track-f1-demo",
        "layout_id": "layout-f1-demo",
        "strategy_id": "strategy-f1-demo",
        "strategy_revision": "accepted-r3",
        "baseline_strategy_revision": "baseline-r1",
        "stint_id": "stint-f1-02",
        "forecast_snapshot_id": "forecast-f1-normal-001",
        "calculated_at_utc": TIMES[0],
        "capture_time_utc": TIMES[0],
        "capture_time_monotonic_ms": 1080000,
        "sequence": {"stream_id": "calculated-race-f1", "sequence_number": 18},
        "freshness": {"state": "live", "age_ms": 120, "valid_until_utc": "2026-07-26T18:00:05Z"},
        "model": {"producer_component": "driver_bridge", "model_family": "f1-mock-race-state", "model_version": "0.1.0"},
        "sample_set": {
            "sample_set_id": "samples-f1-qualifying-02",
            "sample_count": 12,
            "oldest_sample_utc": "2026-07-26T17:58:00Z",
            "newest_sample_utc": TIMES[0],
            "operating_regime": "normal_green_running",
            "excluded_sample_count": 0,
        },
        "telemetry_refs": ["telemetry-f1-001"],
        "assumption_ids": ["assumption-f1-dry"],
        "explanation_ids": ["explanation-f1-fuel-001"],
        "measured_telemetry_summary": {
            "current_fuel_l": 18.7,
            "lap_number": 18,
            "lap_distance_m": 1640.0,
            "normalized_track_position": 0.52,
            "speed_mps": 48.2,
            "current_lap_time_s": 494.231,
            "pit_state": "on_track",
            "traffic_state": "clear",
            "ambient_temperature_c": 24.0,
            "road_temperature_c": 31.0,
            "rain_intensity_0_to_1": 0.0,
            "track_wetness_0_to_1": 0.0,
            "standing_water_0_to_1": 0.0,
            "weather_measurement_id": "measurement-f1-dry-001",
        },
        "derived_current_state": {
            "fuel_use_per_lap_l": 2.38,
            "fuel_use_per_km_l": 0.74,
            "fuel_use_per_minute_l": 0.54,
            "rolling_valid_pace_s_per_lap": 494.4,
            "traffic_adjusted_pace_s_per_lap": 494.4,
            "current_stint_distance_m": 11860.0,
            "stint_progress_ratio": 0.72,
            "fuel_delta_to_plan_l": 1.2,
            "pace_delta_to_target_s_per_lap": 0.18,
            "tyre_degradation_rate_percent_per_lap": 0.8,
            "distance_to_pit_entry_m": 2120.0,
            "estimated_time_to_pit_entry_s": 162.0,
            "fuel_laps_remaining": 6.4,
            "weather_trend": "stable",
            "track_condition_trend": "stable",
        },
        "comparison_to_plan": {
            "target_pace_s_per_lap": 494.22,
            "target_stint_end_lap": 26,
            "current_reserve_l": 1.2,
            "strategy_alignment": "on_plan",
        },
        "active_recommendation_state": {
            "primary_call": "on_plan",
            "secondary_call": None,
            "status": "advisory",
            "acknowledgement_required": False,
            "reason_codes": [],
        },
        "confidence": _confidence(),
        "reason_codes": [],
    }


def forecast_snapshot() -> dict[str, Any]:
    return {
        "schema_version": "0.1.0",
        "forecast_id": "forecast-f1-normal-001",
        "session_id": "session-f1-demo",
        "car_id": "car-avm-demo",
        "driver_id": "driver-demo",
        "track_id": "track-f1-demo",
        "layout_id": "layout-f1-demo",
        "strategy_id": "strategy-f1-demo",
        "based_on_strategy_revision": "accepted-r3",
        "baseline_strategy_revision": "baseline-r1",
        "stint_id": "stint-f1-02",
        "calculated_race_state_id": "state-f1-normal-001",
        "calculated_at_utc": TIMES[0],
        "model": {"model_name": "f1-mock-forecast", "model_version": "0.1.0"},
        "forecast_window": {"horizon_type": "stint", "horizon_minutes": 44},
        "sample_set": {"sample_set_id": "samples-f1-qualifying-02", "sample_count": 12, "operating_regime": "normal_green_running"},
        "assumption_ids": ["assumption-f1-dry"],
        "explanation_ids": ["explanation-f1-fuel-001"],
        "forecast_state": {
            "predicted_fuel_at_pit_entry_l": 13.9,
            "predicted_fuel_at_stint_end_l": 3.4,
            "next_stint_fuel_requirement_l": 46.0,
            "required_fuel_addition_l": 46.0,
            "projected_race_end_fuel_l": 5.2,
            "earliest_safe_pit_lap": 24,
            "optimal_pit_lap": 25,
            "latest_safe_pit_lap": 26,
            "predicted_stint_end_lap": 26,
            "predicted_stint_end_time_utc": "2026-07-26T18:44:00Z",
            "projected_tyre_life_laps": 18.0,
            "projected_pace_degradation_s_per_lap": 0.12,
            "expected_traffic_encounters": 1,
            "expected_pit_release_traffic": "clear",
            "expected_weather_change": "none",
            "estimated_tyre_crossover_lap": None,
            "strategy_feasibility": "feasible",
            "projected_race_completion": "on_time",
            "uncertainty": {
                "fuel_at_pit_entry_l": {"lower_bound": 13.4, "upper_bound": 14.3, "unit": "L"},
                "optimal_pit_lap": {"lower_bound": 24, "upper_bound": 26, "unit": "lap"},
            },
        },
        "recommendation_state": {
            "primary_call": "on_plan",
            "call_horizon_laps": None,
            "call_horizon_minutes": None,
            "status": "advisory",
            "priority": "low",
            "operator_ack_required": False,
            "alternative_calls": ["box_in_n_laps"],
            "reason_codes": [],
        },
        "confidence": _confidence(),
        "reason_codes": [],
    }


def confidence_fixture() -> dict[str, Any]:
    return {
        "schema_version": "0.1.0",
        "confidence_id": "confidence-f1-normal-001",
        "subject_type": "forecast_snapshot",
        "subject_id": "forecast-f1-normal-001",
        "calculated_at_utc": TIMES[0],
        "overall_band": "high",
        "overall_score": 0.92,
        "freshness_state": "live",
        "components": [
            {"dimension": "sample_quantity", "score": 0.9, "weight": 0.2, "status": "ok", "rationale": "Representative laps are available."},
            {"dimension": "weather_stability", "score": 0.95, "weight": 0.15, "status": "ok", "rationale": "Current dry conditions are stable."},
            {"dimension": "identity_validity", "score": 1.0, "weight": 0.2, "status": "ok", "rationale": "Session, car, track, and strategy match."},
        ],
        "reason_codes": [],
        "ui_summary": "High confidence: live samples and stable dry conditions.",
    }


def explanation_fixture() -> dict[str, Any]:
    return {
        "schema_version": "0.1.0",
        "explanation_id": "explanation-f1-fuel-001",
        "subject_type": "calculated_race_state",
        "subject_id": "state-f1-normal-001",
        "calculation_key": "predicted_fuel_at_pit_entry_l",
        "generated_at_utc": TIMES[0],
        "based_on_strategy_revision": "accepted-r3",
        "based_on_sample_set_id": "samples-f1-qualifying-02",
        "summary": "Projected fuel at pit entry retains the planned reserve.",
        "narrative_steps": ["Use representative fuel rate.", "Apply distance to pit entry.", "Compare with accepted plan."],
        "primary_reason_codes": ["FUEL_MODEL_ESTIMATED"],
        "assumptions": [{"assumption_id": "assumption-f1-dry", "label": "Dry running continues", "status": "active", "details": None}],
        "evidence": [{"source_type": "telemetry_envelope", "source_id": "telemetry-f1-001", "field_path": "fuel_l", "capture_time_utc": TIMES[0]}],
        "confidence_summary": _confidence(),
        "uncertainty_summary": [{"field_name": "predicted_fuel_at_pit_entry_l", "lower_bound": 13.4, "upper_bound": 14.3, "unit": "L"}],
        "operator_notes": None,
    }


def engineer_model_fixture() -> dict[str, Any]:
    return {
        "schema_version": "0.1.0",
        "snapshot_id": "engineer-f1-normal-001",
        "session_id": "session-f1-demo",
        "car_id": "car-avm-demo",
        "driver_id": "driver-demo",
        "track_id": "track-f1-demo",
        "layout_id": "layout-f1-demo",
        "generated_at_utc": TIMES[0],
        "baseline_plan_summary": {"strategy_id": "strategy-f1-demo", "strategy_revision": "baseline-r1", "target_pit_lap": 25, "target_stint_laps": 18, "target_fuel_per_lap_l": 2.38, "reserve_target_l": 2.0},
        "accepted_strategy_summary": {"strategy_id": "strategy-f1-demo", "strategy_revision": "accepted-r3", "target_pit_lap": 25, "target_stint_laps": 18, "target_fuel_per_lap_l": 2.38, "reserve_target_l": 2.0},
        "proposed_strategy_summary": None,
        "driver_accepted_strategy_summary": None,
        "measured_layer": {
            "telemetry_refs": ["telemetry-f1-001"],
            "weather_measurement_id": "measurement-f1-dry-001",
            "selected_values": {"current_fuel_l": 18.7, "lap_number": 18, "normalized_track_position": 0.52, "pit_state": "on_track", "traffic_state": "clear", "ambient_temperature_c": 24.0, "road_temperature_c": 31.0, "rain_intensity_0_to_1": 0.0, "track_wetness_0_to_1": 0.0},
        },
        "derived_layer": {"calculated_race_state_id": "state-f1-normal-001", "fuel_delta_to_plan_l": 1.2, "distance_to_pit_entry_m": 2120.0, "fuel_laps_remaining": 6.4, "weather_trend": "stable"},
        "forecast_layer": {"forecast_snapshot_id": "forecast-f1-normal-001", "predicted_fuel_at_pit_entry_l": 13.9, "optimal_pit_lap": 25, "projected_race_end_fuel_l": 5.2, "strategy_feasibility": "feasible"},
        "recommendation_layer": {"primary_call": "on_plan", "status": "advisory", "alternative_calls": ["box_in_n_laps"]},
        "weather_measurement": {"snapshot_id": "measurement-f1-dry-001", "label": "CURRENT"},
        "weather_forecast": {"snapshot_id": "weather-f1-estimated-001", "label": "ESTIMATED"},
        "alternative_scenarios": [],
        "explanations": [{"explanation_id": "explanation-f1-fuel-001", "calculation_key": "predicted_fuel_at_pit_entry_l", "summary": "Projected fuel retains the planned reserve."}],
        "confidence_rollup": _confidence(),
        "reason_codes": [],
    }


SCENARIOS = [
    ("NORMAL_ON_PLAN_DRY", "Dry running, fuel on plan, no urgent instruction."),
    ("FUEL_SAVE_REQUIRED", "Fuel delta is negative and saving is required."),
    ("EXCESS_FUEL_PUSH", "Safe excess fuel supports a push recommendation."),
    ("BOX_THIS_LAP", "Critical engineer pit call with acknowledgement required."),
    ("BOX_IN_THREE_LAPS", "Preparation call before the pit window opens."),
    ("STAY_OUT", "Engineer supersedes a previous pit direction."),
    ("ESTIMATED_RAIN", "Non-authoritative rain estimate with medium confidence."),
    ("SCHEDULED_HEAVY_RAIN", "Authoritative controller schedule for heavy rain."),
    ("UNKNOWN_FUTURE_WEATHER", "Current conditions exist without a future claim."),
    ("STALE_WEATHER", "The previous weather source is expired."),
    ("LOW_CONFIDENCE_FORECAST", "Forecast quality is explicitly low."),
    ("WAITING_FOR_VALID_DATA", "No valid calculation is available."),
    ("BRIDGE_OFFLINE", "Last safe state retained while Driver Bridge is offline."),
    ("ENGINEER_OFFLINE", "Race state remains visible while the message channel is degraded."),
    ("MALFORMED_SNAPSHOT", "Intentionally incomplete input for fallback testing."),
    ("TRAFFIC_WARNING", "Faster class approaching with bounded warning."),
    ("SETUP_AVAILABLE", "Garage-only informational setup offer."),
    ("REPLAN_REQUIRED", "Accepted plan is no longer feasible."),
]


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def build(output_root: Path = FIXTURE_ROOT) -> list[Path]:
    contract_root = output_root / "contracts"
    contract_root.mkdir(parents=True, exist_ok=True)
    outputs: dict[str, Any] = {
        "calculated-race-state-normal.json": calculated_race_state(),
        "forecast-snapshot-normal.json": forecast_snapshot(),
        "driver-status-normal.json": driver_status(),
        "driver-status-estimated-rain.json": driver_status("ESTIMATED_RAIN"),
        "driver-status-box-this-lap.json": driver_status("BOX_THIS_LAP"),
        "weather-measurement-dry.json": weather_measurement(),
        "weather-forecast-estimated-rain.json": weather_forecast("estimated"),
        "weather-forecast-scheduled-heavy-rain.json": weather_forecast("scheduled"),
        "weather-forecast-unknown.json": weather_forecast("unknown"),
        "weather-forecast-stale.json": weather_forecast("stale"),
        "forecast-confidence-normal.json": confidence_fixture(),
        "calculation-explanation-fuel.json": explanation_fixture(),
        "engineer-model-normal.json": engineer_model_fixture(),
    }
    written: list[Path] = []
    for name, value in sorted(outputs.items()):
        path = contract_root / name
        write_json(path, value)
        written.append(path)

    catalog = {
        "schema_version": "f1-scenario-catalog-v1",
        "default_scenario": "NORMAL_ON_PLAN_DRY",
        "malformed_fixture_is_intentional": True,
        "scenarios": [{"id": scenario_id, "description": description} for scenario_id, description in SCENARIOS],
    }
    catalog_path = output_root / "f1-scenario-catalog.json"
    write_json(catalog_path, catalog)
    written.append(catalog_path)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=FIXTURE_ROOT)
    args = parser.parse_args()
    for path in build(args.output):
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
