# TECH SPEC

## Stack
- Engine: Godot 4.3+
- Language: GDScript
- Target: Windows (Steam)

## Architecture
- `Scenes/Main.tscn` boots prototype loop.
- `Scripts/prototype/*` handles simulation mechanics.
- `Scripts/data/*` handles loading, generation, save migration.
- `Data/*.json` is source of truth for tunables and definitions.

## Core systems in this baseline
- Isometric click placement (left place, right remove)
- Cat wander -> overstim -> retreat -> rest -> return
- Patron movement and stimulation pressure
- Procedural cats from trait + visual pools
- One-slot JSON save with migration from v0 to v1

## Validation
- Runtime data validation in `DataLoader`.
- CLI-style validator entry script: `Tools/validate_data.gd`.

## Next implementation targets
- Navigation/pathfinding via tile nav mesh
- Production UI flow and menus
- Adoption/reputation loop wiring
- Audio events and telemetry logging
