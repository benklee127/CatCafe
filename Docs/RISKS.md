# Known Risks

| # | Risk | Likelihood | Impact | Owner | Mitigation |
|---|---|---|---|---|---|
| R1 | Hybrid 3D + SubViewport cat rigs cost too much GPU/CPU with many cats (one viewport per cat). | Medium | High | Track A | `UPDATE_WHEN_VISIBLE` viewports, a 160×160 canvas, and the F6 fallback sprite. Profile with 10+ cats before M3. Consider a shared atlas or impostor if it is too slow. |
| R2 | Footprint, slot and scale data drift from the meshes, so slots become unreachable again. | Medium | High | Track B | A single footprint source (`decor_mesh_map.json` with `scale`), a load-time slot check, and the slot pass in `Tools/probe_core_loop.gd`. |
| R3 | Save format changes break existing saves. | Medium | High | Track C | `save_version` migration, backfill from `run_state_template.json`, atomic write with `.bak`, and refusing future versions. Add a migration test for each version bump. |
| R4 | Data and code disagree on tunables, or JSON typos ship. | Medium | Medium | Track C | Schemas plus `Tools/validate_data.gd` (exits 1). Run it in the daily loop and CI. Code reads `balance_config.json` with defaults. |
| R5 | Nav deadlocks (actors boxed in by decor or the rest partition). | Medium | High | Tracks A + B | Rest-aware `build_path` with door edges, placement blocked on actors, re-path rate limits, and the probe's rest-return and soak checks. |
| R6 | Missing import settings on a fresh clone (`*.import` was gitignored). | Low | Medium | Track C | `.gitignore` no longer excludes `*.import`. Commit the `.import` and `.uid` files with the assets. |
| R7 | Scope creep away from the core overstim and trust loop. | High | Medium | Design | `Docs/SCOPE_GUARDRAILS.md` and `Docs/IDEA_PARKING_LOT.md`. Milestone gates in `Tests/`. |
| R8 | Third-party asset licensing (KayKit placeholders). | Low | Medium | Track C | The KayKit assets are CC0. The credit and mapping are in `Art_Assets/3d/kaykit/core_subset/README.md`. Track every asset in `Docs/ASSET_MANIFEST.md`. |
| R9 | Parallel tracks editing shared files cause merge conflicts and boot breaks. | Medium | Medium | Orchestrator | Disjoint file ownership, contract-only cross-file calls behind `has_method` guards, and a headless boot after each task group. |
