from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from tools.build_f1 import build, verify_deterministic
from tools.f1_host import forbidden_patterns


ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "apps" / "driver-lua"
SRC = APP_ROOT / "src"


class F1RendererVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.csp = (SRC / "adapters" / "csp.lua").read_text(encoding="utf-8")
        cls.bootstrap = (SRC / "bootstrap.lua").read_text(encoding="utf-8")
        cls.app = (SRC / "app.lua").read_text(encoding="utf-8")
        cls.compact = (SRC / "ui" / "compact_mode.lua").read_text(encoding="utf-8")
        cls.expanded = (SRC / "ui" / "expanded_mode.lua").read_text(encoding="utf-8")
        cls.garage = (SRC / "ui" / "garage_mode.lua").read_text(encoding="utf-8")
        cls.layout = (SRC / "ui" / "layout.lua").read_text(encoding="utf-8")

    def test_compact_text_first_contains_real_view_model_sections(self) -> None:
        for label in (
            "MODE: COMPACT",
            "STINT:",
            "LAP:",
            "TIME: ELAPSED:",
            "TARGET STINT:",
            "FUEL: STATUS:",
            "DISTANCE TO PIT ENTRY:",
            "EXPECTED AT PIT ENTRY:",
            "PACE: STATUS:",
            "TYRES: COMPOUND:",
            "WEATHER: CURRENT:",
            "NEXT WEATHER:",
            "ENGINEER:",
            "CONNECTION: BRIDGE:",
            "TELEMETRY AGE:",
        ):
            self.assertIn(label, self.compact)
        render_body = self.compact.split("function compact.render_text_first", 1)[1]
        self.assertNotIn("drawText", render_body)
        self.assertGreaterEqual(render_body.count("csp.text("), 14)

    def test_all_modes_have_mode_specific_text_first_renderers(self) -> None:
        self.assertIn("function expanded.render_text_first", self.expanded)
        self.assertIn('csp.text("MODE: Expanded")', self.expanded)
        self.assertIn("function garage.render_text_first", self.garage)
        self.assertIn('csp.text("MODE: Garage / Diagnostics")', self.garage)
        self.assertIn("expanded.render_text_first(vm)", self.app)
        self.assertIn("garage.render_text_first(vm, state)", self.app)

    def test_full_render_log_is_gated_by_visible_mode_evidence(self) -> None:
        self.assertIn("mode_text + evidence.enhanced + evidence.degraded", self.bootstrap)
        self.assertIn('if runtime.mode_draw_count() > 0 then', self.app)
        self.assertIn('log_once("full_mode_logged", "full mode rendered")', self.app)
        self.assertIn('else\n    recover("selected-mode", "no visible mode-specific draw operation")', self.app)

    def test_adapter_statuses_require_an_underlying_call(self) -> None:
        self.assertIn('return "unavailable", nil, "missing member"', self.csp)
        self.assertIn('return "failed", nil, "member type="', self.csp)
        self.assertIn('return "drawn", result, nil', self.csp)
        self.assertIn('local status, _, detail = call_ui(name, unpack_values(arguments))', self.csp)
        self.assertIn('namespace.runtime.record_draw(kind or "enhanced")', self.csp)

    def test_callable_members_and_constructors_are_not_function_only(self) -> None:
        for source in (self.csp, self.bootstrap):
            self.assertIn('value_type == "userdata"', source)
            self.assertIn("metatable.__call", source)
        self.assertIn('construct("vec2"', self.csp)
        self.assertIn('construct("rgbm"', self.csp)
        self.assertIn("unsupported vector constructor", self.csp)

    def test_window_and_layout_fallbacks_are_explicit(self) -> None:
        self.assertLess(self.csp.index('call_ui("availableSpace")'), self.csp.index('call_ui("windowSize")'))
        self.assertIn('return 780, 380, "fallback"', self.csp)
        self.assertIn('function layout.valid', self.layout)
        self.assertIn('runtime.layout_strategy', self.app)
        self.assertIn('"flow layout selected"', self.app)
        self.assertIn("invalid or off-screen bounds", self.app)

    def test_invalid_alpha_and_clip_failures_do_not_silently_draw(self) -> None:
        self.assertIn("alpha > 0", self.csp)
        self.assertIn('ui.drawTextClipped:', self.csp)
        self.assertIn('runtime.record_draw("degraded")', self.csp)
        self.assertIn('compact.render_simplified(vm, state.mode)', self.app)

    def test_evidence_is_bounded_and_initialization_is_not_permanent(self) -> None:
        for field in ("native", "mode_text", "enhanced", "degraded", "skipped", "first_skip"):
            self.assertIn(field, self.bootstrap)
        self.assertIn('runtime.log_once("render_evidence_logged"', self.bootstrap)
        self.assertIn('if not lifecycle.mode_content_ready and not lifecycle.initialization_attempted then', self.bootstrap)
        self.assertIn('lifecycle.mode_content_ready = true', self.app)

    def test_bundle_scope_and_determinism(self) -> None:
        verify_deterministic()
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "first"
            second = Path(temp) / "second"
            first_manifest = build(first)
            second_manifest = build(second)
            self.assertEqual(first_manifest["bundle_sha256"], second_manifest["bundle_sha256"])
            first_bytes = (first / "AVM_PitWall_F1.lua").read_bytes()
            self.assertEqual(hashlib.sha256(first_bytes).hexdigest(), first_manifest["bundle_sha256"])
            bundle = (first / "AVM_PitWall_F1.lua").read_text(encoding="utf-8")
            self.assertEqual(forbidden_patterns(bundle), [])
            self.assertNotIn("require(", bundle)
            self.assertNotIn("dofile(", bundle)
            self.assertNotIn("Relay Server", bundle)
            self.assertNotIn("Driver Bridge", bundle)


if __name__ == "__main__":
    unittest.main()
