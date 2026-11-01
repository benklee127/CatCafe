# TECH SPEC

## Stack
- Engine: Godot 4.6 (stable). Headless tooling uses the `_console` exe.
- Language: GDScript, statically typed, indented with tabs.
- Target: Windows (Steam).

## Architecture (hybrid 3D)
- `Scenes/Prototype3D/MainLevel3D.tscn` is the main scene (`project.godot` `run/main_scene`).
  - `Scripts/prototype3d/MainLevel3D.gd` is the level API: grid ↔ world, walkability, BFS `build_path` (rest-aware, door edges), decor placement and footprints, slots, overstim pressure, decor aura effects, run state (money, reputation, day) and cat-drought signals.
  - Floor, rest rug, partition, walls and grid lines: `FloorBuilder3D.gd`.
  - Build mode, preview tiles and the build list: `DecorPlacement3D.gd`. Interaction slots: `SlotManager3D.gd`.
  - HUD: `HUD3D.gd` + `UI/HUD3D.tscn`, using the `UI/cozy_theme.tres` theme.
- Cats: `Scenes/Prototype3D/Cat3D.tscn` + `MainLevelCat3D.gd` (CharacterBody3D, layer 2).
  - The procedural 2D rig `Cat2D.tscn` (+ `CatGenome.gd`) is rendered in a 160×160 SubViewport onto a Y-billboard Sprite3D.
  - State machine: IDLE, WANDER, INTERACTING, RETREATING, REST, RETURNING. Trust states: fearful, warming, bonded, adoptable.
- Patrons: `Scenes/Prototype3D/Human3D.tscn` + `MainLevelPatron3D.gd` (CharacterBody3D, layer 4).
  - Archetype-driven `overstim_impact`. Lifecycle: enter → visit → LEAVING → tip.
- Data: `Scripts/data/*`
  - `DataLoader.load_all_data()`: 8 keys + `rescue_sources`, with `last_errors` / `last_warnings`.
  - `SchemaValidator`: a JSON-Schema subset.
  - `CatFactory.generate_cat(rng, seq, source_id)`.
  - `SaveSystem`: atomic one-slot save, migration and backfill.
- `Data/*.json` is the source of truth for tunables and definitions; schemas live in `Data/schemas/`.
- The interface contract between the cat, level, patron and data layers is kept in the implementation plan, section 1. Cross-file scripts are `preload`ed by path; do not add new `class_name` dependencies.

## Visual scale contract
- One cell is 0.7 m. Floor top at y = 0. Actor feet at y = 0.
- Orthographic camera at yaw 45 and pitch 40. Default size 12; overview 16.5; zoom 8–17.
- Cat: SubViewport 160×160 at `pixel_size` 1/160. Fallback sprite at `pixel_size` 0.016.
- Patron: `pixel_size` 0.024, about 1.55 m tall.
- Actor billboards: `BILLBOARD_FIXED_Y`, alpha-cut discard, unshaded, no shadow casting, feet pivot. No `no_depth_test` and no `fixed_size`.
- See `Docs/ART_STYLE_GUIDE.md` for the palette.

## Core systems
- Overstim: patron pressure × trait mult × trust-state mult × decor `interaction_mult`. Retreat at `retreat_threshold`, recover in REST, then RETURNING to the floor through a rest door.
- Trust: calm-band gain per day length, `stress_penalty` on each retreat, sticky adoptable with hysteresis.
- Decor: footprints and slots from `Data/decor_mesh_map.json`, UI from `decor_ui.json`, buffs and cost from `decor.json`, starter layout from `starter_layout.json`.
- Seeding: `--seed=N` (or the `run_seed` export) drives the level, cat and patron rngs. Every cat gets its own seed.

## Validation and tests
- `Tools/validate_data.gd`: schema + cross-reference checks. Exits 1 on errors.
- `Tools/probe_core_loop.gd`: headless probe (run with `--fixed-fps 10`). Exits 1 on failure.
- Manual scripts are in `Tests/`. The release gate is `Tests/REGRESSION_CHECKLIST.md`.

## Legacy 2D prototypes (reference only)
- `Scenes/Main.tscn` (`Scripts/prototype/CafePrototype.gd`, `CatAgent`, `PatronAgent`, `GridPlacer`, `DebugHUD`).
- `Scenes/MainLevel.tscn` (`Scripts/prototype/MainLevel*.gd`).
- `Scenes/Prototype/IsometricPrototype.tscn`.
- They boot without errors and share `Scripts/data/*`. New features go into `Scripts/prototype3d/`.

## Next implementation targets
- Adoption flow (match scoring → adoption event → reputation).
- Menus and production UI flow.
- Audio events and telemetry logging.
