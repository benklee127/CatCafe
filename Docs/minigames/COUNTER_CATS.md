# Counter Cats: Whisker Kitchen (playable demo)

A standalone demo of the "cats" cooking-minigame concept. You make a cafe treat while
the cafe's real cats wander onto the 2D counter. The demo is self-contained so it can
be tried now, before the shared cooking MinigameHost exists.

## Run it

```powershell
& "C:\Users\benkl\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6-stable_win64.exe" --path C:\workspace\CatCafe res://Scenes/MinigameDemos/CounterCats/CounterCatsDemo.tscn
```

The live cafe (`MainLevel3D.tscn`, unmodified) runs underneath. The demo is not the main
scene, so MainLevel3D's own guard turns saving off: playing the demo never touches the save.

## Controls

| Action | Mouse | Keyboard |
|---|---|---|
| Toggle the test panel | | F11 |
| Cook (tap the ring, pour, drop) | left click / hold in the play area | Space or Enter |
| Pet a cat (0.6 s hold, pink ring) | hold left click on the cat | hold P (or E) |
| Catch a batted ingredient / re-grab from the bin | click it | Space |
| Boop a sniffing cat | click the cat | Space |
| Helper paw assist | click the helper cat | A |
| Park / leave (no loss) | Esc button | Esc, then P = park, L = leave, Esc = keep cooking |
| Serve from the result card | Serve! | Enter / Space / Esc |

Accessibility (test panel): leniency x1 / x1.5 / x2 scales every judge window, pour band
and drop tolerance. "Tap instead of hold" makes pour and pet tap-to-start, tap-to-stop
(a pet then finishes on its own).

## What's in it

* **Three verbs.** These are *ring* (stop-the-ring timing tap with Perfect/Great/Good
  windows of 60/120/200 ms; it auto-fires "Ok" after 3 sweeps), *pour* (hold, then
  release on the line; a sage band with a paw marker on a meter plus a dashed line on
  the cup; overshoots are skimmed back so later layers always fit) and *drop* (a
  pendulum garnish: 4 px is Perfect, 24 px is zero; it auto-drops after 4 swings).
* **Three recipes = difficulty.** Catpuccino (Easy, 5 steps, par 26 s), Paw-Print Cookies
  (Medium, 3-hit stamp and a 2-target drop, par 30 s) and Calico Parfait (Fancy, 3 pour
  layers, 2-hit chill and 2 wafer ears, par 32 s). A round takes about 15-25 s of cooking
  plus the result card.
* **Real cats.** Up to 2 cats come from `get_tree().get_nodes_in_group("cats")`, read only
  through guarded `get()`: `display_name`, `cat_def` (genome), `overstimulation`,
  `overstim_threshold`, `trust`, `trait_ids` and `state`. Resting and retreating cats are
  skipped. The most-overstimulated cat comes first ("the cat that most needs a break"),
  or you can pick one in the panel. The counter cat sits on its cushion. In Lively, a
  second cat watches from the window sill.
* **Cat art.** Each cameo is an instance of `Scenes/Prototype3D/Cat2D.tscn` with
  `apply_genome`, `set_pixel_art(true)`, `set_pose` (idle/walk/sit/sleep),
  `set_facing_left` and `set_expression` (open, happy, sleepy, smug, worried, surprised),
  rendered through the existing `CatPixelPipeline.gd` (the same 56 px outline composite as
  in-game). No new cat art. Gestures are whole-rig tweens: a hop for the ear-twitch
  telegraph, a lunge for the bat, a lean for the sniff, a squash for a happy pet. The
  props are procedural: a "!" bubble, a heart "wants pets" bubble, a gold paw bubble, a
  petting hand, the paw-swipe arc, purr lines, hearts, sniff dots and a collar glint.
* **Events** (`cc_game.gd`):
  * LOAF: the cat sleeps on the ingredient tray. A frazzled cat sits with a heart bubble
    and wants pets. Pet it, or ignore it and it leaves after 5 s.
  * BAT (fizzy and feisty cats): the next ingredient slides toward the edge for 1.4 s.
    Catch it, or it plops into the cushion bin and pops back after 1.3 s.
  * SNIFF (at serve): boop the nose within 2 s, or a cosmetic "Cat-Approved" paw sticker
    lands on the dish (no score change).
  * PAW ASSIST (helper: trust 70 or more and calm): replaces one event and auto-completes
    the current step at Great. Helpers also widen every window by 15%.
* **The judges' concerns, addressed:**
  * Events are capped (Off 0, Cozy 1, Lively 2). Never in the first 4 s, at least 5 s apart.
  * Events are always telegraphed for exactly 1.0 s, during the between-steps transition
    when nothing is judged. They arrive as the next step starts.
  * There is no shoo. Ignoring an event is neutral: no stat or score penalty (a missed bat
    only costs the ~1-2 s it takes the ingredient to pop back).
  * Petting freezes the current step (it never ruins a timing) and costs only clock time.
  * Shy cats (trust under 30) only loaf.
* **Rewards on close.** The overlay unpauses first, then applies rewards exactly once:
  * `level.add_money(x, "order")`, guarded with `has_method`. The amount is
    {S 9, A 6, B 4, C 3} x the recipe multiplier (1.0 / 1.2 / 1.5).
  * Cat care for each real cat, looked up by instance id and skipped if it has been
    freed: each pet gives -8 overstim (capped at -15 per cat per round) and +2 trust
    (capped at +4, via `add_trust`). A paw assist gives +1 trust. Overstim is clamped to
    0..threshold.
  * A HUD notice via `show_notice`, guarded.
  * Leaving an order pays no money, but pets that already happened still count. Parking
    keeps the order (F11 opens the panel, then "Resume parked order").
* **Result card.** A procedural pixel grade stamp (S "Purr-fect!", A "Great!", B "Good!",
  C "Still tasty!"), time vs par, precision /70 + speed /30, which cats you petted (with
  the overstim/trust delta), stickers and catches, and the money. There is no fail state.
* **Test helpers in the panel.** "Fizz up cats" sets every cafe cat to 45-90% overstim to
  show fizzy and frazzled behaviour. "Bond a cat" sets one cat to trust 75 and calm, to
  show the helper.

## Files

| Path | What |
|---|---|
| `Scenes/MinigameDemos/CounterCats/CounterCatsDemo.tscn` | demo scene: MainLevel3D instance + launcher + overlay |
| `Scripts/minigame_demos/counter_cats/cc_demo.gd` | root: cat picking (guarded), launcher <-> overlay flow, test helpers |
| `.../cc_launcher.gd` | F11 test panel (CanvasLayer 9) |
| `.../cc_overlay.gd` | CanvasLayer 10: pause + dim, cream window, 320x180 SubViewport, HUD, park prompt, result card, rewards |
| `.../cc_game.gd` | the 2D game (MinigameBase-shaped: `setup`, `get_hud_info`, `scored`, `request_park`, `can_park`) |
| `.../cc_counter_cat.gd` | Cat2D + CatPixelPipeline cameo, motion and props |
| `.../cc_recipes.gd` | recipes, judge windows, scoring, caps (pure data/static) |
| `.../cc_art.gd`, `cc_stamp.gd` | palette, ASCII-map pixel sprites with auto #4A3426 outline, grade stamp |
| `Tools/probe_counter_cats.gd` | headless probe (see below) |

## Checks

```bash
G=".../Godot_v4.6-stable_win64_console.exe"
"$G" --headless --path . --quit-after 600 res://Scenes/MinigameDemos/CounterCats/CounterCatsDemo.tscn
"$G" --headless --path . --fixed-fps 60 --script res://Tools/probe_counter_cats.gd   # exit 0 = pass
```

The probe plays 15 rounds through simulated input (`root.push_input` keys and mouse). The
rounds cover:

* good and bad skill on Cozy and Lively
* mouse-only play
* toggle mode with x2 leniency
* the helper cat
* chaos Off
* forced bat and sniff events
* pet spam (cap check)
* park and resume
* leaving an order
* a round where the real cat is freed mid-round

It asserts:

* no softlock
* the tree is paused while open and unpaused after
* rewards are applied exactly once
* the money delta equals the grade payout
* real-cat overstim/trust deltas stay within the caps
* events stay within the cap, are at least 4 s in, at least 5 s apart and telegraphed at least 1 s ahead

## Moving onto the shared MinigameHost later

`cc_game.gd` already follows the `Scripts/minigame/MinigameBase.gd` contract without
extending it: `setup(ctx)`, `get_hud_info()`, `can_park()`, and the signals `scored(result)`
and `request_park`. The result carries `grade` S/A/B/C and `grade_value` 0..1. To port:

1. Change `extends Node2D` to `extends "res://Scripts/minigame/MinigameBase.gd"` and drop
   the duplicate signals. Map `get_hud_info()` keys onto the host's (`steps` -> `stations`,
   `alert`/`hint` -> `hint`/`banner`).
2. Delete `cc_overlay.gd`. The host owns pause, dim, window, SubViewport, park prompt and
   result card. Keep `_apply_rewards()` as the host's (or level's) `finished` handler,
   since it is the only place that touches the real cats and money.
3. Keep `cc_counter_cat.gd` as a generic "cat cameo" component (brushing, laser and nail
   minigames can reuse it). Move `pick_cats()` into the order/context builder.
4. Replace the `popup` signal with the host's float-text API if it has one. The game emits
   positions in 320x180 space.
5. Recipe data in `cc_recipes.gd` could move to `Data/recipes.json` (with a schema) once
   the cooking workflow settles its format.

## Known limits

* There's no audio. The design mentions a "mrrp" on Perfect.
* There's no gamepad mapping (the keyboard covers everything).
* The trace/latte-art verb from the concept isn't in this demo.
* While the overlay is open the HUD is paused too, so a HUD toast that was mid-animation
  freezes until close.
* Bonded cats (trust 70+) become helpers. Starter cats begin at trust 10 (shy), so use
  "Bond a cat" to see the helper path.
