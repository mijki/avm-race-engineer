# Weather Forecast Test Matrix

## Purpose

This matrix defines the evidence required for weather-source provenance,
five-minute timeline shaping, degraded behavior, and weather-to-strategy
integration. It complements the broader [Forecast Engine Test Strategy](./forecast-engine-test-strategy.md).

## Provenance And Source-State Matrix

| Scenario | Source Shape | Expected Behavior | Minimum Levels |
| --- | --- | --- | --- |
| Current only | measured current weather and track condition, no future source | UI shows `CURRENT` plus `UNKNOWN` future state; no fabricated schedule or probability | unit, contract, CSP runtime |
| Current plus next transition | measured current state plus controller current-to-next transition | UI may show `TRENDING` or `ESTIMATED` next change with bounded confidence and explicit provenance | unit, replay, CSP runtime |
| Authoritative schedule | server or controller deliberately exposes future schedule | five-minute timeline may mark buckets `SCHEDULED` and `authoritative: true` | contract, integration, CSP runtime |
| AVM-derived trend | no authoritative future schedule, enough history for extrapolation | future buckets remain `ESTIMATED`, confidence decays by horizon, and interpolation is explicit | unit, replay |
| Source failure | provider throws, disconnects, or returns malformed data | timeline degrades to stale or unknown without reusing a dead provider indefinitely | unit, integration, on-prem |
| Source conflict | measured current state materially disagrees with future provider | current measured state wins for "now", future confidence degrades, and reason codes explain the conflict | unit, replay, integration |
| Stale source | source age exceeds freshness threshold | UI shows `STALE`, confidence drops, and recommendations avoid false precision | unit, contract, integration |
| Controller change | active weather controller changes mid-session | provenance changes explicitly, old source lineage is closed, and schedule assumptions are re-evaluated | replay, integration, CSP runtime |

## Timeline And Resampling Matrix

| Scenario | Expected Behavior | Minimum Levels |
| --- | --- | --- |
| Five-minute resampling | supported sources are resampled into `now`, `+5`, `+10`, `+15`, `+20`, `+25`, and `+30` minute buckets without claiming the source natively used that cadence | unit, contract |
| Interpolation | interpolated buckets are marked `interpolated: true` and never mistaken for authoritative schedule points | unit, contract |
| Missing buckets | gaps remain explicit and can collapse to `UNKNOWN` instead of silent carry-forward | unit, contract, integration |
| Horizon degradation | confidence and uncertainty widen as forecast horizon grows | unit, property, replay |
| Transition-only source | a simple current-to-next transition can inform near-term buckets but not a fabricated long timeline | unit, replay, CSP runtime |
| Mixed source cadence | coarse schedule and fine current measurements combine without overwriting each other's provenance | unit, integration |

## Runtime Evidence Matrix For F3A

| Probe Scenario | Evidence Required | Why It Matters |
| --- | --- | --- |
| Static dry | captured current conditions and track state in stable dry running | proves baseline field availability and freshness |
| Static wet | captured rain, wetness, and standing-water behavior in stable wet running | proves wet-field availability and scaling |
| Dynamic transition | captured state through dry-to-wet or wet-to-dry change | proves transition behavior and cadence assumptions |
| Online server | observed behavior on an online session with the active controller | distinguishes offline-only access from networked reality |
| Reconnect | disconnect and reconnect evidence with provider continuity or reset behavior | informs stale handling and lineage resets |
| Replay | replay-mode behavior captured separately from live sessions | avoids assuming replay parity with live runtime |
| Active controller behavior | exact fields exposed by the current controller path | prevents unsupported ownership claims |
| Upcoming condition availability | evidence for or against controller-provided next-condition access | shapes transition-provider design |
| Transition availability | evidence for or against explicit transition progress or timing access | shapes confidence and bucket interpolation rules |
| Future schedule availability | evidence for or against authoritative future-schedule access | determines whether `SCHEDULED` is supportable |
| Lua-to-Bridge IPC candidates | verified candidate paths, constraints, and unknowns | prevents unsupported C# interop claims |

## Strategy-Integration Checks

| Scenario | Expected Behavior | Minimum Levels |
| --- | --- | --- |
| Dry-to-wet transition | sample eligibility, pace model, tyre crossover, pit window, and fuel outlook all update with degraded confidence during the transition | replay, integration, CSP runtime |
| Wet-to-dry transition | drying rate, crossover, and pace recovery remain explicit and uncertainty-aware | replay, integration, CSP runtime |
| Unknown future weather | recommendation layer stays conservative and marks forecast uncertainty instead of inventing pit timing precision | unit, replay |
| Weather-source conflict | conflicting measured and forecast states widen uncertainty and may block strong recommendations | unit, replay, integration |
| Missing future source | driver gets compact unknown messaging; engineer gets source-health detail and explanation | contract, integration |

## Contract Checks

- `source_type`, `source_id`, `authoritative`, `interpolated`, `confidence`,
  `uncertainty`, and `reason_codes` must survive every serialization path.
- Rain probability may appear only when the upstream source genuinely provides
  it; intensity or confidence alone is insufficient.
- Five-minute buckets are display buckets, not proof that the source itself is
  authoritative at five-minute resolution.

## Related Documents

- [Forecast Engine Test Strategy](./forecast-engine-test-strategy.md)
- [F3A: Weather Capability Probe](../phases/F3A-weather-capability-probe.md)
