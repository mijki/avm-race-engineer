# Purpose-specific lap eligibility V1

`tools/lap_eligibility.py` is the host-side eligibility oracle for completed
laps. It consumes a completed-lap record and matching immutable race events and
returns a new immutable decision record. The measured lap is never rewritten.

## Validity concepts

Official validity is the simulator or race-control classification. It controls
`useForOfficialAverage`; an officially invalid lap is not silently made
officially valid. Operational representativeness is purpose-specific physical
evidence: continuity, pit/reset/teleport/incident state, measurements, and
regime compatibility. Completeness is tracked independently for fuel and tyre
measurements. Unknown evidence is retained as unknown and produces a
conservative decision with a reason code.

The five decisions are independent:

| Purpose | Meaning |
| --- | --- |
| `useForPace` | representative pace sample in the active regime |
| `useForFuel` | trustworthy fuel-use sample, including permitted invalid laps |
| `useForTyres` | complete tyre measurement, including permitted diagnostics |
| `useForProjection` | compatible sample for a later projection model |
| `useForOfficialAverage` | official-valid arithmetic-average sample |

## Baseline policies

`STRICT` requires official validity and complete, non-structural evidence for
the estimator purposes. `OPERATIONAL` permits purpose-specific use of an
officially invalid but representative lap, especially for fuel and tyres.
Track-limit-invalid pace and projection laps require explicit policy options;
they are not enabled by a general `includeInvalidLaps` switch. `CUSTOM` starts
from the operational rules and applies explicit per-purpose options such as
allowed regimes or disabled purposes.

Each decision carries the policy ID/version, decision version, deterministic
reason codes, source evidence, confidence, and manual-override state. Relevant
event IDs are bounded and retained as evidence; no evidence is fabricated when
CSP does not provide it.

## Regimes and latest references

Dry, wet, mixed, caution, traffic, fuel-save, push, and normal running are
separate tags. An active regime can reject an otherwise valid lap from the
wrong estimator set without deleting the lap or its other-purpose decisions.
The calculation layer must keep latest completed separate from each
latest-purpose-accepted reference; this layer does not replace an accepted
reference when a later lap is excluded.

## Manual overrides and replay

Overrides are per-purpose include/exclude records with a readable reason,
source, sequence, optional timestamp, and optional identity/stint scope. A
restore action returns that purpose to the automatic decision. The active
override index survives recalculation, while the audit history is bounded.
Boundary code may explicitly reset scoped active overrides; ordinary
recalculation does not.

For the same ordered laps, event evidence, policy, and override sequence,
`serialize_eligibility` produces byte-identical output. The emitted
`LAP_ELIGIBILITY_DECIDED` record is an immutable `race-event-v1` envelope.

This task does not calculate stint averages, forecasts, recommendations, or
renderer values, and it does not perform networking or runtime Lua loading.
Unavailable tyre damage such as graining and blistering remains unavailable
until a verified source and a later task provide it.
