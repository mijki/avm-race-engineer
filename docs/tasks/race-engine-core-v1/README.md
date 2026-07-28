# AVM Race Engineer — Race Engine Core V1

Place this folder in:

`E:\Work\Repos\avm-race-engineer\docs\tasks\race-engine-core-v1`

## Execution order

1. `shared-execution-rules.md`
2. `task-01-telemetry-event-contracts.md`
3. `task-02-csp-telemetry-runtime.md`
4. `task-03-automatic-pit-learning.md`

Run all three tasks sequentially on:

`feat/race-engine-core-v1`

Required commits:

1. `Stabilize telemetry and race event contracts`
2. `Harden live CSP telemetry runtime`
3. `Implement automatic pit lane learning`

Each task remains a separate slice with its own scope, tests, gate, and commit.

Later roadmap:

4. Purpose-specific lap eligibility
5. Stint calculation engine
6. Race and pit forecast engine
7. Stable driver-status view model
