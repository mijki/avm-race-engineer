# CSP Weather Probe Plan

Status: RESEARCH - PLANNED, NOT IMPLEMENTED

This plan defines the minimum runtime probes required before AVM Race Engineer
can claim more than a documented SDK surface for weather.

Primary SDK evidence path:
`E:\Games\Steam\steamapps\common\assettocorsa\extension\internal\lua-sdk`

## Probe Goals

1. Prove the runtime cadence and null behavior of current weather fields from
   `ac.getSim()`.
2. Determine the real runtime meaning of `weatherConditions.currentType`,
   `upcomingType`, and `transition`.
3. Confirm when `roadGrip`, `rainWetness`, and `rainWater` change relative to
   visible rain events.
4. Prove whether a generic app can safely hand weather snapshots to Driver
   Bridge through a cross-process channel.
5. Record the CSP build, session mode, and weather-controller context for every
   result.

## Required Probe Matrix

| Probe ID | Question | Runtime surface | Modes to test | Evidence to capture |
| --- | --- | --- | --- | --- |
| WTH-01 | Do current fields update and stay populated? | `ac.getSim()` current fields | offline fixed weather, offline dynamic WeatherFX, online server session | sampled values, cadence, null/zero behavior |
| WTH-02 | Does `roadGrip` react in a useful way? | `ac.getSim().roadGrip` | dry offline, rain onset offline, wet online | value trend, lag versus visible conditions |
| WTH-03 | What does `upcomingType` actually mean? | `ac.getSim().weatherConditions` | WeatherFX transitions, static weather, online conditions | current type, upcoming type, transition progression |
| WTH-04 | Can `transition` support ETA claims? | `ac.getSim().weatherConditions.transition` | long and short transitions | transition progression over wall-clock time |
| WTH-05 | Are `trackState` and rain fields internally coherent? | `ac.ConditionsSet` fields | dry to wet to dry | rainIntensity, rainWetness, rainWater, trackState snapshots |
| WTH-06 | Can generic apps bridge data to an external process safely? | memory-mapped file POC | local offline and online | layout version, torn-read checks, reconnect behavior |
| WTH-07 | Does `ac.connect()` help only Lua probes? | `ac.connect()` with namespaces | app-to-app, app-to-car-script, app-to-track-script where allowed | success/failure by script type and namespace |

## Probe Method Rules

- Record the exact CSP build date or version under test.
- Record whether the runtime surface is `ac_apps`, `ac_wfx_controller`, or a
  different script type.
- Record session type, weather controller, track, and whether the run is
  offline or online.
- Keep raw captures with timestamps so future docs can distinguish stale data
  from true zeros.
- If a field remains zero or nil, record whether the runtime conditions should
  have produced a non-zero value.

## Evidence Boundaries To Respect

- `ac.connect()` is documented with matched layouts, namespaces, and
  script-type restrictions at `ac_apps/lib.lua:7161-7182,907-923`.
- `ac.readMemoryMappedFile()` and `ac.writeMemoryMappedFile()` are the only
  inspected surfaces that explicitly mention a separate process at
  `ac_apps/lib.lua:7424-7429`.
- `rules.json` marks `ac_track_script`, `ac_car_cphys`, and
  `ac_car_scriptable_display` with `"withoutIO": true`, so cross-process probes
  should begin in the generic app surface rather than assuming every script
  type has the same IO capabilities.

## Exit Criteria

The weather-source selection can advance when AVM has:

- at least one successful current-field capture set for offline and online
  sessions;
- at least one probe showing whether `upcomingType` and `transition` are stable
  enough for a `Transition hint` label;
- one documented cross-process proof or rejection path for bridge handoff;
- a written list of fields that stay current-only, hint-only, or unavailable.
