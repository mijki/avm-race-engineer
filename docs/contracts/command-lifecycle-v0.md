# Command Lifecycle v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the required lifecycle for `command-envelope-v0`. This is a behavioral contract draft only.

## Exact Lifecycle States

1. `created`
2. `sent`
3. `delivered`
4. `displayed`
5. `accepted`
6. `rejected`
7. `expired`
8. `applied`
9. `failed`

## Required Transition Semantics

- `created` means the envelope was assembled and passed sender-side schema validation.
- `sent` means the sender emitted the envelope onto the chosen transport.
- `delivered` means the recipient transport endpoint received the envelope.
- `displayed` means the driver-facing surface rendered or surfaced the command.
- `accepted` means the receiving surface or service accepted the instruction for application.
- `rejected` means the command was refused because of wrong session, wrong car, malformed payload, duplicate policy, or operator refusal.
- `expired` means `expires_at_utc` passed before safe acceptance or application.
- `applied` means the intended effect completed successfully.
- `failed` means delivery or application started but did not complete successfully.

## Retries And Duplicates

- Retries must preserve `command_id` and `idempotency_key`.
- Duplicate receipt of the same `(command_id, idempotency_key)` must not create a second `applied` transition.
- Duplicate messages may still generate an audit event, but they should resolve to the original lifecycle record instead of creating a new logical command.

## Expiry, Wrong Session, And Wrong Car

- A command may move to `expired` from `created`, `sent`, `delivered`, or `displayed`, but never from `applied`.
- Wrong-session and wrong-car detections must end in `rejected`.
- The rejection reason must explicitly distinguish `wrong_session` from `wrong_car`.

## Acknowledgement Rules

- When `requires_acknowledgement = true`, a lifecycle that stalls at `delivered` is incomplete.
- The normal acknowledgement-bearing path is `created -> sent -> delivered -> displayed -> accepted -> applied`.
- A command may be `displayed` and then still become `rejected`, `expired`, or `failed`.

## Audit Rules

- Every transition should retain timestamp, actor or subsystem, and reason.
- Audit logs should preserve the first-seen envelope, duplicate detections, and the terminal lifecycle state for the same logical command.
