# Dev Workflow

## Branching
- `main`: protected release branch.
- `dev`: active integration branch.
- feature branches: `feature/<milestone>-<scope>`.

## Daily loop
1. Pull latest `dev`.
2. Run data validation task: `Validate Data (Godot)`.
3. Run game scene and execute active milestone manual tests.
4. Commit only when manual test script pass criteria are met.

## Suggested commit prefixes
- `m0:` foundation
- `m1:` core loop
- `m2:` data systems
- `m3:` vertical slice
- `fix:` bug fix
- `balance:` tuning-only change
