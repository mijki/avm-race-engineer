# Tools

Status: `F1 and F2 host tooling implemented`

This directory contains developer, diagnostic, migration, and release support
tooling. F1 tooling is dependency-free Python so a clean checkout can generate
and validate the driver package without downloading a runtime.

## Expected Uses

- Local preflight helpers
- Telemetry replay and fixture generation
- V1 migration diff tooling
- Packaging and release support scripts

## F1 commands

```text
python tools/f1_fixture_builder.py
python tools/build_f1.py --verify-deterministic
python tools/f1_installer.py --ac-root <explicit-assetto-corsa-root>
```

`f1_fixture_builder.py` writes the deterministic contract fixtures and scenario
catalog. `build_f1.py` validates the explicit Lua graph, creates the generated
bundle and bounded sound assets, and records hashes in `build-manifest.json`.
`f1_installer.py` is dry-run-first; `--apply` is the explicit mutating mode and
only targets `apps/lua/AVM_PitWall_F1`.

`f1_host.py` provides forbidden-pattern, local-count, parser-backend, and
optional Lupa callback checks. If no Lua parser or Lupa runtime is installed,
its static fallback is reported as inspection only and never as CSP proof.

## F2 live tooling

The same deterministic bundle and installer retain the F1 safety gates while
including the live modules. `f1_fixture_builder.py` generates contract fixtures
and validates the two live telemetry fixtures. `f1_validation.py` runs JSON,
loader, bundle, Markdown, and renderer-literal scans. `live_model.py` is the
dependency-free host oracle used because Lua/Lupa is unavailable here.

Tooling should support the documented workflows in `docs/` rather than invent a
parallel source of product truth.
