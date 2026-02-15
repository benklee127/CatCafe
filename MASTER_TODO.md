# CatCafe Master TODO

_Last updated: 2026-02-14_

## Current Focus (Next 7-10 Days)
- [ ] Verify clean boot in local Godot editor (`project.godot` loads with no critical errors).
- [ ] Run `Tests/M1_core_loop.md` end-to-end and log issues in `Docs/BUGS.md`.
- [ ] Implement full Trust lifecycle update rules in runtime loop.
- [ ] Confirm all tuning is data-only via live edit tests.
- [ ] Lock M1 + M2 with a "no new features" freeze until P1 issues are resolved.
- [x] Create `Docs/ASSET_MANIFEST.md` with production asset list and owners.

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
- [ ] Verify clean boot in local Godot editor.

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
- [x] Implement isometric blocked-cell navigation for decor-aware pathing.
- [x] Implement interaction slot claim/release system for decor usage markers.
- [x] Enable y-sorted runtime layering for decor, cats, and patrons.
- [x] Add manual test script `Tests/M2_5_navigation_slots_sorting.md`.
- [ ] Implement full trust lifecycle update rules in runtime loop.
- [x] Add adoption match scoring utility.
- [x] Implement one-slot save/load.
- [x] Add save version migration from v0 to v1.
- [x] Add manual test script `Tests/M2_data_and_generation.md`.
- [ ] Confirm all tuning is data-only via live edit tests.
- [ ] Add deterministic simulation test seeds for balancing regressions.
- [ ] Validate save/load integrity across 10+ in-game days.

### Data/Design Tasks
- [ ] Finalize trait schema fields for: stress modifiers, trust gain, adoption affinity, rarity weight.
- [ ] Finalize patron archetype schema fields for: overstim pressure, spend profile, patience, preferred decor.
- [ ] Finalize decor schema fields for: cat comfort effect, patron dwell effect, placement cost, unlock tier.
- [ ] Add trust-state thresholds (`fearful`, `warming`, `bonded`, `adoptable`) in data.
- [ ] Add rescue source data table: `shelter`, `alley`, `doorstep_event`.

## M3 Vertical Slice
**Goal:** One polished, fully playable slice with representative UX.

### Exit Criteria
- New player can complete one full rescue -> rehabilitate -> adopt loop.
- UI, art, audio, and tutorial are coherent and bug-triaged.

### Core Systems Tasks
- [ ] Implement rescue intake flow.
- [ ] Implement adoption action with reputation gain.
- [ ] Add reputation progression hooks.
- [ ] Add day-end/menu crash-safe checkpoints.
- [ ] Execute balancing scenarios for cat drought frequency and recovery.
- [x] Add manual test script `Tests/M3_vertical_slice.md`.

### Art Production Tasks (Vertical Slice)
- [x] Create `Docs/ART_STYLE_GUIDE.md` (palette, line weight, scale, export settings).
- [ ] Define asset naming convention and import settings for Godot (`nearest`, no filtering for pixel art).
- [ ] Replace placeholder floor with production tile set (floor, wall, rest area, collision variants).
- [ ] Create cat base sprite layers: body base, coat pattern overlay, fur-length overlay, eyes, tail.
- [ ] Create first rare cat visual set: `sphynx`.
- [ ] Create second rare cat visual set: `maine_coon`.
- [ ] Produce patron sprites for 3 archetypes with idle/walk states.
- [ ] Produce staff/player sprite with idle/walk states.
- [ ] Create decor sprites for the 12 MVP decor items.
- [ ] Create interactable VFX sprites: stress pulse, calm aura, adoption confirmation.
- [ ] Create simple portrait/card frame art for cat popup UI.

### UI/UX Tasks (Vertical Slice)
- [ ] Implement main menu UI.
- [ ] Implement settings menu UI.
- [ ] Implement in-game HUD: money, reputation, active cats, cat drought alert.
- [ ] Implement cat popup UI: traits, trust meter, overstim meter, adoption readiness.
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
- [ ] Define and enforce P0/P1 bug severity in `Docs/BUG_TRIAGE.md`.
- [ ] Add performance budget targets (CPU frame time, memory, load times).
- [ ] Add save compatibility policy for future schema/version changes.
- [ ] Add known-risks log with owner + mitigation in `Docs/RISKS.md`.
- [ ] Add playtest template for capturing session metrics (cat droughts, avg trust gain, adoptions/day).

## Anti-Creep Guardrails
- [x] Maintain parking lot in `Docs/IDEA_PARKING_LOT.md`.
- [x] Freeze milestone scope before implementation.
- [ ] Enforce no milestone closure with unresolved P1 issues.
- [ ] Require every new feature request to include milestone + success metric before approval.
- [ ] Enforce "vertical slice complete before content volume expansion" rule.

