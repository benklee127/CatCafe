# CatCafe

A cozy foster-cat cafe management sim built in **Godot 4.6** (GDScript). The game is hybrid 3D: an orthographic 3D diorama room with 2D billboard actors. Cats are procedural 2D rigs rendered through a SubViewport onto a billboard.

## Quick start
1. Install Godot 4.6 stable. Any 4.6.x build works; use the `_console` exe for headless commands on Windows.
2. Open the project folder in Godot and press **F5**. The main scene is `res://Scenes/Prototype3D/MainLevel3D.tscn`, set in `project.godot`.
3. Headless smoke boot from the command line:
   ```powershell
   & $GODOT --headless --path C:\workspace\CatCafe --quit-after 300
   ```
   `$GODOT` is the path to `Godot_v4.6-stable_win64_console.exe` (see `DEPLOY.md`).

## Controls (MainLevel3D)
| Action | Input |
|---|---|
| Open the build menu | **Build** button (bottom-left) |
| Pick an item | Click it in the build list (keys 1–9 also work) |
| Place the held item | Left click on a green footprint (red means blocked; the reason shows by the cursor) |
| Rotate the held item | **R**, **Q / E**, or the mouse wheel while holding |
| Cancel the held item | **Esc** or right click |
| Inspect placed decor | Left click it with nothing held (inspector on the right) |
| Zoom | Mouse wheel when nothing is held (ortho size 8–17) |
| Pan | **WASD** or middle-mouse drag |
| Cat popup | Left click a cat: traits, trust bar and state, overstim bar, adoption-ready flag |
| Toggle the cat rig / fallback sprite | **F6** (debug) |

The top bar shows money, reputation, cats on the floor (X/Y), the day and the clock. A toast appears when every cat is resting (a cat drought). Progress (day, money, reputation, placed decor, cats) saves at the end of each day and on quit, to `user://run_state.json`.

## Structure
- `Scenes/Prototype3D/`: live game scenes. `MainLevel3D.tscn` is the game, `Cat3D`/`Cat2D` are the cat actor and rig, `Human3D` is the patron, `CatPreview.tscn` is the rig test bench, and `Decor/` holds the decor wrapper scenes.
- `Scripts/prototype3d/`: level, placement, slots, floor builder, cat/patron actors, HUD, and the cat genome.
- `Scripts/data/`: `DataLoader`, `SchemaValidator`, `SaveSystem` and `CatFactory`. Shared with the legacy scenes.
- `Data/`: JSON definitions and tunables (the source of truth), plus `Data/schemas/`.
- `Tools/`
  - `validate_data.gd`: data validator; exits 1 on any error.
  - `probe_core_loop.gd`: headless core-loop probe.
  - `capture_screenshot.gd`: screenshot helper.
- `Tests/`: manual test scripts and the regression checklist.
- `Docs/`: specs, the art guide, `BUGS.md`, and the risk and triage notes.

## Checks
```powershell
# Data validation (exit 0 = clean, 1 = errors)
& $GODOT --headless --path . --script res://Tools/validate_data.gd
# Core-loop probe: rest return, retreat/interact transitions, slot reachability, Cat2D rig errors
& $GODOT --headless --path . --fixed-fps 10 --script res://Tools/probe_core_loop.gd
# Screenshot any scene
& $GODOT --path . --script res://Tools/capture_screenshot.gd -- res://Scenes/Prototype3D/MainLevel3D.tscn C:\temp\shot.png 120
```

## Legacy 2D prototypes (reference only)
These scenes still boot, but they are not the game. Keep them for reference and do not build new features on them.
- `Scenes/Main.tscn` (`Scripts/prototype/CafePrototype.gd`): the first M1 loop, with debug circles, `GridPlacer` click placement and `DebugHUD`. It saves to `user://legacy_main_run_state.json`, so it never overwrites the 3D save.
- `Scenes/MainLevel.tscn` (`Scripts/prototype/MainLevel*.gd`): the 2D isometric nav/slot prototype that the 3D level was ported from.
- `Scenes/Prototype/IsometricPrototype.tscn`: the textured-tile visual reference.

## Milestone status
- M0 complete: scaffold, docs and schemas.
- M1/M2 complete on the legacy path. They are being ported to the hybrid 3D path: data-driven overstim and trust, CatFactory cats, patron lifecycle, HUD and save.
- Known issues and owners: `Docs/BUGS.md`.
