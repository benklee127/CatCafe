# Purr-fect Timing (playable demo)

A cozy rhythm and timing cooking minigame. Each order is a short chain of timing beats and
sweet-spot gauges. The rules are generous, mouse-first and never punishing. The demo runs
in a 2D window over the live (paused) cafe.

## Run it

```powershell
& "C:\Users\benkl\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6-stable_win64.exe" --path C:\workspace\CatCafe res://Scenes/MinigameDemos/PurrfectTiming/PurrfectTimingDemo.tscn
```

The scene instances `res://Scenes/Prototype3D/MainLevel3D.tscn` (unmodified) as the
background. The level is not the current scene, so it never loads or writes the player's save.

## Controls

| Where | Mouse (primary) | Keyboard (optional) |
|---|---|---|
| Test panel | click a recipe | F12 show/hide, 1-4 start a recipe |
| Taps (shot, stamp, beat) | click the play area | Space (also Z / X / J / K / Enter) |
| Steam needle | hold the mouse button, let go in the honey | hold Space |
| Steam needle, toggle mode | click to start, click to stop | Space, Space |
| Oven / tea timer | click the ring | O or Tab |
| Pause card | Pause button | Esc or P (Esc / Space resume) |
| Park order (no loss) | "Park order" on the pause card | - |
| Sound | Sound button | M |
| Result card | click, or the Serve button | Space / Enter / Esc |

## What's in it

- **Four recipes, rising difficulty.** Each takes about 30-40 s for a person; the probe's
  perfect bot needs 26-33 s.
  1. Cafe Latte (84 BPM): grind on the beat, pull a double shot, steam the milk, pour on the beat.
  2. Matcha Whisk (92 BPM): heat the water (gauge), steep the tea (back-burner timer), sift,
     whisk on the beat, steam the milk at a different gauge height.
  3. Paw-Print Cookies (100 BPM): knead, put the first tray in the oven (back burner), stamp
     paws on the next tray, sprinkle on the beat, then collect the oven when it dings.
  4. Catpuccino (104 BPM): quick grind with eighth notes, fast double shot, quick-rising
     milk, then latte art. Each beat adds one foam stroke until 15 strokes make a cat face.
- **Step types** (`Scripts/minigame_demos/purrfect_timing/PTRecipes.gd`):
  - `shot`: a timing bar with a ping-ponging paw marker.
  - `needle`: a sweet-spot gauge.
  - `beat`: notes ride a lane to a paw after a 4-beat count-in.
  - `oven`: a parallel ring timer that you collect when it dings. It never burns. If you
    forget it, a cat takes it out as "ok".
- **Generous windows.** Cozy x1 is ±120 ms Purr-fect and ±220 ms Good. Comfy x1.5 and
  Sleepy x2 multiply both. The oven uses x3 on top. Everything else is "ok" (40% credit).
  There is no miss or fail state.
- **Combos never punish.**
  - The Purr chain counts every Good or better hit in the order and never resets. It pays
    +$1 per 5 hits, up to +$3.
  - "Best combo" (the longest unbroken run) is a brag stat on the result card only.
  - Missed beats auto-resolve as "ok".
  - An idle shot or needle is finished by "the cat" after 7-8 s, also as "ok".
  - Overfilling the gauge makes a soft orange foam puff and lets you try again; a second
    overflow counts as "ok".
- **Result card.**
  - Grade stamp: S ≥ 90%, A ≥ 75%, B ≥ 55%, otherwise C "Still tasty!".
  - Counts for Purr-fect, Good and Ok, plus best combo and the chain bonus.
  - Money = round(price × (0.6 + 0.6 × accuracy)) + chain bonus, so a C still pays.
- **Beat feel.**
  - A visual metronome (4 dots in the top bar).
  - Cats hop on the beat; the right cat answers on the off-beat during beat steps.
  - Pulsing paw target, beat ticks on the lane, steam puffs, paw-print hit markers and
    judgement popups.
- **Optional procedural audio** through AudioStreamGenerator: soft woodblock-like ticks
  (quieter outside beat steps) and pentatonic chimes. Mute it with M, the Sound button or
  the panel; the game is fully playable with visuals only.
- **Cats.** Two decorative cats picked from the cafe's live cats. They use `Cat2D.tscn`
  through its public API only (`apply_genome`, `set_pose(&"sit")`, `set_expression`,
  `set_pixel_art`) and are rendered with the in-game `CatPixelPipeline`.
  Expressions: happy (Purr-fect), smug (Good), sleepy (Ok), surprised (oven ding or foam
  puff). No new cat art.
- **Art.** All placeholder art is procedural pixel art in a 320x180 SubViewport with
  nearest filtering. That includes a 5x7 pixel font, cups, the machine, pitcher, kettle,
  gauge, grinder, bowl and whisk, cookie tray, oven, paw markers and grade stamps.
  - Outlines are #4A3426.
  - Palette: cream #FFF6EA, oak #C9A27A, sage #8FBF9F, honey #E8B04B.
  - Alert orange #E07A3F is used only for the gauge overflow.

## Timing model (fair at any fps)

- **One order clock** (`PTClock.gd`) reads `Time.get_ticks_usec()`.
- **Analytic targets.** Every target is a time on that clock:
  - beat notes sit on the BPM grid
  - bar crossings come from the sweep speed
  - the needle target is hold start + (zone - start level) / rate
  - the oven target is its done time

  Judging compares the input time with the target. It never checks which frame the marker
  overlapped the zone.
- **Input stamping.** The overlay stamps each input in `_input` with `clock.now()` at event
  dispatch. While the window is open it sets `Input.use_accumulated_input = false`.
  `update()` only resolves things that need no input (auto-ok, idle helpers, overflow), so a
  low frame rate can delay a popup but cannot change a grade.
- **Calibration.** The input offset slider (−100..+100 ms) is subtracted from every judged
  input time: + means "my hits land late". For the needle it applies to the release only.
- **Audio sync.** Each synth sample is scheduled at
  `now + queued_frames / mix_rate + AudioServer.get_output_latency()`, so ticks land on the
  same beat grid the visuals use.
- **Godot 4 limitation.** `InputEvent` has no hardware timestamp in Godot 4, so dispatch
  time is the best available. Godot normally flushes input once at the start of a frame, so
  a stamp can be up to one frame late (about 7 ms at 144 fps, 17 ms at 60 fps), well inside
  the windows. Turning on the project setting
  `input_devices/buffering/agile_event_flushing` would tighten this; it is not changed here.

## Pause, park, rewards

- **Opening an order** sets `get_tree().paused = true`. The overlay and test panel use
  `PROCESS_MODE_ALWAYS`. The cafe is dimmed and the cream window covers about 70% of the
  viewport, with an integer pixel scale (3x at 1600x900).
- **Esc** freezes the order clock and shows the pause card. Beat steps restart their
  count-in on resume.
- **Park** hides the window and unpauses the cafe with the clock still frozen. "Resume
  parked" on the panel restarts the current step. Earlier steps keep their judgements, and
  judgements from the half-done step are dropped by tag, so nothing double-counts.
- **Serve** unpauses first (restoring the previous pause state), then pays exactly once.
  It calls `level.add_money(money, "order")` and the `HUD3D.show_notice(...)` toast, both
  guarded with `has_method`.

## Files

```
Scenes/MinigameDemos/PurrfectTiming/PurrfectTimingDemo.tscn   demo scene (cafe + root script)
Scripts/minigame_demos/purrfect_timing/
  PurrfectTimingDemo.gd   wires the panel and overlay to the level
  PTLauncher.gd           F12 test panel (recipes, leniency, sound, hold->toggle, reduced motion, offset)
  PTOverlay.gd            dim + cream window, SubViewport, input capture, pause/park, rewards
  PTGame.gd               step logic, bot hooks, all drawing, decorative cats
  PTJudge.gd              windows, leniency, calibration, score / chain / grade / money (pure)
  PTClock.gd              order clock (real or manual), pause/resume
  PTSynth.gd              AudioStreamGenerator metronome + chimes
  PTRecipes.gd            the four demo recipes
  PTPixel.gd              palette, 5x7 pixel font, pixel shape helpers
Tools/probe_purrfect_timing.gd   headless probe (exit 1 on failure)
```

## Checks

- Headless boot (0 errors or warnings):
  `Godot_v4.6-stable_win64_console.exe --headless --path . --quit-after 600 res://Scenes/MinigameDemos/PurrfectTiming/PurrfectTimingDemo.tscn`
- Probe: `Godot_v4.6-stable_win64_console.exe --headless --path . --script res://Tools/probe_purrfect_timing.gd`
  (197 checks). It covers:
  - window edges at x1 / x1.5 / x2 and the oven scale
  - calibration, both on its own and in full orders
  - the chain never going down
  - perfect, early, late, missed and AFK bot runs on every recipe (no softlock)
  - mixed runs, toggle mode, pause / park / resume
  - real Space, mouse and Esc events
  - a real-clock run with the synth
  - pause state restored and rewards paid exactly once
  - no logged errors from these files

  `-- --force-fail` checks the exit-1 path.

## Moving onto the shared MinigameHost later

`Scripts/minigame/MinigameBase.gd` (owned by the cooking workflow) already matches this shape:
a game node under a 320x180 PlayArea SubViewport, `setup(ctx)`, `get_hud_info()`,
`scored(result)` once, `request_park`, `can_park()` and `get_park_state()`. To port:

1. **Game node.** Make `PTGame.gd` extend `MinigameBase.gd`.
   - In `setup(ctx)`, build the clock, judge and synth from `ctx` (recipe, leniency, offset,
     hold mode, audio) and call `start_order`.
   - Emit `scored(result)` instead of `finished`, keeping the same dictionary (`grade`,
     `counts`, `best_combo`, `chain`, `money`, ...).
2. **HUD info.** `get_hud_info()` returns:
   - `title`: the recipe name
   - `stations`: steps with todo / active / done
   - `burner`: the oven ring progress
   - `hot_streak`: the Purr chain
   - `hint`: the instruction line

   The host can then drop the in-viewport top bar, or keep it.
3. **Input.** Drop `PTOverlay.gd` (dim, window, pause, park, reward). Keep a thin input
   adapter: the host forwards clicks and keys, and each one is stamped with `clock.now()`
   at dispatch.
4. **Park.** `can_park()` returns false only during the result card. The host's
   `process_mode = DISABLED` while parked should be paired with `clock.pause()` /
   `clock.resume()` (hook `NOTIFICATION_DISABLED` / `ENABLED`), followed by
   `restart_current_step()`.
5. **Data.** Move recipes to `Data/recipes.json` using the same step dictionaries
   (`{type, label, look, hits, speed, zone, rate, pattern, duration}`) and add schema
   entries. The grade thresholds already match `MinigameBase.DEFAULT_THRESHOLDS`
   (0.90 / 0.75 / 0.55).
6. **Reuse.** `PTJudge`, `PTClock` and `PTSynth` are self-contained and reusable as-is. That
   is the "cheap, reusable timing tech" the design review liked.

## Known issues / limits

- No hardware input timestamps in Godot 4 (see the timing model).
- Audio latency differs by driver. Use the offset slider; there is no tap-test calibration
  screen yet.
- Recipes are fixed. There is no per-cook randomisation, no Chef's Twist variant and no
  real patron order flow. The test panel stands in for orders.
- The latte art is a fixed cat face; it does not take its coat colours from a cafe cat.
- The two decorative cat SubViewports keep rendering while the window is closed (small
  cost).
