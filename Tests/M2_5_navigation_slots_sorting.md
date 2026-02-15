# M2.5 Navigation + Slots + Sorting Manual Test

## Goal
Validate isometric technical-completion systems:
- Decor-driven blocked navigation cells.
- Slot claiming/releasing for patrons/cats.
- Stable depth sorting while actors move.
- Cat FSM transitions under stress.

## Setup
1. Run `Scenes/MainLevel.tscn`.
2. Ensure `draw_debug_grid` is enabled in `MainLevel`.
3. Controls:
- Left mouse (`place_decor`) places a decor obstacle at hovered cell.
- Right mouse (`remove_decor`) removes decor at hovered cell.

## Cases

### 1. Blocked path reroute
1. Place a line of decor cells between a cat and its likely wander target.
2. Observe cat movement.
Expected:
- Cat does not move through blocked decor cells.
- Cat path reroutes around obstacles when alternate routes exist.

### 2. Rest-area retreat pathing
1. Wait for cat overstimulation to hit threshold.
2. Observe transition into retreat.
Expected:
- Cat enters `retreating` state.
- Cat reaches a rest-area tile without clipping through decor.
- Cat enters `rest` and overstimulation decreases.

### 3. Slot claim exclusivity
1. Place several decor objects to create multiple slots.
2. Observe patrons settling near decor.
Expected:
- Each slot is claimed by at most one actor.
- Claimed slots show occupied debug marker state.
- Removing decor invalidates claims and actors recover without freeze.

### 4. Cat interaction behavior
1. Let patrons approach cats.
2. Observe cat state and movement.
Expected:
- Cat transitions `idle/wander -> interacting` when patrons are near.
- Overstimulation rises during interaction, not during calm idle wander.
- Cat can claim cat slots while interacting when available.

### 5. Y-sort / depth correctness
1. Watch cats/patrons cross above and below each other and decor.
Expected:
- Actors higher on screen render behind actors lower on screen.
- No persistent z-fighting flicker on crossing paths.

## Pass Criteria
- All expected behaviors observed in one full play session (3+ minutes).
- No actor becomes permanently stuck after decor add/remove churn.
- No slot remains ghost-claimed after decor removal.
