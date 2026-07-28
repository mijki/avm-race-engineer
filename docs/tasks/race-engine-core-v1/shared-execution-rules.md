# Shared Execution Rules

## Repository and branch

Repository: `E:\Work\Repos\avm-race-engineer`

Required branch: `feat/race-engine-core-v1`

Use one forward-only branch for Tasks 1–3.

## Git policy

Do not switch branches, create another branch, rebase, cherry-pick, merge, squash, amend completed commits, reset, stash, clean, push, tag, or create a pull request.

Each task creates exactly one local commit. Later corrections must be new forward commits.

## Protected resources

Do not modify:

- `E:\Work\Repos\avm-pitwall`
- `E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\AVM_PitWall`
- `E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\LapAlly_HUD`
- `E:\Games\Steam\steamapps\common\assettocorsa\apps\lua\CMRT-Complete-HUD`
- `E:\Games\Steam\steamapps\common\assettocorsa\extension\internal\lua-sdk`

LapAlly, CMRT, and the CSP SDK are read-only references. Do not copy complete functions, modules, layouts, assets, textures, icons, fonts, branding, or distinctive designs.

## Scope boundaries

Tasks 1–3 must not add Relay/Engineer networking, the complete eligibility engine, the complete stint engine, the complete forecast engine, a major HUD redesign, or a visual-asset system.

## Architecture

Preserve:

`CSP telemetry → normalized snapshot → immutable events → race state → eligibility → calculations → forecasts → driver view model → renderer`

Rules:

- UI must not read raw CSP telemetry.
- Renderers must not calculate race values.
- Missing or unsupported values must not become zero.
- Forecasts must not masquerade as measurements.
- Recommendations must not masquerade as forecasts.
- Runtime collections must be bounded.
- No runtime `require` or `dofile`.
- No networking.

## Stop-on-failure

Do not begin the next task unless the current task:

- created its required commit;
- passed the full automated suite;
- passed task-specific tests;
- passed deterministic build verification;
- passed `git diff --check`;
- left a clean worktree;
- introduced no unresolved architectural violation.

On failure, stop and report the failing command, failure summary, affected files, current HEAD, worktree status, and safest forward-only recovery.

## Shared validation

Run before every task commit:

```powershell
python tools\f1_validation.py
python -m unittest discover -s tests -p "test_*.py" -q
python tools\build_f1.py --verify-deterministic
git diff --check
```

Also validate JSON, fixtures, Markdown links, Python compilation, conflict markers, runtime `require`/`dofile`, networking boundaries, installer dry-run, and V1-target rejection.

Do not claim real CSP validation unless the game was actually run.
