# Weather capability findings

Status: RESEARCH - SDK SURFACE INSPECTED, NOT RUNTIME-VALIDATED

The installed SDK candidate at
`E:\Games\Steam\steamapps\common\assettocorsa\extension\internal\lua-sdk`
is the primary evidence source for this assessment. SDK symbols prove that a
surface is documented. They do not prove that every CSP build, session type,
or server configuration produces reliable values at runtime.

Related documents:
[weather source capability matrix](weather-source-capability-matrix.md),
[CSP weather probe plan](csp-weather-probe-plan.md),
[weather forecast architecture](../architecture/weather-forecast-architecture.md),
[weather source selection](../architecture/weather-source-selection.md).

## Capability verdict

| Capability | Verdict | Evidence |
| --- | --- | --- |
| Read current weather fields in a generic CSP app | Documented SDK surface | `ac_apps/lib.lua:5295-5304,5365-5383` |
| Read one upcoming weather-type hint plus transition scalar | Documented SDK surface; semantics still need probing | `ac_apps/lib.lua:5383,7544-7558` |
| Read current track wetness and rain state | Documented SDK surface; runtime semantics still need probing | `ac_apps/lib.lua:5302-5304,7548-7558` |
| Read current track grip | Documented SDK surface | `ac_apps/lib.lua:5298` |
| Change weather time in generic apps | Narrow documented app surface; offline only | `ac_apps/README.md:18377-18383` |
| Set arbitrary weather conditions from a generic app | Not evidenced | No generic-app setter equivalent to controller setters was found |
| Set arbitrary weather conditions from a WeatherFX controller | Documented controller-only surface | `ac_wfx_controller/lib.lua:9598-9607` |
| Share typed weather data between Lua scripts | Documented SDK surface with layout and script-type constraints | `ac_apps/lib.lua:7161-7182,7221-7227,907-923` |
| Share weather data with a separate process | Memory-mapped file surface is documented; bridge-side interop still unproven | `ac_apps/lib.lua:7422-7432` |
| Know a full future weather schedule from current measurements alone | Unavailable | Current samples and a single transition hint do not define a schedule |

## What the SDK actually shows

- `ac.getSim()` documents current-state fields including
  `ambientTemperature`, `roadTemperature`, `roadGrip`, `windSpeedKmh`,
  `rainIntensity`, `rainWetness`, `rainWater`, `weatherType`, and the filtered
  `weatherConditions` structure at `ac_apps/lib.lua:5295-5304,5365-5383`.
- `ac.ConditionsSet` documents `currentType`, `upcomingType`, `transition`,
  temperature parameters, track-state parameters, wind parameters, humidity,
  pressure, and rain-related fields at `ac_apps/lib.lua:7544-7558`.
- `ac.setConditionsSet()` and `ac.setConditionsSet2()` exist only in the
  `ac_wfx_controller` surface, not in `ac_apps/lib.lua`, at
  `ac_wfx_controller/lib.lua:9598-9607`.
- `ac.connect()` is documented as a shared structure between Lua scripts with
  matched layouts, collision-avoidance keys, optional explicit ordering, and
  script-type restrictions at `ac_apps/lib.lua:7161-7182,7221-7227`.
- `ac.readMemoryMappedFile()` and `ac.writeMemoryMappedFile()` are the only
  inspected SDK surfaces that explicitly mention a separate process at
  `ac_apps/lib.lua:7424-7429`.

## Canonical terminology

The product must not collapse different evidence classes into a single
"forecast" label.

| Evidence class | UI label | Meaning |
| --- | --- | --- |
| Direct current measurement | Current | A present-tense observation with source and capture time |
| Direct current track state | Current track | Present surface condition, not a prediction |
| Single upcoming weather-type hint | Transition hint | A documented `upcomingType` plus `transition`, not a full schedule |
| Server or controller supplied future plan | Scheduled | Authoritative future plan as last received |
| Model output with uncertainty | Estimated | Derived forecast with explicit uncertainty |
| Missing or stale future evidence | Unknown | No future weather claim is justified |

## Immediate planning rule

AVM Race Engineer can safely plan around documented current-state fields now.
It must not promise authoritative future weather unless a probe proves the
runtime meaning of `upcomingType` and `transition`, or another source provides
an explicit schedule contract.
