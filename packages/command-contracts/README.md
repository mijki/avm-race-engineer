# Command Contracts

Status: `Planned`

This package will define the commands, acknowledgements, and alert transport
shapes shared across AVM Race Engineer surfaces.

## Responsibilities

- Engineer-to-driver command payloads
- Driver acknowledgements and negative acknowledgements
- Alert severity, delivery, and resolution metadata
- Versioned compatibility rules for V1 migration

## Design Constraints

- Command semantics must remain driver-safe
- Priority and expiration rules must be explicit
- Every transport-visible breaking change requires a documented migration path

See [docs/ux/driver-alert-system.md](../../docs/ux/driver-alert-system.md).
