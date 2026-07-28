"""Dependency-free contract and source-boundary validation for the F1 host gate."""

from __future__ import annotations

import datetime as _datetime
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps" / "driver-lua" / "src"
RENDERERS = [SOURCE / "ui" / name for name in ("compact_mode.lua", "expanded_mode.lua", "garage_mode.lua")]


class ValidationError(ValueError):
    """Raised when an instance or build input violates a repository contract."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path}: invalid JSON: {exc}") from exc


def _json_type(value: Any) -> str:
    if value is None: return "null"
    if isinstance(value, bool): return "boolean"
    if isinstance(value, int): return "integer"
    if isinstance(value, float): return "number"
    if isinstance(value, str): return "string"
    if isinstance(value, list): return "array"
    if isinstance(value, dict): return "object"
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
    if fmt == "date-time":
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
    for candidate in schema.get("allOf", []):
        _validate(instance, candidate, root, path)
    expected = schema.get("type")
    if expected is not None:
        expected_types = expected if isinstance(expected, list) else [expected]
        actual = _json_type(instance)
        if actual not in expected_types and not (actual == "integer" and "number" in expected_types):
            raise ValidationError(f"{path}: expected {expected_types}, got {actual}")
    if "enum" in schema and instance not in schema["enum"]:
        raise ValidationError(f"{path}: {instance!r} is not in enum {schema['enum']!r}")
    if isinstance(instance, str):
        if "minLength" in schema and len(instance) < schema["minLength"]: raise ValidationError(f"{path}: shorter than minLength")
        if "maxLength" in schema and len(instance) > schema["maxLength"]: raise ValidationError(f"{path}: longer than maxLength")
        if "pattern" in schema and re.fullmatch(schema["pattern"], instance) is None: raise ValidationError(f"{path}: does not match pattern")
        if "format" in schema: _check_format(instance, schema["format"], path)
    if _is_number(instance):
        if "minimum" in schema and instance < schema["minimum"]: raise ValidationError(f"{path}: below minimum")
        if "maximum" in schema and instance > schema["maximum"]: raise ValidationError(f"{path}: above maximum")
    if isinstance(instance, list):
        if "minItems" in schema and len(instance) < schema["minItems"]: raise ValidationError(f"{path}: fewer than minItems")
        if "maxItems" in schema and len(instance) > schema["maxItems"]: raise ValidationError(f"{path}: more than maxItems")
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in instance]
            if len(encoded) != len(set(encoded)): raise ValidationError(f"{path}: duplicate array items")
        if "items" in schema:
            for index, item in enumerate(instance): _validate(item, schema["items"], root, f"{path}[{index}]")
    if isinstance(instance, dict):
        for key in schema.get("required", []):
            if key not in instance: raise ValidationError(f"{path}: missing required property {key!r}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(instance) - set(properties))
            if unknown: raise ValidationError(f"{path}: unexpected properties {unknown!r}")
        for key, value in instance.items():
            if key in properties: _validate(value, properties[key], root, f"{path}.{key}")


def validate(instance: Any, schema: dict[str, Any], *, source: str = "instance") -> None:
    _validate(instance, schema, schema, source)


def validate_file(instance_path: Path, schema_path: Path) -> None:
    schema = load_json(schema_path)
    if not isinstance(schema, dict): raise ValidationError(f"{schema_path}: schema root must be an object")
    validate(load_json(instance_path), schema, source=str(instance_path))


def lua_sources() -> list[Path]:
    return sorted(SOURCE.rglob("*.lua"))


def no_runtime_loaders() -> list[str]:
    return [str(path) for path in lua_sources() if re.search(r"\b(?:require|dofile)\s*\(", path.read_text(encoding="utf-8"))]


def no_renderer_race_literals() -> list[str]:
    forbidden = ("31:42", "12:18", "44:00", "18.7", "6.4", "2.12", "13.9", "+0.18", "M3", "Lap 24", "46 L", "8:14.231")
    return [f"{path}: {literal}" for path in RENDERERS for literal in forbidden if literal in path.read_text(encoding="utf-8")]


def json_files(root: Path = ROOT) -> list[Path]:
    return sorted(path for path in root.rglob("*.json") if ".git" not in path.parts)


def parse_all_json(root: Path | None = None) -> list[Any]:
    """Parse JSON; explicit roots return paths for the contract suite, default returns errors for CLI scans."""
    explicit = root is not None
    paths = json_files(root or ROOT)
    errors: list[str] = []
    for path in paths:
        try:
            load_json(path)
        except ValidationError as exc:
            errors.append(str(exc))
    if explicit:
        if errors: raise ValidationError(errors[0])
        return paths
    return errors


def validate_bundle(bundle: Path) -> list[str]:
    text = bundle.read_text(encoding="utf-8")
    errors: list[str] = []
    if re.search(r"\b(?:require|dofile)\s*\(", text): errors.append("runtime loader present")
    if "function script.windowMain(dt)" not in text or "function windowMain(dt)" not in text: errors.append("both CSP callback shapes are not registered")
    return errors


def validate_markdown_links() -> list[str]:
    errors: list[str] = []
    pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for path in sorted(ROOT.rglob("*.md")):
        if "dist" in path.parts:
            continue
        for target in pattern.findall(path.read_text(encoding="utf-8")):
            if target.startswith(("http://", "https://", "mailto:", "#")): continue
            target_path = target.split("#", 1)[0]
            if target_path and not (path.parent / target_path).resolve().exists():
                errors.append(f"{path}: missing Markdown link target {target}")
    return errors


if __name__ == "__main__":
    bundle = ROOT / "apps" / "driver-lua" / "dist" / "AVM_PitWall_F1" / "AVM_PitWall_F1.lua"
    errors = no_runtime_loaders() + no_renderer_race_literals() + parse_all_json() + validate_markdown_links()
    if bundle.exists(): errors.extend(validate_bundle(bundle))
    if errors:
        for error in errors: print(error)
        raise SystemExit(1)
    print("F1 static validation OK")
