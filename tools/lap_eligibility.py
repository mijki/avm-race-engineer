"""Deterministic, purpose-specific completed-lap eligibility.

The eligibility engine is intentionally a pure host-side calculation.  It
consumes immutable completed-lap records and immutable event evidence, and
returns new immutable decision records.  It never changes the measured lap.
"""

from __future__ import annotations

import copy
import json
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Any, Iterable, Mapping, Sequence

from tools.race_engine_core import SCHEMA_VERSIONS, to_plain


PURPOSES = (
    "useForPace",
    "useForFuel",
    "useForTyres",
    "useForProjection",
    "useForOfficialAverage",
)
DECISION_VERSION = "lap-eligibility-v1"
ELIGIBILITY_SCHEMA_VERSION = "lap-eligibility-v1"
OVERRIDE_ACTIONS = frozenset(("INCLUDE", "EXCLUDE", "RESTORE_AUTOMATIC"))
OVERRIDE_STATES = frozenset(("NONE", "INCLUDE", "EXCLUDE"))
REGIMES = frozenset(("DRY", "WET", "MIXED", "CAUTION", "TRAFFIC", "FUEL_SAVE", "PUSH", "NORMAL"))


def _copy(value: Any) -> Any:
    return copy.deepcopy(value)


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(child) for key, child in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(child) for child in value)
    return value


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _bool(value: Any) -> bool | None:
    return value if isinstance(value, bool) else None


def _number(value: Any) -> int | float | None:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _first(mapping: Mapping[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in mapping:
            return mapping[key]
    return None


def _token(value: Any) -> str:
    return str(value or "").strip().upper().replace("-", "_").replace(" ", "_")


def _tokens(value: Any) -> set[str]:
    if isinstance(value, str):
        return {_token(value)}
    if isinstance(value, (list, tuple, set, frozenset)):
        return {_token(item) for item in value if item is not None}
    if isinstance(value, Mapping):
        return {_token(key) for key, item in value.items() if item is True}
    return set()


def _normalize_regime(value: Any) -> str | None:
    token = _token(value)
    aliases = {
        "WETTING": "MIXED",
        "DAMP": "MIXED",
        "FUEL_SAVE_RUNNING": "FUEL_SAVE",
        "FUEL_SAVING": "FUEL_SAVE",
        "PUSH_RUNNING": "PUSH",
        "GREEN": "NORMAL",
        "GREEN_VALID": "NORMAL",
        "NORMAL_OPERATIONAL": "NORMAL",
    }
    token = aliases.get(token, token)
    return token if token in REGIMES else (None if not token else token)


def _contains_token(value: Any, *needles: str) -> bool:
    text = _token(value)
    return any(needle in text for needle in needles)


@dataclass(frozen=True)
class EligibilityPolicy:
    """Versioned policy options; purpose rules remain independent."""

    policy_id: str = "OPERATIONAL"
    policy_version: str = "1.0.0"
    active_regime: str | None = None
    allow_track_limit_invalid_pace: bool = False
    allow_track_limit_invalid_projection: bool = False
    allow_pit_lap_tyres: bool = True
    max_event_evidence: int = 32
    custom: Mapping[str, Any] = field(default_factory=dict)

    @classmethod
    def from_value(cls, value: "EligibilityPolicy | str | Mapping[str, Any] | None") -> "EligibilityPolicy":
        if isinstance(value, cls):
            return value
        if isinstance(value, str):
            return cls(policy_id=value.upper())
        raw = dict(value or {})
        policy_id = str(raw.pop("policy_id", raw.pop("policy", "OPERATIONAL"))).upper()
        if policy_id not in {"STRICT", "OPERATIONAL", "CUSTOM"}:
            raise ValueError(f"unsupported eligibility policy: {policy_id}")
        active = _normalize_regime(raw.pop("active_regime", raw.pop("regime", None)))
        custom = raw.pop("custom", {})
        if not isinstance(custom, Mapping):
            raise TypeError("custom eligibility policy options must be a mapping")
        return cls(
            policy_id=policy_id,
            policy_version=str(raw.pop("policy_version", "1.0.0")),
            active_regime=active,
            allow_track_limit_invalid_pace=bool(raw.pop("allow_track_limit_invalid_pace", False)),
            allow_track_limit_invalid_projection=bool(raw.pop("allow_track_limit_invalid_projection", False)),
            allow_pit_lap_tyres=bool(raw.pop("allow_pit_lap_tyres", True)),
            max_event_evidence=max(1, int(raw.pop("max_event_evidence", 32))),
            custom=_copy({**dict(custom), **raw}),
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "policy_id": self.policy_id,
            "policy_version": self.policy_version,
            "active_regime": self.active_regime,
            "allow_track_limit_invalid_pace": self.allow_track_limit_invalid_pace,
            "allow_track_limit_invalid_projection": self.allow_track_limit_invalid_projection,
            "allow_pit_lap_tyres": self.allow_pit_lap_tyres,
            "max_event_evidence": self.max_event_evidence,
            "custom": _copy(dict(self.custom)),
        }


@dataclass(frozen=True)
class ManualOverride:
    lap_id: str
    purposes: tuple[str, ...]
    action: str
    reason: str
    sequence: int
    source: str = "operator"
    timestamp_s: float | int | None = None
    identity_key: str | None = None
    stint_id: str | None = None

    def __post_init__(self) -> None:
        if not self.lap_id:
            raise ValueError("manual eligibility override requires lap_id")
        if not self.purposes or any(purpose not in PURPOSES for purpose in self.purposes):
            raise ValueError("manual eligibility override has unsupported purpose")
        if self.action not in OVERRIDE_ACTIONS:
            raise ValueError(f"unsupported manual eligibility action: {self.action}")
        if self.action != "RESTORE_AUTOMATIC" and not self.reason.strip():
            raise ValueError("include/exclude overrides require a readable reason")

    def as_dict(self) -> dict[str, Any]:
        return {
            "lap_id": self.lap_id,
            "purposes": list(self.purposes),
            "action": self.action,
            "reason": self.reason,
            "sequence": self.sequence,
            "source": self.source,
            "timestamp_s": self.timestamp_s,
            "identity_key": self.identity_key,
            "stint_id": self.stint_id,
        }


def _event_matches_lap(event: Mapping[str, Any], lap: Mapping[str, Any]) -> bool:
    lap_id = lap.get("lap_id")
    payload = _mapping(event.get("payload"))
    if lap_id is not None and (event.get("lap_id") == lap_id or payload.get("lap_id") == lap_id):
        return True
    lap_number = lap.get("lap_number")
    if lap_number is not None and payload.get("lap_number") == lap_number:
        identity = event.get("identity_key")
        if not identity or not lap.get("identity_key") or identity == lap.get("identity_key"):
            return True
    return False


def _event_evidence(lap: Mapping[str, Any], events: Iterable[Mapping[str, Any]], max_items: int) -> tuple[list[dict[str, Any]], set[str]]:
    matches: list[dict[str, Any]] = []
    event_types: set[str] = set()
    for event in events:
        if not isinstance(event, Mapping) or not _event_matches_lap(event, lap):
            continue
        event_type = _token(event.get("event_type"))
        event_types.add(event_type)
        matches.append({
            "event_id": event.get("event_id"),
            "event_type": event.get("event_type"),
            "sequence": event.get("sequence"),
            "confidence": event.get("confidence"),
            "rejection_reason": event.get("rejection_reason"),
        })
    matches.sort(key=lambda item: (item.get("sequence") is None, item.get("sequence") or 0, str(item.get("event_id") or "")))
    return matches[-max_items:], event_types


def _measurement_complete(value: Any, *, kind: str) -> bool | None:
    if not isinstance(value, Mapping):
        return False
    explicit = _first(value, "measurement_complete", "measurements_complete", "complete", "available")
    if isinstance(explicit, bool):
        return explicit
    if kind == "fuel":
        if any(_number(value.get(key)) is not None for key in ("use_l", "used_l", "fuel_used_l", "delta_l", "start_l", "end_l")):
            return True
        return False
    if kind == "tyres":
        wheels = value.get("wheels", value)
        if isinstance(wheels, Mapping):
            for wheel in wheels.values():
                if isinstance(wheel, Mapping) and any(_number(wheel.get(key)) is not None for key in ("temperature_c", "temp_c", "pressure_psi", "pressure_kpa", "wear", "life")):
                    return True
        return False
    return None


def _extract_evidence(lap: Mapping[str, Any], events: Iterable[Mapping[str, Any]], policy: EligibilityPolicy) -> dict[str, Any]:
    interaction = _mapping(lap.get("pit_reset_interaction"))
    interaction = {**interaction, **_mapping(lap.get("interactions"))}
    classification_values = _tokens(_first(lap, "classification", "classifications"))
    classification_values.update(_tokens(interaction.get("classification")))
    invalidation = _token(_first(lap, "invalidation_reason", "invalid_reason"))
    event_sources, event_types = _event_evidence(lap, events, policy.max_event_evidence)
    event_tokens = set(event_types)

    pit = bool(_first(interaction, "pit", "pit_lane", "pit_lane_interaction", "pit_box", "in_pit", "in_lap", "out_lap"))
    pit = pit or bool(classification_values & {"PIT", "PIT_LAP", "PIT_IN", "PIT_OUT", "IN_LAP", "OUT_LAP", "PIT_BOX"})
    pit = pit or bool(event_tokens & {"PIT_ENTRY_CANDIDATE", "PIT_ENTRY_CONFIRMED", "PIT_BOX_ARRIVAL", "PIT_BOX_DEPARTURE", "PIT_EXIT_CANDIDATE", "PIT_EXIT_CONFIRMED"})
    pit_box = bool(_first(interaction, "pit_box", "in_pit_box")) or bool(classification_values & {"PIT_BOX"})
    reset = bool(_first(interaction, "reset", "reset_interaction", "reset_counter_changed")) or "RESET" in event_tokens
    teleport = bool(_first(interaction, "teleport", "teleport_interaction")) or "TELEPORT" in event_tokens
    incident = bool(_first(lap, "incident", "incident_lap")) or bool(_first(interaction, "incident")) or "INCIDENT" in event_tokens
    incomplete = _first(lap, "complete", "lap_complete", "is_complete")
    complete = incomplete if isinstance(incomplete, bool) else True
    severe_discontinuity = bool(_first(interaction, "severe_discontinuity", "material_discontinuity"))
    severe_discontinuity = severe_discontinuity or bool(_first(lap, "severe_discontinuity", "material_discontinuity"))
    shortcut = bool(_first(lap, "shortcut", "shortcut_detected")) or bool(_first(interaction, "shortcut"))
    shortcut = shortcut or "SHORTCUT" in event_tokens
    implausible = bool(_first(lap, "implausibly_fast", "implausible_fast")) or "IMPLAUSIBLE_FAST" in event_tokens
    continuity = _first(lap, "distance_continuity", "spline_continuity", "continuity")
    continuity_known = isinstance(continuity, bool)
    continuity_ok = continuity if continuity_known else None
    if continuity_ok is False:
        severe_discontinuity = True

    official = _first(lap, "official_validity", "official_valid", "valid")
    official = official if isinstance(official, bool) else None
    track_limit_invalid = _contains_token(invalidation, "TRACK_LIMIT", "TRACKLIMIT", "CUT")
    fuel = _mapping(lap.get("fuel"))
    tyres = lap.get("tyres", lap.get("tyre_measurements", lap.get("tyre")))
    fuel_complete = _measurement_complete(fuel, kind="fuel")
    tyre_complete = _measurement_complete(tyres, kind="tyres")
    lap_regime = _normalize_regime(_first(lap, "regime", "weather_regime", "operating_regime"))
    if lap_regime is None:
        lap_regime = _normalize_regime(_first(interaction, "regime"))
    active_regime = policy.active_regime
    regime_match = active_regime is None or lap_regime is None or lap_regime == active_regime
    regime_known_mismatch = active_regime is not None and lap_regime is not None and lap_regime != active_regime
    traffic = "TRAFFIC" in classification_values or bool(_first(lap, "traffic_affected", "traffic")) or "TRAFFIC" in event_tokens
    fuel_save = "FUEL_SAVE" in classification_values or bool(_first(lap, "fuel_save", "fuel_saving"))
    push = "PUSH" in classification_values or bool(_first(lap, "push_lap", "push"))
    evidence = {
        "official_validity": official,
        "invalidation_reason": lap.get("invalidation_reason"),
        "lap_complete": complete,
        "classification": sorted(classification_values),
        "pit_interaction": pit,
        "pit_box_interaction": pit_box,
        "reset_interaction": reset,
        "teleport_interaction": teleport,
        "incident": incident,
        "severe_discontinuity": severe_discontinuity,
        "shortcut_detected": shortcut,
        "implausibly_fast": implausible,
        "continuity": continuity_ok,
        "fuel_measurement_complete": fuel_complete,
        "tyre_measurement_complete": tyre_complete,
        "weather_regime": lap_regime,
        "active_regime": active_regime,
        "regime_match": regime_match,
        "traffic_affected": traffic,
        "fuel_save": fuel_save,
        "push": push,
        "event_sources": event_sources,
    }
    return {
        **evidence,
        "evidence": evidence,
        "official": official,
        "lap_regime": lap_regime,
        "regime_known_mismatch": regime_known_mismatch,
        "pit": pit,
        "pit_box": pit_box,
        "reset": reset,
        "teleport": teleport,
        "incident": incident,
        "complete": complete,
        "severe": severe_discontinuity or reset or teleport or incident or not complete,
        "shortcut": shortcut,
        "implausible": implausible,
        "track_limit_invalid": track_limit_invalid,
        "fuel_complete": fuel_complete is True,
        "tyre_complete": tyre_complete is True,
    }


def _add_reason(reasons: list[str], *codes: str) -> None:
    for code in codes:
        if code and code not in reasons:
            reasons.append(code)


def _operational_decision(purpose: str, evidence: Mapping[str, Any], policy: EligibilityPolicy) -> tuple[bool, list[str], str]:
    reasons: list[str] = []
    if not evidence["complete"]:
        _add_reason(reasons, "INCOMPLETE_LAP")
        return False, reasons, "LOW"
    if evidence["reset"]:
        _add_reason(reasons, "RESET_INTERACTION")
    if evidence["teleport"]:
        _add_reason(reasons, "TELEPORT_INTERACTION")
    if evidence["incident"]:
        _add_reason(reasons, "INCIDENT_LAP")
    if evidence["severe"]:
        _add_reason(reasons, "SEVERE_DISCONTINUITY")
    if evidence["shortcut"]:
        _add_reason(reasons, "SHORTCUT_ASSISTED")
    if evidence["implausible"]:
        _add_reason(reasons, "IMPLAUSIBLY_FAST")
    if evidence["regime_known_mismatch"]:
        _add_reason(reasons, "REGIME_MISMATCH")

    structural = evidence["severe"] or evidence["shortcut"] or evidence["implausible"]
    if purpose == "useForOfficialAverage":
        if evidence["official"] is True and not evidence["pit"] and not structural:
            _add_reason(reasons, "OFFICIAL_VALID")
            return True, reasons, "HIGH"
        if evidence["official"] is not True:
            _add_reason(reasons, "OFFICIAL_INVALID" if evidence["official"] is False else "OFFICIAL_VALIDITY_UNKNOWN")
        if evidence["pit"]:
            _add_reason(reasons, "PIT_LAP")
        return False, reasons, "LOW" if evidence["official"] is None else "MEDIUM"

    if purpose == "useForTyres":
        if not evidence["tyre_complete"]:
            _add_reason(reasons, "MISSING_TYRE_MEASUREMENTS")
            return False, reasons, "LOW"
        if evidence["reset"] or evidence["teleport"] or evidence["incident"] or not evidence["complete"]:
            return False, reasons, "LOW"
        if evidence["pit"] and not policy.allow_pit_lap_tyres:
            _add_reason(reasons, "PIT_LAP")
            return False, reasons, "MEDIUM"
        if evidence["pit"]:
            _add_reason(reasons, "TYRE_DIAGNOSTIC_PIT_LAP")
        elif evidence["official"] is False:
            _add_reason(reasons, "OFFICIAL_INVALID_OPERATIONALLY_REPRESENTATIVE")
        else:
            _add_reason(reasons, "TYRE_MEASUREMENTS_COMPLETE")
        return True, reasons, "MEDIUM" if evidence["pit"] or evidence["official"] is False else "HIGH"

    if evidence["pit"]:
        _add_reason(reasons, "PIT_LAP")
        return False, reasons, "LOW"
    if structural:
        return False, reasons, "LOW"
    if evidence["regime_known_mismatch"]:
        return False, reasons, "MEDIUM"
    if purpose == "useForFuel":
        if not evidence["fuel_complete"]:
            _add_reason(reasons, "MISSING_FUEL_MEASUREMENTS")
            return False, reasons, "LOW"
        if evidence["official"] is False:
            if evidence["track_limit_invalid"]:
                _add_reason(reasons, "TRACK_LIMIT_INVALID_OPERATIONALLY_REPRESENTATIVE")
            else:
                _add_reason(reasons, "OFFICIAL_INVALID")
                return False, reasons, "MEDIUM"
        elif evidence["official"] is True:
            _add_reason(reasons, "OFFICIAL_VALID")
        else:
            _add_reason(reasons, "OFFICIAL_VALIDITY_UNKNOWN")
        if evidence["traffic_affected"]:
            _add_reason(reasons, "TRAFFIC_ALLOWED_FOR_FUEL")
        if evidence["fuel_save"]:
            _add_reason(reasons, "FUEL_SAVE_REGIME")
        if evidence["push"]:
            _add_reason(reasons, "PUSH_REGIME")
        return True, reasons, "MEDIUM" if evidence["official"] is not True else "HIGH"

    if evidence["traffic_affected"] and purpose in {"useForPace", "useForProjection"}:
        _add_reason(reasons, "TRAFFIC_AFFECTED")
        return False, reasons, "MEDIUM"
    if evidence["fuel_save"] and purpose in {"useForPace", "useForProjection"} and policy.active_regime != "FUEL_SAVE":
        _add_reason(reasons, "FUEL_SAVE_REGIME")
        return False, reasons, "MEDIUM"
    if evidence["track_limit_invalid"] and evidence["official"] is False:
        allow = policy.allow_track_limit_invalid_pace if purpose == "useForPace" else policy.allow_track_limit_invalid_projection
        if not allow:
            _add_reason(reasons, "TRACK_LIMIT_INVALID")
            return False, reasons, "MEDIUM"
        _add_reason(reasons, "TRACK_LIMIT_INVALID_ALLOWED_BY_POLICY")
        return True, reasons, "MEDIUM"
    if evidence["official"] is False:
        _add_reason(reasons, "OFFICIAL_INVALID")
        return False, reasons, "MEDIUM"
    if evidence["official"] is None:
        _add_reason(reasons, "OFFICIAL_VALIDITY_UNKNOWN")
        return False, reasons, "LOW"
    if evidence["fuel_save"]:
        _add_reason(reasons, "FUEL_SAVE_REGIME")
    elif evidence["push"]:
        _add_reason(reasons, "PUSH_REGIME")
    else:
        _add_reason(reasons, "OFFICIAL_VALID")
    return True, reasons, "HIGH"


class EligibilityEngine:
    """Evaluate immutable laps with deterministic, auditable decisions."""

    def __init__(self, policy: EligibilityPolicy | str | Mapping[str, Any] | None = None, *, max_override_history: int | None = None) -> None:
        self.policy = EligibilityPolicy.from_value(policy)
        self.max_override_history = max(1, int(max_override_history or self.policy.max_event_evidence * 2))
        self._override_sequence = 0
        self._override_history: list[ManualOverride] = []
        self._active_overrides: dict[tuple[str, str], ManualOverride] = {}

    @property
    def override_history(self) -> tuple[Mapping[str, Any], ...]:
        return tuple(_freeze(item.as_dict()) for item in self._override_history)

    @property
    def active_overrides(self) -> tuple[Mapping[str, Any], ...]:
        return tuple(_freeze(item.as_dict()) for item in sorted(self._active_overrides.values(), key=lambda item: item.sequence))

    def set_override(
        self,
        lap_id: str,
        purposes: str | Sequence[str],
        action: str,
        reason: str = "",
        *,
        source: str = "operator",
        timestamp_s: float | int | None = None,
        identity_key: str | None = None,
        stint_id: str | None = None,
    ) -> Mapping[str, Any]:
        normalized_purposes = (purposes,) if isinstance(purposes, str) else tuple(purposes)
        normalized_purposes = tuple(dict.fromkeys(normalized_purposes))
        self._override_sequence += 1
        record = ManualOverride(
            lap_id=str(lap_id),
            purposes=normalized_purposes,
            action=str(action).upper(),
            reason=str(reason),
            sequence=self._override_sequence,
            source=str(source),
            timestamp_s=timestamp_s,
            identity_key=identity_key,
            stint_id=stint_id,
        )
        self._override_history.append(record)
        self._override_history = self._override_history[-self.max_override_history :]
        for purpose in record.purposes:
            key = (record.lap_id, purpose)
            if record.action == "RESTORE_AUTOMATIC":
                self._active_overrides.pop(key, None)
            else:
                self._active_overrides[key] = record
        return _freeze(record.as_dict())

    def restore_automatic(self, lap_id: str, purposes: str | Sequence[str], reason: str = "") -> Mapping[str, Any]:
        return self.set_override(lap_id, purposes, "RESTORE_AUTOMATIC", reason)

    def reset_for_boundary(self, *, identity_key: str | None = None, stint_id: str | None = None) -> None:
        """Reset active overrides only when the owning identity/stint says so."""
        for key, override in list(self._active_overrides.items()):
            if identity_key is not None and override.identity_key not in (None, identity_key):
                continue
            if stint_id is not None and override.stint_id not in (None, stint_id):
                continue
            self._active_overrides.pop(key, None)

    def _override_for(self, lap: Mapping[str, Any], purpose: str) -> ManualOverride | None:
        override = self._active_overrides.get((str(lap.get("lap_id")), purpose))
        if override is None:
            return None
        if override.identity_key is not None and lap.get("identity_key") not in (None, override.identity_key):
            return None
        if override.stint_id is not None and lap.get("stint_id") not in (None, override.stint_id):
            return None
        return override

    def _decision(self, purpose: str, evidence: Mapping[str, Any]) -> dict[str, Any]:
        if self.policy.policy_id == "STRICT":
            eligible, reasons, confidence = _operational_decision(purpose, evidence, self.policy)
            if eligible and evidence["official"] is True and not evidence["pit"]:
                _add_reason(reasons, "STRICT_OFFICIAL_VALID")
            else:
                eligible = False
                _add_reason(reasons, "STRICT_REQUIRES_OFFICIAL_VALIDITY")
                confidence = "LOW"
        else:
            eligible, reasons, confidence = _operational_decision(purpose, evidence, self.policy)
            if self.policy.policy_id == "CUSTOM":
                custom = _mapping(self.policy.custom)
                allowed = custom.get("allowed_regimes", {})
                allowed_for_purpose = _tokens(_mapping(allowed).get(purpose)) if isinstance(allowed, Mapping) else set()
                if allowed_for_purpose and evidence.get("lap_regime") not in allowed_for_purpose:
                    eligible = False
                    _add_reason(reasons, "CUSTOM_REGIME_NOT_ALLOWED")
                disabled = {str(item) for item in custom.get("disabled_purposes", [])} if isinstance(custom.get("disabled_purposes"), (list, tuple, set, frozenset)) else set()
                if purpose in disabled:
                    eligible = False
                    _add_reason(reasons, "CUSTOM_PURPOSE_DISABLED")

        override = self._override_for(self._current_lap, purpose)
        manual_state = "NONE"
        manual_reason = None
        if override is not None:
            manual_state = "INCLUDE" if override.action == "INCLUDE" else "EXCLUDE"
            manual_reason = override.reason
            eligible = override.action == "INCLUDE"
            _add_reason(reasons, "MANUAL_INCLUDE" if eligible else "MANUAL_EXCLUDE")
            confidence = "HIGH"
        return {
            "eligible": bool(eligible),
            "policy_id": self.policy.policy_id,
            "policy_version": self.policy.policy_version,
            "reason_codes": reasons,
            "source_evidence": _copy(dict(evidence["evidence"])),
            "confidence": confidence,
            "manual_override_state": manual_state,
            "manual_override_reason": manual_reason,
            "decision_version": DECISION_VERSION,
        }

    def evaluate_lap(self, lap: Mapping[str, Any], events: Iterable[Mapping[str, Any]] = (), *, event_sequence: int = 1) -> Mapping[str, Any]:
        if not isinstance(lap, Mapping):
            raise TypeError("completed lap must be a mapping")
        self._current_lap = lap
        evidence = _extract_evidence(lap, events, self.policy)
        decisions = {purpose: self._decision(purpose, evidence) for purpose in PURPOSES}
        compatibility = {
            purpose: decisions[purpose]["eligible"] for purpose in PURPOSES
        }
        compatibility.update({
            "policy": self.policy.policy_id,
            "policy_version": self.policy.policy_version,
            "reasons": {purpose: decisions[purpose]["reason_codes"] for purpose in PURPOSES},
            "manual_override": any(decision["manual_override_state"] != "NONE" for decision in decisions.values()),
            "decision_version": DECISION_VERSION,
        })
        lap_id = str(lap.get("lap_id") or "lap:unidentified")
        event = {
            "schema_version": SCHEMA_VERSIONS["race_event"],
            "event_id": f"eligibility:{lap_id}:{self.policy.policy_id}:{self.policy.policy_version}:{event_sequence}",
            "sequence": int(event_sequence),
            "event_type": "LAP_ELIGIBILITY_DECIDED",
            "source_snapshot_id": str(lap.get("source_snapshot_id") or lap_id),
            "detection_time_s": lap.get("completed_at_s"),
            "source_time_s": lap.get("completed_at_s"),
            "session_time_s": lap.get("completed_at_s"),
            "identity_key": str(lap.get("identity_key") or ""),
            "confidence": "HIGH" if all(item["confidence"] == "HIGH" for item in decisions.values()) else "MEDIUM",
            "provenance": {"source": "completed-lap-v1", "detector": DECISION_VERSION},
            "payload": {"lap_id": lap.get("lap_id"), "decision_version": DECISION_VERSION, "decisions": decisions},
            "suppression_reason": None,
            "rejection_reason": None,
        }
        result = {
            "schema_version": ELIGIBILITY_SCHEMA_VERSION,
            "lap_id": lap.get("lap_id"),
            "identity_key": lap.get("identity_key", ""),
            "lap_number": lap.get("lap_number"),
            "policy_id": self.policy.policy_id,
            "policy_version": self.policy.policy_version,
            "decision_version": DECISION_VERSION,
            "decisions": decisions,
            "eligibility": compatibility,
            "event": event,
        }
        return _freeze(result)

    def evaluate_laps(self, laps: Iterable[Mapping[str, Any]], events: Iterable[Mapping[str, Any]] = ()) -> tuple[Mapping[str, Any], ...]:
        results = []
        for sequence, lap in enumerate(laps, start=1):
            results.append(self.evaluate_lap(lap, events, event_sequence=sequence))
        return tuple(results)

    def evaluate(self, lap: Mapping[str, Any], events: Iterable[Mapping[str, Any]] = ()) -> Mapping[str, Any]:
        return self.evaluate_lap(lap, events)


def evaluate_completed_lap(lap: Mapping[str, Any], *, policy: EligibilityPolicy | str | Mapping[str, Any] | None = None, events: Iterable[Mapping[str, Any]] = (), overrides: Iterable[Mapping[str, Any]] = ()) -> Mapping[str, Any]:
    engine = EligibilityEngine(policy)
    for override in overrides:
        raw = dict(override)
        engine.set_override(raw["lap_id"], raw["purposes"], raw["action"], raw.get("reason", ""), source=raw.get("source", "operator"), timestamp_s=raw.get("timestamp_s"), identity_key=raw.get("identity_key"), stint_id=raw.get("stint_id"))
    return engine.evaluate_lap(lap, events)


def serialize_eligibility(results: Mapping[str, Any] | Iterable[Mapping[str, Any]]) -> bytes:
    value = results if isinstance(results, Mapping) else list(results)
    return (json.dumps(to_plain(value), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


__all__ = [
    "DECISION_VERSION",
    "ELIGIBILITY_SCHEMA_VERSION",
    "EligibilityEngine",
    "EligibilityPolicy",
    "ManualOverride",
    "PURPOSES",
    "evaluate_completed_lap",
    "serialize_eligibility",
]
