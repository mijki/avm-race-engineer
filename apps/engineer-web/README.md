# Engineer Console

Status: `Planned`

Engineer Console is the browser-based engineering and strategy surface for AVM
Race Engineer. The repository directory remains `apps/engineer-web/`, but the
product-facing name should be Engineer Console.

## Responsibilities

- Present the ten-area information architecture led by Live Overview.
- Display source age and stale/error/empty states beside affected telemetry.
- Provide synchronized telemetry analysis, strategy planning, track/traffic,
  weather, communication, setup, history, access, and health workflows.
- Issue versioned commands and show their delivery, display, acknowledgement,
  expiry, and failure state.
- Require explicit driver consent before active strategy or setup state changes.

## Proposed technology

- [SvelteKit](https://svelte.dev/docs/kit/introduction) with TypeScript.
- Desktop-first responsive browser UI using a supported Node.js LTS toolchain
  selected and locked during F4.
- JSON contracts for the first vertical slice; charting and any MessagePack
  optimization require phase-specific evidence and dependency approval.

## Primary UX References

- [docs/ux/engineer-console-information-architecture.md](../../docs/ux/engineer-console-information-architecture.md)
- [docs/ux/setup-transfer-experience.md](../../docs/ux/setup-transfer-experience.md)
- [docs/ux/driver-alert-system.md](../../docs/ux/driver-alert-system.md)

## Out Of Scope

- Direct simulator telemetry capture
- In-car UI rendering
- Relay transport responsibilities
