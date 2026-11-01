# Art Style Guide

Purpose: lock visual direction so production assets are consistent and readable in gameplay.

## Visual Direction
- Cozy, warm, calm atmosphere.
- Readable simulation first; decorative detail second.
- Silhouettes must remain clear at gameplay zoom.

## Perspective and Composition
- Hybrid 3D: an orthographic 3D diorama room (yaw 45°, pitch 40°) with 2D billboard actors. Cats are a procedural 2D rig rendered through a SubViewport; patrons are sprites.
- Draw actor sprites side-on or 3/4, with the feet at the bottom-centre of the canvas. The billboard pivots at the feet.
- Decor footprint must clearly communicate occupied grid space.
- Cat and patron readability takes priority over background detail.

## Color and Contrast
- Base environment palette: warm neutrals and soft woods.
- Accent colors: muted greens/teals for calm systems, warm oranges for active alerts.
- Stress states: use higher contrast accents reserved for overstimulation warnings.
- Avoid neon saturation except for explicit alert VFX.

## Shape Language
- Cats: rounded, soft forms.
- Patrons/furniture: slightly more angular for quick distinction.
- Keep line thickness consistent per asset family.

## Cat Art Rules (Proc-Gen Compatibility)
- Cat visuals must be split into compatible layers: body, coat pattern, fur variant, eyes, tail.
- Each layer pack should share common anchor points and canvas alignment.
- Rare variants (`sphynx`, `maine_coon`) must preserve animation compatibility.

### Cat rig look (procedural Cat2D, v2 "chibi")
Art target: chibi pixel-art cats, side 3/4 view facing right, both eyes visible.
- One silhouette, one outline: torso loaf + rear haunch + chest bridge + the two near legs are merged (`Geometry2D.merge_polygons`) and get a single warm dark-brown outline (never pure black). No outline rings where legs, chest or haunch meet the body; internal separation is darker fill only (belly overhang on the leg tops, back edge of each leg, a soft crease on the haunch front).
- Head ≈ 1.3× torso depth wide, rounded square with full cheeks, set forward and down so it overlaps the chest top; its bottom sits about mid torso. The head outline stays visible behind the cheek, but a chest-coloured neck patch hides it under the chin so muzzle and bib read as one white area. Ears are wide set on the top corners, tilted slightly out, pink inner.
- Legs: short chunky columns (visible ≈ 7.6 units on a ~42-unit cat) whose wide root sits inside the torso; flat-bottomed oval paws a little wider than the ankle, two light toe lines. Far legs sit behind, 18% darker.
- Tail: thick, rises from the rump in a question-mark hook; banded for tabbies, white tip for tuxedo, darkening for points. Sleep wraps it forward in front of the loaf; it never dips below the floor.
- Face: big eyes with a large white highlight, small pink nose, "w" mouth, near-side whiskers reach past the head outline.
- Shading: faint light on the back, slightly darker underside, soft ground shadow. The pixel renderer keeps these as opaque tone-ramp fills, never lines or alpha (see Pixel renderer below).
- Draw order: shadow, far legs, tail, body union (+ patterns clipped to it, internal shading), ear outlines, head outline, neck patch, ear fills, head fill + face, eyes.
- Tuning knobs live at the top of `Scripts/prototype3d/Cat2D.gd` (`BODY_RX/RY`, `RUMP_LIFT`, `LEG_BASE_LEN`, `LEG_ROOT_W`, `LEG_ANKLE_W`, `HEAD_RX/RY`, `HEAD_EXP`, `HEAD_FORWARD`, `HEAD_UP`, `EAR_W/H`, `FAR_LEG_OFFSET`, `SIT_ROT`, `WALK_STRIDE/LIFT`) plus exports `outline_width`, `far_leg_darken`, `limb_shade_alpha`.
- Performance: body/leg geometry is cached per (quantized pose weights, walk phase 0..7, genome); steady animation runs no polygon booleans. The tail redraws at most 20 Hz.
- Proportion knobs (genome, `CatGenome.SCALAR_RANGES` clamps, 1.0 = reference look): `body_length`, `body_girth`, `leg_length`, `leg_thickness`, `haunch_size`, `head_size`, `cheek_width`, `ear_size`, `neck_fluff` (chest ruff, 0..2), `tail_length`, `tail_thickness`. Legacy `body_scale` still works and multiplies `body_length`/`body_girth`.
- Fur edge: `fur_style` `flat` (clean edge) / `medium` (soft rounded clumps) / `fuzzy` (pointier, more jitter, a little fur on the back), plus `fur_length` (tuft amplitude, units), `fur_density` (tufts per unit), `fur_jitter` (0..1). Missing `fur_style` maps from the legacy `fur` key (none/short → flat, medium → medium, long → fuzzy). Tufts lean backward/down along the fur flow; strength is masked per region: strong on cheeks, chest ruff, belly underside, haunch and tail; weak on the back top; none on the paws. Fill and outline use the same displaced polygon, so there is still one outline. The body core is furred once per genome in rest space; the tail gets leaf-shaped tufts in its band colours.
- Random cats (`CatGenome.from_visual`): domestic cats are mostly flat or medium with the occasional fuzzy (weights from the pool's `fur` or an optional `fur_styles` entry); rarity widens the spread and boosts fuzzy. Maine coons are fuzzy, long-furred, chunky, with a ruff and a plume tail. Sphynx are flat with big ears, a thin tail and slim legs. Shorter legs give a slightly bigger head.
- Fit guard: if some pose of a genome would leave the 192×192 in-game viewport, Cat2D shrinks the whole rig (`fit_scale()`); with the current clamps it almost never triggers.
- Pixel-art rendering (default in game): Cat3D renders Cat2D into a `pixel_density`×`pixel_density` SubViewport (default 56; the same 76.8-unit window as the smooth 192 px one, Cat2D at (n/2, round(n·182/192)), scale n/76.8), MSAA off, `snap_2d_transforms_to_pixel` on, and shows it on the Sprite3D with NEAREST filtering at `pixel_size = 1.2 / n`, `offset.y = feet row − n/2`. World size and feet pivot are identical to smooth mode. 56 gives ≈1.0 screen px per art px vertically and ≈1.33 horizontally at the default camera (size 14.5, 1600×900; the fixed-Y billboard is foreshortened by cos 40°). Toggle with the Cat3D exports `pixel_art` / `pixel_density` (or `configure_rig_rendering(on, n)`); F6 fallback is unaffected.
- Pixel renderer (`Cat2D.pixel_art` / `set_pixel_art()`) is a separate renderer, not a pixelated smooth sprite. It shares with the smooth renderer the genome, proportions, poses, animation timing and the landmark set (`Cat2D.get_landmarks()`: head pose, eye anchors, nose, muzzle, cheek edge, ear roots, paws, leg roots, torso/silhouette polygons, tail root/path, pattern transform). The smooth renderer is unchanged (verified pixel-identical). Pixel-only rules:
  - Head ~12% bigger (`PIXEL_HEAD_SCALE`, ears and face included); the fit guard covers it plus one art px of rounding, so every pose stays in the viewport.
  - Whole-pixel grid: the head pivot snaps to the art grid (no head rotation), the face origin (eye-centre row, nose column) is snapped once, and every face stamp sits at integer offsets from it. Faces are identical for cats sharing a stamp and never jitter with head bob. Breathing moves the back by 0/1 art px.
  - Face stamps live in `Scripts/prototype3d/CatPixelFace.gd` as text arrays (one char = one art px), generated by `Tools/gen_eye_stamps.py` from the open-eye silhouettes in `Tools/eye_silhouettes.txt`. Eye legend: `#` eye line, `L` upper lid (eye line), `d`/`o`/`l` iris dark/mid/light (3-step ramp of the genome eye colour), `p` pupil, `w` glint, `e` eye white, `.` none. Light eye line: only the upper half of the outline is dark; the lower half is drawn in the dark-iris tone, and every open pupil keeps >= 1px of iris / glint between it and the line on the left, right and below (so pupils never merge with the line on dark coats). The per-shape design (pupil size, 3-tone iris, glints) is `SPEC` in `Tools/gen_eye_stamps.py`. Mouth legend: `n` nose pink, `N` nose shadow, `m` mouth line, `r` mouth inside. Buckets by effective density (art px across the 76.8-unit window × fit): S ≤ 60, M ≤ 84, L above; plus compact fallback sets XS and XXS. Eye shapes: round, big, almond, slit, big_slit ("big slit"), gentle, mischievous, wide (genome `eye_shape`; null = seeded weighted pick from `Data/cat_eye_shapes.json`). big and big_slit are drawn 1px larger than their silhouette and fall back through +1 tall / +1 wide / silhouette size before the next smaller stamp set. Retired names in old genomes / saves map in `CatGenome.normalize` (sharp → mischievous, sparkle → big, button → round). Expressions: open, stressed, sleepy, closed (blink and sleep pose), happy, angry, worried, sad, surprised, smug (`Cat2D.set_expression()`); angry/worried/sad add a vein/sweat/tear mark. Both eyes use the same stamp, never scaled; slanted shapes/expressions mirror it for the far eye. Each eye is centred on its landmark anchor (eye_near / eye_far); the 3/4 view lives in their asymmetry.
  - To edit a face: change the characters, keep all rows of a stamp the same width and all expressions of one shape the same size (pad with `.` rows), keep mouth stamps odd-width. Check with `render_cat_seeds.gd -- out.png pixel faces [density]`, which also runs `CatPixelFace.validate()`.
  - Minimum sizes: eyes at 56 px: S 4-6 px wide (round 6×6, big 6×7, almond 6×5, sparkle 5×7, slit 5×6, wide 6×4, gentle/sharp 6×5, button 4×4); M 5–10 wide; L 6–12 wide; nose ≥ 3 px pink with a darker centre pixel on light muzzles; mouth ≥ 5 px wide in the outline colour, or a light tint when the muzzle is too dark for contrast (black, siamese mask); whiskers 2 lines per side (1 below 44 px or for sphynx), near side starts 2–3 px inside the cheek and reaches 3 px past the outline, far side is a 3–5 px line on the cheek beside the muzzle. Whisker colour contrasts with the fur region under each pixel (dark on light fur/muzzle, cream on dark fur); pixels past the outline use the decal alpha so they are not outlined.
  - Snoot axis (`CatPixelFace.SNOOT_FORWARD_PX` = 1): the nose + mouth stamp, the cream muzzle patch (tabby / tuxedo, plus the tuxedo blaze) and the siamese mask are centred on one column: the midpoint of the two PLACED eyes' footprints (after fallback stamps, gap push and face slide) plus 1 art px toward the facing side, because the snoot pokes slightly forward in the 3/4 view (+1 px right facing right, mirrored facing left). A midpoint between two columns also rounds forward, so the nose sits +1 or +1.5 px from the exact eye midpoint. Whiskers anchor on the same axis; an expression tear stops before it would touch the nose/mouth. Smooth mode keeps its landmarks (nose 0.125 × head size forward of the eye midpoint).
  - Eye spacing rules (always on, every shape / expression incl. blink / density 48–96 / pose / facing / genome / debug override; constants in `CatPixelFace.gd`): `MIN_EYE_GAP_PX` = S 3, M 4, L 5 fur columns between the two eyes' footprints (stamp, lids, lashes, arcs, tear); `MIN_EYE_EDGE_PX` = 1 fur px between an eye and the head/ear outline (sides, top, diagonals); smooth renderer `MIN_EYE_GAP_UNITS` = 3 rig units × head size between the two eye shapes. Eyes never touch each other, the outline, the nose/mouth, whiskers or marks. If an eye does not fit: keep the gap, fall back to the next smaller stamp set (L > M > S > XS > XXS, each followed by its size alternates for big / big_slit) on the same centres, then slide the whole face up to `MAX_FACE_SLIDE_PX` (2) toward the far cheek; the gap never shrinks. Cat2D warns if a layout ever breaks the gap, `CatPixelFace.validate()` checks every fallback chain against the smallest supported head (`MIN_HEAD`), and `Tools/check_eye_contacts.gd` verifies it on rendered pixels (after the outline pass).
  - Flat cel shading, opaque only: per colour a base / shade (`_tone(c, -1)`, lerp toward the outline hue; dark coats darken) / highlight (`_tone(c, +1)`) ramp. Shapes: back highlight strip (top rim of the torso), haunch crease, belly-overhang band on top of the near legs, back edge of near legs, far legs one step darker, toe split only above 70 px. No alpha inside the cat; the siamese mask halo is an opaque mid tone (only above 70 px); tail gradients are quantized to bands.
  - Outline: Cat2D draws fills only. `Scripts/prototype3d/CatPixelPipeline.gd` (used by the in-game Sprite3D, CatPreview's pixel view and the render tool) renders three SubViewports sharing the cat's World2D, split by `canvas_cull_mask` / part `visibility_layer` (BACK: far legs, tail, shadow; BODY: body union, near legs, markings; HEAD: head, ears, face, front tail when sleeping), then one ColorRect shader colours every transparent pixel 4-adjacent to a layer's opaque mask with the palette outline and composites back → body → head. Result: one clean 1 px silhouette outline and single 1 px internal lines only where layers overlap (chin over chest, body over far legs). Alpha 0.5–0.98 = decal (shown opaque, never outlined); < 0.5 = soft (ground shadow).
  - Pixel fur: flat/medium/fuzzy become 1–2 px spikes, ≥ 4 art px apart (more with lower `fur_density`), leaning back/down with the fur flow, only where the region mask is strong (cheeks, chin, chest ruff, belly, haunch, tail); weak regions stay smooth instead of turning into noise. Silhouette and markings are clipped at the floor line.
  - Patterns use the same regions as smooth but stay opaque and whole-pixel: tabby stripes ≥ 1.5 art px wide, one 1 px ring per near leg, tuxedo bib/blaze, calico patches, siamese points, sphynx wrinkles as 1 px shade lines.
  - Performance: geometry and booleans stay in the per-pose/walk-phase frame cache; face stamps redraw only on blink/expression change; the outline pass is one tiny shader per cat. Future work: bake each cat's frames to a spritesheet at spawn.
- Review renders: `Tools/render_cat_seeds.gd -- <png> pixel [ref6|random|seeds|faces|fur|poses] [pose] [density] [zoom]` (in-game pixel path incl. the outline pipeline, nearest upscale), `Tools/render_cat_seeds.gd -- <png> ref6 [pose] [scale]` (the six reference coats), `-- <png> phases [coat 0..5]` (walk frames), `-- <png> [seed] [pose] [rarity]` (in-game framing), `-- <png> random [seed] [pose]` (24 factory cats), `-- <png> fur [pose]` (style × length strip), `-- <png> extremes [pose]` (min/max of every knob).

## Animation Priorities
- Required first: idle and walk for cats and patrons.
- Optional later: small expressiveness loops (blink, tail flick).
- Animation timing should stay calm; no jittery motion in normal state.

## UI Art Rules
- UI panels should keep high text readability and clear hierarchy.
- Cat popup visuals must clearly frame trait, trust, and overstim information.
- Use consistent corner radius and border treatment across menus/HUD/popups.

## Technical Export Specs
- Working format: layered source files in `Art_Assets/*/raw/`.
- Export format: `.png` with transparent background where needed.
- Keep pixel scale consistent per asset type (lock exact px sizes before bulk production).
- Do not resize exports in engine to "make it fit"; re-export at correct size.

## Godot Import Defaults
- Texture filter: nearest (for pixel art readability).
- Mipmaps: off for UI and most sprite assets.
- Compression: lossless for pixel assets that need sharp edges.
- Validate every imported sprite in-context in `Scenes/Prototype3D/MainLevel3D.tscn` (the main scene) at the default zoom (ortho size 12). Check the cat rig in `Scenes/Prototype3D/CatPreview.tscn`.

## Review Checklist
- Silhouette readable at gameplay zoom.
- Palette and contrast aligned with this guide.
- Grid footprint/collision footprint visually clear.
- Layer alignment verified for all procedural cat parts.
- No clipping against common floor/wall tiles.

## Definition of Done (Art Asset)
- Source file committed.
- Export file committed.
- Asset manifest entry updated to `review` or `done`.
- Integrated in scene/UI and checked in runtime.
- Approved by art + gameplay pass.

## Scale Contract (hybrid 3D, binding)
| Item | Value |
|---|---|
| Grid cell | 0.7 m. Floor top at y = 0; actor feet at y = 0 |
| Camera | Orthographic, yaw 45, pitch 40. Default size 12; overview 16.5; zoom 8–17 |
| Cat | 1.2 m canvas. Pixel mode (default): SubViewport 56×56, Cat2D at (28, 53), scale 0.729, Sprite3D `pixel_size = 1.2/56`, `offset.y = 25`, NEAREST. Smooth mode: 192×192, Cat2D at (96, 182), scale 2.5, `pixel_size = 1/160`, `offset.y = 86`, linear. Visible body ≈ 0.55 m, roughly half a patron's height. Fallback sprite at `pixel_size = 0.016` |
| Patron | `pixel_size = 0.024` (about 1.55 m), about 120 px tall at default zoom |
| Actor billboards | `billboard = BILLBOARD_FIXED_Y`, `alpha_cut = ALPHA_CUT_DISCARD`, `shaded = false`, `cast_shadow = OFF`, `texture_filter = NEAREST` (fallback sprites), feet pivot via `offset.y = tex_h/2`. Never `no_depth_test`, `fixed_size` or a manual `look_at`. Blob shadow quad under each actor |
| Decor | Scaled per item (`scale` in `Data/decor_mesh_map.json`) so the mesh fits its grid footprint. No 4 m slabs |

## Palette
| Use | Hex |
|---|---|
| Background (outside the diorama) | `#2B2129` cocoa |
| Floor (oak planks) | `#B8916B` / `#AE8763` |
| Walls (peach plaster) | `#E3B9A0`, walnut wainscot `#9C6B4A` |
| Rest area rug (calm systems) | `#9DB8A0` sage |
| Partition / fence / UI border | `#C9A27A` oak |
| UI panel / text | `#FFF6EA` cream, 12 px radius / `#4A3426` |
| Sun / ambient light | `#FFE2BF` / `#FFE6CC` at 0.4 |
| Overstim bar ramp | `#8FBF9F` → `#E8B04B` → `#E07A3F` |
| Alerts only (drought, overstim) | `#E07A3F` |
