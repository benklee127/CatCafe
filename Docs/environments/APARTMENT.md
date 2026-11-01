# Home Apartment environment

Scene: `res://Scenes/Environments/Apartment/Apartment.tscn`

This is the player's small, cozy flat between cafe days. Newly rescued or very fearful fosters decompress here before they go to the cafe. It uses the same look as the cafe: an orthographic iso diorama (yaw 45, pitch 40), warm materials, and billboard pixel cats. Everything is built from primitives and procedural textures. There are no imported assets.

Launch from PowerShell:

```powershell
& "C:\Users\benkl\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6-stable_win64.exe" --path C:\workspace\CatCafe res://Scenes/Environments/Apartment/Apartment.tscn
```

## Controls
| Input | Action |
|---|---|
| Mouse hover | Highlights a hotspot (warm pulsing rim, floor ring, cursor tooltip) |
| Left click | Opens the hotspot's prompt card; clicking empty space closes it |
| Right click / Esc / × | Close the card |
| WASD / arrows, middle-drag | Pan |
| Wheel | Zoom (5.5 up to the full-room fit) |
| Home | Toggle the full-room overview |
| "Go to Cafe" button (bottom right) | Change scene to `MainLevel3D.tscn` |

## Layout (14 × 10 cells of 0.7 m; the camera looks from +X+Z)
- **NW, bed nook:** bed with a rose duvet against an accent wallpaper, fairy lights, a wall shelf with a lamp.
- **N:** wardrobe, then a desk under the big window. The window shows a dusk city skyline on an unshaded backdrop behind the wall, and moonlight spills in. The planner notebook sits on the desk. A bookshelf comes next.
- **NE, kitchenette:** sage cabinets, sink under a small window, stove and kettle, open shelves with an under-shelf light, a retro fridge, checker tiles, and a round table for two.
- **W, living area and entry:** teal sofa, patterned rug, coffee table with a candle, floor lamp, wall shelf, and the front door with a mat, hooks and a bench.
- **SE, cat corner:** round sage rug, bonding nest with a human floor cushion, nap bed, scratch post, cat tree and a litter box. The cat bowls sit in front of the fridge.
- **Front:** record crate, plant and laundry basket.

Lighting is warm evening light: a dim directional "moon" key, lamp omni lights, cool window spotlights and a soft fill.

## Hotspots (stubs) and signals
All signals are on the scene root (`apartment.gd`). Every card button also emits `action_triggered(hotspot_id, action_id)`, and each hotspot (`apt_hotspot.gd`) emits `activated` and `action_chosen`. Clicking any hotspot emits `hotspot_activated(id)`.

| Hotspot id | Where | Primary action → signal | Stub behaviour now | Gameplay to hook up later |
|---|---|---|---|---|
| `feed` | Bowls and kibble tin by the fridge | "Fill the bowls" → `feed_cats_requested` | Every cat walks to a bowl and eats for about 7 s ("nom"); toast | Hunger / fed flag per cat, food stock and cost, small trust or calm bonus |
| `bed` | Bed | "Sleep till morning" → `sleep_requested(day)` | Fade to dark, all cats curl up, day +1 (local counter), "Morning · Day N" | End the day, save, advance the run day, morning summary |
| `planner` | Notebook on the desk | "Plan tomorrow" → `plan_tomorrow_requested` | Toast | Planner UI: choose fosters for the cafe, shopping list, appointments |
| `bond` | Bonding nest | "Sit with a cat" → `bonding_requested(cat)` | The shyest cat (lowest trust) walks over, sits for about 14 s (+3 trust, then the cat's own calm-interaction trust gain); ♥ | Bonding mini-activity, the fearful → warming gate before the cafe |
| `wardrobe` | Wardrobe | "Open wardrobe" → `wardrobe_requested` | Toast | Cosmetics / outfits screen |
| `door` | Front door | "Go to Cafe" / "Go to Town" → `travel_requested("cafe" \| "town")` | Fades and changes scene: cafe → `cafe_scene_path`; town → `town_scene_path` (`res://Scenes/Environments/Town/Town.tscn`), or a toast if that file is missing | Day-phase rules (cafe only in the morning, for example) |

Set `allow_scene_change = false` to keep travel as signals only. The probe does this.

## Cats
- The foster cats (`foster_cat_count`, default 2; `cat_seed` 0 = random) are real `Cat3D.tscn` instances that run their unmodified `MainLevelCat3D` state machine. Cats are generated with `CatFactory` from `Data/` (rescue sources: alley, shelter).
- `apt_nav_grid.gd` is the cat's `level`. It implements the duck-typed API the cat uses: `map_to_world`, `world_to_map`, `is_walkable`, `build_path`, `random_cafe_cell`, `get_overstim_pressure_near` and the rest. There is no rest area, no patrons and no slots. Furniture footprints from the builder become blocked cells.
- Bonding uses the cat's own rules. While a session runs, the nav grid reports a calm "company" point (count 1, pressure 0) at the nest. The cat then switches to INTERACTING (sit pose) and gains trust through its normal calm-interaction rule.
- `apt_cat_director.gd` adds home routines: feed, bond, nap and all-sleep. It also sends a random free cat to the nap bed every 30–55 s. A nap uses the REST state (sleep pose and Zz). The director sets the overstim value so REST ends by itself after about 16 s.
- The overstim bar is hidden at home. No cat art or poses were added; only `set_pose` and facing are driven, through the existing controller.

## Files
- `Scenes/Environments/Apartment/Apartment.tscn`: root, WorldEnvironment, moon light.
- `Scripts/environments/apartment/apartment.gd`: controller, signals, picking, hotspot definitions, cat spawning.
- `Scripts/environments/apartment/apt_room_builder.gd`: procedural room and textures (planks, checker tiles, rug, wallpaper, subway tiles, plaster, city skyline).
- `Scripts/environments/apartment/apt_nav_grid.gd`: level adapter for the cats.
- `Scripts/environments/apartment/apt_cat_director.gd`: home cat routines.
- `Scripts/environments/apartment/apt_hud.gd`: HUD, prompt card, toast, fade, procedural icons.
- `Scripts/environments/common/apt_iso_camera_rig.gd`: reusable iso camera with the same controls as MainLevel3D.
- `Scripts/environments/common/apt_hotspot.gd`: reusable hotspot (Area3D on physics layer 20, rim overlay shader, floor ring).
- `Tools/probe_apartment.gd`: headless probe.
- `Tools/probe_apartment_shots.gd`: windowed screenshot tour.

## Checks
```bash
G=".../Godot_v4.6-stable_win64_console.exe"
"$G" --headless --path . --quit-after 600 res://Scenes/Environments/Apartment/Apartment.tscn   # 0 errors/warnings
"$G" --headless --path . --script res://Tools/probe_apartment.gd                                # PROBE APARTMENT: PASS
"$G" --path . --script res://Tools/probe_apartment_shots.gd -- <out_dir> [seed]                 # 6 PNGs
```
The probe hovers and clicks every hotspot with pushed mouse events, then clicks the primary card button and asserts the signal. It also covers both door options and the HUD button. It watches the cats for about 40 s: they must move, reach the bowls and the nest, and never stand on a blocked or off-floor cell. Headless windows are 64×64, so the probe pushes input in viewport coordinates (`push_input(ev, true)`).

## Integration notes and save data still needed
- **Scene transitions:** the cafe has no way back to the apartment yet. Add an "End day / Go home" path in MainLevel3D or HUD3D that calls `change_scene_to_file("res://Scenes/Environments/Apartment/Apartment.tscn")`. Town ↔ apartment should use the same pattern.
- **Shared run state:** today `day` is a local export and the cats are freshly generated on each visit. A run-state autoload (or SaveSystem) should provide:
  - the day / phase, and day end on `sleep_requested`;
  - the list of fosters at home vs at the cafe. Use `export_cat_def()` / `configure(..., cat_def)` to move cats between scenes with their trust and genome intact;
  - per cat: fed today, bonded today, last bond time;
  - home inventory (food), planner choices for tomorrow, and cosmetics.
- **Bonding balance:** `BOND_TRUST_BONUS`, `BOND_SEC`, `EAT_SEC` and `NAP_SEC` live at the top of `apt_cat_director.gd`. Move them into `Data/balance_config.json` when the feature is real.
- **Caveat:** the director reads and writes a few cat fields and calls the cat's internal `_set_state` / `_stop_moving` by name, because MainLevelCat3D has no public "go here" or "nap now" API. If MainLevelCat3D changes those names, update `apt_cat_director.gd`, or add a public API to the cat.
