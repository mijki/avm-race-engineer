# End-to-End Test Matrix

## Purpose

This matrix lists the planned cross-component scenarios that accumulate through the roadmap. It is a programme target, not a statement that the scenarios already exist.

| ID | Scenario | Components | First Phase | Automated Target | Manual Target |
| --- | --- | --- | --- | --- | --- |
| E2E-01 | Driver Bridge telemetry appears in Engineer Console through Relay Server | Bridge, Relay, Console | F5 | E2E harness | operator smoke |
| E2E-02 | PitWall shell receives live status with real CSP participation | Relay, PitWall | F5 | integration plus E2E | real AC/CSP |
| E2E-03 | BOX BOX command triggers client alert, sound, and driver acknowledgement visible in Engineer Console | Console, Relay, PitWall | F5 | E2E harness | real AC/CSP |
| E2E-04 | Reconnect after network interruption preserves idempotent state and does not duplicate BOX BOX effects | Bridge, Relay, Console, PitWall | F5 | E2E harness | operator plus CSP |
| E2E-05 | Duplicate command is suppressed and audited | Console, Relay, PitWall | F8 | E2E harness | operator review |
| E2E-06 | Expired command is rejected safely and shown clearly | Console, Relay, PitWall | F8 | E2E harness | operator review |
| E2E-07 | Wrong-session command is rejected without affecting active drivers | Console, Relay, PitWall | F8 | E2E harness | operator review |
| E2E-08 | Server restart preserves session safety and allows clean rejoin | Bridge, Relay, Console, PitWall | F10 | on-prem E2E | restart drill |
| E2E-09 | Timing, fuel, tyres, brakes, controls, damage, weather, and strategy telemetry remain coherent across the stack | Bridge, Relay, Console, PitWall | F6 | E2E harness | operator plus CSP |
| E2E-10 | Coordinates, team cars, public opponents, gaps, class, and traffic views stay consistent without private-opponent claims | Bridge, Relay, Console | F7 | E2E harness | operator walkthrough |
| E2E-11 | Setup transfer into a fresh environment succeeds with safe exchange controls | Relay, Console, PitWall package | F10 | on-prem validation | setup rehearsal |
| E2E-12 | Three-hour soak with multiple drivers, remote engineer, and intermittent network faults stays supportable | all | F11 | soak suite | supervised drill |
| E2E-13 | Real team practice, qualifying, endurance, driver swaps, and support runbook succeed in closed alpha | all | F12 | final alpha suite | supervised alpha |

## Usage Notes

- Each scenario should map back to a phase and at least one ADR.
- Real CSP participation is mandatory for client-participating scenarios; host-only runs are not equivalent.
- No scenario should claim private opponent data beyond public opponent visibility planned in F7.
