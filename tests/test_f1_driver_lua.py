from __future__ import annotations

import json
import configparser
import tempfile
import unittest
from pathlib import Path

from tools.build_f1 import build, load_modules, validate_asset_manifest, verify_deterministic
from tools.f1_fixture_builder import SCENARIOS
from tools.f1_host import box_intersects_window, callback_smoke, forbidden_patterns, local_count, parse_lua_files, required_layout_boxes, stage_failure_smoke
from tools import f1_installer
from tools.f1_installer import apply_install_plan, build_install_plan
from tools.f1_validation import load_json, parse_all_json, validate_file


ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "apps" / "driver-lua"
DIST = APP_ROOT / "dist" / "AVM_PitWall_F1"
CONTRACTS = ROOT / "docs" / "contracts"
FIXTURES = APP_ROOT / "fixtures" / "contracts"


FIXTURE_SCHEMAS = {
    "calculated-race-state-normal.json": "calculated-race-state-v0.schema.json",
    "calculation-explanation-fuel.json": "calculation-explanation-v0.schema.json",
    "driver-status-box-this-lap.json": "driver-status-snapshot-v0.schema.json",
    "driver-status-estimated-rain.json": "driver-status-snapshot-v0.schema.json",
    "driver-status-normal.json": "driver-status-snapshot-v0.schema.json",
    "engineer-model-normal.json": "engineer-model-snapshot-v0.schema.json",
    "forecast-confidence-normal.json": "forecast-confidence-v0.schema.json",
    "forecast-snapshot-normal.json": "forecast-snapshot-v0.schema.json",
    "weather-forecast-estimated-rain.json": "weather-forecast-v0.schema.json",
    "weather-forecast-scheduled-heavy-rain.json": "weather-forecast-v0.schema.json",
    "weather-forecast-stale.json": "weather-forecast-v0.schema.json",
    "weather-forecast-unknown.json": "weather-forecast-v0.schema.json",
    "weather-measurement-dry.json": "weather-measurement-v0.schema.json",
}


class F1DriverLuaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        # The release directory is generated/ignored; tests must work from a
        # clean checkout instead of depending on a prebuilt package.
        build(DIST)

    def test_every_repository_json_file_parses(self) -> None:
        paths = parse_all_json(ROOT)
        self.assertGreaterEqual(len(paths), len(FIXTURE_SCHEMAS))

    def test_contract_fixtures_validate(self) -> None:
        for fixture_name, schema_name in FIXTURE_SCHEMAS.items():
            validate_file(FIXTURES / fixture_name, CONTRACTS / schema_name)

    def test_scenario_catalog_contains_required_matrix(self) -> None:
        catalog = load_json(APP_ROOT / "fixtures" / "f1-scenario-catalog.json")
        actual = {entry["id"] for entry in catalog["scenarios"]}
        self.assertEqual(actual, {scenario_id for scenario_id, _ in SCENARIOS})
        self.assertEqual(catalog["default_scenario"], "NORMAL_ON_PLAN_DRY")

    def test_asset_manifest_is_complete(self) -> None:
        records = validate_asset_manifest()
        identifiers = {record["filename_or_identifier"] for record in records}
        for required in ("icon:fuel", "icon:critical", "icon:offline", "assets/sounds/critical.wav", "assets/sounds/ack.wav"):
            self.assertIn(required, identifiers)

    def test_module_graph_is_ordered_and_complete(self) -> None:
        modules = load_modules()
        positions = {module.module_id: index for index, module in enumerate(modules)}
        self.assertEqual(len(modules), 21)
        for module in modules:
            for dependency in module.depends_on:
                self.assertLess(positions[dependency], positions[module.module_id])
        self.assertEqual(modules[-1].module_id, "app")

    def test_module_graph_rejects_missing_dependency_duplicate_and_cycle(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "src").mkdir()
            (root / "src" / "a.lua").write_text("return {}\n", encoding="utf-8")
            (root / "src" / "b.lua").write_text("return {}\n", encoding="utf-8")
            manifest = root / "module-manifest.json"
            manifest.write_text(json.dumps({"schema_version": "f1-lua-module-manifest-v1", "modules": [{"id": "a", "source": "src/a.lua", "depends_on": ["missing"]}]}), encoding="utf-8")
            from tools.build_f1 import load_modules as load_custom
            with self.assertRaises(ValueError):
                load_custom(manifest)
            manifest.write_text(json.dumps({"schema_version": "f1-lua-module-manifest-v1", "modules": [{"id": "a", "source": "src/a.lua", "depends_on": ["b"]}, {"id": "a", "source": "src/b.lua", "depends_on": []}]}), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_custom(manifest)
            manifest.write_text(json.dumps({"schema_version": "f1-lua-module-manifest-v1", "modules": [{"id": "a", "source": "src/a.lua", "depends_on": ["b"]}, {"id": "b", "source": "src/b.lua", "depends_on": ["a"]}]}), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_custom(manifest)

    def test_build_is_byte_deterministic_and_has_release_allowlist(self) -> None:
        verify_deterministic()
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "first"
            second = Path(temp) / "second"
            build(first)
            build(second)
            first_files = {path.relative_to(first).as_posix(): path.read_bytes() for path in first.rglob("*") if path.is_file()}
            second_files = {path.relative_to(second).as_posix(): path.read_bytes() for path in second.rglob("*") if path.is_file()}
            self.assertEqual(first_files, second_files)
            bundle = (first / "AVM_PitWall_F1.lua").read_text(encoding="utf-8")
            self.assertIn("GENERATED FILE - DO NOT EDIT", bundle)
            self.assertNotIn("require(", bundle)
            self.assertNotIn("dofile(", bundle)
            self.assertNotIn("AVM_PitWall.lua", first_files)
            self.assertNotIn("script.lua", first_files)

    def test_bundle_parser_and_safety_scan(self) -> None:
        bundle = DIST / "AVM_PitWall_F1.lua"
        result = parse_lua_files([bundle])
        self.assertTrue(result.backend)
        text = bundle.read_text(encoding="utf-8")
        self.assertEqual(forbidden_patterns(text), [])
        self.assertLessEqual(local_count(text), 20)
        self.assertIn("function script.windowMain(dt)", text)
        self.assertIn("function windowMain(dt)", text)
        self.assertIn('runtime.callback_registered = true', text)
        self.assertLess(text.index("function script.windowMain(dt)"), text.index("BEGIN MODULE runtime_native"))

    def test_callback_registration_precedes_risky_initialization(self) -> None:
        bundle = (DIST / "AVM_PitWall_F1.lua").read_text(encoding="utf-8")
        callback_script = bundle.index("function script.windowMain(dt)")
        callback_global = bundle.index("function windowMain(dt)")
        risky_module = bundle.index("BEGIN MODULE runtime_native")
        app_state = bundle.index("namespace.app_state")
        self.assertLess(callback_script, risky_module)
        self.assertLess(callback_global, risky_module)
        self.assertLess(callback_script, app_state)

    def test_callback_shell_is_direct_and_precedes_application_entry(self) -> None:
        bootstrap = (APP_ROOT / "src" / "bootstrap.lua").read_text(encoding="utf-8")
        self.assertLess(bootstrap.index('function runtime.draw_entry_shell()'), bootstrap.index('local app_entry = runtime.app_entry'))
        self.assertIn('pcall(api.text, bounded(value))', bootstrap)
        self.assertIn('runtime.draw_recovery("runtime-entry", error_value)', bootstrap)

    def test_race_modes_are_single_screen_and_render_critical_copy(self) -> None:
        source = "\n".join(path.read_text(encoding="utf-8") for path in (APP_ROOT / "src").rglob("*.lua"))
        self.assertNotIn("beginChild", source)
        self.assertNotIn("setNextWindowContentSize", source)
        bundle = (DIST / "AVM_PitWall_F1.lua").read_text(encoding="utf-8")
        for label in ("ELAPSED", "REMAINING", "TARGET", "FUEL RANGE", "DISTANCE TO PIT ENTRY", "PIT ROUTE", "EXPECTED AT PIT ENTRY", "TARGET PACE", "WEATHER", "ACK", "BOX BOX - THIS LAP"):
            self.assertIn(label, bundle)

    def test_installer_is_allowlisted_dry_run_first_and_preserves_unrelated_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            ac_root = root / "assetto"
            destination = ac_root / "apps" / "lua" / "AVM_PitWall_F1"
            v1 = ac_root / "apps" / "lua" / "AVM_PitWall"
            destination.mkdir(parents=True)
            v1.mkdir(parents=True)
            (v1 / "sentinel.txt").write_text("V1 untouched\n", encoding="utf-8")
            (destination / "unrelated.ini").write_text("preserve\n", encoding="utf-8")
            package = root / "package"
            build(package)
            plan = build_install_plan(package, ac_root)
            self.assertTrue(plan)
            self.assertTrue(all(operation.destination.parent == destination / operation.relative_path.parent for operation in plan))
            apply_install_plan(plan, ac_root, root / "backup")
            self.assertEqual((v1 / "sentinel.txt").read_text(encoding="utf-8"), "V1 untouched\n")
            self.assertEqual((destination / "unrelated.ini").read_text(encoding="utf-8"), "preserve\n")
            self.assertIn("AVM PitWall F1 deterministic runtime bundle", (destination / "AVM_PitWall_F1.lua").read_text(encoding="utf-8"))

    def test_installer_rejects_v1_target(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            ac_root = root / "assetto"
            package = root / "package"
            build(package)
            original_target = f1_installer.TARGET_RELATIVE
            try:
                f1_installer.TARGET_RELATIVE = Path("apps") / "lua" / f1_installer.V1_NAME
                with self.assertRaises(f1_installer.InstallApplyError):
                    f1_installer.build_install_plan(package, ac_root)
            finally:
                f1_installer.TARGET_RELATIVE = original_target

    def test_manifest_registration_and_canonical_entry(self) -> None:
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(APP_ROOT / "manifest" / "manifest.ini", encoding="utf-8")
        self.assertEqual(parser["ABOUT"]["NAME"], "AVM PitWall F1 Dev")
        self.assertNotEqual(parser["ABOUT"]["NAME"], "AVM PitWall")
        self.assertEqual(parser["WINDOW_..."]["NAME"], "AVM PitWall F1 Dev")
        self.assertEqual(parser["WINDOW_..."]["FUNCTION_MAIN"], "windowMain")
        self.assertNotIn("WINDOW_MAIN", parser.sections())

        generated = DIST / "manifest.ini"
        self.assertEqual(generated.read_text(encoding="utf-8"), (APP_ROOT / "manifest" / "manifest.ini").read_text(encoding="utf-8"))
        canonical = DIST / "AVM_PitWall_F1.lua"
        self.assertTrue(canonical.is_file())
        self.assertIn("function script.windowMain(dt)", canonical.read_text(encoding="utf-8"))
        self.assertFalse((DIST / "AVM_PitWall.lua").exists())
        self.assertFalse((DIST / "script.lua").exists())

        build_manifest = load_json(DIST / "build-manifest.json")
        allowlist = set(build_manifest["release_allowlist"])
        actual = {path.relative_to(DIST).as_posix() for path in DIST.rglob("*") if path.is_file()}
        self.assertEqual(actual, allowlist)
        self.assertIn("AVM_PitWall_F1.lua", allowlist)
        self.assertNotIn("AVM_PitWall.lua", allowlist)
        self.assertNotIn("script.lua", allowlist)

    def test_layout_visibility_matrix(self) -> None:
        for width, height in ((540, 240), (780, 380), (900, 500), (1200, 720)):
            for mode in ("compact", "expanded", "garage"):
                boxes = required_layout_boxes(width, height, mode)
                for name, box in boxes.items():
                    self.assertTrue(box_intersects_window(box, width, height), f"{mode} {name} is outside {width}x{height}")

    def test_runtime_staging_and_first_draw_contract(self) -> None:
        source = (APP_ROOT / "src" / "app.lua").read_text(encoding="utf-8")
        self.assertLess(source.index("native.draw_canary()"), source.index("namespace.app_state.ensure"))
        for stage in ("namespace-ready", "capabilities", "storage", "app-state", "default-fixture", "view-model", "layout", "selected-mode", "alerts", "footer", "audio"):
            self.assertIn(stage, source)
        self.assertIn("test_fail_stage", source)
        self.assertIn("runtime.app_entry = app.windowMain", source)

    def test_runtime_logging_stages_are_bounded_and_once_only(self) -> None:
        bootstrap = (APP_ROOT / "src" / "bootstrap.lua").read_text(encoding="utf-8")
        app = (APP_ROOT / "src" / "app.lua").read_text(encoding="utf-8")
        for message in ("bundle top-level start", "callback registration complete", "first windowMain entry", "early native shell drawn"):
            self.assertIn(message, bootstrap)
        for message in ("namespace ready", "app state ready", "view model ready", "selected mode rendered"):
            self.assertIn(message, app)
        self.assertIn("recovery stage=", bootstrap)
        self.assertIn("runtime.log_once", app)

    def test_forced_stage_failures_keep_recovery_visible(self) -> None:
        cases = [(stage, None) for stage in ("namespace-ready", "capabilities", "storage", "app-state", "default-fixture", "view-model", "layout", "selected-mode", "alerts", "footer", "audio")]
        for stage, mode in cases:
            result = stage_failure_smoke(DIST / "AVM_PitWall_F1.lua", stage, mode)
            if not result.available:
                self.skipTest(result.error or "Lua runtime unavailable")
            self.assertTrue(result.passed, result.error)

    def test_runtime_safety_scope(self) -> None:
        bundle = (DIST / "AVM_PitWall_F1.lua").read_text(encoding="utf-8")
        self.assertEqual(forbidden_patterns(bundle), [])
        self.assertNotIn("function forecast_engine", bundle)
        self.assertNotIn("function strategy_engine", bundle)
        self.assertNotIn("Driver Bridge", bundle)
        self.assertNotIn("Relay Server", bundle)

    def test_callback_smoke_is_explicit_about_runtime_backend(self) -> None:
        result = callback_smoke(DIST / "AVM_PitWall_F1.lua")
        if not result.available:
            self.skipTest(result.error or "Lua runtime unavailable")
        self.assertTrue(result.passed, result.error)
        self.assertGreater(result.draw_count, 0)


if __name__ == "__main__":
    unittest.main()
