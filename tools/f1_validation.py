"""Small, dependency-free validation helpers for the F1 host gate.

The repository intentionally does not require a large JSON-schema dependency
for its deterministic fixture checks. This validator implements the subset
used by the checked-in foundation schemas without requiring a third-party
package.
"""

from __future__ import annotations

import datetime as _datetime
import json
import re
from pathlib import Path
from typing import Any


class ValidationError(ValueError):
    """Raised when an instance does not satisfy a JSON schema."""


def load_json(path: Path) -> Any:
    """Load UTF-8 JSON with a stable error message."""

    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path}: invalid JSON: {exc}") from exc


def _json_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _resolve_ref(root: dict[str, Any], ref: str) -> dict[str, Any]:
    if not ref.startswith("#/"):
        raise ValidationError(f"unsupported schema reference: {ref}")
    current: Any = root
    for part in ref[2:].split("/"):
        current = current[part.replace("~1", "/").replace("~0", "~")]
    if not isinstance(current, dict):
        raise ValidationError(f"schema reference is not an object: {ref}")
    return current


def _check_format(value: str, fmt: str, path: str) -> None:
    if fmt != "date-time":
        return
    try:
        _datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValidationError(f"{path}: invalid date-time: {value!r}") from exc


def _validate(instance: Any, schema: dict[str, Any], root: dict[str, Any], path: str) -> None:
    if "$ref" in schema:
        _validate(instance, _resolve_ref(root, schema["$ref"]), root, path)
        return

    if "anyOf" in schema:
        errors: list[str] = []
        for candidate in schema["anyOf"]:
            try:
                _validate(instance, candidate, root, path)
                break
            except ValidationError as exc:
                errors.append(str(exc))
        else:
            raise ValidationError(f"{path}: no anyOf branch matched ({'; '.join(errors)})")
        return

    if "allOf" in schema:
        for candidate in schema["allOf"]:
            _validate(instance, candidate, root, path)

    expected = schema.get("type")
    if expected is not None:
        expected_types = expected if isinstance(expected, list) else [expected]
        actual = _json_type(instance)
        compatible = actual in expected_types or (actual == "integer" and "number" in expected_types)
        if not compatible:
            raise ValidationError(f"{path}: expected {expected_types}, got {actual}")

    if "enum" in schema and instance not in schema["enum"]:
        raise ValidationError(f"{path}: {instance!r} is not in enum {schema['enum']!r}")

    if isinstance(instance, str):
        if "minLength" in schema and len(instance) < schema["minLength"]:
            raise ValidationError(f"{path}: shorter than minLength")
        if "maxLength" in schema and len(instance) > schema["maxLength"]:
            raise ValidationError(f"{path}: longer than maxLength")
        if "pattern" in schema and re.fullmatch(schema["pattern"], instance) is None:
            raise ValidationError(f"{path}: does not match pattern {schema['pattern']!r}")
        if "format" in schema:
            _check_format(instance, schema["format"], path)

    if _is_number(instance):
        if "minimum" in schema and instance < schema["minimum"]:
            raise ValidationError(f"{path}: below minimum")
        if "maximum" in schema and instance > schema["maximum"]:
            raise ValidationError(f"{path}: above maximum")

    if isinstance(instance, list):
        if "minItems" in schema and len(instance) < schema["minItems"]:
            raise ValidationError(f"{path}: fewer than minItems")
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            raise ValidationError(f"{path}: more than maxItems")
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in instance]
            if len(encoded) != len(set(encoded)):
                raise ValidationError(f"{path}: duplicate array items")
        if "items" in schema:
            for index, item in enumerate(instance):
                _validate(item, schema["items"], root, f"{path}[{index}]")

    if isinstance(instance, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                raise ValidationError(f"{path}: missing required property {key!r}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(instance) - set(properties))
            if unknown:
                raise ValidationError(f"{path}: unexpected properties {unknown!r}")
        for key, value in instance.items():
            if key in properties:
                _validate(value, properties[key], root, f"{path}.{key}")


def validate(instance: Any, schema: dict[str, Any], *, source: str = "instance") -> None:
    """Validate an instance against a foundation JSON schema."""

    _validate(instance, schema, schema, source)


def validate_file(instance_path: Path, schema_path: Path) -> None:
    schema = load_json(schema_path)
    if not isinstance(schema, dict):
        raise ValidationError(f"{schema_path}: schema root must be an object")
    validate(load_json(instance_path), schema, source=str(instance_path))


def parse_all_json(root: Path) -> list[Path]:
    """Parse every repository JSON file without importing project code."""

    paths = sorted(path for path in root.rglob("*.json") if ".git" not in path.parts)
    for path in paths:
        load_json(path)
    return paths
