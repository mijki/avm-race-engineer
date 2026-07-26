# Strategy Domain

Status: `Proposed`

This package is intended to hold shared strategy and race-state interpretation
logic once the telemetry and command contracts are stable.

## Likely Responsibilities

- Fuel and stint state interpretation
- Pit-window and target-lap calculations
- Gap and class-position summary helpers
- Engineer-facing recommendation logic

## Not Yet Locked

- Exact package boundaries
- Whether recommendation logic is fully shared or partly server-owned
- The first release scope of automated strategy assistance
