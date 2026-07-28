"""Deterministically bundle and package the AVM PitWall F1 client."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from tools.f1_validation import ValidationError, load_json
except ModuleNotFoundError:
    from f1_validation import ValidationError, load_json


ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "apps" / "driver-lua"
MODULE_MANIFEST = APP_ROOT / "build" / "module-manifest.json"
DEFAULT_OUTPUT = APP_ROOT / "dist" / "AVM_PitWall_F1"
GENERATED_WARNING = "GENERATED FILE - DO NOT EDIT. Rebuild with tools/build_f1.py."


@dataclass(frozen=True)
class Module:
    module_id: str
    source: Path
    depends_on: tuple[str, ...]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def _normalise_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")


def load_modules(manifest_path: Path = MODULE_MANIFEST) -> list[Module]:
    manifest = load_json(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("schema_version") != "f1-lua-module-manifest-v1":
        raise ValidationError(f"{manifest_path}: unsupported module manifest")
    raw_modules = manifest.get("modules")
    if not isinstance(raw_modules, list) or not raw_modules:
        raise ValidationError(f"{manifest_path}: modules must be a non-empty list")
    modules: list[Module] = []
    seen: set[str] = set()
    source_root = manifest_path.parent.parent if manifest_path.parent.name == "build" else manifest_path.parent
    for raw in raw_modules:
        if not isinstance(raw, dict):
            raise ValidationError(f"{manifest_path}: module entry must be an object")
        module_id = raw.get("id")
        source_name = raw.get("source")
        depends_on = raw.get("depends_on", [])
        if not isinstance(module_id, str) or not module_id or module_id in seen:
            raise ValidationError(f"{manifest_path}: duplicate or invalid module id {module_id!r}")
        if not isinstance(source_name, str) or not source_name:
            raise ValidationError(f"{manifest_path}: {module_id}: source is required")
        if not isinstance(depends_on, list) or any(not isinstance(item, str) for item in depends_on):
            raise ValidationError(f"{manifest_path}: {module_id}: depends_on must be strings")
        source = source_root / source_name
        if not source.is_file():
            raise ValidationError(f"{manifest_path}: {module_id}: missing source {source_name}")
        seen.add(module_id)
        modules.append(Module(module_id, source, tuple(depends_on)))
    for module in modules:
        for dependency in module.depends_on:
            if dependency not in seen:
                raise ValidationError(f"{manifest_path}: {module.module_id}: missing dependency {dependency!r}")
    by_id = {module.module_id: module for module in modules}
    ordered: list[Module] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(module_id: str) -> None:
        if module_id in visiting:
            raise ValidationError(f"{manifest_path}: dependency cycle at {module_id}")
        if module_id in visited:
            return
        visiting.add(module_id)
        for dependency in by_id[module_id].depends_on:
            visit(dependency)
        visiting.remove(module_id)
        visited.add(module_id)
        ordered.append(by_id[module_id])

    for module in modules:
        visit(module.module_id)
    return ordered


def validate_asset_manifest(path: Path = APP_ROOT / "asset-manifest.json") -> list[dict[str, Any]]:
    manifest = load_json(path)
    if not isinstance(manifest, dict) or manifest.get("schema_version") != "f1-asset-manifest-v1":
        raise ValidationError(f"{path}: unsupported asset manifest")
    assets = manifest.get("assets")
    if not isinstance(assets, list) or not assets:
        raise ValidationError(f"{path}: assets must be a non-empty list")
    required = {"filename_or_identifier", "purpose", "ownership", "license", "expected_dimensions", "runtime_usage", "fallback_behavior"}
    seen: set[str] = set()
    for asset in assets:
        if not isinstance(asset, dict) or not required.issubset(asset):
            raise ValidationError(f"{path}: asset record is incomplete")
        identifier = asset["filename_or_identifier"]
        if not isinstance(identifier, str) or not identifier or identifier in seen:
            raise ValidationError(f"{path}: duplicate or invalid asset {identifier!r}")
        seen.add(identifier)
        if ".." in Path(identifier).parts:
            raise ValidationError(f"{path}: asset escapes package: {identifier}")
    return assets


def bundle_source(modules: list[Module]) -> tuple[str, dict[str, str]]:
    source_hashes: dict[str, str] = {}
    chunks = [
        "-- AVM PitWall F1 deterministic runtime bundle",
        f"-- {GENERATED_WARNING}",
        "-- Runtime dependency loading is intentionally absent.",
        "-- Source order and hashes are recorded in build-manifest.json.",
        "",
    ]
    for module in modules:
        source = _normalise_text(module.source)
        digest = sha256_bytes(source.encode("utf-8"))
        source_hashes[module.module_id] = digest
        label = module.source.relative_to(APP_ROOT).as_posix()
        chunks.append(f"-- BEGIN MODULE {module.module_id} ({label}) sha256={digest}")
        chunks.append("do")
        chunks.extend(f"  {line}" if line else "" for line in source.split("\n"))
        chunks.extend(["end", f"-- END MODULE {module.module_id}", ""])
    return "\n".join(chunks).rstrip() + "\n", source_hashes


def _tone_samples(duration_s: float, frequencies: tuple[float, ...], gap_s: float = 0.0) -> bytes:
    sample_rate = 44100
    total = int(duration_s * sample_rate)
    gap = int(gap_s * sample_rate)
    parts: list[float] = []
    for frequency in frequencies:
        tone_length = max(1, (total - gap * max(0, len(frequencies) - 1)) // len(frequencies))
        for index in range(tone_length):
            envelope = min(1.0, index / (sample_rate * 0.012), (tone_length - index) / (sample_rate * 0.035))
            parts.append(math.sin(2.0 * math.pi * frequency * index / sample_rate) * 0.28 * max(0.0, envelope))
        parts.extend([0.0] * gap)
    return b"".join(struct.pack("<h", max(-32767, min(32767, int(sample * 32767)))) for sample in parts[:total])


def generate_sound_assets(asset_root: Path) -> dict[str, str]:
    sound_specs = {"info.wav": (0.22, (660.0,), 0.0), "warning.wav": (0.42, (540.0, 720.0), 0.055), "critical.wav": (0.52, (390.0, 390.0), 0.065), "ack.wav": (0.18, (880.0,), 0.0)}
    sound_dir = asset_root / "sounds"
    sound_dir.mkdir(parents=True, exist_ok=True)
    hashes: dict[str, str] = {}
    for filename, (duration, frequencies, gap) in sound_specs.items():
        path = sound_dir / filename
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(44100)
            stream.writeframes(_tone_samples(duration, frequencies, gap))
        hashes[f"assets/sounds/{filename}"] = sha256_file(path)
    return hashes


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")


def build(output_dir: Path = DEFAULT_OUTPUT) -> dict[str, Any]:
    modules = load_modules()
    validate_asset_manifest()
    bundle, source_hashes = bundle_source(modules)
    output_dir.mkdir(parents=True, exist_ok=True)
    _write_text(output_dir / "manifest.ini", _normalise_text(APP_ROOT / "manifest" / "manifest.ini"))
    _write_text(output_dir / "README.md", _normalise_text(APP_ROOT / "README.md"))
    _write_text(output_dir / "asset-manifest.json", json.dumps(load_json(APP_ROOT / "asset-manifest.json"), indent=2, sort_keys=True) + "\n")
    for stale_name in ("AVM_PitWall.lua", "script.lua"):
        stale_path = output_dir / stale_name
        if stale_path.is_file():
            stale_path.unlink()
    _write_text(output_dir / "AVM_PitWall_F1.lua", bundle)
    asset_hashes = generate_sound_assets(output_dir / "assets")
    build_manifest: dict[str, Any] = {
        "schema_version": "f1-build-manifest-v1",
        "tool_version": "1.0.0",
        "generated_warning": GENERATED_WARNING,
        "module_order": [module.module_id for module in modules],
        "source_file_hashes": source_hashes,
        "bundle_sha256": sha256_bytes(bundle.encode("utf-8")),
        "included_asset_hashes": asset_hashes,
        "release_allowlist": ["manifest.ini", "AVM_PitWall_F1.lua", "README.md", "asset-manifest.json", "build-manifest.json", "assets/sounds/info.wav", "assets/sounds/warning.wav", "assets/sounds/critical.wav", "assets/sounds/ack.wav"],
    }
    build_manifest["package_file_hashes"] = {
        path.relative_to(output_dir).as_posix(): sha256_file(path)
        for path in sorted(output_dir.rglob("*"))
        if path.is_file() and path.name != "build-manifest.json"
    }
    _write_text(output_dir / "build-manifest.json", json.dumps(build_manifest, indent=2, sort_keys=True) + "\n")
    return build_manifest


def _tree_bytes(root: Path) -> dict[str, bytes]:
    return {path.relative_to(root).as_posix(): path.read_bytes() for path in sorted(root.rglob("*")) if path.is_file()}


def verify_deterministic() -> None:
    with tempfile.TemporaryDirectory(prefix="avm-f1-build-") as temp:
        first, second = Path(temp) / "first", Path(temp) / "second"
        build(first)
        build(second)
        left, right = _tree_bytes(first), _tree_bytes(second)
        if left != right:
            names = sorted(set(left) | set(right))
            raise ValidationError(f"deterministic build mismatch: {[name for name in names if left.get(name) != right.get(name)]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--verify-deterministic", action="store_true")
    args = parser.parse_args()
    if args.verify_deterministic:
        verify_deterministic()
        print("deterministic-build: PASS")
    manifest = build(args.output)
    print(f"bundle-sha256: {manifest['bundle_sha256']}")
    print(f"modules: {len(manifest['module_order'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
