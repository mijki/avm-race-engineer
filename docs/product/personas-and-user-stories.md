# Personas And User Stories

Status: `Planned`

## Primary Personas

### Driver

The driver needs fast, low-noise information while actively controlling the
car. They care about only the next decision, the next risk, and whether the
system can be trusted right now.

### Race Engineer

The race engineer needs a live operational picture with command authority,
acknowledgement visibility, and confidence indicators for stale or degraded
data.

### Team Operator

The team operator handles setup, pairing, environment readiness, and recovery
when the stack needs to be restarted or transferred under time pressure.

## User Stories

### Driver Stories

- As a driver, I want only the most important alerts to interrupt me so that I
  can keep driving without filtering noise.
- As a driver, I want a clear mode model so that I can choose the amount of
  guidance I receive before or during a stint.
- As a driver, I want critical alerts to break through every mode so that I do
  not miss session-threatening issues.

### Race Engineer Stories

- As an engineer, I want a Live Overview that shows action-first race state so
  that I can decide quickly without opening five views.
- As an engineer, I want command acknowledgement state so that I know whether a
  driver actually received and accepted guidance.
- As an engineer, I want degraded-state indicators so that I do not mistake
  stale telemetry for real race state.

### Team Operator Stories

- As an operator, I want a readiness checklist so that I can confirm the stack
  before a session starts.
- As an operator, I want safe session transfer steps so that a reconnect or
  handoff does not silently attach the wrong car or driver.
- As an operator, I want version and compatibility checks surfaced early so that
  race-day startup does not depend on guesswork.
