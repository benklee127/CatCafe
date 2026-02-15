# Art Style Guide

Purpose: lock visual direction so production assets are consistent and readable in gameplay.

## Visual Direction
- Cozy, warm, calm atmosphere.
- Readable simulation first; decorative detail second.
- Silhouettes must remain clear at gameplay zoom.

## Perspective and Composition
- Use top-down/isometric-friendly sprites consistent with current prototype camera.
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
- Validate every imported sprite in `Scenes/Main.tscn` for in-context readability.

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
