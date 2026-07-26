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


def forbidden_patterns(text: str) -> list[str]:
    return [pattern.pattern for pattern in FORBIDDEN_RUNTIME_PATTERNS if pattern.search(text)]


def local_count(text: str) -> int:
    return sum(1 for line in text.splitlines() if re.match(r"^local\s+", line))


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
        ui = {}
        function ui.windowSize() return { x = 780, y = 380 } end
        function ui.windowWidth() return 780 end
        function ui.windowHeight() return 380 end
        function ui.drawRectFilled(...) draw_count = draw_count + 1 end
        function ui.drawRect(...) draw_count = draw_count + 1 end
        function ui.drawLine(...) draw_count = draw_count + 1 end
        function ui.drawCircle(...) draw_count = draw_count + 1 end
        function ui.drawCircleFilled(...) draw_count = draw_count + 1 end
        function ui.drawTriangleFilled(...) draw_count = draw_count + 1 end
        function ui.text(...) draw_count = draw_count + 1 end
        function ui.textColored(...) draw_count = draw_count + 1 end
        function ui.textAligned(...) draw_count = draw_count + 1 end
        function ui.button(...) return false end
        function ui.checkbox(...) return false end
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
    runtime.globals().windowMain(0.016)
    count = int(runtime.globals().draw_count)
    return SmokeResult(True, count > 0, "lupa", count, None if count > 0 else "no visible draw operation")


def callback_smoke(bundle_path: Path) -> SmokeResult:
    if importlib.util.find_spec("lupa") is None:
        return SmokeResult(False, False, "unavailable", 0, "lupa is not installed; real callback execution is pending")
    try:
        return _lupa_smoke(bundle_path)
    except Exception as exc:  # narrow boundary for the host harness
        return SmokeResult(True, False, "lupa", 0, str(exc))
