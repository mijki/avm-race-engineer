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
    gap = 6.0
    outer_x, outer_y = 8.0, 8.0
    outer_width = max(300.0, width - 16.0)
    outer_height = max(180.0, height - 16.0)
    header_height = 48.0 if mode == "garage" else 44.0
    banner_height = 56.0 if critical else 38.0
    footer_height = 32.0 if mode == "garage" else 26.0
    content_y = outer_y + header_height + gap + banner_height + gap
    content_height = max(70.0, outer_height - header_height - banner_height - footer_height - gap * 4)
    cards: dict[str, tuple[float, float, float, float]] = {}
    if mode == "compact":
        weather_height = max(24.0, min(54.0, content_height * 0.27))
        grid_height = max(2.0, content_height - weather_height - gap)
        row_height = max(1.0, (grid_height - gap) / 2)
        column_width = (outer_width - gap) / 2
        cards["fuel"] = (outer_x, content_y, column_width, row_height)
        cards["weather"] = (outer_x, content_y + grid_height + gap, outer_width, weather_height)
    elif mode == "expanded":
        available = max(24.0 + 30.0 + 20.0, content_height - gap * 2)
        top_height = max(24.0, available * 0.28)
        middle_height = max(30.0, available * 0.34)
        if top_height + middle_height > available - 20.0:
            scale = max(0.0, (available - 20.0) / max(1.0, top_height + middle_height))
            top_height = max(24.0, top_height * scale)
            middle_height = max(30.0, middle_height * scale)
        bottom_height = max(20.0, available - top_height - middle_height)
        overflow = top_height + middle_height + bottom_height - available
        if overflow > 0:
            bottom_height = max(1.0, bottom_height - overflow)
        column_width = (outer_width - gap) / 2
        middle_y = content_y + top_height + gap
        cell_width = (outer_width - gap * 3) / 4
        cards["timing"] = (outer_x, content_y, column_width, top_height)
        cards["fuel"] = (outer_x, middle_y, cell_width, middle_height)
        bottom_y = middle_y + middle_height + gap
        cards["weather"] = (outer_x, bottom_y, outer_width * 0.74, bottom_height)
    else:
        available = max(30.0 + 24.0 + 24.0, content_height - gap * 2)
        top_height = max(30.0, available * 0.22)
        row_height = max(24.0, available * 0.39)
        if top_height + row_height > available - 24.0:
            scale = max(0.0, (available - 24.0) / max(1.0, top_height + row_height))
            top_height = max(30.0, top_height * scale)
            row_height = max(24.0, row_height * scale)
        cards["overview"] = (outer_x, content_y, outer_width, top_height)

    banner = (outer_x, outer_y + header_height + gap, outer_width, banner_height)
    return {
        "header": (outer_x, outer_y, outer_width, header_height),
        "stint_timing": cards.get("timing", cards.get("overview", banner)),
        "fuel": cards.get("fuel", cards.get("overview", banner)),
        "weather": cards.get("weather", cards.get("overview", banner)),
        "engineer_message": banner,
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
    count = int(runtime.globals().draw_count)
    return SmokeResult(True, count > 0, "lupa", count, None if count > 0 else "no visible draw operation")


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
    passed = count > 0 and any(expected in item for item in texts)
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
