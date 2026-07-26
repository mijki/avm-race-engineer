# Setup And Transfer Experience

Status: `Planned`

This document defines the safe setup-package transfer flow for Engineer Console,
AVM PitWall, and the supporting transport path. Setup transfer is not silent
automation. It is a staged, auditable workflow with identity, compatibility, and
operator-consent barriers.

## Core Rule

No setup package may apply itself silently. Every setup flow must preserve:

- package identity
- session identity
- car identity
- revision
- checksum or equivalent integrity proof
- explicit garage-side consent before manual load

## End-To-End Flow

### 1. Upload

The engineer or operator uploads a setup package in Engineer Console.

Required UI output:

- file name
- package size
- detected format
- upload timestamp

Safety threats:

- wrong file
- wrong car family
- outdated local export

### 2. Validate

The system validates schema, required fields, and obvious corruption before the
package is allowed deeper into the flow.

Required validation checks:

- contract version readable
- package parse success
- required setup sections present when expected
- session and car fields structurally valid
- basename-only filename with an allowlisted `.ini` extension
- bounded non-zero file size
- checksum matches the uploaded bytes
- content is treated as data and never executed

Safety threats:

- malformed package accepted as valid
- partial data misread as complete
- path traversal or absolute-path filename
- arbitrary file placement
- invalid extension or excessive size
- malicious payload content

### 3. Identify Package ID, Revision, And Checksum

The system extracts or computes:

- `transfer_id`
- `session_id`
- `car_id`
- `track_id` and `layout_id`
- `setup_revision`
- checksum or content hash

The UI must show these values clearly enough for manual verification.

Safety threats:

- wrong session
- wrong car
- wrong track or layout
- revised package mistaken for older package
- corrupted file copied under the same filename

### 4. Stage

Validated packages enter a staged state rather than immediate availability in
the car.

Required UI output:

- staged badge
- who staged it
- when it was staged
- whether another staged revision already exists

Safety threats:

- operator assumes staging means applied
- stale staged package remains visible as current after a newer revision exists

### 5. Show `SETUP AVAILABLE`

AVM PitWall may present a clear non-silent state such as `SETUP AVAILABLE` only
when:

- the package is staged
- the session and car match
- the package is still unexpired if expiry exists
- compatibility checks completed

`SETUP AVAILABLE` is an offer, not an auto-apply action.

Safety threats:

- the driver mistakes availability for applied state
- the banner appears for the wrong session

### 6. Compatibility Review

Engineer Console and AVM PitWall must both surface compatibility hints and
limits.

Required checks:

- game family compatibility
- setup profile compatibility
- unsupported fields
- partial-import risk

Safety threats:

- importing unsupported fields silently
- treating advisory compatibility as proof of successful application

### 7. Garage Consent Gate

Setup import must require a garage-safe consent point. The system must not
encourage setup loading while the car is actively racing.

Required UI behavior:

- explicit "ready in garage" or equivalent gating
- visible warning if the car is on track
- confirmation that the driver or operator understands the package is not yet
  loaded

Safety threats:

- accidental mid-race setup application attempt
- operator bypasses garage-only intent

### 8. Backup Existing Setup

Before copying or importing a staged setup, the system should prompt for or
verify backup of the currently active local setup when feasible.

Required UI output:

- backup created, skipped, or unavailable
- local backup identity and timestamp if created

Safety threats:

- irreversible overwrite of a working local setup
- operator assumes backup exists when it does not

### 9. Copy To Target Environment

Only after staging, compatibility review, and garage consent should the package
copy into the target environment.

Required UI output:

- copy started
- copy completed or failed
- copied revision and checksum confirmation

Safety threats:

- interrupted copy
- copied file differs from staged checksum
- wrong local folder target
- remote metadata attempts to select an arbitrary destination path

Driver Bridge derives the only permitted Assetto Corsa setup destination from
validated local car/track identity. Remote metadata never supplies the
destination path.

### 10. Manual Load

The final setup load remains a manual driver or garage-side action unless a
future phase explicitly defines a safer supported path.

Required UI output:

- manual-load instructions
- package revision and checksum for comparison
- confirmation affordance after load

Safety threats:

- driver loads the wrong revision
- operator assumes copy implies active setup

### 11. Post-Load Confirmation

The system should record whether the setup was:

- copied only
- loaded manually
- declined
- rejected for compatibility or identity reasons

Safety threats:

- later audit cannot tell whether the setup actually became active

## Recovery And Mismatch Handling

- Wrong session or wrong car: reject from active flow, preserve audit, allow
  manual review only
- Superseded revision: mark older staged package superseded and prevent it from
  masquerading as current
- Checksum mismatch after copy: block manual-load confirmation and raise a
  critical setup error
- Invalid extension, excessive size, malicious payload, path traversal, or
  arbitrary placement attempt: reject, audit, and do not stage
- Offline or stale state: allow review, but block any UI that implies transfer
  success without fresh confirmation

Backup retention must be bounded by policy but long enough to support rollback
for the active and recently superseded revisions.

## Readiness Checklist

Before a team enters a live session, Setup and Transfer UX should still verify:

- telemetry inbound
- command outbound
- alert delivery path
- session and car identity match
- driver mode default
- setup transfer status
- version and compatibility state

## Transfer Principles

- Availability is not application
- Staging is not copying
- Copying is not loading
- Loading is not confirmation

Each state transition must remain explicit, auditable, and reversible where
possible.

## Status Note

This setup flow is documented as intended UX and safety behavior only. No setup
upload, staging, copy, or manual-load workflow is implemented in this
repository yet.
