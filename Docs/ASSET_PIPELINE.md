# Asset Pipeline

Purpose: define the repeatable workflow from concept to integrated game-ready asset.

## Directory Layout
- `Art_Assets/<category>/raw/`: editable source files.
- `Art_Assets/<category>/export/`: game-ready files committed to repo.
- `Audio/raw/`: editable audio project files.
- `Audio/export/`: game-ready `.wav`/`.ogg` files.

Suggested categories under `Art_Assets/`:
- `cats`
- `patrons`
- `decor`
- `tiles`
- `ui`
- `vfx`
- `minigames`
- `vip`
- `marketing`

## Workflow
1. Create/confirm task and `asset_id` in `Docs/ASSET_MANIFEST.md`.
2. Produce source asset in `raw/` folder.
3. Export game-ready files to matching `export/` folder.
4. Import into Godot and apply import defaults from `Docs/ART_STYLE_GUIDE.md`.
5. Integrate into scene/UI/data references.
6. Validate in runtime (`Scenes/Main.tscn`) for readability and behavior.
7. Update manifest status (`todo` -> `in_progress` -> `review` -> `done`).

## Naming Convention
Use stable, sortable names:
- Art: `<category>_<set>_<name>_v###.png`
- Audio: `<type>_<theme>_<name>_v###.wav` or `.ogg`

Examples:
- `cat_layer_body_tabby_v001.png`
- `decor_chair_velvet_red_v003.png`
- `sfx_ui_click_soft_v002.wav`

## Versioning Rules
- Increment version suffix for export changes (`v001`, `v002`, ...).
- Keep prior versions only if needed for rollback/review; otherwise replace and note in commit.
- Do not commit throwaway files or editor autosaves.

## Integration Rules
- Data-driven systems must reference stable asset ids/paths.
- Any renamed/moved asset requires updating all references in scenes/scripts/data.
- No direct use of raw files in runtime; runtime uses export assets only.

## Quality Gates
Before marking `done`:
- Manifest entry complete (owner, paths, status, notes).
- Asset passes style guide review.
- Asset passes in-engine check at target zoom.
- No broken references after integration.

## PR Checklist (Asset Changes)
- Updated `Docs/ASSET_MANIFEST.md`.
- Added/updated exported asset files.
- Updated scene/data references.
- Included before/after screenshot or short clip when useful.
