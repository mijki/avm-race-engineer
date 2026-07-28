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
except ModuleNotFoundError:
    from build_f1 import DEFAULT_OUTPUT


TARGET_NAME = "AVM_PitWall_F1"
TARGET_RELATIVE = Path("apps") / "lua" / TARGET_NAME
V1_NAME = "AVM_PitWall"
PACKAGE_FILES = ("manifest.ini", "AVM_PitWall_F1.lua", "README.md", "asset-manifest.json", "build-manifest.json")


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


def package_root() -> Path:
    return DEFAULT_OUTPUT


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def target_root(ac_root: Path) -> Path:
    root = Path(ac_root)
    if root.name == V1_NAME:
        raise ValueError("installer refuses the installed V1 AVM_PitWall target")
    target = root / TARGET_RELATIVE
    if target.name != TARGET_NAME:
        raise ValueError("installer target guard rejected unexpected application name")
    return target


def _assert_real_path(path: Path) -> None:
    if path.is_symlink():
        raise InstallApplyError(f"refusing symlink/reparse-point path: {path}")
    if os.name == "nt" and path.exists() and getattr(path.stat(), "st_file_attributes", 0) & 0x400:
        raise InstallApplyError(f"refusing reparse-point path: {path}")


def _release_files(package_dir: Path) -> list[Path]:
    if not package_dir.is_dir():
        raise InstallApplyError(f"release package does not exist: {package_dir}")
    build_manifest = package_dir / "build-manifest.json"
    if not build_manifest.is_file():
        raise InstallApplyError("release package is missing build-manifest.json")
    allowlist = {Path(name) for name in PACKAGE_FILES} | {Path("assets/sounds") / name for name in ("info.wav", "warning.wav", "critical.wav", "ack.wav")}
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
    ac_root = Path(ac_root).resolve()
    package_dir = Path(package_dir).resolve()
    destination_root = ac_root / TARGET_RELATIVE
    if destination_root.name == V1_NAME:
        raise InstallApplyError("refusing to target the installed AVM_PitWall V1 directory")
    if destination_root.name != TARGET_NAME:
        raise InstallApplyError("installer target guard rejected unexpected application name")
    _assert_real_path(ac_root)
    _assert_real_path(destination_root)
    operations: list[InstallOperation] = []
    for relative_path in _release_files(package_dir):
        source = package_dir / relative_path
        destination = destination_root / relative_path
        _assert_real_path(source)
        if destination.exists():
            _assert_real_path(destination)
        operations.append(InstallOperation(relative_path, source, destination, "update" if destination.is_file() else "create", sha256(source), sha256(destination) if destination.is_file() else None))
    return operations


def plan(ac_root: Path, package: Path | None = None) -> list[tuple[Path, Path]]:
    package = package or package_root()
    target = target_root(ac_root)
    missing = [name for name in PACKAGE_FILES if not (package / name).is_file()]
    if missing:
        raise FileNotFoundError("package is missing: " + ", ".join(missing))
    return [(package / name, target / name) for name in PACKAGE_FILES]


def format_install_plan(operations: list[InstallOperation]) -> str:
    lines = [f"Target: {TARGET_RELATIVE.as_posix()}", "Mode: dry-run unless --apply is supplied"]
    for operation in operations:
        lines.append(f"{operation.action.upper():6} {operation.relative_path.as_posix()} {operation.source_sha256} (before {operation.destination_sha256 or '<missing>'})")
    return "\n".join(lines) if lines else "No operations."


def apply_install_plan(operations: list[InstallOperation], ac_root: Path, backup_root: Path | None = None) -> None:
    if not operations:
        return
    ac_root = Path(ac_root).resolve()
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
                if operation.destination.is_file():
                    backup_path = backup_dir / operation.relative_path
                    backup_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(operation.destination, backup_path)
            for operation in operations:
                operation.destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(stage_root / operation.relative_path, operation.destination)
                if sha256(operation.destination) != operation.source_sha256:
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
    parser.add_argument("--ac-root", type=Path, required=True, help="Explicit Assetto Corsa root")
    parser.add_argument("--package", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--apply", action="store_true", help="Apply the verified plan; default is dry-run")
    parser.add_argument("--backup-root", type=Path)
    args = parser.parse_args()
    operations = build_install_plan(args.package, args.ac_root)
    print(format_install_plan(operations))
    if args.apply:
        apply_install_plan(operations, args.ac_root, args.backup_root)
        print("apply: PASS")
    else:
        print("apply: skipped (dry-run)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
