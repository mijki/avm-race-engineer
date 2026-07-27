# Tests

Status: `F1 and F2 host coverage implemented; CSP runtime gate pending`

This directory holds cross-component verification for AVM Race Engineer. The
F1 suite is intentionally host-side and does not claim to replace an actual
Assetto Corsa/CSP run.

## Expected Coverage

- Contract compatibility checks
- V1 parity and regression fixtures
- Forecast-engine unit, property, replay, and contract fixtures
- Weather timeline and provenance fixtures
- Relay and bridge integration tests
- Engineer Console workflow and alert-state validation

## F1 command

```text
python -m unittest discover -s tests -p "test_f1_*.py" -q
```

The F1 tests parse repository JSON, validate the foundation contract fixtures,
check the exact scenario catalog, validate the asset and module manifests,
prove deterministic package bytes, scan the bundle for forbidden loaders and
unsafe global pressure, exercise the installer in a temporary target, and run
the optional callback smoke when Lupa is available. A skipped callback smoke
means the real runtime gate is still pending.

## Quality Rule

Behavior inherited from the V1 reference should gain explicit regression
coverage before it is intentionally changed.

## F2 live-driver coverage

test_live_telemetry.py exercises the host oracle for CSP normalization,
identity/session resets, lap and stint boundaries, bounded sample storage, fuel
and pace equations, pit-entry wraparound, calibration absence, confidence,
weather trend, and future-weather honesty. test_f1_vertical_slice.py covers
source ownership, renderer constraints, JSON parsing, deterministic bundling,
and installer target guards.

Lua/Lupa is not available on the current validation host. These tests are
supplemented by source scans and bundle checks; they do not count as real
Assetto Corsa/CSP evidence.
