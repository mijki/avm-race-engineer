# Weather Measurement v0

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Purpose

Defines the measured current weather and track-condition contract. This
contract is for direct observations only. It must not be used to imply a future
forecast.

## Required Fields

- `schema_version`
- `measurement_id`
- `session_id`
- `car_id`
- `track_id`
- `layout_id`
- `capture_time_utc`
- `capture_time_monotonic_ms`
- `sequence`
- `source_attribution`
- `freshness`
- `conditions`
- `confidence`
- `reason_codes`

## Measured Versus Forecast Rules

- Current observed conditions belong here.
- Future schedule, estimated future buckets, and trend-derived future claims do
  not belong here.
- `current_to_next_transition` may describe a directly exposed controller
  transition, but that still does not create a full authoritative timeline.

## Units

- temperature: degrees Celsius
- wind speed: metres per second
- wind direction: degrees from north
- rain intensity, track wetness, standing water, humidity, and track grip:
  normalized `0.0` to `1.0`

## Schema

Authoritative draft schema:
[weather-measurement-v0.schema.json](./weather-measurement-v0.schema.json)
