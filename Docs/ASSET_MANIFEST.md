# Asset Manifest

Purpose: single source of truth for all production assets, ownership, and delivery status.

## Status Legend
- `todo`: not started
- `in_progress`: actively being produced
- `review`: ready for review/integration
- `done`: approved and integrated

## Columns
- `asset_id`: stable identifier used in tickets and commits
- `owner`: person responsible
- `milestone`: target milestone (`M3`, `M4`, `M6`)
- `source_path`: raw/source file path
- `export_path`: game-ready exported file path
- `engine_path`: final Godot path (`res://...`)

## M3 Vertical Slice Assets
| asset_id | category | description | owner | milestone | status | source_path | export_path | engine_path | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| art_tile_floor_base_01 | tile | Base cafe floor tile set | TBD | M3 | todo | Art_Assets/tiles/raw/ | Art_Assets/tiles/export/ | res://Art_Assets/tiles/ | Replace prototype floor |
| art_tile_rest_area_01 | tile | Rest area tile variant | TBD | M3 | todo | Art_Assets/tiles/raw/ | Art_Assets/tiles/export/ | res://Art_Assets/tiles/ | Include collision mask |
| art_cat_layer_body_01 | cat | Cat body base layer pack | TBD | M3 | todo | Art_Assets/cats/raw/ | Art_Assets/cats/export/ | res://Art_Assets/cats/ | Layered proc-gen compatible |
| art_cat_layer_pattern_01 | cat | Cat coat pattern layer pack | TBD | M3 | todo | Art_Assets/cats/raw/ | Art_Assets/cats/export/ | res://Art_Assets/cats/ | Tie to trait visuals |
| art_cat_rare_sphynx_01 | cat_rare | Rare sphynx set | TBD | M3 | todo | Art_Assets/cats/raw/ | Art_Assets/cats/export/ | res://Art_Assets/cats/rare/ | Rare roll visual |
| art_cat_rare_mainecoon_01 | cat_rare | Rare maine coon set | TBD | M3 | todo | Art_Assets/cats/raw/ | Art_Assets/cats/export/ | res://Art_Assets/cats/rare/ | Rare roll visual |
| art_patron_arch_01 | patron | Patron archetype set 1 | TBD | M3 | todo | Art_Assets/patrons/raw/ | Art_Assets/patrons/export/ | res://Art_Assets/patrons/ | Idle + walk |
| art_patron_arch_02 | patron | Patron archetype set 2 | TBD | M3 | todo | Art_Assets/patrons/raw/ | Art_Assets/patrons/export/ | res://Art_Assets/patrons/ | Idle + walk |
| art_patron_arch_03 | patron | Patron archetype set 3 | TBD | M3 | todo | Art_Assets/patrons/raw/ | Art_Assets/patrons/export/ | res://Art_Assets/patrons/ | Idle + walk |
| art_decor_mvp_12 | decor | MVP decor sprite pack (12 items) | TBD | M3 | todo | Art_Assets/decor/raw/ | Art_Assets/decor/export/ | res://Art_Assets/decor/ | Sync ids with data |
| art_ui_cat_card_01 | ui | Cat popup card frame | TBD | M3 | todo | Art_Assets/ui/raw/ | Art_Assets/ui/export/ | res://UI/ | Trust + overstim readable |
| art_vfx_stress_pulse_01 | vfx | Stress pulse effect | TBD | M3 | todo | Art_Assets/vfx/raw/ | Art_Assets/vfx/export/ | res://Art_Assets/vfx/ | Overstim feedback |

## M4 Content Expansion Assets
| asset_id | category | description | owner | milestone | status | source_path | export_path | engine_path | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| art_decor_pack_02 | decor | Additional decor set toward 50 total | TBD | M4 | todo | Art_Assets/decor/raw/ | Art_Assets/decor/export/ | res://Art_Assets/decor/ | Add 38 net new |
| art_cat_layer_variants_02 | cat | Extra coat/eyes/tail/fur variants | TBD | M4 | todo | Art_Assets/cats/raw/ | Art_Assets/cats/export/ | res://Art_Assets/cats/ | Increase diversity |
| art_minigame_brush_01 | minigame | Brushing mini-game art pack | TBD | M4 | todo | Art_Assets/minigames/raw/ | Art_Assets/minigames/export/ | res://Art_Assets/minigames/ | UI + props |
| art_minigame_laser_01 | minigame | Laser mini-game art pack | TBD | M4 | todo | Art_Assets/minigames/raw/ | Art_Assets/minigames/export/ | res://Art_Assets/minigames/ | UI + effects |
| art_vip_alumni_01 | vip | VIP alumni owner/cat visuals | TBD | M4 | todo | Art_Assets/vip/raw/ | Art_Assets/vip/export/ | res://Art_Assets/vip/ | Happy aura compatible |

## Hybrid 3D Core Set (M2.6)
| asset_id | category | description | owner | milestone | status | source_path | export_path | engine_path | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| art3d_floor_grid_01 | env3d | 3D floor + rest area block layout | TBD | M2.6 | done | Art_Assets/3d/kaykit/core_subset/ | Scenes/Prototype3D/ | res://Scenes/Prototype3D/MainLevel3D.tscn | Built via FloorBuilder3D |
| art3d_decor_velvet_armchair_01 | decor3d | Velvet armchair 3D wrapper scene | TBD | M2.6 | done | Art_Assets/3d/kaykit/core_subset/ | Scenes/Prototype3D/Decor/ | res://Scenes/Prototype3D/Decor/VelvetArmchair3D.tscn | Replace mesh with KayKit source when imported |
| art3d_decor_espresso_bar_01 | decor3d | Espresso bar 3D wrapper scene | TBD | M2.6 | done | Art_Assets/3d/kaykit/core_subset/ | Scenes/Prototype3D/Decor/ | res://Scenes/Prototype3D/Decor/EspressoBar3D.tscn | 2-cell footprint mapping in data |
| art3d_decor_wall_shelf_01 | decor3d | Wall shelf 3D wrapper scene | TBD | M2.6 | done | Art_Assets/3d/kaykit/core_subset/ | Scenes/Prototype3D/Decor/ | res://Scenes/Prototype3D/Decor/WallShelf3D.tscn | Slot markers mapped in data |
| art3d_decor_window_perch_01 | decor3d | Window perch 3D wrapper scene | TBD | M2.6 | done | Art_Assets/3d/kaykit/core_subset/ | Scenes/Prototype3D/Decor/ | res://Scenes/Prototype3D/Decor/WindowPerch3D.tscn | Slot markers mapped in data |

## Audio Assets
| asset_id | category | description | owner | milestone | status | source_path | export_path | engine_path | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| aud_bgm_cafe_loop_01 | bgm | Core cafe loop track | TBD | M3 | todo | Audio/raw/bgm/ | Audio/export/bgm/ | res://Audio/ | Cozy baseline |
| aud_sfx_core_pack_01 | sfx | Meow/purr/ui/place/adopt core pack | TBD | M3 | todo | Audio/raw/sfx/ | Audio/export/sfx/ | res://Audio/ | Normalize loudness |
| aud_ambience_cafe_01 | ambience | Cafe room tone + soft machine cues | TBD | M3 | todo | Audio/raw/ambience/ | Audio/export/ambience/ | res://Audio/ | Loop-safe |

## Marketing Assets (M6)
| asset_id | category | description | owner | milestone | status | source_path | export_path | engine_path | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mkt_screenshot_set_01 | marketing | 12+ gameplay screenshots | TBD | M6 | todo | Art_Assets/marketing/raw/ | Art_Assets/marketing/export/ | n/a | Steam + socials |
| mkt_trailer_cut_01 | marketing | 30-60s trailer cut | TBD | M6 | todo | Art_Assets/marketing/raw/ | Art_Assets/marketing/export/ | n/a | Gameplay only |
| mkt_short_clip_batch_01 | marketing | 8 short-form clips | TBD | M6 | todo | Art_Assets/marketing/raw/ | Art_Assets/marketing/export/ | n/a | TikTok/Reddit/Shorts |
