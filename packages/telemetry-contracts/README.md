# Telemetry Contracts

Status: `Planned`

This package will define the shared telemetry schema used across Driver Bridge,
Relay Server, Engineer Console, and test fixtures.

## Responsibilities

- Canonical field names and units
- Versioned event and snapshot payload shapes
- Health and connectivity status payloads
- Compatibility rules for V1 migration where telemetry-visible behavior matters

## Design Constraints

- Contracts must stay explicit and versionable
- Unit ambiguity is unacceptable
- Backward-compatibility decisions must be documented before rollout
