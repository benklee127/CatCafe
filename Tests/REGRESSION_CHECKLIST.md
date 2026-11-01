# Regression Checklist

Run before merging to `main` or cutting any build. Every line must pass.

## Automated (headless)
- [ ] `Tools/validate_data.gd` exits 0.
- [ ] `Tools/probe_core_loop.gd` (`--fixed-fps 10`) exits 0 and prints `[probe] PASS`. It checks:
  - forced REST at (2,2) returns to the floor in 15 s or less;
  - 0 retreating→interacting and 0 rest→interacting transitions;
  - `unwalkable_slots=[]` for every decor and rotation;
  - 0 Cat2D `det == 0` errors.
- [ ] A headless boot (`--quit-after 300`) prints 0 `ERROR:` lines for each of:
  - `MainLevel3D.tscn`
  - `CatPreview.tscn`
  - `Scenes/Main.tscn`
  - `Scenes/MainLevel.tscn`
  - `Scenes/Prototype/IsometricPrototype.tscn`

## Manual (MainLevel3D, F5)
- [ ] Placement respects the floor bounds, occupancy, actors (`occupied_by_actor`) and funds (`insufficient_funds`). The ghost is green when placeable and red when blocked.
- [ ] Clicking or scrolling over UI never places, rotates or zooms the world.
- [ ] The cat retreat → rest → returning → floor cycle never deadlocks. A cat leaves the rest area through the door.
- [ ] Cats and patrons stand on the floor (no floating) at the expected sizes: a patron is about 120 px and a cat about 55 px at default zoom.
- [ ] Patrons arrive at the entrance, visit, leave and tip, and money goes up.
- [ ] The HUD shows money, reputation, cats on floor X/Y, the day and the clock. The drought toast appears when every cat is resting.
- [ ] Save and load work on the current version and migrate the previous one. Quit and reload keep the day, money, decor and cats. A future-version save is refused and left untouched.
- [ ] No fatal script errors after a 30-minute session.
- [ ] Adoption and reputation values stay non-negative.
