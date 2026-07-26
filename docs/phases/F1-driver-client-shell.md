# F1: Driver Client Shell

## Goal
Deliver a polished AVM PitWall shell inside the CSP Lua runtime without any live networking.

## Dependencies
F0.

## Deliverables
Polished CSP shell; Compact Race Mode, Expanded Race Mode, and
Garage/Diagnostics Mode; mock telemetry and alerts; sound handling; mock
acknowledgement UX; build-time bundling; render fallback; and real CSP
validation evidence.

## Exclusions
Live networking, relay connectivity, real engineer commands, and shared-memory bridge work.

## Implementation Sequence
1. Define the shell UX and the Compact Race, Expanded Race, and
   Garage/Diagnostics mode boundaries.
2. Validate mock telemetry, alerts, sound, and acknowledgement states with bundled assets only.
3. Prove build-time bundling, render fallback, and real CSP runtime behavior without networking.

## Automated Tests
Bundle parser, bundle order, forbidden API scan, local module checks, mock telemetry fixtures, mock alert fixtures, mock acknowledgement fixtures, and render fallback host checks.

## Manual Tests
Real Assetto Corsa and CSP shell validation covering mode switching, sound, fallback rendering, and unavailable-state behavior.

## CSP Runtime Requirements
Required; this phase establishes the supported shell assumptions and package discipline.

## Security
Keep the shell non-privileged and avoid implicit control capabilities.

## Exit Criteria
The shell is polished, networking-free, CSP-valid, and ready to accept later relay-backed payloads without redesign.

## Rollback
Reduce to Compact mode plus fallback rendering if the full three-mode shell threatens runtime safety.

## Risks
CSP incompatibility, package sprawl, and over-designing acknowledgement UX before real transport exists.

## Complexity
medium

## Clean-Thread Recommendation
Yes - move bridge work into a new thread once the client shell constraints are fixed.
