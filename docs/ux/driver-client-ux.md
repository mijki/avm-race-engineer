# Driver Client UX

Status: `Planned`

AVM PitWall is the in-car surface for AVM Race Engineer. Its UX must optimize
for glanceability under load, deterministic alert behavior, and safe operation
when telemetry or command freshness degrades.

## Design Rules

- No race scrolling. The active driving layout must fit on one stable screen per
  mode.
- Critical state must never rely on color alone. Shape, icon, copy, and sound
  must all contribute.
- The top-priority instruction always owns the primary attention zone.
- Driver-visible data must follow one fixed hierarchy so the screen does not
  reorder itself unpredictably during a stint.
- Interaction during live driving must remain constrained to safe, deliberate
  actions.

## Information Hierarchy

Every live race mode follows this priority stack:

1. Critical instruction
2. Pit instruction
3. Stint state
4. Fuel state
5. Pace state
6. Tyre state
7. Weather or traffic context
8. Connection state

Lower-priority items may compress or disappear by mode, but higher-priority
items must remain stable and visually dominant.

## Canonical Race View Model

The three modes expose different subsets of one bounded view model. When
trustworthy data exists, that model contains:

- current stint number and total planned stints;
- current lap and planned stint laps;
- stint completion percentage;
- stint elapsed time and estimated time remaining;
- fuel remaining and estimated fuel laps remaining;
- fuel delta against plan and target fuel consumption;
- pace against target, current-lap delta, and rolling pace trend;
- tyre condition and trend;
- projected pit window and target pit lap;
- traffic warnings;
- measured current weather and track condition;
- Engineer Console connection state;
- current engineer instruction, priority, and acknowledgement state.

Unavailable fields remain explicitly unavailable; the layout must not invent
zeroes or silently substitute stale values.

## Mode A: Compact Race Mode

Purpose: the default low-noise race layout for endurance stints.

### Information Shown

- One primary instruction banner when any command, pit call, or critical alert
  is active
- Current lap or sector progress indicator
- Stint age or laps into stint
- Fuel remaining plus simple trend: safe, tight, critical
- Pace delta summary: on target, slightly off, well off
- Tyre condition summary if trustworthy enough to expose
- Minimal connection badge: live, degraded, stale, disconnected

### Allowed Interaction

- Acknowledge a command or critical instruction
- Reject an instruction where its command type permits rejection
- Repeat the latest still-valid engineer message
- Report a predefined issue through a short fixed list
- Select an already-approved strategy alternative
- Dismiss only non-critical informational prompts
- Switch to Expanded Race Mode or Garage/Diagnostics Mode only while stationary
  or through a deliberate protected action

### Suppressed Or Minimized

- No detailed message history
- No scrolling telemetry tables
- No large charts
- No low-priority setup details

## Mode B: Expanded Race Mode

Purpose: richer in-session race context when the driver can tolerate more
information without compromising safety.

### Information Shown

- Everything from Compact Race Mode
- Next pit window framing: box this lap, prepare to pit, pit not yet open
- Fuel estimate in laps or time remaining
- Pace delta with short target context
- Tyre state split by simple front/rear or wear temperature condition
- Weather or traffic advisory chip when relevant and fresh
- Most recent engineer command state and acknowledgement status

### Allowed Interaction

- Acknowledge or reject commands that require explicit confirmation
- Open one transient detail overlay for fuel, stint, or tyres
- Request repeat of the latest engineer command if the command is still valid

### Constraints

- Overlays auto-close after timeout
- Only one transient detail overlay can be open at a time
- Layout still stays single-screen with fixed regions and no scrolling

## Mode C: Garage/Diagnostics Mode

Purpose: pre-session, post-session, pit-garage, and troubleshooting mode when
the car is stationary or the driver is not under racing load.

### Information Shown

- Full session and car identity
- Connection state for AVM PitWall, Driver Bridge, and Relay Server
- Setup transfer status and compatibility result
- Message history and last command audit state
- Version, revision, and data freshness indicators
- Diagnostics summary for missing permissions or unsupported integrations

### Allowed Interaction

- Pair or confirm session identity
- Review pending setup packages
- Accept or decline a setup download only while safely in the garage
- Run readiness checks
- Switch into a race mode after readiness passes

### Constraints

- Garage/Diagnostics controls must never silently affect a live race state
- High-risk actions require confirmation and a visible before/after summary

## Visual Language

### Colors

- Neutral base surfaces should stay low contrast and non-distracting
- `Critical`: red plus a dedicated hazard icon and explicit action verb
- `Pit`: amber plus pit icon and call-to-action label
- `Stint` and `Fuel`: white or cyan emphasis when healthy, amber when tight
- `Connection`: blue for live, amber for degraded, gray with strike or broken
  link icon for stale or disconnected

Critical states must always include text and iconography, not color alone.

### Icons

- Hazard triangle for critical
- Pit board or wrench for pit instructions
- Fuel drop for fuel state
- Stopwatch for pace
- Tyre ring for tyre state
- Cloud, rain, or traffic markers for contextual advisories
- Link-state icon for connection health

Icons should be simple, high-contrast, and recognizable at racing glance
distance.

### Typography

- Primary instruction: bold condensed uppercase, large enough for one-glance
  parsing
- Secondary numeric state: tabular numerals for lap, fuel, delta, and timers
- Supporting labels: short title case or uppercase abbreviations only
- Never rely on long sentences during race modes

### Motion

- Critical alerts may pulse or flash briefly on arrival, then settle into a
  steady persistent state
- Non-critical updates should use restrained fades, not continuous animation
- No animated elements may obscure the primary instruction after the arrival
  moment

### Sound And Speech

- Distinct tones for critical, pit, and advisory levels
- Text-to-speech should be optional and limited to concise phrases
- TTS must never overlap itself; newer higher-priority speech may interrupt
  lower-priority speech
- Sound-off mode must still preserve strong visual signalling

## Command, Acknowledgement, And Timeout Rules

- Commands requiring acknowledgement must remain visible until acknowledged,
  superseded, expired, or cancelled
- Acknowledgement affordance must be one deliberate tap or button action, never
  a swipe or hidden gesture
- Expired commands must close as expired, not silently vanish as if completed
- Repeated commands with the same command identity should update the existing
  visible state rather than stack duplicate cards

## Offline, Degraded, And Stale Rules

- `Live`: normal behavior
- `Degraded`: keep race view active, but add a visible warning that timing or
  recommendations may be delayed
- `Stale`: freeze the last known values, stamp them as stale, and suppress any
  risky derived recommendations
- `Disconnected`: show persistent broken-link state and block any UI that would
  imply fresh remote control or fresh strategy truth

Connection state belongs at hierarchy position 8, but stale or disconnected
state may temporarily rise higher when it invalidates a visible command or
recommendation.

## Screen-Size Targets

- Race modes target compact in-car HUD proportions first
- Compact Race Mode must remain legible on the smallest supported in-car layout
  without truncating the primary instruction beyond recognition
- Expanded Race Mode may use a denser two-column composition only if both
  columns remain readable at glance distance
- Garage/Diagnostics Mode may assume a larger stationary view, but still should
  avoid deep nesting and scrolling for the most important readiness states

## Status Note

This document defines intended AVM PitWall behavior only. The modes, visuals,
ack rules, TTS behavior, and offline handling are not implemented in this
repository yet.
