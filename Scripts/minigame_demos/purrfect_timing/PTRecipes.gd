extends RefCounted

## Purr-fect Timing demo recipes (rising difficulty). Data lives here, not in Data/, because
## this is a self-contained demo (see Docs/minigames/PURRFECT_TIMING.md for the JSON shape
## it would take in Data/recipes.json later).
##
## Step types:
##   shot   timing bar: a paw marker ping-pongs across a bar; tap when it crosses the honey
##          zone. hits = taps needed, speed = bar widths per second, zone = 0..1 centre.
##   needle sweet-spot gauge: hold (or click-to-start/stop) to raise the needle at `rate`
##          gauge/s, let go in the honey band at `zone`. Over the top = soft foam puff, retry.
##   beat   gentle cafe beat: notes ride a lane to the paw; tap on the beat. pattern chars are
##          eighth notes ("x" = note, "." = rest) at the recipe bpm, after a 4-beat count-in.
##   oven   back-burner ring timer (parallel): starts, then the next step runs; collect it
##          (click the ring / O / Tab) when it dings. Never burns.
## `look` picks the station art.

static func all() -> Array:
	return [
		{
			"id": "cafe_latte", "name": "Cafe Latte", "tier": 1, "price": 6, "bpm": 84,
			"blurb": "Grind, pull, steam, pour. A gentle first order.",
			"steps": [
				{"type": "beat", "label": "GRIND THE BEANS", "pattern": "x.x.x.x.x.x.x...", "look": "grind"},
				{"type": "shot", "label": "PULL THE SHOT", "hits": 2, "speed": 0.62, "zone": 0.6, "look": "espresso"},
				{"type": "needle", "label": "STEAM THE MILK", "zone": 0.68, "rate": 0.4, "look": "milk"},
				{"type": "beat", "label": "POUR ON THE BEAT", "pattern": "x.x.x.x.x.x.x...x.x.x.x.x...x...", "look": "pour"},
			],
		},
		{
			"id": "matcha_whisk", "name": "Matcha Whisk", "tier": 2, "price": 7, "bpm": 92,
			"blurb": "Two gauges at different heights, a steeping pot and a whisk groove.",
			"steps": [
				{"type": "needle", "label": "HEAT THE WATER", "zone": 0.55, "rate": 0.46, "look": "kettle"},
				{"type": "oven", "label": "STEEP THE TEA!", "duration": 9.0, "look": "tea"},
				{"type": "shot", "label": "SIFT THE MATCHA", "hits": 2, "speed": 0.75, "zone": 0.42, "look": "sift"},
				{"type": "beat", "label": "WHISK THE MATCHA", "pattern": "x.x.x.x.x.x.xx..x.x.x.x.x.xx....", "look": "whisk"},
				{"type": "needle", "label": "STEAM THE MILK", "zone": 0.78, "rate": 0.5, "look": "milk"},
			],
		},
		{
			"id": "pawprint_cookies", "name": "Paw-Print Cookies", "tier": 3, "price": 8, "bpm": 100,
			"blurb": "Knead, then stamp and sprinkle the next tray while the first one bakes.",
			"steps": [
				{"type": "beat", "label": "KNEAD THE DOUGH", "pattern": "x.x.x.x.xx.xx...x.x.x.x.x.xx....", "look": "knead"},
				{"type": "oven", "label": "FIRST TRAY IN!", "duration": 10.0, "look": "cookie"},
				{"type": "shot", "label": "STAMP THE PAWS", "hits": 3, "speed": 0.8, "zone": 0.5, "look": "stamp"},
				{"type": "beat", "label": "SPRINKLE THE TOPS", "pattern": "x.x.x.xxx.x.x.xx", "look": "sprinkle"},
			],
		},
		{
			"id": "catpuccino", "name": "Catpuccino", "tier": 4, "price": 10, "bpm": 104,
			"blurb": "Quick grind, quick shots, hot milk and latte art, one stroke per beat.",
			"steps": [
				{"type": "beat", "label": "GRIND THE BEANS", "pattern": "x.x.xxx.x.x.xxx.", "look": "grind"},
				{"type": "shot", "label": "PULL A DOUBLE", "hits": 2, "speed": 0.95, "zone": 0.64, "look": "espresso"},
				{"type": "needle", "label": "STEAM THE MILK", "zone": 0.66, "rate": 0.58, "look": "milk"},
				{"type": "beat", "label": "DRAW THE LATTE CAT", "pattern": "x.x.x.x.x.xxx...x.x.x.xxx.x.....", "look": "art"},
			],
		},
	]
