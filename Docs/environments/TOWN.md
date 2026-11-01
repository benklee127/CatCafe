# Town environment

`res://Scenes/Environments/Town/Town.tscn` is a compact autumn town block seen through the cafe's camera: orthographic, yaw 45, pitch 40, zoomed out further (default size 17, overview about 30). Everything is built in code from primitives, with procedural ImageTextures for bricks, siding, pavers, cobbles, asphalt, grass, shingles and planks. The scene uses no image or model files.

Run it:

```
Godot_v4.6-stable_win64.exe --path C:\workspace\CatCafe res://Scenes/Environments/Town/Town.tscn
```

## Controls
| Input | Action |
|---|---|
| WASD / arrows, middle-drag | Pan (clamped to the town; the pan range grows as you zoom in) |
| Mouse wheel | Zoom (8 up to the full-town fit) |
| Home | Switch between the overview and the default zoom |
| Hover | Highlights a hotspot: brighter ring, name tag, warm overlay on the building, hand cursor |
| Left click | Opens the hotspot's prompt card (Go / Not now). A click on empty ground closes it |
| T | Changes the time of day: afternoon → evening → night |
| Esc | Closes the card |

## Layout
The block is laid out in `Scripts/environments/town/TownLayout.gd`. All coordinates are world metres, with `Rect2 = (x, z, w, d)`.
- **North row** (facades face +Z): corner townhouse (backdrop), **Cat Cafe**, **Paws & Hearts Shelter**, **Back Alley** (dead end with a brick wall, a fence, a dumpster, bins, boxes, a pallet, food bowls and string lights), and a garden lot with pumpkins.
- **West column** (facades face +X): **Maple Court** apartments (the player's home) and **Kibble & Co.** pet supplies.
- **Front:** Maple Park (path, bench nook, big maple, pond with ducks) and a cobbled plaza with the **Corner Market** stall, bistro tables, a bus stop and a bike rack.
- **Streets:** a T-junction with two zebra crossings, lane dashes, curbed sidewalks, lampposts with real lights, planters, a hydrant, street-name signs and about 450 fallen leaves (one MultiMesh).

## Hotspots and signals
All signals are declared on the root `Town` node (`Scripts/environments/town/Town.gd`).

How a hotspot runs:
1. A click calls `activate_hotspot(id)`, which only opens the card.
2. The card's Go button calls `confirm_hotspot(id)`.
3. `confirm_hotspot` always emits `hotspot_activated(id, info)`, then the hotspot's own signal from the table below.

Each action is a **stub** for now: a toast plus the signal.

| id | Card verb | Specific signal | Current stub behaviour | Intended gameplay |
|---|---|---|---|---|
| `cafe` | Enter cafe | `enter_cafe_requested()` | `travel_requested(path)`, then changes scene to `MainLevel3D.tscn` | Start or continue the cafe day |
| `shelter` | Visit shelter | `visit_shelter_requested(source)` | Toast. `source` = `shelter` row of `Data/rescue_sources.json` | Shelter intake UI: pay `cost_money`, pick a calm cat (trust 30–45) |
| `alley` | Search alley | `alley_searched(found_stray, rarity, source)` | Rolls `alley_find_chance` (export, default 0.35). On a find, rolls the rarity from `rarity_weights`. Strays react; toast | Costs `time_cost_hours`. Finding a stray starts intake with trust 5–20 |
| `home` | Go home | `go_home_requested(scene_available)` | If `Apartment.tscn` exists: changes scene. Otherwise shows a "coming soon" toast | Apartment / sleep / end of day |
| `shop` | Browse shop | `shop_browse_requested()` | Toast | Decor and treats shop |
| `park` | Sit a while | `park_sit_requested()` | Toast | Meet patrons, VIP alumni visits with adopted cats |
| `market` | Browse stall | `market_visit_requested()` | Toast | Buy recipe ingredients for the cooking minigame |
| `doorstep_cafe` (hidden) | Peek inside | `doorstep_event_found(spot_id, source)` | A tuxedo stray peeks out of a box by the cafe door; startles on confirm | `doorstep_event` intake (trust 0–10). Could be gated by `event_chance_per_day` |
| `doorstep_home` (hidden) | Take a look | `doorstep_event_found(spot_id, source)` | Wobbling basket by the apartment stoop | Same as `doorstep_cafe` |

Other signals:
- `hotspot_hovered(id)`
- `travel_requested(scene_path)`, emitted before every scene change

Hidden spots show no ring or marker until hovered.

Exports on `Town`:
- `time_of_day` (0 = day, 0.55 = evening by default, 1 = night). It blends the sun, the ambient light, window glow and lamp energy.
- `auto_travel`: turn it off to keep the scene when Go is pressed. The probe uses this.
- `alley_find_chance`
- `walker_count` (5)
- `stray_count` (2)
- `rng_seed`

Public helpers:
- `pick_hotspot_at(screen_pos)`
- `get_hotspot_ids()`
- `get_hotspot(id)`
- `cycle_time_of_day()`
- `get_rescue_source(id)`

To add a hotspot, add a row to `hotspot_defs()` and a branch in `confirm_hotspot()`.

## Life
- **Townsfolk:** `Human3D.tscn` instances that are never `configure()`d, so the patron AI stays idle. `TownWalker.gd`, a child node, walks them back and forth along the sidewalk routes in `TownLayout.walker_routes()`, with pauses. It drives the existing art hooks (`_is_moving`, `_walk_phase`, `_update_visuals`, `sprite.flip_h`). Looks come from `Data/patron_archetypes.json`.
- **Strays:** `Cat3D.tscn` instances, also not configured. `TownStray.gd` uses only the Cat2D API (`apply_genome` with `CatGenome.from_visual`, `set_pose`, `set_facing_left`, `set_move_speed`, `set_expression`), with existing poses and expressions only.
  - ROAM mode: wanders inside `STRAY_AREA` and walks, sits or naps.
  - PEEK mode: hides in the doorstep box and peeks out.

## Files
- `Scenes/Environments/Town/Town.tscn`: root, world, camera rig, environment and sun
- `Scripts/environments/town/`:
  - `Town.gd`: controller, signals, hotspots, actors, time of day
  - `TownLayout.gd`: layout constants, walkable rects, routes
  - `TownBuilder.gd`: ground, streets, alley, park, plaza, furniture, leaves
  - `TownFacades.gd`: buildings and facade parts
  - `TownHotspot.gd`: Area3D hotspot with ring, marker and overlay
  - `TownCamera.gd`: iso camera rig
  - `TownHUD.gd`: chip, hint, card, toast
  - `TownWalker.gd`
  - `TownStray.gd`
- `Scripts/environments/common/town_proc_kit.gd`: material, mesh, label and texture helpers
- `Tools/probe_town.gd`: headless probe

## Checks
```
Godot_console.exe --headless --path . --quit-after 600 res://Scenes/Environments/Town/Town.tscn
Godot_console.exe --headless --path . --fixed-fps 30 --script res://Tools/probe_town.gd
```

The probe checks four things:
- Every hotspot opens its card, and Go emits `hotspot_activated` plus its own signal. It also checks the alley rolls (chance 1 and chance 0), the home availability flag and toast, and the cafe travel path.
- A camera ray through each hotspot picks that hotspot.
- Townsfolk stay on walkable rects and actually walk, over 1800 frames.
- Strays stay inside `STRAY_AREA` and move.

Exit code 0 means every check passed.

## Integration notes
- **Getting into the town:** nothing links to it yet. A future "Go to town" button in the cafe HUD would call `change_scene_to_file("res://Scenes/Environments/Town/Town.tscn")`.
- **Rescue flows:** connect `alley_searched`, `visit_shelter_requested` and `doorstep_event_found` to a rescue intake that uses `CatFactory` with the given `source` row.
- **Hotspot gating:** for unlocks or opening hours, hide a hotspot or change its card `tags` and `verb` before `activate_hotspot`.
