# Driver Alert System

Status: `Planned`

The AVM driver alert system governs what AVM PitWall may interrupt, how alerts
stack, how they repeat, and how the engineer can trust that a driver actually
saw a message.

## Alert Families

The driver-facing system should treat these as the canonical alert families for
MVP:

1. `critical_instruction`: stop immediately, serve immediate safety action,
   severe system fault, or command path safety override
2. `pit_call`: pit now, pit this lap, pit window open, pit aborted
3. `stint_state`: stint target reached, over target, driver change prep
4. `fuel_state`: fuel safe, fuel tight, fuel critical
5. `pace_state`: push, hold, save, off-target delta
6. `tyre_state`: tyre warmup, tyre pressure or wear caution, tyre protection
7. `weather_or_traffic`: rain onset, track condition caution, traffic warning
8. `connection_state`: degraded, stale, disconnected, recovered

## Canonical Alert Vocabulary

The initial driver vocabulary is deliberately short and unmistakable:

| Driver text | Family |
| --- | --- |
| `BOX BOX` | pit call |
| `STAY OUT` | pit call |
| `SAVE FUEL` | fuel state |
| `PUSH` | pace state |
| `LIFT AND COAST` | fuel/pace guidance |
| `TARGET PACE` | pace state |
| `TRAFFIC AHEAD` | weather or traffic |
| `FASTER CLASS APPROACHING` | weather or traffic |
| `RAIN EXPECTED` | weather warning; only when an authoritative scheduled or estimated source is labelled |
| `STRATEGY UPDATED` | strategy offer requiring review |
| `SETUP AVAILABLE` | garage-only setup offer |
| `ENGINEER MESSAGE` | bounded free-text message |

`RAIN EXPECTED` must also identify whether the evidence is **Scheduled** or
**Estimated**. A measured trend alone uses `RAIN TRENDING`, not an unqualified
forecast claim.

## Priority Ladder

- `P1 Critical`: critical instruction
- `P2 Immediate Race Action`: pit now, pit this lap, fuel critical
- `P3 Near-Term Race Action`: pit window open, stint threshold, tyre caution
- `P4 Guidance`: pace, weather, traffic, non-urgent fuel guidance
- `P5 State Only`: live/degraded/recovered informational events

Priority determines placement, sound, persistence, and whether the alert may
interrupt text-to-speech or replace a lower-priority visible state.

## Driver-Facing Rules By Mode

- Compact Race Mode: show P1 to P3 immediately; P4 only when actionable soon;
  P5 as small state chips
- Expanded Race Mode: show P1 to P4 with richer context; P5 remains secondary
- Garage/Diagnostics Mode: show all priorities with history and diagnostics

## Exact Driver Delivery Rules

- A single active P1 or P2 alert owns the primary instruction zone
- Lower-priority alerts must queue behind a higher-priority unresolved alert
- No two alerts may compete for the main banner at the same time
- Critical state must never rely on color only; icon, text, and optionally sound
  must reinforce it
- Alerts that affect the same instruction should merge into one visible incident
  instead of stacking duplicates

## Dedupe Rules

- Same `alert_family`, same target car, same session, and same underlying cause
  should update the existing alert instead of creating a second one
- Refreshing timestamps or revised recommended actions may revise the current
  alert card in place
- Repeated delivery of the same command-path event during reconnect should be
  treated as duplicate transport unless the revision changed

## Escalation Rules

- An unacknowledged P1 alert remains pinned until acknowledged, expired, or
  explicitly cleared by a newer authoritative state
- A P2 alert escalates to stronger sound and visual emphasis if it remains
  unacknowledged past its first repeat window
- Repeated connection degradation should escalate from passive badge to visible
  warning if stale state begins to invalidate other displayed guidance
- A superseding higher-priority alert may interrupt a lower-priority sound or
  TTS event immediately

## Sound Rules

- P1: unmistakable multi-tone critical sound
- P2: urgent pit or action sound distinct from P1
- P3: short warning tone
- P4 and P5: optional subtle chime or silent visual-only behavior depending on
  mode

Sound design must differentiate "act now" from "note this soon" without forcing
the driver to memorize many tones.

## Text-To-Speech Rules

- TTS is optional and should be configurable per team or driver preference
- TTS phrases must be short: examples include "Pit this lap", "Fuel critical",
  "Connection stale"
- P1 and P2 may speak automatically if TTS is enabled
- P3 to P5 should speak only in Expanded Race Mode or Garage/Diagnostics Mode
- TTS must not loop endlessly; each alert revision should speak at most once per
  repeat window

## Repeat Rules

- P1 repeats until acknowledgement, expiry, or supersession
- P2 repeats on a shorter cadence while it remains actionable
- P3 may repeat once if still unresolved and near-term
- P4 and P5 generally should not repeat unless the underlying state worsens

## Acknowledgement Rules

- Alerts linked to an engineer command should preserve command acknowledgement
  state separately from passive visual exposure
- A visible alert may count as displayed, but not acknowledged, until explicit
  driver input or a defined passive-confirmation rule exists
- Missing acknowledgement before expiry should close as expired or unresolved,
  never as completed
- Acknowledging a lower-priority alert must not dismiss a still-active higher
  priority alert

## Empty, Stale, And Error States

- No active alerts: show calm state with only essential connection health
- Stale telemetry: freeze the last alert context and mark it stale
- Disconnected command path: raise connection-state priority high enough that
  the driver is not misled into trusting old commands as current
- Local rendering error: fail safe to the smallest possible critical-safe banner
  instead of a blank surface

## Status Note

This defines the intended driver alert contract and UX behavior only. Actual
transport, incident grouping, sound packs, and TTS pipelines are not yet
implemented in this repository.
