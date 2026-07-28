from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps" / "driver-lua" / "src"


class PitContractBoundaryTests(unittest.TestCase):
    def test_runtime_contains_no_loader_or_networking_and_keeps_pit_adapter_fields(self) -> None:
        source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCE.rglob("*.lua"))
        self.assertNotRegex(source, r"\b(?:require|dofile)\s*\(")
        self.assertNotIn("websocket", source.lower())
        self.assertIn("isInPitlane", source)
        self.assertIn("isInPit", source)
        self.assertIn("PIT_ENTRY_CANDIDATE", source)
        self.assertIn("MANUAL_OVERRIDE", source)

    def test_pit_learning_does_not_redesign_renderers(self) -> None:
        pit = (SOURCE / "live" / "pit_learning.lua").read_text(encoding="utf-8")
        compact = (SOURCE / "ui" / "compact_mode.lua").read_text(encoding="utf-8")
        self.assertNotIn("function compact", pit)
        self.assertIn("components.card", compact)

    def test_storage_uses_new_marker_key_without_reusing_v1_settings_key(self) -> None:
        storage = (SOURCE / "adapters" / "storage.lua").read_text(encoding="utf-8")
        self.assertIn("avm_race_engineer_pit_markers_v1", storage)
        self.assertIn("pit-marker-record-v1", storage)
        self.assertIn("avm_race_engineer_f1_presentation_v1", storage)


if __name__ == "__main__":
    unittest.main()
