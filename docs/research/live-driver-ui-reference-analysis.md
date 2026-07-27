# Live Driver UI Reference Analysis

Status: Research complete for the F2 live-driver slice

This note records a read-only inspection of the installed visual references.
It is a design input, not a source dependency.

## References inspected

- E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\CMRT-Complete-HUD\CMRT-Complete-HUD.lua
- E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\CMRT-Complete-HUD\fullscreen\first.lua
- E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\CMRT-Complete-HUD\damagepanel\first.lua
- E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\LapAlly_HUD\LapAlly_HUD.lua
- E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\LapAlly_HUD\resize.lua
- the installed CSP SDK ac_apps/README.md and ac_apps/lib.lua for drawing API confirmation

## Principles observed

- CMRT keeps high-attention values in stable bands and uses deliberate spacing
  between panels instead of relying on dense borders.
- LapAlly groups related values with consistent vertical rhythm, aligns numeric
  columns, and changes density at the window boundary rather than introducing
  race-mode scrolling.
- Both references use measured text/drawing primitives, clipping, and window
  dimensions to keep content inside a changing viewport.
- Strong primary values and quieter supporting labels make a glanceable
  hierarchy more effective than exposing every available telemetry field.

## Techniques adopted in AVM PitWall

- Layout is calculated from the current CSP window size with explicit boxes.
- Cards use restrained fills, borders, semantic accent colors, and clipped text.
- Compact and Expanded modes are fixed single-screen compositions.
- Garage uses a taller diagnostic surface because it is stationary-only.
- Every code-defined icon concept has a readable text label; no reference asset
  is required by the runtime bundle.

## Techniques not adopted

- No bitmap dashboard, logo, font, texture, or icon from either application.
- No one-for-one layout, color palette, panel arrangement, or source function.
- No opponent leaderboard, full-screen racing overlay, or reference-specific
  animation system.
- No external asset loading or remote networking in the PitWall slice.

## AVM visual distinction

AVM uses a dark charcoal surface, teal/cyan measured-data accent, restrained
raised cards, and a five-region Compact hierarchy: stint, fuel, pace/tyres,
weather/track, and engineer. The identity is intentionally text-first and
calculation-aware rather than a copy of either reference dashboard.
