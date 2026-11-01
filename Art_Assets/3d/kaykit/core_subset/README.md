# KayKit Core Subset (vendored placeholders)

This folder holds a small vendored subset of **KayKit Prototype Bits** by Kay Lousberg. The hybrid 3D runtime uses these meshes as placeholder decor.

## License and credit
- **License:** CC0 1.0 Universal (public domain). Attribution is not required, but we give it anyway.
- **Credit:** "Prototype Bits" by Kay Lousberg, https://kaylousberg.com / https://kaylousberg.itch.io
- **Shared texture:** `prototypebits_texture.png`. Every `.gltf` here references it.
- Keep this credit when the files are copied or moved. If the upstream `License.txt` is downloaded again, add it to this folder.

## Files and decor mapping
The authoritative mapping is `Data/decor_mesh_map.json` (owned by the level track). It holds each item's `mesh_scene`, `scale`, footprint and slot markers. The table below is a snapshot; when they differ, the JSON wins.

| File | Used by decor_id (scale) |
|---|---|
| `table_medium_Decorated.gltf` | velvet_armchair (0.9) |
| `table_medium_long.gltf` | espresso_bar (0.9) |
| `table_medium.gltf` | tea_station (0.9) |
| `Pallet_Small.gltf` | wall_shelf (0.7, 1.6, 0.7), heating_pad (0.33, 0.2, 0.33) |
| `Pallet_Large.gltf` | book_nook (0.34, 0.6, 0.34), adoption_corner (0.34, 0.8, 0.34) |
| `Primitive_Window.gltf` | window_perch (0.85, 0.5, 0.6), quiet_signage (0.5, 0.3, 0.6) |
| `Primitive_Wall_Half.gltf` | plant_partition (1.0, 0.3, 0.6), cat_tunnel (0.7, 0.12, 0.6) |
| `Primitive_Wall.gltf` | scratch_post (0.17, 0.3, 0.6) |

## Notes
- These are stand-ins. Several decor ids share a mesh and tell themselves apart by `scale` and the tint or material override set by the level track (see `Docs/ASSET_MANIFEST.md`).
- Every mesh is scaled to the 0.7 m grid cell. Never place a mesh at 1:1 KayKit scale.
- Commit each `.gltf.import` and `.png.import` with its asset. The import settings are versioned.
