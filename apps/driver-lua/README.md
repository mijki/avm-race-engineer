# AVM PitWall

Status: `Host-complete; CSP runtime pending`

AVM PitWall is the compact in-car CSP Lua client. It is the driver-facing AVM
surface and therefore carries the strictest safety constraints.

## Responsibilities

- Render Compact Race, Expanded Race, and Garage/Diagnostics modes.
- Present bounded stint, fuel, pace, tyre, weather, traffic, connection, and
  engineer-instruction state.
- Collect only CSP-specific supplemental data justified by an evidence record.
- Acknowledge or reject commands, repeat the latest message, report predefined
  issues, and accept an approved setup download only while safely in the garage.
- Keep a useful limited local view when the Driver Bridge or Relay Server is
  unavailable.

## F1 implementation boundary

- CSP Lua app is maintained as small source modules under `src/` and bundled in
  an explicit dependency order from `build/module-manifest.json`.
- The generated package contains one runtime bundle, no runtime `require` or
  `dofile`, four deterministic WAV tones, an asset manifest, and a build hash
  manifest. Generated files are ignored and recreated by the build.
- CSP calls, audio, and presentation storage are isolated behind
  `src/adapters/`; contracts, formatting, view-model reduction, alert state,
  and layout selection remain host-testable.
- The shell has exactly three modes: Compact Race, Expanded Race, and
  Garage/Diagnostics. Race modes are fixed single-screen compositions with no
  scrolling child UI.
- F1 consumes deterministic fixtures only. It has no networking, live
  telemetry, production weather or strategy calculation, setup application, or
  arbitrary numeric editing.
- The host gate is complete. A real in-game CSP callback/render gate remains
  explicitly pending and is not represented as passed by host tests.

## Build and validate

From the repository root:

```text
python tools/f1_fixture_builder.py
python tools/build_f1.py --verify-deterministic
python -m unittest discover -s tests -p "test_f1_*.py" -q
```

The generated development package is written to
`apps/driver-lua/dist/AVM_PitWall_F1/` and is not hand-edited. The package
contains `manifest.ini`, `AVM_PitWall.lua`, `script.lua`, `README.md`,
`asset-manifest.json`, `build-manifest.json`, and `assets/sounds/`.

## Fixture scenarios

The garage fixture catalog covers normal, fuel, pace, pit, weather provenance,
confidence, unavailable, malformed, traffic, setup, and replan states. The
catalog is in `fixtures/f1-scenario-catalog.json`; contract-shaped examples
are in `fixtures/contracts/`. `MALFORMED_SNAPSHOT` is intentionally a Lua-only
invalid envelope used to exercise the visible fallback shell.

## Safe development install

The installer is dry-run by default and requires an explicit Assetto Corsa
root. It targets only `apps/lua/AVM_PitWall_F1`, never the installed V1
`AVM_PitWall` directory:

```text
python tools/f1_installer.py --ac-root "E:\Games\Steam\steamapps\common\assettocorsa"
python tools/f1_installer.py --ac-root "E:\Games\Steam\steamapps\common\assettocorsa" --apply
```

Use `--apply` only after reviewing the dry-run allowlist. The installer stages
and hash-checks the package, preserves unrelated target files, and keeps a
rollback backup outside the application target.

## Must Preserve From V1

- Driver-first interaction density
- CSP-compatible integration behavior
- Safe fallback behavior during communication loss

## Out Of Scope

- Long-form strategy analysis
- Complex setup configuration during active driving
- Server-side telemetry storage or orchestration
- High-volume telemetry transport, authentication, file transfer, profile
  administration, and server reconnection orchestration

See [docs/ux/driver-client-ux.md](../../docs/ux/driver-client-ux.md) and
[docs/architecture/lua-source-and-build-architecture.md](../../docs/architecture/lua-source-and-build-architecture.md).
