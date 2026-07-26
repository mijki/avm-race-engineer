# Transport And Storage Estimates

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Scope

This note estimates F0 rates for one selected driver and for three concurrently bridged drivers over exactly `3 hours`. These are planning assumptions only.

## Assumptions

- JSON is the first-slice transport recommendation because it is easier to inspect, debug, and replay while contracts are still moving.
- MessagePack is modeled at roughly `62%` of the equivalent JSON payload size.
- Rates below distinguish raw capture, local aggregation, network publish, browser render, recording cadence, and event-driven triggers.

## Stream Rates

| Stream | Raw capture | Local aggregation | Network publish | Browser render | Recording | Event-driven trigger | Avg JSON size |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Controls | `60 Hz` | `20 Hz` | `20 Hz` | `20 Hz` | `20 Hz` | threshold crossings and command context | `0.55 KB` |
| Motion | `60 Hz` | `20 Hz` | `10 Hz` | `10 Hz` | `10 Hz` | heavy-cornering snapshots | `0.75 KB` |
| Map | `20 Hz` | `10 Hz` | `5 Hz` | `5 Hz` | `5 Hz` | lap markers and pit entry or exit | `0.65 KB` |
| Fuel | `10 Hz` | `2 Hz` | `2 Hz` | `2 Hz` | `1 Hz` | lap close and pit-service events | `0.45 KB` |
| Tyres | `20 Hz` | `5 Hz` | `5 Hz` | `5 Hz` | `2 Hz` | pit out and threshold alerts | `0.75 KB` |
| Brakes | `20 Hz` | `5 Hz` | `5 Hz` | `5 Hz` | `2 Hz` | threshold alerts | `0.55 KB` |
| Damage | `10 Hz` | `1 Hz` | `1 Hz` | `1 Hz` | `1 Hz` | new damage only | `0.40 KB` |
| Competitors | `20 Hz` | `2 Hz` | `2 Hz` | `2 Hz` | `2 Hz` | overtake and traffic deltas | `1.20 KB` |
| Weather | `2 Hz` | `1 Hz` | `1 Hz` | `1 Hz` | `1 Hz` | weather-step changes | `0.35 KB` |
| Strategy | `1 Hz` | `0.2 Hz` | `0.2 Hz` | `0.2 Hz` | `0.2 Hz` | revision publication only | `0.70 KB` |
| Events | `0 Hz` | `0 Hz` | `0.05 Hz` | `0.05 Hz` | `0.05 Hz` | lap complete, flag, penalty, command ack | `0.40 KB` |
| Health | `2 Hz` | `1 Hz` | `1 Hz` | `1 Hz` | `1 Hz` | connection or source degradation | `0.30 KB` |

## Derived Publish And Recording Totals

Network-publish steady state per driver:

- controls: `20 * 0.55 = 11.00 KB/s`
- motion: `10 * 0.75 = 7.50 KB/s`
- map: `5 * 0.65 = 3.25 KB/s`
- fuel: `2 * 0.45 = 0.90 KB/s`
- tyres: `5 * 0.75 = 3.75 KB/s`
- brakes: `5 * 0.55 = 2.75 KB/s`
- damage: `1 * 0.40 = 0.40 KB/s`
- competitors: `2 * 1.20 = 2.40 KB/s`
- weather: `1 * 0.35 = 0.35 KB/s`
- strategy: `0.2 * 0.70 = 0.14 KB/s`
- events: `0.05 * 0.40 = 0.02 KB/s`
- health: `1 * 0.30 = 0.30 KB/s`

Total network publish per driver: `32.76 KB/s` JSON, about `20.31 KB/s` MessagePack.

Total recording per driver:

- same as network publish except fuel records at `1 Hz`, tyres at `2 Hz`, and brakes at `2 Hz`
- resulting steady rate: `28.41 KB/s` JSON, about `17.61 KB/s` MessagePack

## Exact 3-Hour Totals

Using `3 hours = 10,800 seconds`:

| Scope | Network JSON | Network MessagePack | Recording JSON | Recording MessagePack |
| --- | --- | --- | --- | --- |
| 1 driver | `32.76 * 10800 = 353.8 MB` | `20.31 * 10800 = 219.3 MB` | `28.41 * 10800 = 306.8 MB` | `17.61 * 10800 = 190.2 MB` |
| 3 drivers | `1,061.4 MB` | `657.9 MB` | `920.5 MB` | `570.5 MB` |

## Browser And Aggregation Notes

- Raw capture totals are intentionally higher than publish totals and should remain local to the bridge or local collector whenever possible.
- Browser render should track network publish for the visible streams, not raw capture.
- Competitor and traffic streams are the first place rate pressure increases once more than one driver is visible.
- Event streams remain bursty and small; they are not the main steady-state bandwidth risk.

## Recommendation

- Recommend JSON for the first slice.
- Keep the logical contracts transport-neutral so MessagePack can be added later if relay fan-out or archive size becomes painful.
