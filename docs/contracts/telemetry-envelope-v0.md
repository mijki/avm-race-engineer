# Telemetry Envelope v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the F0 telemetry envelope shared across local capture, relay publication, and `Engineer Console` consumption. This is a contract draft only; it does not claim any running producer or consumer exists.

## Required Envelope Content

Every envelope must clearly contain:

- capture UTC time
- capture monotonic time
- sequence information
- session identity
- car identity
- source attribution
- age
- validity
- compatibility

## Exact Required Fields

- `schema_version`
- `message_id`
- `category`
- `session_id`
- `car_id`
- `capture_time_utc`
- `capture_time_monotonic_ms`
- `sequence`
- `source_attribution`
- `age_ms`
- `valid_until_utc`
- `compatibility`
- `payload`

## Field Semantics

- `capture_time_utc` is the wall-clock capture time in RFC 3339 UTC.
- `capture_time_monotonic_ms` is the sender-local monotonic timestamp captured with the same observation so age and ordering can survive wall-clock jumps.
- `sequence.stream_id` and `sequence.sequence_number` are the ordered stream coordinates for duplicate detection and replay.
- `session_id` and `car_id` are mandatory routing guards. Wrong-session and wrong-car envelopes must be quarantined, not merged into active state.
- `source_attribution` records which component observed or derived the value and how much trust to assign.
- `age_ms` is the sender-computed age at serialization time.
- `valid_until_utc` is the explicit operational validity horizon for this observation bundle.
- `compatibility` records the producer family and version plus whether the bridge path is required for meaningful interpretation.
- `payload` contains category-specific fields and may use `null` for known-but-unavailable values.

## Ordering, Freshness, And Audit

- Duplicate `(stream_id, sequence_number)` pairs must be treated as retries, not new observations.
- Consumers should reject or flag envelopes whose `valid_until_utc` is already in the past.
- Audit trails should retain `message_id`, `(session_id, car_id)`, sequence coordinates, duplicate outcome, and stale outcome.
- This draft intentionally leaves transport framing open so JSON and MessagePack remain viable.

## Schema

Authoritative draft schema: [telemetry-envelope-v0.schema.json](./telemetry-envelope-v0.schema.json)
