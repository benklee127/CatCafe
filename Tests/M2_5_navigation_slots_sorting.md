# M2.5 Navigation + Slots + Sorting Manual Test (hybrid 3D)

## Goal
Validate the technical-completion systems in the 3D main scene:
- Decor-driven blocked navigation cells.
- Slot claiming/releasing for patrons and cats.
- Stable depth sorting of billboard actors.
- Cat FSM transitions under stress, including the rest-area door.

## Setup
1. Run the project (F5). The main scene is `Scenes/Prototype3D/MainLevel3D.tscn`.
2. Open **Build**. The grid lines are visible only in build mode.
3. Controls:
   - Left click to place the held item.
   - **R**, **Q/E** or the wheel (while holding) to rotate.
   - **Esc** or right click to cancel.
   - With nothing held, the wheel zooms and **WASD** or a middle-drag pans.
4. Automated slot check: `Tools/probe_core_loop.gd --fixed-fps 10`. It places every decor at (14,12) at all 4 rotations and expects `unwalkable_slots=[]`.
5. The legacy 2D version of this test can still run in `Scenes/MainLevel.tscn` (reference only).

## Cases

### 1. Blocked path reroute
1. Place a line of decor between a cat and the open floor.
2. Watch the cat move.

Expected:
- The cat never walks through blocked decor cells.
- The cat reroutes around obstacles when another route exists.

### 2. Rest-area retreat and return
1. Wait for a cat's overstim to hit the threshold. Placing a chair next to busy patrons speeds this up.
2. Watch the transitions.

Expected:
- The cat enters `retreating` and enters the rest area only through the door gap in the partition.
- The cat enters `rest` and its overstim decreases.
- At or below `rest_release_threshold` it enters `returning`, walks out through the door, then goes back to `idle` or `wander`.

### 3. Slot claim exclusivity
1. Place several decor items to create multiple slots.
2. Watch patrons and cats settle at the decor.

Expected:
- Each slot is claimed by at most one actor.
- Removing decor invalidates its claims, and the actors recover without freezing.
- Fearful cats do not seek slots.

### 4. Cat interaction behavior
1. Let patrons approach cats.
2. Watch the cat's state and movement.

Expected:
- The cat goes from `idle`/`wander` to `interacting` when patrons are near, but never while it is in `retreating`, `rest` or `returning`.
- Overstim rises during interaction, not during calm wandering.
- An interacting cat claims a cat slot when one is free.

### 5. Depth sorting
1. Watch cats and patrons cross in front of and behind each other and decor.

Expected:
- Nearer actors render in front. Billboards are depth-tested, never `no_depth_test`.
- No persistent flicker on crossing paths. Feet stay on the floor (y = 0).

### 6. Decor on actors
1. Hold an item over a cell where a cat or patron stands.

Expected:
- The placement is blocked (`occupied_by_actor`). No actor ever ends up inside furniture.

## Pass Criteria
- Every expected behavior is seen in one play session of 3+ minutes.
- No actor gets permanently stuck after rounds of adding and removing decor.
- No slot stays ghost-claimed after its decor is removed.
