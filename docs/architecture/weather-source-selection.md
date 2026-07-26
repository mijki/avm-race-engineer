# AVM Race Engineer Weather Source Selection

Status: DRAFT

This document selects the candidate weather sources that AVM Race Engineer
should carry forward for probing and phased adoption.

Related documents:
[weather forecast architecture](weather-forecast-architecture.md),
[weather capabilities](../research/weather-capabilities.md),
[weather source capability matrix](../research/weather-source-capability-matrix.md),
[forecast model risks](../research/forecast-model-risks.md).

## Selection Summary

| Need | Selected candidate | Why | Current limit |
| --- | --- | --- | --- |
| Bridge-native current environment | Standard Assetto Corsa shared-memory inventory and probe | Could avoid a supplemental Lua path for fields already exposed to Driver Bridge | Exact environmental fields and semantics are not yet proven |
| Current weather and rain state | CSP generic app `ac.getSim()` fields | Direct documented read surface in the generic app SDK | Runtime cadence and null behavior still need probing |
| Current track grip | CSP generic app `roadGrip` | Direct documented field | Needs runtime validation across session types |
| Transition hint | Filtered `weatherConditions` / `ConditionsSet` | Documents `currentType`, `upcomingType`, and `transition` | Not a full schedule and not yet runtime-proven |
| Authoritative future schedule | None selected yet | No inspected generic-app surface publishes a full schedule | Must come from a later proven controller, plugin, or service |
| Estimated forecast | Deferred | Architecture can support it later without relabeling current data | Out of scope until current-source probes complete |
| Cross-process bridge handoff | Memory-mapped file proof of concept | Only inspected surface that explicitly mentions a separate process | Layout, synchronization, and ACLs remain AVM responsibilities |
| Lua-to-Lua helper | `ac.connect()` | Useful for same-session script exchange and probe fixtures | Not approved as a C# bridge contract |

## Why `ac.getSim()` Is The CSP Current-Lane Candidate

The installed SDK documents current generic-app weather fields at
`ac_apps/lib.lua:5295-5304,5365-5383`, including temperatures, wind, rain
state, `weatherType`, and filtered `weatherConditions`. That is enough to
justify a current-observation lane with medium confidence once runtime probes
confirm cadence and edge cases.

The selection is intentionally narrow:

- adopt current observations first;
- keep them clearly labeled as current;
- keep future-weather claims out of the lane.

F2 and F3A should first inventory the standard Assetto Corsa shared-memory
structures available to Driver Bridge. Any directly available ambient, road,
wind, or grip fields should use that Bridge-native path; the CSP supplemental
path remains necessary only for fields the standard structures do not prove.

## Why Transition Hints Stay Separate

`ac.ConditionsSet` documents `currentType`, `upcomingType`, and `transition` at
`ac_apps/lib.lua:7544-7558`. That is useful, but still narrower than a future
schedule contract:

- there is only one `upcomingType`;
- the SDK text does not define a clock-based ETA for `transition`;
- the structure does not publish a multi-step schedule;
- runtime semantics can differ by CSP build, mode, or controller.

Therefore AVM should ingest this surface, if probes confirm it, as a
`Transition hint` lane only.

## Why No Authoritative Schedule Is Selected Yet

The inspected generic-app surface does not expose a complete future-weather
schedule. The inspected WeatherFX controller surface documents setters
(`ac.setConditionsSet()` and `ac.setConditionsSet2()` at
`ac_wfx_controller/lib.lua:9598-9607`) but does not, by itself, prove that a
generic app or the external bridge can read the controller's authored schedule
in a durable contract shape.

Until that source exists and is proven, the future lane stays `Unknown` rather
than guessed.

## Why `ac.connect()` Is Not The Bridge Contract

`ac.connect()` is documented as a shared structure between Lua scripts with:

- identical layouts;
- optional uniqueness keys;
- optional explicit ordering; and
- script-type restrictions, including car-script-to-car-script and
  track-script-to-track-script limits.

Evidence: `ac_apps/lib.lua:7161-7182,7221-7227,907-923`.

That is valuable for Lua-side probes and fixtures. It is not enough evidence to
claim a supported C# interoperability contract for Driver Bridge.

## Why Memory-Mapped Files Stay In The Evaluation Set

`ac.readMemoryMappedFile()` and `ac.writeMemoryMappedFile()` explicitly mention
retaining state when created by "a separate process" at
`ac_apps/lib.lua:7424-7429`. That makes memory-mapped files the strongest
documented candidate for a Bridge-facing proof of concept.

Even so, AVM still must prove:

- layout versioning;
- explicit ordering and alignment;
- synchronization and torn-read behavior;
- cleanup rules;
- ACL and local-scope behavior on Windows.

## Phase Rule

Until the probe plan completes:

- current weather may be designed as current observation;
- transition hints may be designed as conditional hints;
- authoritative schedule remains unavailable;
- model-based forecasting remains out of scope for delivery claims.
