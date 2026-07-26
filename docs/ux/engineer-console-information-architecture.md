# Engineer Console Information Architecture

Status: `Planned`

Engineer Console is the browser workspace for race engineers and operators. The
information architecture must support fast live action first, then deeper
analysis, administration, and audit without collapsing those concerns into one
overloaded screen.

## Area Index

1. Live Overview
2. Telemetry
3. Track Map and Traffic
4. Strategy
5. Weather
6. Messages and Commands
7. Setups
8. Session History
9. Team and Access
10. System Health

## 1. Live Overview

Purpose: the primary action-first workspace during a live session.

Primary user: race engineer.

Critical widgets:

- Session header with session phase, clock, track, selected car, current driver,
  driver mode, and freshness state
- Action rail with pinned critical alerts, pending acknowledgements, expiring
  commands, and setup or strategy blocks that need explicit review
- Car state strip with position, lap, gap, fuel trend, stint age, pit-window
  state, tyre summary, and connection state
- Strategy summary card with current target, latest rationale, confidence, and
  revision state
- Messages and commands card with latest outbound command, command lifecycle
  state, and pending resend or supersede actions
- Event timeline with recent incidents, pit calls, driver changes, and health
  transitions
- System trust band showing live, degraded, stale, or disconnected data states

Sources:

- Relay Server live session state
- Driver Bridge telemetry envelopes
- Command lifecycle events
- Strategy revision records
- Alert and incident streams

Update frequency:

- Header, action rail, and car strip: near-real-time
- Strategy summary: on revision or relevant telemetry change
- Event timeline: append on meaningful event arrival

Empty state:

- "No active live session" with quick links to Setup, Session History, and Team
  selection

Stale state:

- Freeze visible values, stamp them stale, suppress risky recommendation
  affordances, and elevate System Health context inline

Error state:

- Show which source failed, which values remain trustworthy, and which actions
  are blocked

MVP:

- Session header
- Action rail
- Car state strip
- Strategy summary
- Command summary
- Event timeline

Later:

- Comparative multi-car summary
- Richer embedded charts
- Cross-team collaboration cues

## 2. Telemetry

Purpose: detailed measured and derived vehicle state inspection.

Primary user: race engineer.

Critical widgets:

- Time-series charts for lap timing, fuel, tyre, and speed-related signals
- Current-value rail with freshness and unit labels
- Signal provenance labels: measured, derived, inferred
- Bookmarkable telemetry moments or incidents

Sources:

- Telemetry contracts and relay-delivered envelopes

Update frequency:

- Near-real-time while live; batch append during reconnect catch-up

Empty state:

- No telemetry for selected car yet

Stale state:

- Charts stop advancing and display stale watermark plus last sample time

Error state:

- Signal parsing or schema mismatch warnings with field-level visibility where
  possible

MVP:

- Core lap, fuel, pace, and tyre traces

Later:

- Custom dashboards
- Advanced correlation and comparison tools

## 3. Track Map And Traffic

Purpose: show where the selected car sits relative to traffic, incidents, and
pit entry or exit decisions.

Primary user: race engineer.

Critical widgets:

- Simplified track map
- Car markers with relative class or rival highlights
- Traffic proximity and overlap markers
- Incident markers and yellow or caution context if available

Sources:

- Position telemetry
- Session timing state
- Incident events

Update frequency:

- Near-real-time

Empty state:

- Track map unavailable until position telemetry is live

Stale state:

- Freeze markers and show stale overlay; disable traffic-based call confidence

Error state:

- Position source unavailable or unreliable

MVP:

- Selected car plus nearby traffic context

Later:

- Full-field replayable map
- Predicted traffic windows

## 4. Strategy

Purpose: present race plan state, rationale, revision history, and operator
approval points.

Primary user: race engineer.

Critical widgets:

- Current strategy revision and status
- Fuel-to-target and stint target cards
- Pit-window recommendation with confidence and validity window
- Operator override controls with audit notes

Sources:

- Strategy-domain outputs
- Telemetry and lap timing inputs
- Manual operator notes and approvals

Update frequency:

- On strategy revision, operator action, or key telemetry threshold changes

Empty state:

- No active strategy revision yet

Stale state:

- Mark revision stale and block silent application or promotion

Error state:

- Strategy unavailable because inputs are missing, stale, or contradictory

MVP:

- Single selected strategy revision with rationale

Later:

- Scenario branching
- Comparative what-if analysis

## 5. Weather

Purpose: expose current measured weather or track-condition context and its
confidence limits.

Primary user: race engineer.

Critical widgets:

- Current conditions card
- Rain or track-surface caution markers if supported
- Source confidence and sample age
- Impact note for strategy or tyre decisions

Sources:

- CSP or external weather-capable telemetry if proven
- Manual operator annotation where necessary

Update frequency:

- On new weather sample arrival

Empty state:

- Weather unknown or unsupported

Stale state:

- Last known weather retained with explicit stale label

Error state:

- Source contradiction or unsupported field mapping

MVP:

- Conservative current-condition visibility only

Later:

- Authoritative scheduled-weather integrations and clearly labelled estimates
- Automated weather-driven recommendation hints

## 6. Messages And Commands

Purpose: manage engineer-to-driver communication with explicit lifecycle state.

Primary user: race engineer.

Critical widgets:

- Draft or quick-command composer
- Active command queue
- Command lifecycle list: issued, validated, accepted, delivered,
  acknowledged, completed, rejected, expired, superseded
- Driver acknowledgement and repeat controls

Sources:

- Command contracts
- Relay transport events
- Driver acknowledgement events

Update frequency:

- Near-real-time on command lifecycle transitions

Empty state:

- No active or recent commands

Stale state:

- Freeze lifecycle transitions and warn that delivery confidence is reduced

Error state:

- Wrong car, wrong session, expired, or rejected command states displayed with
  explicit reasons

MVP:

- Send, view, and track one active command path safely

Later:

- Saved command patterns
- Richer grouped conversation history

## 7. Setups

Purpose: review, validate, stage, and transfer setup packages without silent
application.

Primary user: team operator or race engineer in garage workflows.

Critical widgets:

- Upload and validation panel
- Setup identity block with package ID, revision, checksum, session, and car
- Compatibility result card
- Staged package list
- Driver consent and garage-ready state
- Transfer audit trail

Sources:

- Setup transfer contract
- Local file metadata
- Session identity and compatibility rules

Update frequency:

- On upload, validation, staging, transfer, or acknowledgement events

Empty state:

- No setup packages uploaded or staged

Stale state:

- Staged package marked outdated when superseded or mismatched to current car or
  session

Error state:

- Validation failure, checksum mismatch, wrong session, wrong car, or unsupported
  fields

MVP:

- Upload, validate, stage, and auditable transfer flow

Later:

- Side-by-side setup diffs
- Batch package libraries

## 8. Session History

Purpose: preserve audit and replay visibility after or between live sessions.

Primary user: race engineer and team operator.

Critical widgets:

- Session list and filters
- Event timeline replay
- Past alerts, commands, and setup transfers
- Summary cards for stint, pit, and health milestones

Sources:

- Persisted relay and audit records

Update frequency:

- On new audit entry or completed session sync

Empty state:

- No saved session history yet

Stale state:

- Historical views are inherently non-live and must be labeled accordingly

Error state:

- Partial or missing audit record warnings

MVP:

- Basic session timeline and audit lookup

Later:

- Rich replay tools
- Search across teams or seasons

## 9. Team And Access

Purpose: manage operator identity, active team context, and permission-sensitive
actions.

Primary user: team operator or administrator.

Critical widgets:

- Active team and role badge
- Session control ownership indicator
- Access matrix for high-risk actions
- Invite, revoke, or handoff controls when implemented

Sources:

- Auth and team membership systems
- Session ownership records

Update frequency:

- On login, role change, or session-control handoff

Empty state:

- No team selected or no permissions assigned yet

Stale state:

- Access state must revalidate on reconnect before risky actions proceed

Error state:

- Permission denied, expired session, or ownership conflict messaging

MVP:

- Active identity and role visibility
- Basic session control ownership display

Later:

- Full team admin workflows
- Granular access policy editing

## 10. System Health

Purpose: make trust, freshness, and failure state explicit across the stack.

Primary user: team operator during setup, race engineer during live use.

Critical widgets:

- AVM PitWall, Driver Bridge, Relay Server, and Engineer Console status cards
- Freshness ladder: live, degraded, stale, disconnected
- Recent failures and recovery attempts
- Recommended next diagnostic or recovery action

Sources:

- Heartbeats
- Connection-state events
- Local diagnostics
- Audit logs

Update frequency:

- Near-real-time on health transitions

Empty state:

- No health samples yet for the selected stack

Stale state:

- Health state itself marked stale and treated as unreliable until refreshed

Error state:

- Source unavailable, probe failed, or contradictory health signals

MVP:

- Stack health cards plus freshness state and latest failure reason

Later:

- Automated remediation suggestions
- Deep per-component diagnostics

## Navigation Rules

- Live Overview is the default landing area for an active session
- Telemetry, Track Map and Traffic, Strategy, Messages and Commands, and System
  Health must preserve the selected car and session context while navigating
- Setups, Session History, and Team and Access may switch into broader operator
  workflows, but must show the active live context before risky actions

## Status Note

This document defines the intended Engineer Console structure only. Exact
layouts, API shapes, and persistence details remain unimplemented.
