# MVP Definition

Status: `Planned`

## MVP Standard

The MVP for AVM Race Engineer is the smallest vertical slice that a real team
could trust for one live operational loop without the product becoming a hidden
source of risk.

## MVP Vertical Slice

The first MVP must cover this exact 14-step slice:

1. The driver starts Assetto Corsa.
2. Driver Bridge detects the session.
3. Driver Bridge reads basic telemetry.
4. Driver Bridge connects to the on-prem Relay Server.
5. The engineer opens Engineer Console.
6. Engineer Console shows driver online, car, track, session, speed, RPM, gear,
   fuel, and current lap.
7. The engineer sends `BOX BOX`.
8. Relay Server routes the command to the correct driver.
9. AVM PitWall displays a large visual `BOX BOX` alert.
10. AVM PitWall plays the alert sound.
11. The driver acknowledges the command.
12. Engineer Console shows the acknowledgement.
13. Disconnecting Relay Server does not crash or blank AVM PitWall.
14. Reconnecting does not display or apply the same command twice.

## MVP Must Include

- AVM PitWall with exactly three modes:
  Compact Race Mode, Expanded Race Mode, and Garage/Diagnostics Mode
- Driver-facing alert priorities, dedupe, repeat, and acknowledgement rules
- Engineer Console Live Overview plus the core navigation areas required for the
  vertical slice
- Driver Bridge to Relay Server to Engineer Console telemetry path
- `BOX BOX` command lifecycle visibility from issue through driver
  acknowledgement
- Server-disconnect degradation and reconnect idempotency
- System health and freshness visibility across the stack

## MVP Must Prove

- The driver can remain in Compact Race Mode and still receive all critical
  instructions safely
- The engineer can understand what requires action now from Live Overview
- Stale or disconnected data is visibly untrustworthy and does not masquerade as
  live control truth
- V1 compatibility-sensitive behavior is either preserved or explicitly called
  out as a deliberate divergence

## Explicitly Not Required For MVP

- Automated strategy execution without operator review
- Full historical analytics suites
- Multi-team administration depth beyond the minimum needed for safe access
- Full forecast-grade weather intelligence
- Setup transfer, which remains planned for F10 and must never apply silently
