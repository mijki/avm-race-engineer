# Product Vision

Status: `Planned`

## Vision

AVM Race Engineer should give an endurance-racing team one coherent operating
system across the car, the pit wall, and the engineering desk. The product must
let the driver stay focused, let the engineer act quickly, and let the team set
up the full stack without hidden failure modes.

## Product Shape

The platform consists of four named surfaces:

- **AVM PitWall:** the in-car CSP client
- **Driver Bridge:** the local Windows process that collects and forwards data
- **Relay Server:** the real-time backend relay
- **Engineer Console:** the browser workspace for engineers and operators

## Product Principles

- **Driver safety first:** no feature is worth adding if it increases in-car
  cognitive load without clear race value
- **Operational trust before sophistication:** telemetry, command delivery, and
  alerting must be believable before automated assistance expands
- **Fast shared context:** the engineer must understand race state and system
  health at a glance
- **Deliberate migration:** V1 informs requirements and compatibility, but this
  repository is allowed to replace the architecture cleanly

## What This Repository Represents Today

As of 2026-07-26 this repository is still a foundation artifact, not a shipped
product release. The current deliverable is a clear product and UX definition
that implementation can follow without renaming concepts midstream or
overloading the driver surface.
