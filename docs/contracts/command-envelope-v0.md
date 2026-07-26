# Command Envelope v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the F0 command envelope for engineer-to-driver messaging and lightweight race-operation intents. This is a contract draft only; it does not claim any live delivery path is implemented across `Engineer Console`, relay, bridge, or in-car surfaces.

## Exact Required Fields

- `schema_version`
- `command_id`
- `session_id`
- `target_driver_id`
- `target_car_id`
- `issuer_id`
- `command_type`
- `priority`
- `issued_at_utc`
- `expires_at_utc`
- `monotonic_sequence`
- `strategy_revision`
- `requires_acknowledgement`
- `payload`
- `idempotency_key`

## Field Semantics

- `schema_version` is the contract version string, independent of transport or deployment version.
- `command_id` is the immutable logical command identifier and remains stable across retries.
- `session_id`, `target_driver_id`, and `target_car_id` are mandatory routing guards. `target_driver_id` may be `null` for car-scoped commands, but the field itself must still be present.
- `issuer_id` identifies the operator, service account, or automation rule that authored the command.
- `command_type` is restricted to the enumerated F0 command vocabulary in the schema.
- `priority` is an ordering hint only and must not bypass wrong-session, wrong-car, duplicate, or expiry checks.
- `issued_at_utc` and `expires_at_utc` are RFC 3339 UTC timestamps.
- `monotonic_sequence` may be `null` until a sender-side monotonic counter exists, but the field must remain present for forward compatibility.
- `strategy_revision` may be `null` unless the command was generated from a specific strategy recommendation revision.
- `requires_acknowledgement` declares whether the sender expects a positive acknowledgement before considering the command complete.
- `payload` is command-specific and may contain `null` for known-but-unset optional values.
- `idempotency_key` is the retry key. Retries must preserve both `command_id` and `idempotency_key`.

## Retry, Duplicate, Expiry, And Safety Rules

- Duplicate delivery of the same `(command_id, idempotency_key)` must not execute the underlying action twice.
- Commands received after `expires_at_utc` must transition to `expired` with no side effects.
- Wrong-session or wrong-car commands must transition to `rejected`, not be silently dropped.
- A receiver must not auto-retarget a command to another session, driver, or car.
- Missing required fields are schema failures and must be audited as malformed inputs.

## Acknowledgement And Audit

- If `requires_acknowledgement = true`, the lifecycle must not end at `delivered`; it must progress to `displayed`, `accepted`, `rejected`, `expired`, or `failed`.
- Audit trails should retain `command_id`, `issuer_id`, the routing tuple `(session_id, target_driver_id, target_car_id)`, delivery timestamps, duplicate detection outcome, and the terminal lifecycle state.
- Command lifecycle semantics are defined in [command-lifecycle-v0.md](./command-lifecycle-v0.md).

## Schema

Authoritative draft schema: [command-envelope-v0.schema.json](./command-envelope-v0.schema.json)
