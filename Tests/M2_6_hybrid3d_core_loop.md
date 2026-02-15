# M2.6 Hybrid 3D Core Loop Manual Test

## Goal
Validate the hybrid 3D runtime path:
- 3D environment/decor placement
- 2D billboard actors in 3D world
- grid occupancy/pathing parity
- slot claim/release behavior parity

## Setup
1. Run `Scenes/Prototype3D/MainLevel3D.tscn`.
2. Confirm camera is fixed isometric view.
3. Controls:
- Left mouse (`place_decor`) places selected decor.
- Right mouse (`remove_decor`) removes decor under hovered grid.
- `R` rotates placement preview (90-degree step).

## Cases

### 1. Scene boot and render layers
1. Start scene.
2. Verify floor blocks and rest-area partition are visible.
3. Verify cat and patron billboards are visible.
Expected:
- Scene boots with no missing resource errors.
- Actors render above floor/decor and face camera.

### 2. Placement validation + rotation
1. Move cursor around floor.
2. Place decor on valid cells, rotate with `R`, place again.
3. Try placing on blocked/invalid cells.
Expected:
- Valid placement succeeds.
- Invalid placement is rejected.
- Rotated decor footprints apply correctly for occupancy.

### 3. Removal and occupancy release
1. Place multiple decor items.
2. Remove one by right-clicking occupied cell.
Expected:
- Decor node is removed.
- Occupancy and slot claims for that decor are released.

### 4. Pathing reroute
1. Place decor barriers to disrupt direct movement.
2. Observe cat/patron movement.
Expected:
- Actors reroute around blocked cells when paths exist.
- Actors do not pass through blocked decor footprint cells.

### 5. Retreat/rest behavior parity
1. Let cat interact until overstimulation threshold is reached.
2. Observe retreat flow.
Expected:
- Cat transitions to retreating.
- Cat reaches rest area path target and enters rest state.
- Overstimulation decreases during rest.

### 6. Slot exclusivity + invalidation
1. Place decor that provides slots.
2. Observe patron/cat claiming.
3. Remove claimed decor.
Expected:
- One actor max per slot.
- Removing decor invalidates claims without actor freeze.

## Pass Criteria
- All six cases pass in one play session.
- No known P1: missing meshes, actor clipping through blocked cells, slot deadlocks, or scene boot errors.
