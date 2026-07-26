# F10: Setup Transfer

## Goal
Make the system installable, transferable, and supportable for a new team environment with exact safe setup exchange.

## Dependencies
F9.

## Deliverables
Engineer upload; metadata validation; setup ID, revision, and checksum; bridge
staging; compatibility display; garage-only driver acceptance; destination
backup; safe local placement; rollback; and manual in-game loading.

## Exclusions
Open public rollout and reliability hardening beyond setup-transfer scope.

## Implementation Sequence
1. Define the exact artifacts and secrets that can be exchanged safely.
2. Rehearse setup transfer into a fresh team-controlled environment.
3. Capture support and rollback steps for incomplete or unsafe transfers.

## Automated Tests
Install and configuration validation, package-shape checks, safe-exchange validation, and missing-secret detection.

## Manual Tests
Fresh setup rehearsal by someone other than the original implementer using only the documented safe exchange steps.

## CSP Runtime Requirements
Required; the transferred PitWall package and instructions must remain CSP-valid in the target environment.

## Security
Ensure secrets, certificates, defaults, and local-only artifacts do not leak through setup transfer.

## Exit Criteria
A new team environment can be prepared repeatably through an exact safe setup exchange with documented support expectations.

## Rollback
Fallback to a narrower supported setup topology if transfer complexity exceeds support capacity.

## Risks
Environment drift, hidden operator knowledge, unsafe secret exchange, and packaging gaps across surfaces.

## Complexity
medium

## Clean-Thread Recommendation
Yes - run reliability and security in a dedicated thread so hardening evidence is not buried inside install work.
