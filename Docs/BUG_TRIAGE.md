# Bug Triage

How bugs in `Docs/BUGS.md` are rated, owned and closed.

## Severity
| Level | Definition | Examples | Response |
|---|---|---|---|
| **P0** | Breaks the core loop, crashes, corrupts or loses a save, or blocks boot. | Cats stuck in the rest area forever; a parse error in the main scene; a save overwritten with bad data. | Fix before any other work. No merge to `main` with an open P0. |
| **P1** | A major feature is wrong or missing, the game is clearly broken to a player, or a data/tuning value is ignored. | Decor slots unreachable; clicks pass through the UI; actors mis-scaled; the validator can never fail. | Fix before the next milestone or vertical-slice build. |
| **P2** | Minor, cosmetic, polish, hygiene or docs. Has a workaround. | Grid always visible; stale README; legacy scene off-centre. | Schedule as time allows. Batch with related work. |

When unsure, pick the higher severity, then downgrade after a repro.

## Required fields
Each `Docs/BUGS.md` row needs:
- an id (`BUG-###`)
- an area
- the `file:line`
- a one-line symptom
- the suggested fix
- the owner track (A, B or C, or a person)
- the plan task id, if there is one
- the status

## Status flow
`open` → `fixed` (code merged; say how it was verified) → `verified` (someone else reran the repro, a test script or `Tools/probe_core_loop.gd`). `wontfix` needs a one-line reason.

## Verification gates
- `Tools/validate_data.gd` exits 0.
- `Tools/probe_core_loop.gd --fixed-fps 10` exits 0. This covers rest return, retreat/interact transitions, slot reachability and Cat2D rig errors.
- A headless boot of `MainLevel3D.tscn`, `CatPreview.tscn` and the three legacy scenes prints 0 `ERROR:` lines.
- The relevant manual script in `Tests/` passes, and `Tests/REGRESSION_CHECKLIST.md` passes before a release.
