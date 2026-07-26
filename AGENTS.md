# AVM Race Engineer Repository Contract

This repository defines the next AVM Race Engineer platform across four bounded
surfaces:

- `apps/driver-lua/`: **AVM PitWall**, the in-car CSP client
- `apps/driver-bridge/`: **Driver Bridge**, the Windows telemetry and command
  process
- `services/relay-server/`: **Relay Server**, the backend session and transport
  service
- `apps/engineer-web/`: **Engineer Console**, the browser engineering workspace

## Source Of Truth Rules

- Product naming is fixed: AVM Race Engineer, AVM PitWall, Driver Bridge, Relay
  Server, Engineer Console.
- Product intent and UX behavior live in `README.md`, component `README.md`
  files, `docs/product/`, and `docs/ux/`.
- Architecture, contracts, and phase docs must align with those names and may
  not silently redefine product behavior.
- The previous `avm-pitwall` repository is a V1 requirements and compatibility
  reference only. Do not copy V1 wholesale into this repository.

## Phase And Scope Discipline

- Work one declared phase or task at a time.
- Do not add production code from documentation alone unless the active phase or
  task explicitly calls for implementation.
- Do not install dependencies, introduce services, or widen scope unless the
  active task requires it.
- Update affected docs whenever terminology, behavior, or boundaries change.

## Component Boundary Rules

- AVM PitWall owns in-car presentation and driver-safe acknowledgements only.
- Driver Bridge owns local simulator collection, normalization, and transport to
  Relay Server.
- Relay Server owns backend relay, session presence, and transport-layer health.
- Engineer Console owns operator workflows, live overview, setup, and command
  issuing.
- Shared packages own contracts and pure domain logic, not runtime-specific side
  effects.

## Implementation Guardrails

- No runtime Lua `require` or `dofile` in the shipped AVM PitWall runtime path.
- Generated bundles are outputs, never hand-edited sources.
- No bare globals; every runtime surface must keep explicit ownership of state.
- CSP integration must stay behind an adapter boundary.
- Strategy and setup domain logic should remain pure and reusable.
- Strategy recommendations or setup changes must never apply silently; operator
  intent or explicit acknowledgement is required.
- Never commit secrets, credentials, or environment-specific sensitive data.

## Verification Rules

- Before claiming completion, run the relevant lint, typecheck, tests, and
  static scans for the changed scope.
- Distinguish clearly between simulated validation and real CSP/runtime
  validation; one does not imply the other.
- If a required verification step cannot run, say so explicitly with the reason.

## Git Safety

- Do not overwrite or revert unrelated user changes.
- Do not use destructive git operations unless explicitly requested.
- Do not push branches, tags, or history rewrites unless the user explicitly
  asks for that action.

## Current Documentation Map

- Product vision:
  [docs/product/product-vision.md](docs/product/product-vision.md)
- Scope and release framing:
  [docs/product/product-scope.md](docs/product/product-scope.md)
- Personas and stories:
  [docs/product/personas-and-user-stories.md](docs/product/personas-and-user-stories.md)
- MVP definition:
  [docs/product/mvp-definition.md](docs/product/mvp-definition.md)
- Non-goals:
  [docs/product/non-goals.md](docs/product/non-goals.md)
- V1 lessons and migration policy:
  [docs/product/v1-lessons.md](docs/product/v1-lessons.md)
- Driver UX:
  [docs/ux/driver-client-ux.md](docs/ux/driver-client-ux.md)
- Driver alerts:
  [docs/ux/driver-alert-system.md](docs/ux/driver-alert-system.md)
- Engineer Console IA:
  [docs/ux/engineer-console-information-architecture.md](docs/ux/engineer-console-information-architecture.md)
- Setup and transfer UX:
  [docs/ux/setup-transfer-experience.md](docs/ux/setup-transfer-experience.md)
