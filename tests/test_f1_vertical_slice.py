from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

from tools.f1_installer import TARGET_NAME, plan, target_root
from tools.f1_validation import no_renderer_race_literals, no_runtime_loaders, parse_all_json, validate_markdown_links
from tools.live_model import layout_boxes, layout_valid


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps" / "driver-lua" / "src"


class StaticBoundaryTests(unittest.TestCase):
    def test_no_runtime_require_or_dofile(self) -> None:
        self.assertEqual(no_runtime_loaders(), [])

    def test_renderer_has_no_concept_race_values(self) -> None:
        self.assertEqual(no_renderer_race_literals(), [])

    def test_json_is_parseable(self) -> None:
        self.assertEqual(parse_all_json(), [])

    def test_markdown_links_resolve(self) -> None:
        self.assertEqual(validate_markdown_links(), [])

    def test_exactly_one_render_function_per_race_mode(self) -> None:
        for name in ("compact_mode.lua", "expanded_mode.lua"):
            text = (SOURCE / "ui" / name).read_text(encoding="utf-8")
            self.assertEqual(text.count("function compact.render(") + text.count("function expanded.render("), 1)
            self.assertNotIn("beginChild", text)

    def test_garage_is_only_mock_selection_surface(self) -> None:
        state_text = (SOURCE / "app_state.lua").read_text(encoding="utf-8")
        garage_text = (SOURCE / "ui" / "garage_mode.lua").read_text(encoding="utf-8")
        self.assertIn("if self.mode ~= \"garage\" then return false end", state_text)
        self.assertIn("MOCK BASELINE", garage_text)
        self.assertNotIn("mock_scenario", (SOURCE / "ui" / "compact_mode.lua").read_text(encoding="utf-8"))

    def test_ui_does_not_call_raw_telemetry_api(self) -> None:
        for path in (SOURCE / "ui").rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("getSim", text)
            self.assertNotIn("getCar", text)

    def test_driver_source_has_no_networking_or_backend_runtime(self) -> None:
        for path in SOURCE.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("ac.connect", text)
            self.assertNotIn("web.", text)
            self.assertNotIn("os.execute", text)

    def test_race_layouts_fit_supported_sizes_without_overlap(self) -> None:
        for width, height in ((700, 300), (780, 380), (900, 450)):
            self.assertTrue(layout_valid(layout_boxes(width, height, "compact"), width, height, "compact"))
        for width, height in ((1000, 560), (1200, 720)):
            self.assertTrue(layout_valid(layout_boxes(width, height, "expanded"), width, height, "expanded"))
        self.assertTrue(layout_valid(layout_boxes(780, 380, "garage"), 780, 380, "garage"))

    def test_installer_rejects_v1_target(self) -> None:
        with self.assertRaises(ValueError):
            target_root(Path("C:/Assetto Corsa/apps/lua/AVM_PitWall"))


class ToolingTests(unittest.TestCase):
    def test_build_is_deterministic(self) -> None:
        subprocess.run([sys.executable, "tools/build_f1.py", "--verify-deterministic"], cwd=ROOT, check=True, capture_output=True, text=True)
        manifest = json.loads((ROOT / "apps/driver-lua/dist/AVM_PitWall_F1/build-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest["module_order"]), 31)
        self.assertEqual(manifest["bundle_sha256"], manifest["package_file_hashes"]["AVM_PitWall_F1.lua"])

    def test_installer_plan_targets_only_f1(self) -> None:
        package = ROOT / "apps/driver-lua/dist/AVM_PitWall_F1"
        operations = plan(Path("C:/Assetto Corsa"), package)
        self.assertTrue(all(destination.parent.name == TARGET_NAME for _, destination in operations))


if __name__ == "__main__":
    unittest.main()
