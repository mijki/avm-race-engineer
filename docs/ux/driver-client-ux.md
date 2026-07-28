# Driver Client UX

Status: `F1 live-driver slice implemented; real CSP visual re-validation pending`

AVM PitWall is the in-car surface for AVM Race Engineer. Its UX must optimize
for glanceability under load, deterministic alert behavior, and safe operation
when telemetry or command freshness degrades.

## Design Rules

- No race scrolling. Compact and Expanded race layouts fit on one stable screen
  per mode; Garage/Diagnostics may expose a longer stationary configuration
  surface.
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
- compact forecast framing for next pit and stint outcome where confidence is
  high enough;
- traffic warnings;
- measured current weather and track condition;
- weather-status provenance: current, scheduled, estimated, trending, unknown,
  stale;
- tyre crossover or strategy implication when it is actionable and trustworthy;
- Engineer Console connection state;
- current engineer instruction, priority, and acknowledgement state.

Unavailable fields remain explicitly unavailable; the layout must not invent
zeroes or silently substitute stale values.

## Compact Calculation And Weather Rules

The race view must reduce the model to a driver-safe summary:

- current state first;
- one next-action recommendation at most;
- one next meaningful weather change at most;
- concise trust framing for calculated or forecast values.

Driver weather and calculation context must use explicit labels where relevant:

- `CURRENT`
- `SCHEDULED`
- `ESTIMATED`
- `TRENDING`
- `UNKNOWN`
- `STALE`

The driver should not have to infer whether a value is measured, scheduled, or
estimated from icon shape or color alone.

## Mode A: Compact Race Mode

Purpose: the default low-noise race layout for endurance stints.

### Information Shown

- One primary instruction banner when any command, pit call, or critical alert
  is active
- Current lap or sector progress indicator
- Stint age or laps into stint
- Fuel remaining plus simple trend: safe, tight, critical
- Fuel delta or pit-readiness framing only when confidence is sufficient
- Pace delta summary: on target, slightly off, well off
- Tyre condition summary if trustworthy enough to expose
- Current weather plus the next meaningful change in compact form
- Tyre crossover or strategy implication only when actionable
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
- No dense weather timeline or model comparison matrix
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
- Compact weather provenance label and simple change timing when justified
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

## Current local live-driver contract

The current F1 local slice keeps the driver-facing data flow bounded:

`CSP telemetry -> normalized snapshot -> identity/lap/stint trackers -> bounded
sample histories -> local calculations -> status -> view model -> renderer`.

Compact answers the immediate driver questions in this order: Engineer action,
stint/lap context, Fuel/Pace/Pit, four-wheel Tyres, Weather, then trust
indicators. Expanded adds samples, confidence, freshness, deltas, per-wheel
details, and Trust. Garage contains raw normalized telemetry, API diagnostics,
configuration, calibration, sample history, reset controls, mock selection, and
Engineer-message injection. Race renderers never call raw CSP APIs.

### Trust indicators

The Compact header has one custom `AVM PitWall` header below the native CSP title
bar and three independent indicators:

- `TEL`: `LIVE`, `PARTIAL`, `STALE`, or `OFFLINE` for the local CSP snapshot.
- `BRG`: `NOT USED` while no real Driver Bridge heartbeat exists.
- `ENG`: `NOT ASSIGNED` while no Engineer Console or assigned engineer source
  exists.

Filled, warning, hollow, and crossed shapes supplement semantic color. The
Engineer strip is reserved for an instruction or bounded informational message;
source health is explained in Trust or Garage instead.

### Session, stint, and representative samples

Where data is available, the header/timing context exposes race lap, stint lap,
stint elapsed time, remaining time, and session time remaining. Remaining time
is marked estimated unless it comes from a trustworthy session constraint.

Accepted laps feed representative pace and fuel history. Invalid, pit, out, in,
wet, caution, and incomplete laps are classified and retained in diagnostics;
they do not clear the latest valid lap or representative average. Identity,
session/replay restart, explicit reset, or a material refuel/stint transition
may reset the active estimator. A refuel archives the previous bounded stint
history separately and cannot create negative consumption.

Pace exposes configured target, representative average, latest valid
representative lap, latest completed lap, latest-valid versus target, latest-valid
versus average, and average versus target. Fuel uses the same comparison model,
plus current fuel, range, fuel/km, fuel/minute, and predicted fuel at pit entry.
Target values are never fabricated. A target delta remains unavailable until a
Garage/strategy target exists.

### Tyres, pressure, and temperature

The local model produces independent `FL`, `FR`, `RL`, and `RR` cells. Current
temperature is the verified CSP `tyreCoreTemperature` value; current-lap
minimum/maximum are tracked locally from that same field and reset at the lap
boundary. Surface and inside/middle/outside fields are retained separately for
diagnostics and are not silently mixed into the core value.

The installed CSP field `tyrePressure` is treated as PSI at the adapter
boundary. Internal kPa equivalents are retained, and Garage configuration may
select PSI or kPa for display. Pressure targets use this precedence: a verified
car/compound source if one becomes available, then explicit Garage
car/compound/wheel configuration, otherwise unavailable. No universal target is
hardcoded.

The documented CSP wear field is normalized as `0..1`; the UI labels both
`WEAR` and `LIFE`, with life shown as `(1 - wear) * 100` (for example,
`LIFE 97%`). Flat spotting uses the inspected reference 0..1 unit scale and is
shown as Flat spotting when significant. CSP exposes Graining and Blistering
fields, but the installed SDK does not establish their ranges; the local slice
keeps those raw values in Garage diagnostics and shows `Unsupported` rather
than a false `0%`.

Cell tones are semantic and local: neutral for missing targets/evidence,
informational for measured values, good for within threshold, caution for a
moderate deviation or low confidence, critical for a major deviation or
verified flat spot, and muted for unavailable data. Every state also has text,
sign, or shape. Comparison thresholds are explicit configuration rather than
implicit dashboard-wide green tinting.

### Weather and wind

The naked `CURRENT 100` value came from the CSP weather enum's string form,
not from a driver-readable condition. The formatter now maps that form using
the measured track state and labels the result. Compact Weather shows current
condition, air/road temperature, wind speed and cardinal direction, track
condition/wetness, and labeled grip when available. `windSpeedKmh` and
`windDirectionDeg` are read through the CSP adapter; the direction is treated
as an absolute real-world compass degree with track heading already accounted
for by CSP, and AVM does not invert it or claim an unverified meteorological
from/toward conversion. If direction is missing, only wind speed is shown.
Future weather remains `No reliable future forecast` until an authoritative
forecast source exists.

### Pit calibration and Engineer messages

Pit-entry distance is track/layout-bound and is unavailable until Garage
performs `ARM PIT ENTRY CAPTURE` followed by `CAPTURE NOW` while stationary.
Capture stores the normalized spline, track length, identity, timestamp, and
route addition. Clear, validate, forward-distance, wraparound, and route-edit
operations remain Garage-only. Predicted fuel at pit entry additionally
requires valid fuel/km, fresh telemetry, and a known route addition (including
an explicit zero).

Engineer messages are structured with ID, source, severity, title, detail,
creation/expiry, priority, acknowledgement requirement/state, and optional
reason. Local calculations and Garage test injection are supported now;
networked Driver Bridge and Engineer Console sources remain future boundaries.
Acknowledgement state is preserved across recalculation and an expired
non-acknowledgement message is removed.

### Responsive shell and future endurance rules

The manifest owns one native `AVM PitWall F1 Dev` title bar and an opaque
application surface. The renderer owns one custom `AVM PitWall` header and
fills the entire usable CSP content region before drawing cards. Compact uses
three Fuel/Pace/Pit primary cards at `width >= 850`, two Fuel/Pace columns with
full-width Pit below that, two Tyres/Weather secondary columns, and a full-width
Engineer strip at the bottom. The supported validation sizes include
`500x425`, `700x300`, `800x408`, `900x450`, and `1600x370`.

Endurance constraints are configuration-only in this slice: maximum driver
stint/continuous driving time, rest, driver-change, tyre, fuel, and stop rules
may be stored in Garage/strategy configuration. No universal event rule or
full race-control authority is assumed; Compact exposes such rules only when
they become actionable.

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

If weather or calculated model confidence drops below the threshold for safe
guidance, the race view should prefer `UNKNOWN`, `STALE`, or a conservative
instruction over precise-looking tactical detail.

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

## F2 implementation note

The integrated F1/F2 client implements the three mode compositions, fixed race
hierarchy, explicit unavailable/stale/unknown framing, bounded visual alert
acknowledgement and repeat behavior, deterministic contract fixtures, and
local live telemetry normalization. The client has no TTS, networking, setup
application, or production strategy calculation. Real CSP render and
interaction evidence remains pending under the [CSP Runtime Gate](../testing/csp-runtime-gate.md).

### F1 composition notes

- Compact Race is purpose-built as a single screen: engineer message, fuel
  range and pit-entry fuel, pace, tyres, pit strategy, weather provenance, and
  connection state.
- Expanded Race adds elapsed/remaining/target timing, a larger engineer region,
  richer fuel/pace/tyre/pit cards, a reduced weather timeline, and health state.
- Garage/Diagnostics exposes source status, raw telemetry, bounded sample
  counts, traceability, pit-entry calibration, presentation/audio controls,
  and Garage-only mock controls. It never changes live strategy or setup state.
- The fallback shell keeps product identity, failure stage, and recovery copy
  visible when a snapshot is malformed or a render stage raises an error.
The live slice extends the stable hierarchy as a code-defined dark-charcoal
layout. Compact mode is the default and shows stint timing, fuel/range and pit
entry, pace/tyres, measured weather/track, and one engineer line. Expanded mode
adds calculation detail without scrolling. Garage exposes raw state, sample
counts, traceability, calibration, and the explicit MOCK controls.

Visible dynamic fields are reduced in view_model.lua; race renderers do not
call CSP telemetry APIs or contain scenario values. When no trusted future
source exists the text is exactly No reliable future forecast.

The command transport, TTS, and remote connection portions remain planned. The
live local telemetry, calculations, and three-mode interface changes are
implemented and covered by host-side checks; a new real CSP runtime and visual
test is still required before the shell/background/header correction can be
called visually validated.
