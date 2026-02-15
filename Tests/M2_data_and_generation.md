# M2 Manual Test: Data + Generation

## Data load
1. Launch scene; verify no missing-file errors.
2. Break one required key in JSON and relaunch; verify validator error.

## Procedural generation
1. Run with deterministic seed enabled twice.
2. Verify same cat trait compositions spawn each run.
3. Disable deterministic seed and verify variation.

## Trait/archetype math
1. Compare overstim speed for timid vs stoic cats.
2. Compare overstim pressure from gentle_reader vs hyper_toddler.

## Save/load
1. Launch once and exit to create save.
2. Relaunch and verify save loads without parse errors.
3. Set `save_version=0` in save and relaunch; verify migration to v1.

## Pass criteria
- All outcomes driven by JSON data edits.
