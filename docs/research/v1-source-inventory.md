# V1 source inventory and migration policy

**Status: REFERENCE REVIEW — NO V1 CODE MIGRATED**

This inventory treats `E:\Work\Repos\avm-pitwall` as a read-only source of
requirements, failure history, CSP compatibility evidence, and regression
scenarios. It is not an implementation template for AVM Race Engineer.

## High-value references

| Reference | Use in this repository |
| --- | --- |
| `AGENTS.md`, root and app READMEs | V1 invariants, terminology, and validation status |
| `apps/lua/AVM_PitWall/manifest.ini` and `AVM_PitWall.lua` | CSP registration and visible load-failure lessons |
| `apps/lua/AVM_PitWall/script.lua` | Requirements discovery and failure analysis only |
| `docs/wiki/phase-map.md` | Functional evolution from planner to race guidance |
| `docs/wiki/current-baseline.md` | Most recent implemented-versus-validated status |
| `docs/wiki/known-runtime-pitfalls.md` | CSP runtime hazards and validation gaps |
| `docs/audits/` | R1–R6 findings, remediation evidence, and residual risk |
| `tests/` | Candidate regression scenarios and host-test limitations |
| `tools/install_lua_app.py` | Installer safety requirements, not reusable installation code |

The highest-signal history inspected was the audit baseline at `24ab357`, the
remediation closure at `2157176`, and the blank-window correction at
`d9a0c56`.

## Lessons retained as requirements

1. **A loaded app is not necessarily a rendered app.** V1 loaded and registered
   its window, then failed before its first visible draw because
   `get_status_band_values()` was called before the later local binding existed.
   The new client requires a production-callback smoke test and a visible,
   bounded render-failure shell.
2. **Host validation is necessary but not sufficient.** Parser checks and host
   tests did not reproduce every CSP main-chunk and first-frame behavior. Each
   driver-client phase therefore includes a real Assetto Corsa/CSP gate.
3. **Module order must be generated, not accidental.** Development modules will
   be bundled in a deterministic dependency order. The generated runtime must
   not use `require` or `dofile`.
4. **Top-level local pressure is a runtime constraint.** V1 recorded CSP load
   failures after the main chunk exceeded a practical local ceiling. The bundle
   gate will measure main-chunk locals and preserve headroom rather than treating
   a host parser result as proof.
5. **Globals must be namespaced.** V1's declaration-order failure resolved an
   intended local reference as a nil global. Configuration and shared state must
   live under an explicit AVM namespace; bare constants are forbidden.
6. **Pit guidance must prefer invalid/stale states over optimistic advice.** V1
   once allowed a passed plan to remain `CAN EXTEND` and bypassed configurable
   thresholds. Rewritten domain logic must test boundary precedence and use
   validated configuration.
7. **Text-replacement tooling can corrupt Lua.** A V1 resize edit injected
   literal line-ending escape text. Bundle generation must be deterministic and
   byte-level output checks must precede CSP installation.

## Knowledge that may be migrated

- endurance-racing terminology and stint concepts;
- fuel, pace, sample-eligibility, pit-window, Recovery, and Replan requirements;
- CSP API discoveries with an evidence reference and fresh SDK check;
- telemetry probes and their trust limitations;
- installer and filesystem-safety requirements;
- failure cases and regression scenarios.

Each migrated behavior must be documented as a requirement, rewritten behind a
clean boundary, protected by tests, and runtime-validated when CSP-dependent.

## What must not be copied wholesale

- V1 `script.lua`, global state, UI layout, persistence model, or profile editor;
- declaration-order-sensitive functions or old phase prompts as implementation
  authority;
- third-party code, comments, assets, branding, fonts, sounds, or file layout
  referenced by V1 research.

The new AVM PitWall is a compact, predominantly read-only race client. Strategy
construction and detailed administration belong in the Engineer Console.

## Evidence classification

V1 documentation can establish a requirement or a historical observation. It
cannot by itself establish that the new architecture is implemented, or that an
installed CSP capability works in the new runtime. Those claims require the
phase-specific gates in
[CSP runtime gate](../testing/csp-runtime-gate.md) and
[compatibility policy](../contracts/compatibility-policy-v0.md).
