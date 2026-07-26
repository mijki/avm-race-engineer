# Programme Roadmap

## Scope

This roadmap describes the planned delivery sequence for AVM Race Engineer from
foundation (`F0`) through closed team alpha (`F13`). It is intentionally
forward-looking and should be read with the proposed ADRs in
[../decisions](../decisions/).

## Phase Overview

| Logical Phase | Focus | Depends On | Key Exit Signal |
| --- | --- | --- | --- |
| [F0](./F0-foundation.md) | foundation | none | ADR, testing, and roadmap baseline accepted |
| F0.1 | race and weather forecast foundation amendment | F0 | calculation ownership, weather provenance, contracts, and sequencing documented |
| [F1](./F1-driver-client-shell.md) | compact driver client shell with deterministic calculated and weather mocks | F0.1 | shell scope and mock-snapshot coverage agreed |
| [F2](./F2-driver-bridge-poc.md) | driver bridge proof of concept and raw telemetry capture | F1 | raw telemetry and identity path proven locally |
| [F3A](./F3A-weather-capability-probe.md) | weather capability and local IPC probe | F2 | CSP and controller weather capabilities evidenced and bounded |
| [F3](./F3-race-model-and-forecast-engine.md) | race model and forecast engine baseline | F2, F3A | Bridge-owned calculations and forecast contracts proven |
| [F4](./F3-relay-server.md) | relay server | F3 | authoritative distribution path available for calculated and forecast state |
| [F5](./F4-engineer-web.md) | Engineer Console read-only dashboard | F4 | read-only operator dashboard usable with measured and forecast state |
| [F6](./F5-end-to-end-vertical-slice.md) | first end-to-end vertical slice | F5 | first Bridge-Relay-Console-PitWall slice validated |
| F7 ([file](./F6-telemetry-expansion.md)) | telemetry and forecast expansion | F6 | richer telemetry and forecast coverage stable |
| F8 ([file](./F7-map-and-traffic.md)) | track map and traffic | F7 | spatial and traffic workflows validated |
| F9 ([file](./F8-engineer-commands.md)) | engineer commands | F8 | explicit command acknowledgement path proven |
| F10 ([file](./F9-strategy-workspace.md)) | strategy workspace and simulation | F9 | strategy workflows usable from live or replay context |
| F11 ([file](./F10-setup-transfer.md)) | setup transfer | F10 | installation and team handoff rehearsed |
| F12 ([file](./F11-reliability-and-security.md)) | reliability, security, and operations | F11 | hardening and incident gates pass |
| F13 ([file](./F12-closed-team-alpha.md)) | closed team alpha | F12 | supervised alpha is supportable and reversible |

## Cross-Cutting Gates

- Testing model: [Testing Strategy](../testing/testing-strategy.md)
- Forecast-specific coverage: [Forecast Engine Test Strategy](../testing/forecast-engine-test-strategy.md)
- Weather-source coverage: [Weather Forecast Test Matrix](../testing/weather-forecast-test-matrix.md)
- PitWall constraint gate: [CSP Runtime Gate](../testing/csp-runtime-gate.md)
- Cross-stack journeys: [End-to-End Test Matrix](../testing/end-to-end-test-matrix.md)

## Numbering Note

- `F0.1`, `F3A`, and the new downstream logical numbering are authoritative for
  programme sequencing.
- Existing filenames from the original F3-F12 run are retained where practical
  to avoid unnecessary link churn; the mapping above is the source of truth for
  logical ordering.

## Roadmap Assumptions

- The prior `avm-pitwall` project remains a requirements reference only.
- No production release exists yet; all milestones below are programme intent,
  not completed capability.
- Relay, Bridge, Engineer Console, and PitWall are sequenced to de-risk CSP
  constraints first, then weather capability evidence, then Bridge-owned live
  calculations before broader distribution and operator workflows.
