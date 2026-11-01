# CatCafe Master TODO

_Last updated: 2026-10-24 — audit + fix pass (see `Docs/BUGS.md`). Checks: headless boot of all scenes clean, `Tools/validate_data.gd` exit 0, `Tools/probe_core_loop.gd` PASS._

## Current Focus (Next 7-10 Days)
- [ ] Verify clean boot in local Godot editor (`project.godot` loads with no critical errors). _Headless boot of all 5 scenes is clean (0 errors); editor open + re-import still to confirm._
- [ ] Run `Tests/M1_core_loop.md` end-to-end and log issues in `Docs/BUGS.md`. _`Docs/BUGS.md` now exists, seeded with 95 audit findings; manual playtest still needed._
- [x] Implement full Trust lifecycle update rules in runtime loop.
- [ ] Confirm all tuning is data-only via live edit tests. _Overstim/trust/economy/population now read from `balance_config.json`; not yet live-edit tested. Known gap: `overstim.crowd_mult` has no effect in the 3D level._
- [ ] Lock M1 + M2 with a "no new features" freeze until P1 issues are resolved.
- [x] Create `Docs/ASSET_MANIFEST.md` with production asset list and owners.

### Open follow-ups (2026-10-24 pass)
- [ ] Owner to define final cat + patron sprite direction (current procedural actors are interim; sprite files frozen pending this).
- [ ] Manual playtest in editor of the 3D loop; mark `Docs/BUGS.md` rows `verified` as confirmed.
- [ ] Commit the 2026-10-24 changes (nothing committed yet) and open the project in the editor once so new files get `.uid`/import entries.
- [ ] Perf: cat rig redraws tail/legs every frame per cat — profile with 10+ cats (see `Docs/RISKS.md` R1).
- [ ] Clicking a patron does nothing; patrons can briefly overlap.
- [ ] Placing bar (top-centre) overlaps the back of the nap zone; controls help no longer lists F6.

## Cat2D Rig Track (Hybrid Actor Visuals)
**Goal:** Move cat rendering to a reusable 2D rig rendered into the 3D world via `SubViewport`.

### Exit Criteria
- `Cat2D.tscn` has a stable bone hierarchy and reusable placeholder animation setup. _(Skeleton2D replaced by procedural Node2D parts — nothing is skinned.)_
- `Cat3D.tscn` renders the `Cat2D` rig through a billboard viewport in-world.
- Cat direction, palette params, and part-swapping hooks are scriptable from a per-cat genome dictionary.

### Phase A: Skeleton Scaffold
- [x] Create `Scenes/Prototype3D/Cat2D.tscn` with `Skeleton2D` + core bones (`Hip`, `Spine`, `Head`, `Tail_01..04`, 4 leg chains).
- [x] Add placeholder `Sprite2D` nodes parented to bones for fast visual verification. _Superseded: parts are now drawn procedurally (`CatPart2D.gd`)._
- [x] Add `Scripts/prototype3d/Cat2D.gd` with exported visual/genome parameters.
- [x] Add `Scenes/Prototype3D/CatPreview.tscn` with live UI controls for cat visual tuning.
- [x] Add base idle + walk animation clips. _Done procedurally in `Cat2D.gd` (idle, walk, sit, sleep poses) instead of `AnimationPlayer`._

### Phase B: 3D Wrapper Integration
- [x] Refactor `Scenes/Prototype3D/Cat3D.tscn` to include `BillboardAnchor`, `SubViewport`, and `Cat2D` instance.
- [x] Route the viewport texture to the cat billboard renderer.
- [x] Replace root `Node3D` actor with `CharacterBody3D` movement/collision pass (without gameplay behavior changes).
- [x] Add runtime toggle for fallback static sprite vs viewport rig. _(F6 in-game)_

### Phase C: Direction + Motion
- [ ] Implement camera-relative direction bucketing (4-dir baseline, 8-dir ready). _Currently 2-dir (left/right from camera right axis); front/back views not started._
- [x] Add left/right mirror support for reduced directional art load.
- [x] Add procedural secondary motion (tail sway + subtle head bob).

### Phase D: Genome Pipeline
- [x] Define `CatGenome` data contract (colors, pattern, body proportions, part variants, personality motion values). _`Scripts/prototype3d/CatGenome.gd` + `Data/schemas/CatGenome.schema.json`._
- [x] Add `Cat2D.apply_genome(genome: Dictionary)` with validation + defaults.
- [x] Connect `CatFactory` output to Cat3D/Cat2D runtime.
- [ ] Add deterministic visual regression test seeds. _`Tools/render_cat_seeds.gd` renders a seeded 6×4 sheet; no automated golden-image comparison yet._

## M0 Foundation
**Goal:** Stable project scaffold and workflow.

### Exit Criteria
- Project opens and runs from clean checkout.
- Team workflow/docs are usable without tribal knowledge.

### Tasks
- [x] Initialize git repo with `main` + `dev` workflow.
- [x] Add `.gitignore` for Godot/editor artifacts.
- [x] Create folders: `Scenes`, `Scripts`, `Data`, `Art_Assets`, `Audio`, `UI`, `Tests`, `Docs`, `Tools`.
- [x] Add `project.godot` with baseline display/physics/input settings.
- [x] Add VS Code workspace recommendations/settings.
- [x] Add tech/game/scope docs.
- [x] Add draft data schemas in `Data/schemas`.
- [x] Add data validation runner script (`Tools/validate_data.gd`).
- [x] Document GitHub labels/milestones setup.
- [ ] Verify clean boot in local Godot editor. _(headless clean; editor pending)_

## M1 Ugly Prototype
**Goal:** Prove the core loop is fun with placeholder visuals.

### Exit Criteria
- Placement, cat behavior, patron pressure, and auto-retreat loop all work in one playable session.
- Manual playtest completed with prioritized bug list.

### Tasks
- [x] Build `Scenes/Main.tscn` with prototype world layers.
- [x] Implement isometric click placement and remove logic.
- [x] Implement cat wander behavior.
- [x] Implement patron movement.
- [x] Implement overstimulation growth loop.
- [x] Implement auto-retreat to rest area and cooldown return.
- [x] Add debug HUD for cat state and overstim values.
- [x] Add deterministic seed flag.
- [x] Add manual test script `Tests/M1_core_loop.md`.
- [ ] Run manual playtest and capture issues.
- [ ] Fix all M1 P1 defects before milestone closure.

## M2 Systems + Data
**Goal:** Shift gameplay tuning to data and procedural systems.

### Exit Criteria
- Cat generation, trait impacts, patron impacts, trust lifecycle, and save/load are stable.
- Designers can tune core values via JSON without code edits.

### Engineering Tasks
- [x] Implement JSON data loader and runtime key validation.
- [x] Add seed data: 6 traits, 3 patron archetypes, 12 decor items.
- [x] Implement procedural cat generation with rarity weighting.
- [x] Bind trait and patron impacts into overstim pressure.
- [x] Scaffold hybrid 3D runtime path in `Scenes/Prototype3D/MainLevel3D.tscn`.
- [x] Add data contract and seed mapping file: `Data/decor_mesh_map.json`.
- [x] Implement 3D decor placement/removal with rotation preview and grid occupancy.
- [x] Port cat/patron core movement + slot behavior to 3D billboard actor scenes.
- [x] Add manual test script `Tests/M2_6_hybrid3d_core_loop.md`.
- [x] Implement isometric blocked-cell navigation for decor-aware pathing.
- [x] Implement interaction slot claim/release system for decor usage markers.
- [x] Enable y-sorted runtime layering for decor, cats, and patrons.
- [x] Add manual test script `Tests/M2_5_navigation_slots_sorting.md`.
- [x] Implement full trust lifecycle update rules in runtime loop.
- [x] Add adoption match scoring utility.
- [x] Implement one-slot save/load.
- [x] Add save version migration from v0 to v1.
- [x] Add manual test script `Tests/M2_data_and_generation.md`.
- [ ] Confirm all tuning is data-only via live edit tests.
- [ ] Add deterministic simulation test seeds for balancing regressions. _`--seed=N` flag + seeded `Tools/probe_core_loop.gd` (seed 4242) exist; no balance-metric assertions yet._
- [ ] Validate save/load integrity across 10+ in-game days. _3D save/load (day end + on quit, atomic with `.bak`) verified for 1 day round-trip._

### Data/Design Tasks
- [ ] Finalize trait schema fields for: stress modifiers, trust gain, adoption affinity, rarity weight.
- [ ] Finalize patron archetype schema fields for: overstim pressure, spend profile, patience, preferred decor.
- [ ] Finalize decor schema fields for: cat comfort effect, patron dwell effect, placement cost, unlock tier. _`cost` + `display_name` added; unlock tier pending._
- [x] Add trust-state thresholds (`fearful`, `warming`, `bonded`, `adoptable`) in data.
- [x] Add rescue source data table: `shelter`, `alley`, `doorstep_event`. _(`Data/rescue_sources.json`; not yet used by an intake flow)_

## M3 Vertical Slice
**Goal:** One polished, fully playable slice with representative UX.

### Exit Criteria
- New player can complete one full rescue -> rehabilitate -> adopt loop.
- UI, art, audio, and tutorial are coherent and bug-triaged.

### Core Systems Tasks
- [ ] Implement rescue intake flow.
- [x] Implement adoption action with reputation gain. _`adopt_cat()` + "Find a home" button on the cat card (+10 rep, +11 with adoption corner); a replacement rescue cat arrives. No patron matchmaking yet._
- [ ] Add reputation progression hooks.
- [ ] Add day-end/menu crash-safe checkpoints. _Day-end + quit saves are atomic with `.bak` fallback; menu checkpoint pending (no menu yet)._
- [ ] Execute balancing scenarios for cat drought frequency and recovery. _First pass done: trust now rises in a calm cafe (cats reach `warming` on day 2–3), retreats ~1–4 per cat per day, naps ~9 s. Only checked on 2–3 seeds; fearful cats wander a lot._
- [x] Add manual test script `Tests/M3_vertical_slice.md`.

### Art Production Tasks (Vertical Slice)
- [x] Create `Docs/ART_STYLE_GUIDE.md` (palette, line weight, scale, export settings).
- [ ] Define asset naming convention and import settings for Godot (`nearest`, no filtering for pixel art).
- [ ] Replace placeholder floor with production tile set (floor, wall, rest area, collision variants). _Interim: procedural plank floor, walls, rest rug + fenced doorway in `FloorBuilder3D.gd`._
- [ ] Create cat base sprite layers: body base, coat pattern overlay, fur-length overlay, eyes, tail. _Interim procedural cat in `Cat2D.gd`; owner has own plans for final sprites._
- [ ] Create first rare cat visual set: `sphynx`.
- [ ] Create second rare cat visual set: `maine_coon`.
- [ ] Produce patron sprites for 3 archetypes with idle/walk states. _Interim procedural patrons in `MainLevelPatron3D.gd`; owner has own plans._
- [ ] Produce staff/player sprite with idle/walk states.
- [ ] Create decor sprites for the 12 MVP decor items. _Interim: 12 distinct primitive-mesh decor scenes in `Scenes/Prototype3D/Decor/`._
- [ ] Create interactable VFX sprites: stress pulse, calm aura, adoption confirmation.
- [ ] Create simple portrait/card frame art for cat popup UI.

### UI/UX Tasks (Vertical Slice)
- [ ] Implement main menu UI.
- [ ] Implement settings menu UI.
- [x] Implement in-game HUD: money, reputation, active cats, cat drought alert.
- [x] Implement cat popup UI: traits, trust meter, overstim meter, adoption readiness.
- [ ] Implement rescue choice UI (shelter/alley/doorstep event).
- [ ] Implement tutorial popups for first day.
- [ ] Add accessibility baseline: text size, contrast, audio sliders, key remap.

### Audio Tasks (Vertical Slice)
- [ ] Create `Docs/AUDIO_STYLE_GUIDE.md` (cozy mix targets + loudness policy).
- [ ] Add 1 looping BGM track for cafe floor.
- [ ] Add core SFX set: meow variants, purr loop, UI click, purchase/place, adoption success.
- [ ] Add ambience bed: cafe room tone, soft cup/espresso sounds.
- [ ] Wire audio events to gameplay states (normal, high stress, adoption moment).

## M4 Content Expansion
**Goal:** Expand replayability without destabilizing core loop.

### Exit Criteria
- Content targets hit and balance remains within defined ranges.
- Mini-games and VIP system integrate cleanly with economy and stress loop.

### Gameplay/Systems Tasks
- [ ] Expand patron archetypes to 5.
- [ ] Implement brushing mini-game.
- [ ] Implement laser-pointer mini-game.
- [ ] Implement nail trimming mini-game (if still in scope after vertical slice review).
- [ ] Implement VIP alumni visit event.
- [ ] Add more traits and rare variants.
- [ ] Add tuning import pipeline.
- [ ] Run structured balancing passes.
- [x] Add manual test script `Tests/M4_content_and_balance.md`.

### Art Production Tasks (Content Grind)
- [ ] Expand decor content to 50 total items (38 net new after MVP 12).
- [ ] Create tiered cafe upgrade art for Tier 1 -> Tier 3 expansion.
- [ ] Add additional cat visual layer variants (coat patterns, eye colors, tail types, fur variants).
- [ ] Add 2 more patron archetype sprite sets with animation states.
- [ ] Create mini-game-specific art packs (brush tools, laser target, grooming UI elements).
- [ ] Create VIP alumni visual treatment (owner variants + happy aura effect).

### Audio Tasks (Content Grind)
- [ ] Add 2-3 additional BGM loops.
- [ ] Expand SFX library for mini-games and decor interactions.
- [ ] Add state transition stingers (cat drought warning, trust milestone, reputation level up).

### Narrative/Content Tasks
- [ ] Write rescue event text pool for shelter/alley/doorstep events.
- [ ] Write patron flavor text pool for archetypes and adoption dialogue.
- [ ] Write adoption outcome snippets (successful match, neutral, mismatch feedback).

## M5 Pre-Launch QA
**Goal:** Shipping candidate quality and operational readiness.

### Exit Criteria
- Regression suite stable across release candidates.
- Top UX and balance issues addressed with no open ship blockers.

### Tasks
- [ ] Build Windows Steam release checklist.
- [ ] Run full regression suite each RC.
- [ ] Add telemetry-lite local metrics logs.
- [ ] Validate onboarding completion with playtesters.
- [ ] Fix top UX/balance defects.
- [ ] Create launch branch/tag strategy.
- [ ] Final pass on crash handling + save corruption recovery.
- [ ] Validate deterministic seed behavior between builds.
- [ ] Run performance pass on low-end target PC profile.

## M6 Marketing + Steam
**Goal:** Convert demo interest into wishlists before launch.

### Exit Criteria
- Store page live, demo available, and weekly funnel cadence sustained.
- Wishlist trend is measurable and improving.

### Tasks
- [ ] Create Steam page media and metadata.
- [ ] Pay Steam Direct fee and complete compliance.
- [ ] Build and publish Itch demo pipeline.
- [ ] Maintain weekly Reddit/TikTok cadence.
- [ ] Track and optimize wishlist funnel metrics.
- [ ] Lock launch window after two stable RCs.
- [ ] Build lightweight content calendar in `Docs/MARKETING_CALENDAR.md`.

### Marketing Asset Tasks
- [ ] Capture 12+ clean gameplay screenshots from vertical slice.
- [ ] Produce 30-60 second trailer cut from actual gameplay.
- [ ] Produce short-form clip batch (at least 8 clips) for TikTok/Shorts/Reddit.
- [ ] Create capsule/header art variants for Steam page A/B testing.
- [ ] Create store copy set: short description, long description, feature bullets.

## Cross-Cutting Implementation Tracks

### Asset Pipeline
- [x] Create `Docs/ASSET_PIPELINE.md` with source -> export -> import workflow.
- [ ] Define directory structure under `Art_Assets/` by category (cats/patrons/decor/ui/vfx/tiles).
- [ ] Add art review checklist (readability at target zoom, silhouette clarity, palette compliance).
- [ ] Add versioning rules for raw source files and exported game-ready assets.

### Data + Content Ops
- [ ] Add content manifest files for traits, patrons, decor, rescue events, mini-games.
- [ ] Add validation rules for required localization-ready text keys (even before localization support).
- [ ] Add balancing spreadsheet or JSON export/import pipeline for tuning round-trips.

### QA + Observability
- [ ] Add CI run for: data validation, headless smoke launch, and schema checks.
- [x] Define and enforce P0/P1 bug severity in `Docs/BUG_TRIAGE.md`.
- [ ] Add performance budget targets (CPU frame time, memory, load times).
- [ ] Add save compatibility policy for future schema/version changes.
- [x] Add known-risks log with owner + mitigation in `Docs/RISKS.md`.
- [ ] Add playtest template for capturing session metrics (cat droughts, avg trust gain, adoptions/day).

## Anti-Creep Guardrails
- [x] Maintain parking lot in `Docs/IDEA_PARKING_LOT.md`.
- [x] Freeze milestone scope before implementation.
- [ ] Enforce no milestone closure with unresolved P1 issues.
- [ ] Require every new feature request to include milestone + success metric before approval.
- [ ] Enforce "vertical slice complete before content volume expansion" rule.

