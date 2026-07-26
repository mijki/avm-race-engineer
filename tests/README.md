# Tests

Status: `F1 host coverage implemented; CSP runtime pending`

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
