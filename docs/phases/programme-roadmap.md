# Programme Roadmap

## Scope

This roadmap describes the planned delivery sequence for AVM Race Engineer from foundation (`F0`) through closed team alpha (`F12`). It is intentionally forward-looking and should be read with the proposed ADRs in [../decisions](../decisions/).

## Phase Overview

| Phase | Focus | Depends On | Key Exit Signal |
| --- | --- | --- | --- |
| [F0](./F0-foundation.md) | foundation | none | ADR, testing, and roadmap baseline accepted |
| [F1](./F1-driver-client-shell.md) | driver client shell | F0 | CSP shell scope and packaging direction agreed |
| [F2](./F2-driver-bridge-poc.md) | driver bridge proof of concept | F1 | bridge telemetry path proven locally |
| [F3](./F3-relay-server.md) | relay server | F2 | authoritative relay path available |
| [F4](./F4-engineer-web.md) | Engineer Console | F3 | read-only operator dashboard usable |
| [F5](./F5-end-to-end-vertical-slice.md) | end-to-end vertical slice | F4 | first Bridge–Relay–Console–PitWall slice validated |
| [F6](./F6-telemetry-expansion.md) | telemetry expansion | F5 | richer telemetry coverage stable |
| [F7](./F7-map-and-traffic.md) | map and traffic | F6 | spatial and traffic workflows validated |
| [F8](./F8-engineer-commands.md) | engineer commands | F7 | explicit command acknowledgement path proven |
| [F9](./F9-strategy-workspace.md) | strategy workspace | F8 | strategy workflows usable from live or replay context |
| [F10](./F10-setup-transfer.md) | setup transfer | F9 | installation and team handoff rehearsed |
| [F11](./F11-reliability-and-security.md) | reliability and security | F10 | hardening and incident gates pass |
| [F12](./F12-closed-team-alpha.md) | closed team alpha | F11 | supervised alpha is supportable and reversible |

## Cross-Cutting Gates

- Testing model: [Testing Strategy](../testing/testing-strategy.md)
- PitWall constraint gate: [CSP Runtime Gate](../testing/csp-runtime-gate.md)
- Cross-stack journeys: [End-to-End Test Matrix](../testing/end-to-end-test-matrix.md)

## Roadmap Assumptions

- The prior `avm-pitwall` project remains a requirements reference only.
- No production release exists yet; all milestones below are programme intent, not completed capability.
- Relay, Bridge, Engineer Console, and PitWall are sequenced to de-risk CSP constraints first, observability second, and commands in the narrow F5 vertical slice after the read-only console baseline.
