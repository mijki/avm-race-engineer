# Compatibility Policy v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines how the F0 contract set evolves without creating silent data corruption across `Driver Bridge`, `Relay Server`, `Engineer Console`, and any future strategy services.

## Versioning Policy

- Contract versions use semantic versioning with draft suffixes allowed during F0.
- Producers must emit an explicit `schema_version`; consumers must not infer it
  from transport path or deployment version.
- Minor-version additions may add optional fields but must not change the meaning of existing fields.
- Major-version changes may tighten semantics or remove fields only with a coordinated rollout plan.

## Null, Missing, And Unknown Fields

- `null` means the field name is known but no trustworthy value is available.
- Omitted means the field is not included in the current payload or contract surface.
- Unknown fields must be ignored safely unless the receiving contract explicitly marks `additionalProperties: false`.

## Freshness And Expiry Policy

- Staleness handling is contract data, not transport convention.
- Consumers must honor contract freshness and expiry metadata before using a value operationally.
- Sticky metadata may persist longer than high-rate telemetry but must still carry clear provenance.

## Idempotency Policy

- Commands, transfers, and telemetry retries must preserve their logical identifiers.
- Duplicate detection must be scoped by the relevant identity set, such as `(message_id)` or `(command_id, idempotency_key)`.

## Wrong-Session And Wrong-Car Policy

- Mismatched scope is a safety error, not a soft warning.
- Active-path consumers must reject mismatched session or car data and record the incident for audit.

## Audit Policy

- Audit logs should retain enough identifiers and timestamps to reconstruct who sent what, when, and why it was accepted or rejected.
- This policy does not yet mandate a specific storage backend or retention period.
