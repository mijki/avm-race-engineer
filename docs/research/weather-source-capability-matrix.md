# Weather Source Capability Matrix

Status: RESEARCH - DRAFT, NOT IMPLEMENTED

This matrix compares the candidate weather sources inspected for AVM Race
Engineer. It is intentionally conservative and mirrors the authoritative detail
in [weather-source-capability-matrix.json](weather-source-capability-matrix.json).

Primary SDK evidence path:
`E:\Games\Steam\steamapps\common\assettocorsa\extension\internal\lua-sdk`

## Source Summary

| Source candidate | Runtime surface | Current observation | Transition hint | Authoritative schedule | Weather mutation | Cross-process readiness | F0 disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Standard Assetto Corsa shared memory | Driver Bridge shared-memory reader candidate | Candidate ambient temperature, road temperature, wind, and surface-grip fields; not verified in this amendment | No evidence | No evidence | No | Native external-process path, field semantics unproven | Inventory and probe in F2/F3A |
| CSP generic app sim state | `ac.getSim()` via `ac_apps/lib.lua` | Yes | Partial, via filtered `weatherConditions` | No evidence | No evidence | Not proven | Adopt for current-lane probe |
| CSP filtered conditions set | `ac.ConditionsSet` via `weatherConditions` | Yes | Yes, single upcoming type plus scalar transition | No evidence | No | Not proven | Keep as transition-hint probe only |
| WeatherFX controller | `ac_wfx_controller` setters | Controller can author conditions | Controller likely knows more internally, but read contract not proven here | Not proven as a generic-app or bridge read source | Yes | Not proven | Do not select as F0 read source |
| Shared Lua structure | `ac.connect()` | Indirect only | Indirect only | No | No | Lua-to-Lua only in inspected docs | Probe helper, not bridge contract |
| Memory-mapped file | `ac.readMemoryMappedFile()` / `ac.writeMemoryMappedFile()` | Indirect only | Indirect only | No | No | Best documented separate-process candidate | Controlled bridge POC candidate |

## Key Findings

- Generic apps document the current weather fields needed for a `Current`
  weather lane.
- Standard Assetto Corsa shared memory remains a Bridge-native current-field
  candidate, but its exact environmental fields, units, cadence, and session
  behavior were not proven by the installed CSP Lua SDK inspection.
- The filtered `weatherConditions` structure documents a narrow next-step hint:
  `currentType`, `upcomingType`, and `transition`.
- No inspected generic-app source documents a full future-weather schedule.
- Weather mutation is documented only on the WeatherFX controller surface.
- `ac.connect()` is useful for Lua-to-Lua sharing but does not document an
  external-process endpoint.
- Memory-mapped files are the only inspected surface that explicitly mentions a
  separate process.

## Interpretation Rule

The matrix should be read lane-by-lane:

- `Current observation` can be adopted when runtime probes succeed.
- `Transition hint` is not a schedule.
- `Authoritative schedule` remains unavailable until another source proves it.
- `Weather mutation` does not imply readback or scheduling authority for AVM.
