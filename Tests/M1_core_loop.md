# M1 Manual Test: Core Loop (hybrid 3D)

Scene: run the project (F5). The main scene is `Scenes/Prototype3D/MainLevel3D.tscn`.
Automated equivalent for the AI section: `Tools/probe_core_loop.gd --fixed-fps 10`.

## Placement
1. Click **Build** (bottom-left) and pick an item. A ghost and footprint tiles follow the cursor.
2. Hover a free floor area. The tiles are green. Left click: the decor appears snapped to the grid and money drops by its cost.
3. Hover the same spot again. The tiles are red and the reason label says it is occupied. Clicking does nothing.
4. Press **R**, **Q/E** or scroll while holding: the ghost rotates in 90° steps, and the footprint rotates the same way as the model.
5. Press **Esc** or right click: the held item is cancelled.
6. Hover outside the floor or over a cat or patron: the tiles are red (`out_of_bounds` / `occupied_by_actor`).
7. With nothing held, click placed decor: the inspector opens on the right.

## AI / Overstim
1. Cats wander the cafe floor.
2. Patrons enter at the entrance, move to slots and get near cats.
3. A cat's overstim pip bar fills while it is interacting.
4. At 100 the cat retreats (`!` glyph) toward the rest-area door. Nearby patrons do not pull it back into interacting.
5. The cat reaches the rest rug and rests (`Zz`), and its overstim drains.
6. The cat walks back out through the door and resumes wandering.

## Pass criteria
- No cat is stuck in any state for 3 minutes.
- No script errors in the output.
