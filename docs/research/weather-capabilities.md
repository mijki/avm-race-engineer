# Weather capability findings

**Status: RESEARCH — API SURFACE INSPECTED, NOT RUNTIME-VALIDATED**

The installed SDK candidate at
`E:\Games\Steam\steamapps\common\assettocorsa\extension\internal\lua-sdk` is
the preferred local authority for this assessment. API presence is evidence of
a documented surface, not proof that a particular CSP version, session type, or
server exposes a reliable value.

## Capability verdict

| Capability | Verdict | Evidence |
| --- | --- | --- |
| Read current weather in a generic CSP app | Documented SDK surface | `ac_apps/lib.lua:4678-4684,5295-5304,5365-5383` |
| Read current track/rain state | Documented SDK surface; runtime semantics need probing | Same `ac.getSim()` weather fields |
| Change weather time in offline sessions | Narrow documented app surface | `ac_apps/lib.lua:15378-15389` |
| Set arbitrary conditions from a generic app | **Unknown / not evidenced** | No equivalent generic-app setter found |
| Set arbitrary conditions from a WeatherFX controller | Documented controller-only surface | `ac_wfx_controller/lib.lua:7544-7559,9598-9607` |
| Know future weather from current measurements | **Unavailable** | Future state does not follow from a current sample |
| Display server/controller schedule | Proposed when an authoritative source supplies it | Contract and integration work remain unimplemented |

Candidate current fields include ambient temperature, road temperature, wind
speed, rain intensity, rain wetness, rain water, weather type, and the filtered
weather-conditions structure. Every adopted field still needs a real CSP probe
that records session type, CSP build, source, null behavior, and update cadence.

## Canonical terminology

The product must not collapse different kinds of evidence into “forecast.”

| Evidence class | UI label | Meaning |
| --- | --- | --- |
| Measured current weather | **Current** | Direct observation with capture time and source |
| Measured current track state | **Current track** | Direct or documented surface condition |
| Derived change over recent samples | **Trending** | Statistical direction, not a promise |
| Model output with uncertainty | **Estimated** | Derived likelihood or time range |
| Server/controller-provided future plan | **Scheduled** | Authoritative schedule as last received, still subject to change |
| No authoritative future source | **Unknown** | No forecast claim is possible |

The Engineer Console should show source and age beside scheduled or estimated
future information. The AVM PitWall race view should use short wording such as
`RAIN TRENDING` or `RAIN SCHEDULED 10 MIN`; it must not show `RAIN IN 10 MIN`
unless the contract identifies an authoritative schedule source.

## Proposed source precedence

1. Preserve all raw observations with source and capture metadata.
2. Prefer a server/controller schedule for the **Scheduled** lane.
3. Compute **Trending** only from compatible, sufficiently fresh measurements.
4. Never promote a trend into a schedule.
5. Display **Unknown** when evidence is absent, stale, contradictory, or
   incompatible.

Related design: [telemetry capability matrix](telemetry-capability-matrix.md),
[telemetry envelope](../contracts/telemetry-envelope-v0.md), and
[driver alert system](../ux/driver-alert-system.md).
