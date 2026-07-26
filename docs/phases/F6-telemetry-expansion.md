# F6: Telemetry Expansion

## Goal
Broaden telemetry coverage beyond the first vertical slice while preserving contract stability.

## Dependencies
F5.

## Deliverables
Expanded telemetry for timing, fuel, tyres, brakes, controls, damage, weather, strategy, and recording, plus fixture and view updates.

## Exclusions
Command-catalog expansion, setup transfer, and non-telemetry hardening work.

## Implementation Sequence
1. Add timing, fuel, tyres, brakes, controls, damage, weather, strategy, and recording telemetry in priority order.
2. Extend Relay Server, Engineer Console, and PitWall-facing contracts without breaking the validated slice.
3. Re-check client impact for any driver-facing telemetry summaries.

## Automated Tests
Contract, component, and end-to-end updates covering timing, fuel, tyres, brakes, controls, damage, weather, strategy, and recording.

## Manual Tests
Operator review of the expanded Engineer Console surfaces plus CSP validation for any new driver-facing summaries.

## CSP Runtime Requirements
Required when added telemetry changes driver-facing status assumptions; otherwise document non-impact explicitly.

## Security
Preserve least exposure and avoid assuming all telemetry must be visible to every operator role.

## Exit Criteria
Telemetry breadth increases across timing, fuel, tyres, brakes, controls, damage, weather, strategy, and recording without destabilizing the vertical slice.

## Rollback
Defer low-value telemetry families if schema churn threatens downstream reliability.

## Risks
Schema bloat, UI overload, and drift between operator and driver-facing interpretations.

## Complexity
large

## Clean-Thread Recommendation
Yes - start map and traffic work in a new thread so spatial features can evolve against a stable telemetry baseline.
