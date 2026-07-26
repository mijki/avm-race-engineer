# F0: Foundation

## Goal
Establish the roadmap, ADRs, and test gates that will govern implementation.

## Dependencies
None.

## Deliverables
Seven proposed ADRs, testing strategy, CSP runtime gate, end-to-end test matrix, and programme roadmap.

## Exclusions
Production code, live simulator integration, and finalized deployment automation.

## Implementation Sequence
1. Define architectural boundaries and ordering constraints.
2. Publish quality gates and CSP-specific runtime rules.
3. Capture the F0-F12 programme sequence in one roadmap.

## Automated Tests
Document completeness checks for filenames, section coverage, and internal links.

## Manual Tests
Stakeholder walkthrough against README scope and the V1-reference constraint.

## CSP Runtime Requirements
Advisory only; this phase defines the gate rather than exercising the runtime.

## Security
Set security as a standing roadmap concern rather than a late-stage add-on.

## Exit Criteria
All required planning artifacts exist and remain internally consistent.

## Rollback
Reduce to a smaller planning baseline if the full phase map proves misleading.

## Risks
Overstating certainty, hidden assumptions, and planning drift before implementation begins.

## Complexity
medium

## Clean-Thread Recommendation
Yes - start implementation in a clean thread after F0 so delivery work is not mixed with roadmap editing.
