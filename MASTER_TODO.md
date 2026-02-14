# CatCafe Master TODO

## M0 Foundation
- [x] Initialize git repo with `main` + `dev` workflow.
- [x] Add `.gitignore` for Godot/editor artifacts.
- [x] Create folders: Scenes, Scripts, Data, Art_Assets, Audio, UI, Tests, Docs, Tools.
- [x] Add `project.godot` with baseline display/physics/input settings.
- [x] Add VS Code workspace recommendations/settings.
- [x] Add tech/game/scope docs.
- [x] Add draft data schemas in `Data/schemas`.
- [x] Add data validation runner script (`Tools/validate_data.gd`).
- [x] Document GitHub labels/milestones setup.
- [ ] Verify clean boot in local Godot editor.

## M1 Ugly Prototype
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

## M2 Systems + Data
- [x] Implement JSON data loader and runtime key validation.
- [x] Add seed data: 6 traits, 3 patron archetypes, 12 decor items.
- [x] Implement procedural cat generation with rarity weighting.
- [x] Bind trait and patron impacts into overstim pressure.
- [ ] Implement full trust lifecycle update rules in runtime loop.
- [x] Add adoption match scoring utility.
- [x] Implement one-slot save/load.
- [x] Add save version migration from v0 to v1.
- [x] Add manual test script `Tests/M2_data_and_generation.md`.
- [ ] Confirm all tuning is data-only via live edit tests.

## M3 Vertical Slice
- [ ] Replace placeholders with production art and tiles.
- [ ] Implement main menu/settings/cat popup UI.
- [ ] Implement rescue intake flow.
- [ ] Implement adoption action with reputation gain.
- [ ] Add reputation progression hooks.
- [ ] Add baseline audio pass.
- [ ] Add first-run tutorial sequence.
- [ ] Execute balancing scenarios.
- [ ] Add day-end/menu crash-safe checkpoints.
- [x] Add manual test script `Tests/M3_vertical_slice.md`.

## M4 Content Expansion
- [ ] Expand decor content to 50 items.
- [ ] Expand patron archetypes to 5.
- [ ] Implement brushing and laser mini-games.
- [ ] Implement VIP alumni visit event.
- [ ] Add more traits and rare variants.
- [ ] Add tuning import pipeline.
- [ ] Run structured balancing passes.
- [x] Add manual test script `Tests/M4_content_and_balance.md`.

## M5 Pre-Launch QA
- [ ] Build Windows Steam release checklist.
- [ ] Run full regression suite each RC.
- [ ] Add telemetry-lite local metrics logs.
- [ ] Validate onboarding completion with playtesters.
- [ ] Fix top UX/balance defects.
- [ ] Create launch branch/tag strategy.

## M6 Marketing + Steam
- [ ] Create Steam page media and metadata.
- [ ] Pay Steam Direct fee and complete compliance.
- [ ] Build and publish Itch demo pipeline.
- [ ] Maintain weekly Reddit/TikTok cadence.
- [ ] Track and optimize wishlist funnel metrics.
- [ ] Lock launch window after two stable RCs.

## Anti-Creep Guardrails
- [x] Maintain parking lot in `Docs/IDEA_PARKING_LOT.md`.
- [x] Freeze milestone scope before implementation.
- [ ] Enforce no milestone closure with unresolved P1 issues.
