# AVM Race Engineer

AVM Race Engineer is a distributed endurance-racing engineering platform for
Assetto Corsa and Custom Shaders Patch.

## Current Status

This repository is in the foundation and architecture phase as of 2026-07-26.
No production release exists yet. Product and UX documents in this repository
describe either:

- `Reference` behavior inherited from the previous V1 implementation
- `Planned` behavior intended for the first release from this repository
- `Proposed` behavior that still requires validation before it becomes planned

## Platform Components

- **AVM PitWall:** compact in-car CSP Lua display and communication client
- **Driver Bridge:** Windows telemetry collector and communication service
- **Relay Server:** on-prem real-time telemetry and command relay
- **Engineer Console:** browser-based engineering, telemetry, and strategy
  console housed in `apps/engineer-web/`

Detailed responsibility boundaries live in the component READMEs:

- [apps/driver-lua/README.md](apps/driver-lua/README.md)
- [apps/driver-bridge/README.md](apps/driver-bridge/README.md)
- [services/relay-server/README.md](services/relay-server/README.md)
- [apps/engineer-web/README.md](apps/engineer-web/README.md)
- [packages/telemetry-contracts/README.md](packages/telemetry-contracts/README.md)
- [packages/command-contracts/README.md](packages/command-contracts/README.md)
- [packages/strategy-domain/README.md](packages/strategy-domain/README.md)

## Product Documentation

- [docs/product/product-vision.md](docs/product/product-vision.md)
- [docs/product/product-scope.md](docs/product/product-scope.md)
- [docs/product/personas-and-user-stories.md](docs/product/personas-and-user-stories.md)
- [docs/product/mvp-definition.md](docs/product/mvp-definition.md)
- [docs/product/non-goals.md](docs/product/non-goals.md)
- [docs/product/v1-lessons.md](docs/product/v1-lessons.md)

## UX Documentation

- [docs/ux/driver-client-ux.md](docs/ux/driver-client-ux.md)
- [docs/ux/driver-alert-system.md](docs/ux/driver-alert-system.md)
- [docs/ux/engineer-console-information-architecture.md](docs/ux/engineer-console-information-architecture.md)
- [docs/ux/setup-transfer-experience.md](docs/ux/setup-transfer-experience.md)

## Foundation Index

- [System context](docs/architecture/system-context.md)
- [Component boundaries](docs/architecture/component-boundaries.md)
- [Telemetry envelope draft](docs/contracts/telemetry-envelope-v0.md)
- [Command envelope draft](docs/contracts/command-envelope-v0.md)
- [Telemetry capability matrix](docs/research/telemetry-capability-matrix.md)
- [Security boundaries](docs/operations/security-boundaries.md)
- [Testing strategy](docs/testing/testing-strategy.md)
- [Programme roadmap](docs/phases/programme-roadmap.md)

## V1 Reference Implementation

The previous `avm-pitwall` repository remains the V1 reference for driver-safe
behavior, CSP compatibility, and command semantics. It is a requirements and
migration reference, not a source for wholesale code copy. The lessons and
migration policy are documented in
[docs/product/v1-lessons.md](docs/product/v1-lessons.md).

## Repository Layout

- `apps/` user-facing applications and runtime clients
- `services/` network-facing backend services
- `packages/` shared contracts and domain logic
- `tests/` cross-component and regression verification
- `tools/` developer and release tooling
- `deploy/docker/` containerized local and deployment packaging
- `docs/` product, UX, architecture, decisions, and phase artifacts
