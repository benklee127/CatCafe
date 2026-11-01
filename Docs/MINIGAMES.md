# MINIGAMES

The minigame framework and the cooking minigame, *Paw & Pour: Station Kitchen*.
The design source is `COOKING_MINIGAME_DESIGN.md` (sections 2.4–2.8, 3 and 5). This file is the build contract: the APIs, the step (verb) contract, the per-verb params and the integration hook points.

## Files

| Path | What it is |
|---|---|
| `UI/Minigame/MinigameHost.tscn` + `Scripts/minigame/MinigameHost.gd` | A generic overlay: a CanvasLayer on layer 20 (above HUD3D's 5 and DecorPlacement3D's PlacementCursorLayer 12) with `PROCESS_MODE_ALWAYS`. It contains the dim, the cream window, the header, the 320×180 PlayArea, the footer, the ParkPrompt and the ResultCard. |
| `Scripts/minigame/MinigameBase.gd` | The base class for every hosted game. It provides `setup`, `scored`, `request_park`, `get_hud_info` and the static `grade_for`. |
| `Scripts/minigame/cooking/CookingGame.gd` | The recipe runner. It handles the ticket, the steps, the back burner, the par clock, the hot streak, scoring and the Serve bell. |
| `Scripts/minigame/cooking/steps/StepBase.gd` | **The verb contract** (below). |
| `Scripts/minigame/cooking/steps/DebugInstantStep.gd` | The test and stand-in verb. |
| `Scripts/minigame/cooking/StepRegistry.gd` | Maps a step type to a verb file. It tolerates missing files. |
| `Scripts/minigame/cooking/PixelDraw.gd` | Palette and crisp pixel helpers: rect, rounded rect, circle, ring, meter, band, star, paw, sparkle, mug, and a hand-made bitmap pixel font (`text()`, `text_width()`: caps 5x7, size 8 = 1x, 16 = 2x) so in-station text is as crisp as the art. |
| `Scripts/minigame/cooking/KitchenArt.gd` | Shared procedural art: 10x10 verb/station icons, grade stamps (S/A/B/C), dish sprites for all 10 recipes in a "great" and a "homely" look, the latte-art thumbnail. |
| `Scripts/minigame/cooking/KitchenChrome.gd` + `KitchenPixelBox.gd` | Art styles B..F for the host / launcher chrome: pixel panels (old border kept as an inner band inside an ink outline), bold theme font, the shared text rule on system-font labels, and `art_canvas()` (E/F halo / shadow for host-drawn art). |
| `Scripts/minigame/cooking/TracePaths.gd` + `steps/{Pour,KeepZone,StopRing,Trace,Place,BackBurner}Step.gd` | The six verbs (each script's header comment has the full behaviour). |
| `Scripts/minigame/CookingDemo.gd` + `Scenes/Minigames/CookingDemo.tscn` | **Test Kitchen**: the live cafe (MainLevel3D) as background + a launcher panel. |
| `Data/recipes.json` + `Data/schemas/RecipeDefinition.schema.json` | The 10 recipes from the Recipe Book. |
| `Tools/probe_cooking_framework.gd` | Framework probe (129 checks). |
| `Tools/probe_cooking_{pour_keep_zone,stop_ring_place,trace_back_burner}.gd` | Verb probes (104 / 70 / 108 checks). |
| `Tools/probe_cooking_demo.gd` | Test Kitchen glue probe (69 checks): cafe background, pay-on-serve, queue, park, pause, art coverage. |
| `Tools/probe_cooking_fixpass.gd` | Fix-pass probe (27 checks): park keeps finished steps (also at the Serve bell), result-card input guard, close() on the result card still pays, demo debug keys dropped on park, ticket read time, keyboard-only drag PLACE, burner slot, pixel font. |

No file uses a `class_name`. Every script is preloaded or extended by its path.

## How to run

`G` = the Godot 4.6 console exe (`Godot_v4.6-stable_win64_console.exe`); run from the project root.

```sh
# Test Kitchen (the cafe runs behind; launcher top-right):
"$G" --path . res://Scenes/Minigames/CookingDemo.tscn
#   optional user args after `--` (combine freely):
#     open=catpuccino                 open a recipe (ticket first)
#     step=not_tuna_taiyaki:2         jump to step k (earlier steps count as perfect at par)
#     result=catpuccino               instant perfect cook -> S result card (+1 pending ticket so
#                                     "Next order >" shows)
#     resultc=calico_pancake_stack    sloppy + slow instant cook -> C "Still tasty!" card
#     serve=tuxedo_affogato           instant cook, stops at the Serve bell
#     park=kitten_mochi               open, then show the park prompt after 1.5 s
#     queue                           order-queue simulation (1 open + 2 pending)
#     mod=to_go|take_your_time|kid_size   lenient=1|1.5|2   collapsed   hidden
# Probes (exit code 0 = pass; the framework probe prints one deliberate ERROR):
for p in framework pour_keep_zone stop_ring_place trace_back_burner demo; do
  "$G" --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_$p.gd; done
# Screenshot (always pass --fixed-fps 60):
"$G" --path . --fixed-fps 60 --script res://Tools/capture_screenshot.gd -- res://Scenes/Minigames/CookingDemo.tscn out.png 150 result=catpuccino
```

### Test Kitchen launcher

- Own `CanvasLayer` (layer 8, `PROCESS_MODE_ALWAYS`), cozy theme, top-right under the day chip. **F10** hides/shows it; the **-** button collapses it.
- **Recipes:** all 10, each with its dish sprite, tier stars, base price and its verb icon strip. Click to cook.
- **Per-run options:** patron modifier (None / To go! / Take your time / Kid size), Gentle Paws leniency (Cozy 1.0 / Relaxed 1.5 / Sleepy 2.0), Hold > Toggle, No-Clock, Reduced motion, seed (Random / Fixed + value).
- **Random order:** a random recipe with a random modifier.
- **Order queue (3):** opens one ticket and leaves two pending; the result card then shows **Next order >**. Pending tickets (parked ones go to the front) are listed and clickable.
- After **Back to cafe** / **Next order >** the cafe unpauses, then the demo calls `level.add_money(money, "order")`, `level.add_reputation()` for whole rep points (fractions carry over) and `HUD3D.show_notice()`, each guarded with `has_method`. The level is a child, not the current scene, so it never touches the player's save.

### Controls (in the kitchen)

| Input | Does |
|---|---|
| LMB / Space | pour (hold), keep zone (hold), stop ring (tap), trace (hold + drag), place (tap; drag mode: drag with the mouse, or Space = pick up, Space again = drop) |
| Arrows / WASD | steer the keyboard trace pen; nudge a dragged PLACE item |
| Right-click / Backspace / X | undo the last PLACE drag item |
| O, or click the burner ring | collect the back burner |
| Enter, or click the bell | serve |
| F1 | re-show the step hint |
| Esc / [x] | park prompt (Enter = park, Esc = keep cooking); on the result card Esc = Back to cafe |
| Enter on the result card | primary button (Next order > / Back to cafe); ignored for the first 0.45 s. Space does nothing there |
| Click / Space on the ticket | start now (otherwise it starts by itself after 2 s + 0.3 s per step) |

## Art (`KitchenArt.gd`)

All art is drawn in code from 1px rects and pixel rows (no image assets), in the cozy palette with `#4A3426` outlines. Alert orange stays reserved for spills inside the verbs.

- `verb_icon(ci, top_left, type)`: 10x10 icons for `pour`, `keep_zone`, `stop_ring`, `trace`, `place`, `back_burner`, `serve`, `counter`. Used on the ticket (1x), the station strip (2x) and the launcher (2x).
- `grade_stamp(ci, center, grade)`: S gold paw "PURR-FECT!", A sage paw "Great!", B cream paw + heart "Yummy!", C sleepy cat with a thumbs-up "Still tasty!". `GRADE_STAMPS` holds the colours and texts (the host reads it).
- `dish(ci, bottom_center, recipe_id, dish_def, info)`: one sprite per recipe, about 64x56. `info = dish_info(result_steps, precision)`. `great` (precision >= 0.75) picks the neat look; otherwise the homely look (wonky stack, darker bake, red bean peeking out...). It redraws the player's TRACE strokes (`extra.art`) on the foam and tints cookies / taiyaki / pancakes from STOP_RING browning. `fx: false` turns off the sparkles / heart for small icons. Unknown ids fall back to the `dish.kind` look.
- `latte_art(ci, center, r, info)`: top-down thumbnail of the player's trace ("your art" on the result card).
- Host chrome: bunting along the window top, a dish badge left of the title, a patron-mood bubble left of the par clock (heart below 80% of par, wiggling "..." up to par, "Zz" after; the clock bar turns honey at 80%), icon chips in the station strip (recipes with more than 4 steps collapse to icon + stars except the active chip), and the result card: grade-tinted card (S honey glow + 12-piece confetti, C softer cream), a big tilted grade letter that slams in, the dish at 4x sized to the sprite (`MinigameHost.DISH_H`), and step stars revealed one by one.

---

## Art styles A-F (outline options)

The six shared minigame art options (same letters, titles and text rules as Counter Cats and Purr-fect Timing; wording from `art_options/shared/style_table.json`). The switch lives in `PixelDraw.gd` (`STYLES`, `set_style()`, `legacy()`); every helper keeps its original code path in **A**, so A renders byte-identical (verified by pixel-diffing frames of every verb, the ticket, S and C result cards and the launcher).

| Letter | Look | Text |
|---|---|---|
| A | Current (today) | today's pixel / UI font |
| B | 2px outer outline, same shapes | bold |
| C | 2px outline + chunky (2px min lines / notches, shine strokes dropped, light icon tints merged) | bold |
| D | C + 1px top/left rim light + 2-tone cel shade | bold + 1px outline |
| E | C + 1px cream sticker halo around whole objects | bold + 1px outline + cream halo |
| F | 3px outline + chunky + 1px cocoa drop shadow (35%) | bold + 2px outline (1px at 1x) + drop shadow |

- **Pick it:** `-- --ck-art-style=D` (read at boot by `PixelDraw`), the Test Kitchen **Art style** option (live: rebuilds the launcher and calls `MinigameHost.apply_art_style()`, which restyles the chrome and calls `CookingGame.apply_art_style()`), or `PixelDraw.set_style("D")` + `host.apply_art_style()` from code.
- **Where it applies:** shared helpers (`outlined_rect`, `rounded_rect`, `circle`, `ring`, `line`, `dotted`, `star`, `paw`, `sparkle`, `text`), new `PixelDraw.px()` (thin details: ink rects >= 2px, chunky 2px min), `hl()` (shine strokes, dropped when chunky), `outlined_poly()` (fish, taiyaki, mochi, ears); `KitchenArt.bitmap/oval/poly` (bitmaps grow their ink silhouette by 1px); the six verbs, ticket, bell and dish; host window / cards / chips / buttons / stamp panels (`KitchenChrome.box`); bold theme font + text rule.
- **E / F:** the step, burner and ticket/dish layers move into one `CanvasGroup` with `PixelDraw.FX_SHADER` (cream halo / cocoa shadow); the wall + counter background stays outside. Host art (dish badge, station icons, stamps, result dish, latte plate, mood, burner) is wrapped the same way via `KitchenChrome.art_canvas()`.
- **Not restyled on purpose:** steam puffs (translucent vapour), the player's trace ink / latte art (1px pen), tiny face features and the 9x8 paw-mark bitmaps, cats / patrons (the kitchen draws none).
- **Thin by design:** the dotted drop guides and the dotted latte-art guide stay 1px dots in B (2px from C up). Ink details (swing cord, shaker motion dashes, tea-bag string) are 2px in B..F; whisk tines are 2px from C up.
- **Outlined in B..F:** pour streams (ow() ink both sides, 2px core), marshmallow-cat heads in the place verb (food, not patrons: ears + head get the full ow() outline), the keep-zone pointer arrow.
- **Bold pixel font:** each run grows 1px right except into a 1-unit inner gap (keeps m / N / # / % open); at 1x, W / M / w use hand-made bold bitmaps (`PixelDraw._BOLD_GLYPHS`) so "Wonky!" never reads "Honky!".
- **Small system-font text (< 20px):** 1px ring, no halo; in F also the 1px shadow, and mid-tone (oak) print turns cream so the cocoa ring reads. Translucent chip fills are pre-blended over cream (as light as A); chips get extra left / right padding so the station icon sits inside the border.
- B..F fixed text boxes widen to fit the bold font (pour label, keep-zone progress, trace hint card, burner tag, ticket); the keep-zone progress box is also 2px taller and the SERVE label lifts by the extra outline. A keeps its sizes.

## MinigameHost API

```gdscript
const MinigameHost := preload("res://UI/Minigame/MinigameHost.tscn")
host.open(game, context)   # game: Script | PackedScene | "res://..gd/.tscn" | Node (extends MinigameBase)
host.close()               # hard close -> aborted(context); on the result card -> finished (still paid)
host.is_open() -> bool
host.request_park() / confirm_park() / cancel_park()
host.choose_result(next_order: bool)
host.get_game() -> Node ; host.get_play_scale() -> int ; host.get_physical_scale() -> int
host.reduced_motion: bool ; host.settings: Dictionary   # defaults merged into context.settings
signal finished(context, result)   # result = the game's scored(result) + result.next_order
signal parked(context)             # context + game.get_park_state() (seed + resume) + park_count
signal aborted(context)
signal opened(context)
```

**Pausing**
- `open()` saves `get_tree().paused` and sets it to `true`. `close()`, park and finish all restore the saved value.
- **Every signal is emitted after the unpause.** The handlers can pay out, tween and toast immediately.

**Input**
- The `Dim` ColorRect (`MOUSE_FILTER_STOP`) and the window swallow mouse input.
- The paused cafe gets no `_process` or `_unhandled_input` calls.
- Esc toggles the park prompt. On the result card, Esc means "Back to cafe".
- Enter on the result card picks the primary button, but only after `RESULT_GUARD_SEC` (0.45 s); the buttons have the same guard. Space is swallowed there (it also rings the Serve bell, so a fast tapper would otherwise skip the card).
- While the prompt is up, the game is frozen with `process_mode = DISABLED`.

**Layout**
- The window is about 70% of the viewport and centred.
- The PlayArea is a `SubViewportContainer` (`stretch`, `stretch_shrink = 1`, size 320×180) holding a 320×180 `SubViewport` with nearest filtering. The container is scaled by `k / f`, where `f` is the canvas_items stretch factor (physical px per logical unit) and `k` the largest whole number of **physical** pixels per art pixel that fits: 2 at 1280×720, 3 at 1600×900, 4 at 1920×1080. So art pixels are always an even k×k block on screen. Headless runs use f = 1.
- The layout recalculates on `size_changed`.

**Header, footer and banner** are filled each frame from `game.get_hud_info()`. See `MinigameBase.gd` for the keys: `title`, `subtitle`, `par_sec`, `elapsed_sec`, `show_clock`, `hot_streak`, `burner{visible,progress,state,label}`, `stations[{label,state,stars}]`, `hint`, `banner{visible,title,text,style,stars}` and `phase`.

**Context keys the host uses:** `settings.reduced_motion` and `has_next_order` (shows `[Next order >]`). The host writes `_play_scale` (logical screen px per art px, rounded; 3 at 1600×900) into the context.

## CookingGame context

| Key | Type | Notes |
|---|---|---|
| `recipe` | Dictionary | **Required.** One entry of `Data/recipes.json`. |
| `seed` | int | Seeds the target rolls. If it is missing, the game rolls one and writes it back, so a parked order keeps it. |
| `modifier` | String | `to_go` (par ×0.85, pay ×1.2), `take_your_time` (par ×1.3), `kid_size` (windows ×1.25, drops the step marked `kid_skip`) or `""`. |
| `archetype` | String | Used when `modifier` is absent: `busy_remote_worker` → to_go, `gentle_reader` → take_your_time, `hyper_toddler` → kid_size. |
| `patron_name` | String | Shown in the header subtitle. |
| `settings` | Dictionary | `leniency` (1.0, 1.5 or 2.0), `hold_to_toggle`, `no_clock`, `reduced_motion` (Gentle Paws). |
| `balance` | Dictionary | Overrides `CookingGame.DEFAULT_BALANCE`. This is where the future `balance_config.cooking` block goes. |
| `mastery_mult` | float | Pay multiplier (default 1.0). |
| `has_next_order` | bool | Host: shows `[Next order >]`. |
| `allow_stand_ins` | bool | Default `true`. A missing verb then plays as the DebugInstantStep card. With `false`, the step is logged and scored as 0.4. |
| `step_override` | Dictionary | For tests: `{script, accuracy: float or [..], time: float or [..], delay}`. |
| `skip_intro`, `pace` | bool, float | For tests and screenshots: skip the ticket, and scale the ticket, hint and pop durations. |
| `start_step` | int | Demo / screenshots: jump to step k; earlier steps are recorded as perfect at par (no extras). |
| `resume` | Dictionary | Written by `get_park_state()` on park: `{results, clock, hot_count, recipe_id}` for the finished steps from the start up to the first unfinished one. `setup()` restores them and continues at the next step (or straight at the Serve bell). A back-burner pot that was still simmering restarts, and later steps are redone. `CookingGame.resume_step_count(ctx)` reads it. |

**Flow**
1. Ticket for 2 s + 0.3 s per step (3.2 s for 4 steps, 4.4 s for 8), with a pulsing "Space>" chip whose underline drains. Click or Space starts sooner.
2. For each step:
   1. The card slides in.
   2. A **1 s verb hint** shows while the step is visible but frozen. Click or Space skips it.
   3. The step is active, and the clock runs.
   4. `done` arrives, followed by a **0.5 s pop** (stars and a word), and the next card auto-advances.
3. A `back_burner` step shows its hint and then keeps running in the top-right slot while the later cards play.
4. After the last card, if the burner has not been collected yet, the game waits for it with the clock still running.
5. **Serve bell**: click the bell or dish, or press Enter or Space. (The result card then ignores Space and early Enter.)
6. `scored(result)` is emitted.

F1 shows the current step's hint again.

**Par clock.** It counts only the time while a step is active or the game is waiting for the burner. It does not count the ticket, hints, pops or the bell. Par = (Σ `par_sec` + `par_bonus_sec`) × the modifier's `par_mult`.

**Scoring** (design 2.7; static functions on `CookingGame` you can unit-test):
```
precision = Σ(w·acc)/Σw            # w = step.weight (trace 1.5 in data; default 1.5 for trace, else 1)
speed     = 1 if t<=par or no_clock else clamp(1 - 0.6*(t-par)/par, 0.4, 1)
hot       = count of steps with time <= par_sec*par_mult and acc >= 0.85 ; bonus = min(0.03*hot, 0.09)
score     = clamp(0.70*precision + 0.30*speed + bonus, 0, 1)
grade     = S >= 0.90, A >= 0.75, B >= 0.55, else C
money     = round(base_price * {S:1.5,A:1.2,B:1.0,C:0.7} * modifier_pay_mult * mastery_mult)
rep       = {S:1.0, A:0.5, B:0, C:0}   # carry / daily cap / first-S bonus are the level's job
```
The tier window multiplier (T1 ×1.0, T2 ×0.85, T3 ×0.7) and the tier sweep (2.4, 2.0 or 1.6 s) are injected into each step's params.

**Result payload** (`finished(context, result)`):
`{kind:"cooking", recipe_id, display_name, grade, grade_text, score, precision, speed, steps:[{type,label,accuracy,time,par_sec,weight,stars,hot,extra}], time_sec, par_sec, no_clock, hot_streak, hot_streak_bonus, money, rep, base_price, modifier, modifier_label, pay_mult, seed, effects, next_order}`

---

## StepBase contract (for the verb builders)

Each verb lives at `Scripts/minigame/cooking/steps/<Name>Step.gd`, or at `Scenes/Minigames/Steps/<Name>Step.tscn` if it needs a scene. The scene is looked up first. The verb starts with:

```gdscript
extends "res://Scripts/minigame/cooking/steps/StepBase.gd"
```

| type | file |
|---|---|
| `pour` | `PourStep` |
| `keep_zone` | `KeepZoneStep` |
| `stop_ring` | `StopRingStep` |
| `trace` | `TraceStep` |
| `place` | `PlaceStep` |
| `back_burner` | `BackBurnerStep` |

**Lifecycle**
1. CookingGame instantiates the node, adds it under `StepLayer` at (0,0), and sets `hold_to_toggle`.
2. It calls `start(params, leniency, rng)`. The base stores these and calls your `_on_start()`.
3. **The node is frozen** (`PROCESS_MODE_DISABLED`) during the 1 s hint, but it is drawn. Draw the idle state from `_on_start()` and `queue_redraw()`.
4. When it is unfrozen, the base accumulates `elapsed` (game time, which also freezes under the park prompt) and routes input to the hooks.
5. Call `finish(accuracy)` **exactly once**. It emits `done(accuracy, time_sec)`, using `elapsed` when no time is passed. Later calls are ignored.
6. CookingGame frees the node after the 0.5 s pop. Keep showing the final state until then.

**Fields:**
- `params: Dictionary`
- `leniency: float`
- `hold_to_toggle: bool`
- `rng: RandomNumberGenerator` (seeded per step)
- `elapsed: float`
- `extra: Dictionary`: optional result data that later steps receive in `params._prev`, such as `{"fill": 0.71}` for the layered pour.

**Helpers:**
- `window_scale()`: tier × modifier × leniency. Multiply every band or window width by it.
- `time_scale()`: leniency. Multiply sweep or cycle durations by it.
- `roll(key, default)`
- `play_scale()`
- `reduced_motion()`
- `safe_rect()`
- `slot_rect()`
- `to_play_coords(event)`: maps the event or mouse into 320×180 viewport space.
- `to_local_play(event)`
- `nudge_vector()`: arrows or WASD.
- `is_primary_held()`
- `is_running()`

**Input hooks.** Override these. If you override `_unhandled_input`, call `super(event)` first.

| Hook | When it fires |
|---|---|
| `_on_tap(play_pos, from_mouse)` | Every LMB or Space press (tap verbs). |
| `_on_hold_begin(play_pos, from_mouse)` / `_on_hold_end(play_pos)` | Holds. These are toggle-aware: with `hold_to_toggle`, a tap starts the hold and the next tap stops it. A mouse or Space release outside the PlayArea is caught from the device state. |
| `_on_pointer_moved(play_pos)` | Mouse motion in play space. Use it for TRACE dragging and PLACE dragging. |
| `_on_burner_key()` | The O key. |

When your verb uses an event, call `get_viewport().set_input_as_handled()`.

The back burner sits in a later sibling layer, so it gets input **before** the active card. It must mark clicks on its own ring as handled, so they don't count as a tap on the card.

**Reserved params** injected by CookingGame. They all start with `_`. Recipe params never do.

| Key | Meaning |
|---|---|
| `_type`, `_label`, `_index` | Identity of the step. |
| `_tier` | 1 to 3. |
| `_window_mult` | Tier mult × modifier window mult. Use it through `window_scale()`. |
| `_sweep_sec` | Tier sweep. STOP_RING uses it when `sweep_sec` is absent. |
| `_roll` | Seeded rolls: pour `{target}`, keep_zone `{zone_center}`, stop_ring `{sweep_mult 0.9–1.1}`, trace `{shape}`, place `{target_x −0.15..0.15}`, back_burner `{cook_sec}`. **Use these instead of rolling yourself**, so parked orders replay identically. |
| `_prev` | Results of earlier steps: `[{type,label,accuracy,time,par_sec,weight,stars,hot,extra}]`. |
| `_play_scale` | Logical screen px per art px (rounded; 3 at 1600×900). Screen-space px = art px × `_play_scale`. TRACE's tolerance is in screen px. |
| `_safe_rect` | Where a card should draw: `Rect2(8,8,256,164)` when the recipe has a burner, else `Rect2(8,8,304,164)`. |
| `_slot_rect` | The burner slot, `Rect2(272,4,44,44)`. |
| `_reduced_motion` | Gentle Paws reduced motion. Read it with `reduced_motion()`. |

The banner overlays the top of the PlayArea (about the top 30 art px) during hints and pops. Keep the important parts of a card below y≈36 or centred.

**Art rules**
- Draw only with `_draw` and the `PixelDraw` helpers, in 320×180 art pixels.
- Outline `#4A3426`; cream `#FFF6EA`, oak `#C9A27A`, sage `#8FBF9F`, honey `#E8B04B`.
- Alert orange `#E07A3F` is **only for spill or overflow**, and never the only signal: pair it with a shape such as a paw notch or a star notch.
- Honour `reduced_motion()`, which reads `params._reduced_motion`: no bounce, shake or particles.
- No image assets.

**Optional for back_burner:** implement `get_burner_info() -> {state: "cooking"|"ready"|"good"|"late", progress: 0..1}`. The header burner slot shows it. Without it, CookingGame estimates progress from `elapsed / _roll.cook_sec`.

### Per-verb params (recipe `params`) and precision rules (leniency ×1.0)

All widths are multiplied by `window_scale()`, and all durations by `time_scale()`.

**`pour`**: hold to pour, release on the line.
- `target_range [lo,hi]`. The target itself is `_roll.target`.
- Flow ramps from `flow_min` to `flow_max` (fraction of the vessel per second) over `ramp_sec`. Defaults are 0.15, 0.6 and 1.0. Holding longer pours faster.
- `bands` defaults to `[0.03,0.06,0.10]`: a distance from the line within each band scores 1.0, 0.85 or 0.65; otherwise 0.4.
- Filling past the line by more than `spill_over` (0.15) is a cute spill, capped at `spill_cap` (0.65). Spill is the only use of orange.
- `vessel`: `mug`, `bowl`, `glass`, `pan` or `mold`. `liquid` is a hex colour.
- `base_fill` and `base_liquid`: the vessel starts with a pre-filled layer, as in the matcha recipe.
- `layer: "A"|"B"` with `line_from_prev: true`: line B moves by the fill error of the previous pour (`_prev[-1].extra.fill − its target`), which forgives that error. Put `extra.fill` and `extra.target` in your own `extra`.
- `no_overflow: true`: any overfill is capped at 0.65, with no spill margin.

**`keep_zone`**: hold to raise the needle, release to let it fall.
- The zone is centred on `_roll.zone_center` (from `zone_center`, or rolled from `zone_range`), with width `zone_size` (0.18).
- Fill `need_sec` (2.0) of in-zone time within `window_sec` (6.0). It ends when the time is filled or the window runs out.
- Accuracy = in-zone time ÷ active time.
- `rise_speed` and `fall_speed` are in gauge units per second. `drift` is an optional wobble amplitude.
- `gauge` is a cosmetic id: `milk`, `kettle`, `whisk`, `shaker` or `teapot`.

**`stop_ring`**: tap when the ring is golden.
- `sweep_sec` defaults to `_sweep_sec` × `_roll.sweep_mult`. The ring goes from raw to golden to toasty.
- The golden window `golden_sec` (0.40) is centred on `golden_center` (0.5 of the sweep). Its middle `perfect_sec` (0.16) scores 1.0, and the rest of the window 0.85.
- A miss scores 0.4 and loops once ("it cooled a bit"). The retry is capped at `retry_cap` (0.7).
- `hits: n` makes it a conveyor: the accuracy is the mean of the hits.
- `tempo_sec` makes it a steady-tempo pounding, as in the mochi recipe.
- `food` is a cosmetic id: `cookie`, `stamp`, `taiyaki`, `pancake` or `mochi`.
- Put the browning in `extra`, e.g. `{"brown": 0.0..1.0}`. The pancake PLACE step tints from it.

**`trace`**: hold and drag along a dotted Curve2D path within `time_sec` (4–5 s).
- Accuracy = 1 − (mean distance in **screen px** ÷ `tolerance_px`, which is 14). Screen px = art px × `_play_scale`.
- Coverage below `min_coverage` (0.8) caps it at `coverage_cap` (0.6).
- The shape is `_roll.shape`, drawn from `path_pool`: `cat_face`, `paw`, `loaf`, `fish`, `swirl`, `spiral`, `circle`, `zigzag` or `bow_tie`.
- `ink`, `ink2` (two-tone) and `canvas` are colours.
- Keyboard: hold Space while an auto-pen runs along the path, and steer with `nudge_vector()`. The magnet is always on for keyboard. Recipes give trace a weight of 1.5.

**`place`**: drop items on a marker.
- `mode`:
  - `swing`: the item sways ±`swing_amp_px` over a `swing_sec` period. Tap to drop it.
  - `drag`: drag the item to a ghost marker. RMB / Backspace undoes. Keyboard: Space picks the next item up, arrows / WASD move it, Space drops it. Its default hint is `VERB_HINTS.place_drag` (`CookingGame.hint_for(step)`).
  - Targets: honey outline + sage fill pulsing 0.35–0.75 at 1.5 Hz (steady with reduced motion), 2px brackets on targets 8px or wider, and a honey down-arrow under the counter at the swing target x. The count pips fill with the item colour.
- Place `count` items. The offset of each from its target scores against `bands_px` `[5,10,18]` → 1.0, 0.85, 0.65, else 0.4. Accuracy is the mean.
- The marker is offset by `_roll.target_x` × the vessel width.
- `stack: true` stacks the items. `tint_from_prev: "stop_ring"` tints them from earlier `extra.brown`.
- `item` is a cosmetic id: `marshmallow_cat`, `red_bean`, `eyes_ears`, `pancake` or `button`.
- Off-centre looks wonky, never broken.

**`back_burner`**: a parallel timer of `_roll.cook_sec` (from `cook_sec`, or rolled from `cook_range`).
- Once ready, it scores 1.0 for `done_window_sec` (1.2), then 0.65 for `good_window_sec` (1.3), then 0.4 forever. Nothing burns.
- Collect it by clicking its ring in `slot_rect()` or pressing O (`_on_burner_key`).
- It runs while later cards play. Each recipe has at most one.
- `item` is a cosmetic id: `iron`, `pot` or `portafilter`.
- Set its `par_sec` in the data to about `cook_sec` + 1, so a prompt collect counts toward the hot streak.

**Test-only params:** `debug_accuracy`, `debug_time`, `debug_delay`. They come from `step_override`, and only DebugInstantStep reads them.

---

## Recipes (`Data/recipes.json`)

There are 10 recipes in design order. All of them are in the data. The game also gates on `unlock` and `station`, but that gating is the level's job.

The schema is `RecipeDefinition.schema.json`. It validates with `SchemaValidator`, which the probe checks.

**Deviations from the design table:**
- `steps` allows up to **8** entries, because the Calico Pancake Stack has 3 × (pour, flip), plus place and trace.
- The optional fields are:
  - `dish {kind, colors}`: the procedural dish on the serve screen.
  - `flavor_text`.
  - `kid_skip` (per step): which step "Kid size" drops.
  - `hint` (per step): overrides the verb hint.
- `icon` is `procedural:<id>`, because there are no image assets.

## Recipe data format (`Data/recipes.json`)

An array of recipe objects (schema: `Data/schemas/RecipeDefinition.schema.json`):

| Key | Type | Notes |
|---|---|---|
| `id` | string | snake_case; also the KitchenArt dish id |
| `display_name`, `flavor_text` | string | |
| `station` | string | `"counter"` or a `decor.json` id that must be placed to cook it |
| `tier` | 1-3 | sets `_window_mult` (1.0 / 0.85 / 0.7) and the default sweep |
| `unlock` | object | e.g. `{"day": 3}`, `{"reputation": 15}`, `{"adoptions": 1}` (checked by the level) |
| `base_price` | int | money = base x grade mult x modifier pay mult x mastery |
| `par_bonus_sec` | number | added to the sum of step pars (default 3) |
| `steps` | array (2-8) | `{type, label, par_sec, params, weight?, kid_skip?, hint?}`; `type` is one of the six verbs |
| `dish` | object | `{kind: plate/mug/glass, colors: [...]}` fallback look; `coat_from` (mochi) |
| `effects` | object | passed through to the result (e.g. `calm_aura`) |
| `icon` | string | `procedural:<id>` |

## Integration hook points (follow-up; not done here)

| Where | What to add |
|---|---|
| `HUD3D.tscn` / `MainLevel3D` | Instance `res://UI/Minigame/MinigameHost.tscn` once. Add `HUD3D.open_cooking(patron, recipe_id)`, which builds the context `{recipe: recipe_data_by_id[id], seed: patron.pending_order.rolled_seed, modifier, archetype, patron_name, settings: gentle_paws, has_next_order: pending_count > 1}` and calls `host.open(preload("res://Scripts/minigame/cooking/CookingGame.gd"), ctx)`. Store `patron` in `ctx["patron"]`; the host passes the context back untouched. |
| `HUD3D.is_cooking_open()` | Returns `host.is_open()`. Guard `_unhandled_input` (B, F1, F7, Esc). This is only needed for nodes with `PROCESS_MODE_ALWAYS`, because paused nodes get no input. Hide the build panel and cards on `opened`, and show them again on `finished`, `parked` or `aborted`. |
| `MainLevel3D._on_cooking_finished(ctx, result)` | Connect it to `host.finished`. Runs after the unpause. It does the following: `add_money(result.money, "order")`; reputation through `cooking_rep_carry` and the daily cap, plus the first-S bonus; `recipe_stats`; `orders_served_total`; `result.effects.calm_aura` when the grade is at least `min_grade`; the patron gets `order_satisfied` (S or A) and `extend_visit(10)`. If `result.next_order` is set, open the oldest pending order. |
| `host.parked(ctx)` | The patron's `pending_order` stays. Patience +10 s, capped. The seed is unchanged (`ctx.seed`), and `ctx.resume` holds the finished steps: store the whole ctx (or at least `seed` + `resume`) on the pending order and pass it back to `host.open` to continue. |
| `host.aborted(ctx)` | Treat it like parked. |
| `balance_config.json` `cooking` block | Pass it as `ctx.balance`. The keys match `CookingGame.DEFAULT_BALANCE`. |
| `DataLoader` | Add `DATA_FILES["recipes"]` (an array validated with `RecipeDefinition.schema.json`). Cross-check that `station` is `"counter"` or a `decor.json` id. |
| Gentle Paws settings | User settings, not run state. Pass them as `ctx.settings`, or set `host.settings` once. |

Rewards must be applied in the signal handlers (after the unpause), never inside the overlay.

### Integration checklist (follow-up)

- [ ] **Order roll**: in `MainLevelPatron3D._process_slot()`, when a seated patron starts dwelling, roll `pending_order = {recipe_id, seed: randi(), modifier: ARCHETYPE_MODIFIERS[archetype]}` from the recipes whose `unlock` is met and whose `station` is placed. Show the order bubble, and hold `dwell_timer` while an order is pending (patience ring instead).
- [ ] **Click a patron**: add `pick_patron_at(screen_pos)` to `DecorPlacement3D` (mirror `pick_cat_at`) and a `patron_clicked(patron)` signal. The level forwards it to the HUD when the patron has a `pending_order`.
- [ ] **`HUD3D.open_cooking(patron, recipe_id)`**: instance `UI/Minigame/MinigameHost.tscn` once (layer 20 sits above HUD3D's layer 5 and DecorPlacement3D's `PlacementCursorLayer` 12). Before `host.open`, cancel decor placement (`DecorPlacement3D.cancel_hold()` when `is_holding()`), as `CookingDemo._cancel_decor_placement()` does, so its cursor UI isn't left frozen. Build the context exactly like `CookingDemo.make_context()`, plus `ctx.patron`, `has_next_order`, `balance` and `mastery_mult`, then call `host.open(CookingGame.gd, ctx)`. Add `is_cooking_open()` and guard B / F1 / F7 / Esc.
- [ ] **Pay on serve**: `MainLevel3D._on_cooking_finished(ctx, result)` on `host.finished` (after unpause): `add_money(result.money, "order")`, rep carry, patron mood, `result.effects`. Then `result.next_order` opens the oldest pending order (see `CookingDemo._on_finished`).
- [ ] **Park / abort**: on `host.parked` / `host.aborted`, keep `pending_order` (same seed, plus `ctx.resume` from a park) and give patience +10 s. `host.close()` while the result card is up emits `finished` (the dish was served), so a scene change or Esc guard never forfeits the pay.
- [ ] **Data**: `DataLoader.DATA_FILES["recipes"]` validated with the schema; a `balance_config.json` `cooking` block becomes `ctx.balance` (keys = `CookingGame.DEFAULT_BALANCE`).
- [ ] **Save keys**: `run_state.cooking = {recipe_stats: {id: {served, best_grade, s_count}}, orders_served_total, rep_carry}`. Unlocked recipes ride on `unlocked_content`. Gentle Paws (`leniency`, `hold_to_toggle`, `no_clock`, `reduced_motion`, `trace_magnet`) are user settings, not run state.
- [ ] **Known glue gaps**: CookingGame does not connect the verbs' `sfx(id)` signals yet; `trace_magnet` is read from `context.settings` by TraceStep but has no launcher toggle; the schema's `path_pool` enum lacks `heart` / `bow_tie_two_tone`.
