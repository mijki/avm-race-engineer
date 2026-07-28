# Task 3 — Implement Automatic Pit Lane Learning

Required commit: `Implement automatic pit lane learning`

Dependencies: Tasks 1 and 2 committed, validated, clean worktree.

## Purpose

Implement automatic pit-entry and pit-exit learning from:

- `car.isInPitlane`
- `car.isInPit`
- `car.splinePosition`
- `car.position`
- `car.resetCounter`

Automatic learning is primary. Manual calibration remains a fallback and explicit override.

Do not implement complete stint calculations, eligibility, race forecasts, pit-loss forecasts, networking, or major UI redesign.

## Source of truth

- `isInPitlane` controls current live pit-lane state.
- `isInPit` controls current pit-box state.
- false→true creates an entry observation.
- true→false creates an exit observation.

Calibration is not required for live pit state. It is required for predictive distance and later forecasts.

## No fixed ten-second delay

Do not delay `IN PIT LANE` by ten seconds and do not reject all visits shorter than ten seconds.

A longer threshold may only be one configurable confidence/plausibility input. Use short debounce/hysteresis while preserving the original transition sample.

## State machine

Implement equivalent semantics:

- `ON_TRACK`
- `ENTRY_CANDIDATE`
- `IN_PIT_LANE`
- `AT_PIT_BOX`
- `LEAVING_PIT_BOX`
- `EXIT_CANDIDATE`
- `BACK_ON_TRACK`
- `RESET_SUPPRESSED`

`APPROACHING_PIT_ENTRY` is a later forecast state, not measured pit state.

## Entry

On false→true:

1. capture original transition snapshot;
2. emit candidate;
3. update live state immediately;
4. validate short-term stability;
5. check reset/teleport/identity/movement;
6. confirm or reject;
7. preserve original spline/world boundary;
8. emit final event;
9. update marker record if accepted.

## Pit box

On `isInPit false→true`, record arrival, entry-to-box duration, and service start.

On `isInPit true→false`, record departure, service end, and box-to-exit start.

Drive-throughs without a box event must remain valid.

## Exit

On true→false:

1. capture original transition snapshot;
2. emit candidate;
3. update live state to back on track;
4. validate stability and discontinuities;
5. confirm or reject;
6. preserve original boundary;
7. stop pit-lane timing;
8. update marker and route observations.

## Reset and start-in-pit protection

Suppress learning after reset, teleport, identity change, reload, replay jump, or implausible spline/world jump.

Do not erase a good marker because of one rejected observation.

Starting in the pits must not fabricate an entry marker. The app may learn box departure and exit, then wait for a later natural entry.

## Marker learning

Store bounded observations per track/layout.

Use circular clustering/robust center, outlier rejection, and world-position consistency.

Suggested centralized progression:

- 1 credible observation → `PROVISIONAL`
- 2 consistent → `LEARNED`
- 3+ consistent → `CONFIRMED`

Support `UNAVAILABLE`, `PROVISIONAL`, `LEARNED`, `CONFIRMED`, `CONFLICTED`, and `MANUAL_OVERRIDE`.

One outlier must not destroy multiple consistent observations.

## Persistence

Persist versioned, bounded records by deterministic track/layout key:

- entry/exit spline and world positions;
- observation counts and bounded accepted/rejected IDs;
- confidence and marker state;
- first/last observed times;
- source;
- manual override;
- pit-route timing summaries.

Automatic learning must not overwrite manual override. Do not modify V1 storage.

## Circular distance

Implement forward circular distance:

`(target - current + 1) modulo 1`

Metres require valid entry marker, current spline, and verified track length.

Handle wraparound. Do not implement full ETA or fuel-at-entry forecast yet.

## World validation and timing

Use world position as secondary evidence for teleport rejection, consistency, overlapping sections, and diagnostics.

Record bounded observations for entry, box arrival/departure, exit, entry-to-box, service, box-to-exit, total lane duration, and movement distance.

Distinguish normal stop, drive-through, lane visit without service, reset-suppressed visit, and incomplete visit.

## Manual fallback and diagnostics

Support manual entry/exit override, clear override, return to automatic learning, validation, and track/layout binding.

Expose live pit states, marker state/confidence, observation counts, distance when available, latest accepted/rejected observation, current timing, and override state.

Do not let missing calibration degrade unrelated telemetry.

## Required scenarios

Test normal entry/stop/exit, drive-through, no-service visit, start on track/in pits, reset/teleport, candidate interruption, flicker, short legitimate lane, false on-track trigger, repeated observations, outliers/conflicts, all marker states, manual override lifecycle, track/layout changes, spline wraparound, distance, pit timing, incomplete visits, bounded retention, storage versioning, preservation of manual override and good calibration, immediate live state, original-boundary preservation, unrelated telemetry stability, and deterministic replay.

Also verify no forecast engine, UI redesign, networking, runtime `require`/`dofile`, or V1 modification.

## Task gate

Before commit:

1. confirm Task 2 is previous;
2. run shared validation;
3. run pit-state, reset/teleport, start-in-pit, clustering, distance, persistence, and override tests;
4. replay twice and confirm byte identity;
5. run deterministic build twice;
6. confirm no scope creep;
7. confirm only Task 3 changes.

Create exactly one commit, run final Tasks 1–3 validation, and stop. Do not start Task 4.
