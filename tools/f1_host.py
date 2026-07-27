"""Host-side Lua bundle inspection and optional callback smoke execution."""

from __future__ import annotations

import importlib.util
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any


FORBIDDEN_RUNTIME_PATTERNS = (
    re.compile(r"\brequire\s*\("),
    re.compile(r"\bdofile\s*\("),
    re.compile(r"\bloadfile\s*\("),
    re.compile(r"\bloadstring\s*\("),
    re.compile(r"\b(web|http|https|socket|WebSocket|SignalR)\b", re.IGNORECASE),
)


@dataclass(frozen=True)
class ParseResult:
    backend: str
    files: tuple[Path, ...]


@dataclass(frozen=True)
class SmokeResult:
    available: bool
    passed: bool
    backend: str
    draw_count: int
    error: str | None = None
    visible_text: tuple[str, ...] = ()


def forbidden_patterns(text: str) -> list[str]:
    return [pattern.pattern for pattern in FORBIDDEN_RUNTIME_PATTERNS if pattern.search(text)]


def local_count(text: str) -> int:
    return sum(1 for line in text.splitlines() if re.match(r"^local\s+", line))


def required_layout_boxes(width: int, height: int, mode: str = "compact", critical: bool = False) -> dict[str, tuple[float, float, float, float]]:
    """Mirror the F1 layout's bounded geometry for host visibility checks."""
    margin = 8.0
    gap = 6.0
    outer_height = max(1.0, height - 12.0)
    header_height = 32.0 if mode == "garage" else max(28.0, min(34.0, height * 0.09))
    outer_width = width - margin * 2
    header = (margin, 6.0, outer_width, header_height)
    content = (0.0, 0.0, float(width), float(height))
    if mode == "compact":
        footer_height = max(42.0, min(54.0, height * 0.13))
        body_y = 6.0 + header_height + gap
        footer_y = 6.0 + outer_height - footer_height
        body_height = max(1.0, footer_y - gap - body_y)
        large = width >= 850
        primary_height = max(76.0, min(128.0, body_height * 0.50)) if large else max(62.0, min(112.0, body_height * 0.32))
        pit_height = primary_height if large else max(50.0, min(78.0, body_height * 0.23))
        secondary_height = body_height - primary_height - (gap if large else gap * 2) - (0 if large else pit_height)
        primary_width = (outer_width - gap * 2) / 3 if large else (outer_width - gap) / 2
        secondary_width = (outer_width - gap) / 2
        secondary_y = body_y + primary_height + gap if large else body_y + primary_height + gap + pit_height + gap
        return {
            "content": content,
            "header": header,
            "stint_timing": header,
            "fuel": (margin, body_y, primary_width, primary_height),
            "pace": (margin + primary_width + gap, body_y, primary_width, primary_height),
            "pit": (margin + (primary_width + gap) * 2, body_y, primary_width, primary_height) if large else (margin, body_y + primary_height + gap, outer_width, pit_height),
            "tyres": (margin, secondary_y, secondary_width, secondary_height),
            "weather": (margin + secondary_width + gap, secondary_y, secondary_width, secondary_height),
            "engineer_message": (margin, footer_y, outer_width, footer_height),
            "fallback_shell": (10.0, 10.0, max(160.0, width - 20.0), max(120.0, height - 20.0)),
        }
    if mode == "expanded":
        body_y = 6.0 + header_height + gap
        body_height = max(1.0, 6.0 + outer_height - body_y)
        left_width = outer_width * 0.43
        right_x = margin + left_width + gap
        right_width = outer_width - left_width - gap
        row_height = max(24.0, (body_height - gap * 4) / 5)
        left_card_height = max(24.0, (body_height - gap * 2) / 3)
        return {
            "content": content,
            "header": header,
            "stint_timing": (right_x, body_y, right_width, row_height),
            "fuel": (margin, body_y, left_width, left_card_height),
            "pace": (margin, body_y + left_card_height + gap, left_width, left_card_height),
            "pit": (margin, body_y + (left_card_height + gap) * 2, left_width, left_card_height),
            "weather": (right_x, body_y + (row_height + gap) * 3, right_width, row_height),
            "engineer_message": (right_x, body_y + row_height + gap, right_width, row_height),
            "tyres": (right_x, body_y + (row_height + gap) * 2, right_width, row_height),
            "connections": (right_x, body_y + (row_height + gap) * 4, right_width, row_height),
            "fallback_shell": (10.0, 10.0, max(160.0, width - 20.0), max(120.0, height - 20.0)),
        }
    body_y = 6.0 + header_height + gap
    overview_height = 50.0
    controls_y = body_y + overview_height + gap
    controls_height = min(160.0, max(86.0, 6.0 + outer_height - controls_y - gap - 1.0))
    diagnostics_y = controls_y + controls_height + gap
    diagnostics_height = max(1.0, 6.0 + outer_height - diagnostics_y)
    overview = (margin, body_y, outer_width, overview_height)
    return {
        "content": content,
        "header": header,
        "stint_timing": overview,
        "fuel": overview,
        "weather": overview,
        "engineer_message": (margin, diagnostics_y, outer_width, diagnostics_height),
        "fallback_shell": (10.0, 10.0, max(160.0, width - 20.0), max(120.0, height - 20.0)),
    }


def box_intersects_window(box: tuple[float, float, float, float], width: int, height: int) -> bool:
    x, y, box_width, box_height = box
    return box_width > 0 and box_height > 0 and x < width and y < height and x + box_width > 0 and y + box_height > 0


def parse_lua_files(paths: list[Path]) -> ParseResult:
    if importlib.util.find_spec("luaparser") is not None:
        from luaparser import ast  # type: ignore[import-not-found]

        for path in paths:
            ast.parse(path.read_text(encoding="utf-8"))
        return ParseResult("luaparser", tuple(paths))
    luac = shutil.which("luac")
    if luac:
        for path in paths:
            subprocess.run([luac, "-p", str(path)], check=True, capture_output=True, text=True)
        return ParseResult("luac -p", tuple(paths))
    # This fallback is intentionally not treated as CSP proof. It catches the
    # most common accidental corruption while making the host suite runnable
    # in a clean checkout without downloading a toolchain.
    for path in paths:
        text = path.read_text(encoding="utf-8")
        if text.count("{") != text.count("}") or text.count("(") != text.count(")"):
            raise SyntaxError(f"unbalanced delimiters in {path}")
        if "-- AVM PitWall F1 deterministic runtime bundle" in text and "function" not in text:
            raise SyntaxError(f"bundle has no functions: {path}")
    return ParseResult("static-fallback (not CSP proof)", tuple(paths))


def _lupa_smoke(bundle_path: Path) -> SmokeResult:
    from lupa import LuaRuntime  # type: ignore[import-not-found]

    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
        draw_count = 0
        draw_texts = {}
        ui = {}
        script = {}
        function ui.windowSize() return { x = 780, y = 380 } end
        function ui.windowWidth() return 780 end
        function ui.windowHeight() return 380 end
        function ui.drawRectFilled(...) draw_count = draw_count + 1 end
        function ui.drawRect(...) draw_count = draw_count + 1 end
        function ui.drawLine(...) draw_count = draw_count + 1 end
        function ui.drawCircle(...) draw_count = draw_count + 1 end
        function ui.drawCircleFilled(...) draw_count = draw_count + 1 end
        function ui.drawTriangleFilled(...) draw_count = draw_count + 1 end
        function ui.drawText(value, ...) draw_count = draw_count + 1; draw_texts[#draw_texts + 1] = value end
        function ui.drawTextClipped(...) draw_count = draw_count + 1 end
        function ui.text(...) draw_count = draw_count + 1 end
        function ui.textColored(...) draw_count = draw_count + 1 end
        function ui.textAligned(...) draw_count = draw_count + 1 end
        function ui.button(...) return false end
        function ui.checkbox(...) return false end
        function ui.setCursorScreenPos(...) end
        function ui.invisibleButton(...) return false end
        function ui.sameLine(...) end
        function ui.newLine(...) end
        function ui.separator(...) end
        rgbm = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        vec2 = function(x, y) return { x = x or 0, y = y or x or 0 } end
        ac = { AudioEvent = { fromFile = function(_) return { start = function(_) end } end } }
        function ac.isAudioReady() return true end
        """
    )
    source = bundle_path.read_text(encoding="utf-8")
    runtime.execute(source)
    runtime.globals().script.windowMain(0.016)
    script_count = int(runtime.globals().draw_count)
    runtime.globals().windowMain(0.016)
    count = int(runtime.globals().draw_count)
    return SmokeResult(True, count > script_count and count > 0, "lupa", count, None if count > 0 else "no visible draw operation")


def _lupa_stage_failure_smoke(bundle_path: Path, stage: str, mode: str | None = None) -> SmokeResult:
    from lupa import LuaRuntime  # type: ignore[import-not-found]

    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
        draw_count = 0
        draw_texts = {}
        ui = {}
        script = {}
        function ui.windowSize() return { x = 780, y = 380 } end
        function ui.drawRectFilled(...) draw_count = draw_count + 1 end
        function ui.drawRect(...) draw_count = draw_count + 1 end
        function ui.drawLine(...) draw_count = draw_count + 1 end
        function ui.drawCircle(...) draw_count = draw_count + 1 end
        function ui.drawCircleFilled(...) draw_count = draw_count + 1 end
        function ui.drawTriangleFilled(...) draw_count = draw_count + 1 end
        function ui.drawText(value, ...) draw_count = draw_count + 1; draw_texts[#draw_texts + 1] = value end
        function ui.drawTextClipped(value, ...) draw_count = draw_count + 1; draw_texts[#draw_texts + 1] = value end
        function ui.text(value) draw_count = draw_count + 1; draw_texts[#draw_texts + 1] = value end
        function ui.textColored(value, ...) draw_count = draw_count + 1; draw_texts[#draw_texts + 1] = value end
        function ui.button(...) return false end
        function ui.checkbox(...) return false end
        function ui.setCursorScreenPos(...) end
        function ui.invisibleButton(...) return false end
        function ui.sameLine(...) end
        function ui.newLine(...) end
        function ui.separator(...) end
        rgbm = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        vec2 = function(x, y) return { x = x or 0, y = y or x or 0 } end
        ac = { AudioEvent = { fromFile = function(_) return { start = function(_) end } end } }
        function ac.isAudioReady() return true end
        """
    )
    runtime.execute(bundle_path.read_text(encoding="utf-8"))
    globals = runtime.globals()
    globals.AVM_PITWALL_F1.runtime.test_fail_stage = stage
    if mode is not None:
        globals.AVM_PITWALL_F1.app_state.initialize()
        globals.AVM_PITWALL_F1.app_state.mode = mode
        globals.AVM_PITWALL_F1.app_state.dirty = true
    globals.script.windowMain(0.016)
    count = int(globals.draw_count)
    texts = tuple(str(item) for item in globals.draw_texts.values())
    expected = "Stage: " + stage
    passed = count > 0 and (stage == "audio" or any(expected in item for item in texts))
    return SmokeResult(True, passed, "lupa", count, None if passed else f"no recovery text for {stage}", texts)


def stage_failure_smoke(bundle_path: Path, stage: str, mode: str | None = None) -> SmokeResult:
    if importlib.util.find_spec("lupa") is None:
        return SmokeResult(False, False, "unavailable", 0, "lupa is not installed; forced callback execution is pending")
    try:
        return _lupa_stage_failure_smoke(bundle_path, stage, mode)
    except Exception as exc:  # narrow boundary for the host harness
        return SmokeResult(True, False, "lupa", 0, str(exc))


def callback_smoke(bundle_path: Path) -> SmokeResult:
    if importlib.util.find_spec("lupa") is None:
        return SmokeResult(False, False, "unavailable", 0, "lupa is not installed; real callback execution is pending")
    try:
        return _lupa_smoke(bundle_path)
    except Exception as exc:  # narrow boundary for the host harness
        return SmokeResult(True, False, "lupa", 0, str(exc))
