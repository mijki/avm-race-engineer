"""Safe dry-run-first installer for the AVM_PitWall_F1 development package."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

try:
    from tools.build_f1 import DEFAULT_OUTPUT
except ModuleNotFoundError:  # direct ``python tools/f1_installer.py`` invocation
    from build_f1 import DEFAULT_OUTPUT


TARGET_NAME = "AVM_PitWall_F1"
TARGET_RELATIVE = Path("apps") / "lua" / TARGET_NAME
V1_NAME = "AVM_PitWall"


class InstallApplyError(RuntimeError):
    """Raised when an install plan cannot be safely applied."""


@dataclass(frozen=True)
class InstallOperation:
    relative_path: Path
    source: Path
    destination: Path
    action: str
    source_sha256: str
    destination_sha256: str | None


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _assert_real_path(path: Path) -> None:
    if path.is_symlink():
        raise InstallApplyError(f"refusing symlink/reparse-point path: {path}")
    if os.name == "nt" and path.exists():
        attributes = getattr(path.stat(), "st_file_attributes", 0)
        if attributes & 0x400:
            raise InstallApplyError(f"refusing reparse-point path: {path}")


def _release_files(package_dir: Path) -> list[Path]:
    if not package_dir.is_dir():
        raise InstallApplyError(f"release package does not exist: {package_dir}")
    build_manifest = package_dir / "build-manifest.json"
    if not build_manifest.is_file():
        raise InstallApplyError("release package is missing build-manifest.json")
    allowlist = {
        Path("manifest.ini"),
        Path("AVM_PitWall.lua"),
        Path("script.lua"),
        Path("README.md"),
        Path("asset-manifest.json"),
        Path("build-manifest.json"),
        Path("assets/sounds/info.wav"),
        Path("assets/sounds/warning.wav"),
        Path("assets/sounds/critical.wav"),
        Path("assets/sounds/ack.wav"),
    }
    actual = {path.relative_to(package_dir) for path in package_dir.rglob("*") if path.is_file()}
    unexpected = actual - allowlist
    missing = allowlist - actual
    if unexpected:
        raise InstallApplyError(f"release contains files outside allowlist: {sorted(map(str, unexpected))}")
    if missing:
        raise InstallApplyError(f"release is missing allowlisted files: {sorted(map(str, missing))}")
    return sorted(allowlist)


def build_install_plan(package_dir: Path, ac_root: Path) -> list[InstallOperation]:
    if not ac_root:
        raise InstallApplyError("an explicit Assetto Corsa root is required")
    ac_root = ac_root.resolve()
    package_dir = package_dir.resolve()
    destination_root = ac_root / TARGET_RELATIVE
    v1_root = ac_root / "apps" / "lua" / V1_NAME
    if destination_root == v1_root or destination_root.name == V1_NAME:
        raise InstallApplyError("refusing to target the installed AVM_PitWall V1 directory")
    _assert_real_path(ac_root)
    _assert_real_path(destination_root)
    operations: list[InstallOperation] = []
    for relative_path in _release_files(package_dir):
        source = package_dir / relative_path
        destination = destination_root / relative_path
        _assert_real_path(source)
        if destination.exists():
            _assert_real_path(destination)
        operations.append(
            InstallOperation(
                relative_path,
                source,
                destination,
                "update" if destination.is_file() else "create",
                sha256(source),
                sha256(destination) if destination.is_file() else None,
            )
        )
    return operations


def format_install_plan(operations: list[InstallOperation]) -> str:
    if not operations:
        return "No operations."
    lines = [f"Target: {TARGET_RELATIVE.as_posix()}", "Mode: dry-run unless --apply is supplied"]
    for operation in operations:
        before = operation.destination_sha256 or "<missing>"
        lines.append(f"{operation.action.upper():6} {operation.relative_path.as_posix()} {operation.source_sha256} (before {before})")
    return "\n".join(lines)


def apply_install_plan(operations: list[InstallOperation], ac_root: Path, backup_root: Path | None = None) -> None:
    if not operations:
        return
    ac_root = ac_root.resolve()
    destination_root = ac_root / TARGET_RELATIVE
    if destination_root.name == V1_NAME:
        raise InstallApplyError("refusing to target V1")
    destination_root.parent.mkdir(parents=True, exist_ok=True)
    _assert_real_path(destination_root.parent)
    backup_root = (backup_root or ac_root / ".avm_pitwall_f1-backups").resolve()
    if backup_root == destination_root or destination_root in backup_root.parents:
        raise InstallApplyError("backup root must be outside the application target")
    backup_root.mkdir(parents=True, exist_ok=True)
    _assert_real_path(backup_root)
    with tempfile.TemporaryDirectory(prefix="AVM_PitWall_F1.stage-", dir=str(destination_root.parent)) as stage_name:
        stage_root = Path(stage_name)
        for operation in operations:
            staged = stage_root / operation.relative_path
            staged.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(operation.source, staged)
            if sha256(staged) != operation.source_sha256:
                raise InstallApplyError(f"staging verification failed: {operation.relative_path}")
        backup_dir = backup_root / "latest"
        backup_dir.mkdir(parents=True, exist_ok=True)
        try:
            for operation in operations:
                current = operation.destination
                if current.is_file():
                    backup_path = backup_dir / operation.relative_path
                    backup_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(current, backup_path)
            for operation in operations:
                destination = operation.destination
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(stage_root / operation.relative_path, destination)
                if sha256(destination) != operation.source_sha256:
                    raise InstallApplyError(f"destination verification failed: {operation.relative_path}")
        except Exception as exc:
            for operation in operations:
                backup_path = backup_dir / operation.relative_path
                if backup_path.is_file():
                    operation.destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(backup_path, operation.destination)
            if isinstance(exc, InstallApplyError):
                raise
            raise InstallApplyError(str(exc)) from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ac-root", type=Path, required=True, help="Explicit Assetto Corsa installation root")
    parser.add_argument("--package", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--apply", action="store_true", help="Apply the verified plan; default is dry-run")
    parser.add_argument("--backup-root", type=Path)
    args = parser.parse_args()
    plan = build_install_plan(args.package, args.ac_root)
    print(format_install_plan(plan))
    if args.apply:
        apply_install_plan(plan, args.ac_root, args.backup_root)
        print("apply: PASS")
    else:
        print("apply: skipped (dry-run)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
