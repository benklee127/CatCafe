extends RefCounted

# CatGenome: JSON-safe description of a cat's look + idle personality.
# No class_name on purpose: preload("res://Scripts/prototype3d/CatGenome.gd").
#
# Every key is optional. normalize() merges over DEFAULT_GENOME, clamps the
# numbers and parses colors. resolve() turns a normalized genome into the
# runtime values Cat2D draws with (Colors, pattern ids, tail preset, ...).
#
# Colors may be Color, "#RRGGBB" / "RRGGBB" strings or [r,g,b(,a)] arrays
# (0..1 floats, or 0..255 ints when any channel is > 1).

const GENOME_VERSION: int = 1
const SCALE_MIN: float = 0.5
const SCALE_MAX: float = 2.0

const DEFAULT_GENOME: Dictionary = {
	"genome_version": GENOME_VERSION,
	"seed": 0,
	"breed": "domestic",
	"coat": "tabby",
	"fur": "short",
	"eye": "amber",
	"tail": "classic",
	"fur_primary": null,
	"fur_secondary": null,
	"eye_color": null,
	"body_scale": [1.0, 1.0],
	"head_size": 1.0,
	"leg_length": 1.0,
	"tail_length": 1.0,
	"tail_thickness": 1.0,
	"ear_size": 1.0,
	# v2 proportion knobs (1.0 = the reference chibi look).
	"body_length": 1.0,
	"body_girth": 1.0,
	"leg_thickness": 1.0,
	"cheek_width": 1.0,
	"neck_fluff": 1.0,
	"haunch_size": 1.0,
	# Fur edge. null = derived from the legacy "fur" key / the style preset.
	"fur_style": null,
	"fur_length": null,
	"fur_density": null,
	"fur_jitter": null,
	"tail_sway_deg": 10.0,
	"tail_sway_speed": 2.2,
	"idle_fidget_rate": 1.0,
	"walk_speed_mult": 1.0,
	# Pixel-art face stamp (CatPixelFace.gd). null = derived from breed/coat/seed.
	"eye_shape": null,
}

# primary = main fur, stripe = darker marking color, belly = light chest/belly,
# accent = second patch / point color, pattern = how markings are drawn.
const COAT_PRESETS: Dictionary = {
	"tabby": {"primary": "#B98A5E", "stripe": "#7A5236", "belly": "#F2E4CF", "accent": "#7A5236", "pattern": "stripes"},
	"ginger": {"primary": "#E8954A", "stripe": "#C46A2B", "belly": "#F7DDBE", "accent": "#C46A2B", "pattern": "stripes"},
	"tuxedo": {"primary": "#383133", "stripe": "#2C2627", "belly": "#FBF8F2", "accent": "#FBF8F2", "pattern": "tuxedo"},
	"calico": {"primary": "#FFF8EE", "stripe": "#E08A3C", "belly": "#FFFDF8", "accent": "#3A3333", "pattern": "patches"},
	"black": {"primary": "#3A3133", "stripe": "#2E2729", "belly": "#4A4042", "accent": "#4A4042", "pattern": "solid"},
	"siamese": {"primary": "#F1E3CC", "stripe": "#E2CDAE", "belly": "#FFF7EA", "accent": "#5A4034", "pattern": "points"},
	"sphynx": {"primary": "#EBC6B4", "stripe": "#D4A08E", "belly": "#F4D8CA", "accent": "#D4A08E", "pattern": "wrinkles"},
}

const EYE_COLORS: Dictionary = {
	"amber": "#F2A93B",
	"green": "#6CC56A",
	"hazel": "#A7944A",
	"gold": "#E8C547",
	"blue": "#5AA7F0",
}

# length / thickness multipliers, fluffy = plume-style wavy outline.
const TAIL_PRESETS: Dictionary = {
	"stubby": {"length": 0.45, "thickness": 1.15, "fluffy": false},
	"classic": {"length": 1.0, "thickness": 1.0, "fluffy": false},
	"long": {"length": 1.3, "thickness": 0.9, "fluffy": false},
	"plume": {"length": 1.1, "thickness": 1.45, "fluffy": true},
}

# Legacy coat length. Only whiskers come from here now; the edge look is
# fur_style (see FUR_STYLES / LEGACY_FUR_STYLE).
const FUR_PRESETS: Dictionary = {
	"none": {"whiskers": 0.5},
	"short": {"whiskers": 1.0},
	"medium": {"whiskers": 1.0},
	"long": {"whiskers": 1.0},
}

# Fur edge styles (Cat2D fur pass). length = tuft amplitude in rig units,
# density = tufts per unit of edge length, jitter = 0..1 randomness.
# flat = clean smooth edge (fur_length is ignored).
const FUR_STYLES: Dictionary = {
	"flat": {"length": 0.0, "density": 0.36, "jitter": 0.3},
	"medium": {"length": 0.9, "density": 0.36, "jitter": 0.4},
	"fuzzy": {"length": 1.5, "density": 0.42, "jitter": 0.6},
}
# Legacy "fur" key -> fur_style when fur_style is not given.
const LEGACY_FUR_STYLE: Dictionary = {"none": "flat", "short": "flat", "medium": "medium", "long": "fuzzy"}

const BREED_PRESETS: Dictionary = {
	"domestic": {},
	"sphynx": {"fur": "none", "fur_style": "flat", "coat": "sphynx", "ear_size": 1.3, "tail_thickness": 0.75, "neck_fluff": 0.0},
	"maine_coon": {"fur": "long", "fur_style": "fuzzy", "tail": "plume", "body_length": 1.2, "body_girth": 1.12, "leg_thickness": 1.15, "neck_fluff": 1.6, "ear_size": 1.1},
}

# Pixel face eye stamps (must equal CatPixelFace.EYE_SHAPES; validate_data
# checks). Unset eye_shape = seeded weighted pick over ALL shapes, with
# breed / coat / trait multipliers from Data/cat_eye_shapes.json
# (EYE_SHAPE_ODDS_FALLBACK when the file is missing).
const EYE_SHAPES: Array[String] = ["round", "big", "almond", "slit", "big_slit", "gentle", "mischievous", "wide"]
# Retired / renamed shapes in old genomes and saves -> current shape.
const EYE_SHAPE_LEGACY: Dictionary = {"sharp": "mischievous", "sparkle": "big", "button": "round"}
const EYE_SHAPE_ODDS_PATH: String = "res://Data/cat_eye_shapes.json"
const EYE_SHAPE_ODDS_FALLBACK: Dictionary = {
	"base": {"round": 1.0, "big": 0.8, "almond": 0.6, "slit": 0.6, "big_slit": 0.4, "gentle": 0.6, "mischievous": 0.5, "wide": 0.55},
	"breed_bias": {"sphynx": {"almond": 4.0, "wide": 3.5}, "maine_coon": {"round": 3.0, "gentle": 3.0}},
	"coat_bias": {"siamese": {"slit": 4.0, "big_slit": 3.0, "almond": 4.0}, "black": {"big": 3.0, "big_slit": 2.5, "slit": 2.5}},
	"trait_bias": {},
}
static var _eye_odds: Dictionary = {}

const COLOR_KEYS: Array[String] = ["fur_primary", "fur_secondary", "eye_color"]
# key -> [min, max]. Clamped so any combination stays attached; Cat2D also
# shrinks a cat that would leave the 192x192 viewport in some pose (fit guard).
const SCALAR_RANGES: Dictionary = {
	"head_size": [0.8, 1.25],
	"leg_length": [0.7, 1.4],
	"tail_length": [0.5, 1.6],
	"tail_thickness": [0.6, 1.6],
	"ear_size": [0.7, 1.45],
	"body_length": [0.8, 1.3],
	"body_girth": [0.8, 1.3],
	"leg_thickness": [0.75, 1.35],
	"cheek_width": [0.8, 1.3],
	"neck_fluff": [0.0, 2.0],
	"haunch_size": [0.75, 1.35],
	"walk_speed_mult": [0.5, 2.0],
	"idle_fidget_rate": [0.5, 2.0],
}
const FUR_RANGES: Dictionary = {
	"fur_length": [0.0, 2.5],
	"fur_density": [0.15, 0.8],
	"fur_jitter": [0.0, 1.0],
}
const BODY_SCALE_RANGE: Array[float] = [0.7, 1.4]
const SCALAR_KEYS: Array[String] = ["head_size", "leg_length", "tail_length", "tail_thickness", "ear_size", "body_length", "body_girth", "leg_thickness", "cheek_width", "neck_fluff", "haunch_size", "walk_speed_mult", "idle_fidget_rate"]

# Accepts Color, "#hex", [r,g,b(,a)] (0..1 or 0..255). Returns fallback otherwise.
static func to_color(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is String or v is StringName:
		var s: String = str(v).strip_edges()
		if s.is_empty():
			return fallback
		if Color.html_is_valid(s):
			return Color.html(s)
		return fallback
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array or v is PackedInt32Array:
		var a: Array = Array(v)
		if a.size() < 3:
			return fallback
		var vals: Array[float] = []
		var over_one: bool = false
		for i in range(mini(a.size(), 4)):
			var f: float = 0.0
			if a[i] is float or a[i] is int:
				f = float(a[i])
			else:
				return fallback
			if f > 1.0:
				over_one = true
			vals.append(f)
		if over_one:
			for i in range(vals.size()):
				vals[i] = vals[i] / 255.0
		var alpha: float = vals[3] if vals.size() > 3 else 1.0
		return Color(clampf(vals[0], 0.0, 1.0), clampf(vals[1], 0.0, 1.0), clampf(vals[2], 0.0, 1.0), clampf(alpha, 0.0, 1.0))
	return fallback

static func _color_to_hex(c: Color) -> String:
	return "#" + c.to_html(false).to_upper()

static func _to_float(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and str(v).is_valid_float():
		return float(str(v))
	return fallback

static func _to_vec2_array(v: Variant, fallback: Array) -> Array:
	if v is Vector2:
		return [v.x, v.y]
	if v is float or v is int:
		return [float(v), float(v)]
	if v is Array and v.size() >= 2:
		return [_to_float(v[0], float(fallback[0])), _to_float(v[1], float(fallback[1]))]
	return fallback.duplicate()

# Pulls the genome out of a cat_def ({genome}/{visual}) or returns the dict itself.
static func extract(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if src.has("visual") and src["visual"] is Dictionary:
		out.merge(src["visual"], true)
	if src.has("genome") and src["genome"] is Dictionary:
		out.merge(src["genome"], true)
	for k in src.keys():
		if k == "visual" or k == "genome":
			continue
		if DEFAULT_GENOME.has(k):
			out[k] = src[k]
	if not out.has("seed") and src.has("seed"):
		out["seed"] = src["seed"]
	if not out.has("seed") and src.has("id"):
		out["seed"] = absi(hash(str(src["id"])))
	return out

# Merge over defaults, clamp scalars, parse colors back to "#RRGGBB" (JSON-safe).
static func normalize(g: Variant) -> Dictionary:
	var src: Dictionary = {}
	if g is Dictionary:
		src = extract(g)
	var out: Dictionary = DEFAULT_GENOME.duplicate(true)
	# Breed presets apply first; explicit keys win.
	var breed: String = str(src.get("breed", out["breed"]))
	if not BREED_PRESETS.has(breed):
		breed = "domestic"
	out.merge(BREED_PRESETS[breed].duplicate(true), true)
	for k in src.keys():
		out[k] = src[k]
	out["breed"] = breed
	# A stored legacy body_scale already includes the breed's size: do not
	# stack the breed's v2 body_length / body_girth on top of it.
	if src.has("body_scale"):
		if not src.has("body_length"):
			out["body_length"] = 1.0
		if not src.has("body_girth"):
			out["body_girth"] = 1.0
	out["genome_version"] = GENOME_VERSION
	out["seed"] = int(_to_float(out.get("seed", 0), 0.0))
	for key in ["coat", "fur", "eye", "tail"]:
		out[key] = str(out[key]) if out[key] != null else str(DEFAULT_GENOME[key])
	if not COAT_PRESETS.has(out["coat"]):
		out["coat"] = DEFAULT_GENOME["coat"]
	if not FUR_PRESETS.has(out["fur"]):
		out["fur"] = DEFAULT_GENOME["fur"]
	if not EYE_COLORS.has(out["eye"]):
		out["eye"] = DEFAULT_GENOME["eye"]
	if not TAIL_PRESETS.has(out["tail"]):
		out["tail"] = DEFAULT_GENOME["tail"]
	for key in COLOR_KEYS:
		var v: Variant = out.get(key, null)
		if v is Array and not v.is_empty() and (v[0] is String):
			# Palette list (visual pool shape): take the first entry.
			v = v[0]
		if v == null:
			out[key] = null
			continue
		var c: Color = to_color(v, Color(0, 0, 0, 0))
		out[key] = _color_to_hex(c) if c.a > 0.0 else null
	for key in SCALAR_KEYS:
		var rng_lim: Array = SCALAR_RANGES[key]
		out[key] = clampf(_to_float(out.get(key, DEFAULT_GENOME[key]), float(DEFAULT_GENOME[key])), float(rng_lim[0]), float(rng_lim[1]))
	var bs: Array = _to_vec2_array(out.get("body_scale", [1.0, 1.0]), [1.0, 1.0])
	out["body_scale"] = [clampf(float(bs[0]), BODY_SCALE_RANGE[0], BODY_SCALE_RANGE[1]), clampf(float(bs[1]), BODY_SCALE_RANGE[0], BODY_SCALE_RANGE[1])]
	# Fur style: explicit fur_style wins, else mapped from the legacy fur key.
	var style: String = str(out.get("fur_style", "")) if out.get("fur_style", null) != null else ""
	if not FUR_STYLES.has(style):
		style = str(LEGACY_FUR_STYLE.get(out["fur"], "flat"))
	out["fur_style"] = style
	var sp: Dictionary = FUR_STYLES[style]
	for key in FUR_RANGES.keys():
		var preset_key: String = str(key).trim_prefix("fur_")
		var lim: Array = FUR_RANGES[key]
		var dv: float = float(sp[preset_key])
		var v: Variant = out.get(key, null)
		out[key] = clampf(_to_float(v, dv) if v != null else dv, float(lim[0]), float(lim[1]))
	var es: Variant = out.get("eye_shape", null)
	if es != null:
		es = legacy_eye_shape(str(es))
	if es == null or not EYE_SHAPES.has(str(es)):
		out["eye_shape"] = pick_eye_shape(breed, str(out["coat"]), int(out["seed"]), [])
	else:
		out["eye_shape"] = str(es)
	out["tail_sway_deg"] = clampf(_to_float(out.get("tail_sway_deg", 10.0), 10.0), 0.0, 40.0)
	out["tail_sway_speed"] = clampf(_to_float(out.get("tail_sway_speed", 2.2), 2.2), 0.2, 10.0)
	return out

# Current name of an eye shape (maps retired / renamed shapes, EYE_SHAPE_LEGACY).
static func legacy_eye_shape(shape: String) -> String:
	return str(EYE_SHAPE_LEGACY.get(shape, shape))

# Eye shape odds table (Data/cat_eye_shapes.json, cached; fallback const).
static func eye_shape_odds() -> Dictionary:
	if _eye_odds.is_empty():
		_eye_odds = EYE_SHAPE_ODDS_FALLBACK
		if FileAccess.file_exists(EYE_SHAPE_ODDS_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EYE_SHAPE_ODDS_PATH))
			if parsed is Dictionary and (parsed as Dictionary).get("base", null) is Dictionary:
				_eye_odds = parsed
	return _eye_odds

# Final weight of every shape for a breed / coat / trait list.
static func eye_shape_weights(breed: String, coat: String, trait_ids: Array = []) -> Dictionary:
	var odds: Dictionary = eye_shape_odds()
	var base: Dictionary = odds.get("base", {})
	var mults: Array = []
	var bb: Dictionary = odds.get("breed_bias", {})
	if bb.get(breed, null) is Dictionary:
		mults.append(bb[breed])
	var cb: Dictionary = odds.get("coat_bias", {})
	if cb.get(coat, null) is Dictionary:
		mults.append(cb[coat])
	var tb: Dictionary = odds.get("trait_bias", {})
	for t in trait_ids:
		if tb.get(str(t), null) is Dictionary:
			mults.append(tb[str(t)])
	var out: Dictionary = {}
	for k in EYE_SHAPES:
		var w: float = maxf(0.0, _to_float(base.get(k, 0.0), 0.0))
		for m in mults:
			w *= maxf(0.0, _to_float((m as Dictionary).get(k, 1.0), 1.0))
		out[k] = w
	return out

# Deterministic weighted pick (own rng stream: same seed + inputs = same shape).
static func pick_eye_shape(breed: String, coat: String, seed: int, trait_ids: Array = []) -> String:
	var w: Dictionary = eye_shape_weights(breed, coat, trait_ids)
	var total: float = 0.0
	for k in EYE_SHAPES:
		total += float(w[k])
	if total <= 0.0:
		return "round"
	var r := RandomNumberGenerator.new()
	r.seed = seed * 69069 + 40503
	var roll: float = r.randf() * total
	for k in EYE_SHAPES:
		roll -= float(w[k])
		if roll < 0.0:
			return k
	return EYE_SHAPES[EYE_SHAPES.size() - 1]

# Legacy name: the seeded pick without traits.
static func default_eye_shape(breed: String, coat: String, seed: int) -> String:
	return pick_eye_shape(breed, coat, seed, [])

# Runtime values for drawing. Input should be normalize()d.
static func resolve(n: Dictionary) -> Dictionary:
	var coat: Dictionary = COAT_PRESETS.get(n.get("coat", "tabby"), COAT_PRESETS["tabby"])
	var pattern: String = str(coat["pattern"])
	var primary: Color = to_color(coat["primary"])
	var stripe: Color = to_color(coat["stripe"])
	var belly: Color = to_color(coat["belly"])
	var accent: Color = to_color(coat["accent"])
	if n.get("fur_primary", null) != null:
		primary = to_color(n["fur_primary"], primary)
		if pattern == "stripes":
			stripe = primary.darkened(0.3)
		elif pattern == "solid":
			belly = primary.lightened(0.12)
		elif pattern == "wrinkles":
			stripe = primary.darkened(0.12)
	if n.get("fur_secondary", null) != null:
		var sec: Color = to_color(n["fur_secondary"], accent)
		match pattern:
			"stripes":
				# Darker secondary = stripe color, lighter = belly/chest cream.
				if sec.get_luminance() < primary.get_luminance():
					stripe = sec
				else:
					belly = sec
			"tuxedo":
				belly = sec
				accent = sec
			"patches":
				if sec.get_luminance() < 0.3:
					accent = sec
				else:
					stripe = sec
			"points":
				accent = sec
			"solid":
				belly = sec
			"wrinkles":
				stripe = sec
			_:
				accent = sec
	var eye: Color = to_color(EYE_COLORS.get(n.get("eye", "amber"), EYE_COLORS["amber"]))
	if n.get("eye_color", null) != null:
		eye = to_color(n["eye_color"], eye)
	var tail_preset: Dictionary = TAIL_PRESETS.get(n.get("tail", "classic"), TAIL_PRESETS["classic"])
	var fur_preset: Dictionary = FUR_PRESETS.get(n.get("fur", "short"), FUR_PRESETS["short"])
	var dark_coat: bool = primary.get_luminance() < 0.25
	var bs: Array = n.get("body_scale", [1.0, 1.0])
	var style: String = str(n.get("fur_style", LEGACY_FUR_STYLE.get(n.get("fur", "short"), "flat")))
	if not FUR_STYLES.has(style):
		style = "flat"
	var fur_len: float = float(n.get("fur_length", FUR_STYLES[style]["length"]))
	if style == "flat":
		fur_len = 0.0
	return {
		"pattern": pattern,
		"primary": primary,
		"stripe": stripe,
		"belly": belly,
		"accent": accent,
		"eye": eye,
		"outline": primary.darkened(0.6).lerp(Color("#3A2620"), 0.5) if not dark_coat else Color("#1C1312"),
		"inner_ear": Color("#F4A7A8") if pattern != "points" else Color("#B98C80"),
		"nose": Color("#F28E9B") if pattern != "points" else Color("#7A5248"),
		"blush": Color(1.0, 0.55, 0.6, 0.33 if not dark_coat else 0.22),
		"whisker": Color(0.92, 0.86, 0.8, 0.6) if dark_coat else Color(0.3, 0.2, 0.16, 0.5),
		"dark_coat": dark_coat,
		"whiskers": float(fur_preset["whiskers"]),
		"fur_style": style,
		"fur_length": fur_len,
		"fur_density": float(n.get("fur_density", FUR_STYLES[style]["density"])),
		"fur_jitter": float(n.get("fur_jitter", FUR_STYLES[style]["jitter"])),
		"tail_length": clampf(float(tail_preset["length"]) * float(n.get("tail_length", 1.0)), 0.4, 1.6),
		"tail_thickness": clampf(float(tail_preset["thickness"]) * float(n.get("tail_thickness", 1.0)), 0.55, 1.9),
		"tail_fluffy": bool(tail_preset["fluffy"]) or style == "fuzzy",
		# Legacy body_scale multiplies the v2 body_length / body_girth knobs.
		"body_scale": Vector2(float(bs[0]) * float(n.get("body_length", 1.0)), float(bs[1]) * float(n.get("body_girth", 1.0))),
		"head_size": float(n.get("head_size", 1.0)),
		"leg_length": float(n.get("leg_length", 1.0)),
		"leg_thickness": float(n.get("leg_thickness", 1.0)),
		"cheek_width": float(n.get("cheek_width", 1.0)),
		"neck_fluff": float(n.get("neck_fluff", 1.0)),
		"haunch_size": float(n.get("haunch_size", 1.0)),
		"ear_size": float(n.get("ear_size", 1.0)),
		"seed": int(n.get("seed", 0)),
		"eye_shape": legacy_eye_shape(str(n.get("eye_shape", "round"))) if EYE_SHAPES.has(legacy_eye_shape(str(n.get("eye_shape", "")))) else "round",
		# Pixel face mouth stamp: seeded ":3" or "w" (CatPixelFace.MOUTHS).
		"mouth": ":3" if posmod(int(n.get("seed", 0)) * 1103515245 + 12345, 7) < 3 else "w",
	}

static func _pick(rng: RandomNumberGenerator, v: Variant) -> Variant:
	if v is Array:
		if v.is_empty():
			return null
		return v[rng.randi_range(0, v.size() - 1)]
	return v

static func _range(rng: RandomNumberGenerator, props: Dictionary, key: String, lo: float, hi: float) -> float:
	var r: Variant = props.get(key, null)
	if r is Array and r.size() >= 2:
		lo = _to_float(r[0], lo)
		hi = _to_float(r[1], hi)
	if hi < lo:
		var t: float = lo
		lo = hi
		hi = t
	return rng.randf_range(lo, hi)

# Builds a per-cat genome from a visual pool entry. Deterministic for a given seed.
# Builds a per-cat genome from a visual pool entry. Deterministic for a given seed.
# The first rng stream keeps its pre-v2 draw order (colors, base proportions),
# so existing seeds keep their colors. The v2 shape/fur knobs come from a
# second stream. Rarity widens the spread (common 1.0, uncommon 1.3, rare 1.6)
# and makes fuzzy fur more likely.
const RARITY_SPREAD: Dictionary = {"common": 1.0, "uncommon": 1.3, "rare": 1.6}
const DEFAULT_FUR_STYLE_WEIGHTS: Dictionary = {
	"none": {"flat": 1.0},
	"short": {"flat": 0.62, "medium": 0.32, "fuzzy": 0.06},
	"medium": {"flat": 0.2, "medium": 0.6, "fuzzy": 0.2},
	"long": {"medium": 0.4, "fuzzy": 0.6},
}

static func from_visual(visual: Dictionary, seed: int, rarity: String = "common", trait_ids: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g: Dictionary = {
		"genome_version": GENOME_VERSION,
		"seed": seed,
		"breed": str(visual.get("breed", "domestic")),
		"coat": str(visual.get("coat", "tabby")),
		"fur": str(visual.get("fur", "short")),
		"eye": str(visual.get("eye", "amber")),
		"tail": str(visual.get("tail", "classic")),
	}
	var p: Variant = _pick(rng, visual.get("fur_primary", null))
	if p != null:
		g["fur_primary"] = _color_to_hex(to_color(p))
	var s: Variant = _pick(rng, visual.get("fur_secondary", null))
	if s != null:
		g["fur_secondary"] = _color_to_hex(to_color(s))
	if visual.has("eye_color"):
		g["eye_color"] = _color_to_hex(to_color(_pick(rng, visual["eye_color"])))
	if visual.has("eye_shape"):
		# Pool override: a shape or a list of shapes (seeded pick, own stream so
		# the colour/proportion draws above keep their order).
		var er := RandomNumberGenerator.new()
		er.seed = seed * 40503 + 7
		var es: Variant = _pick(er, visual["eye_shape"])
		if es != null and EYE_SHAPES.has(legacy_eye_shape(str(es))):
			g["eye_shape"] = legacy_eye_shape(str(es))
	var props: Dictionary = visual.get("proportions", {}) if visual.get("proportions", {}) is Dictionary else {}
	var body: float = _range(rng, props, "body", 0.94, 1.08)
	g["body_length"] = snappedf(body * rng.randf_range(0.97, 1.04), 0.001)
	g["body_girth"] = snappedf(body * rng.randf_range(0.95, 1.05), 0.001)
	g["head_size"] = snappedf(_range(rng, props, "head", 0.92, 1.12), 0.001)
	g["leg_length"] = snappedf(_range(rng, props, "leg", 0.9, 1.1), 0.001)
	g["tail_length"] = snappedf(_range(rng, props, "tail", 0.9, 1.15), 0.001)
	g["tail_thickness"] = snappedf(rng.randf_range(0.92, 1.08), 0.001)
	g["ear_size"] = snappedf(rng.randf_range(0.92, 1.1), 0.001)
	g["tail_sway_deg"] = snappedf(rng.randf_range(6.0, 14.0), 0.01)
	g["tail_sway_speed"] = snappedf(rng.randf_range(1.6, 2.8), 0.01)
	g["idle_fidget_rate"] = snappedf(rng.randf_range(0.7, 1.4), 0.01)
	g["walk_speed_mult"] = snappedf(rng.randf_range(0.92, 1.08), 0.001)

	# ---- v2 shape + fur stream.
	var r2 := RandomNumberGenerator.new()
	r2.seed = seed * 2654435761 + 97
	var spread: float = float(RARITY_SPREAD.get(rarity, 1.0))
	var weights: Variant = visual.get("fur_styles", null)
	if not (weights is Dictionary) or (weights as Dictionary).is_empty():
		weights = DEFAULT_FUR_STYLE_WEIGHTS.get(g["fur"], DEFAULT_FUR_STYLE_WEIGHTS["short"])
	var style: String = _weighted(r2, weights, spread)
	# Chibi correlation: shorter legs -> slightly bigger head.
	var leg: float = float(g["leg_length"])
	g["head_size"] = snappedf(float(g["head_size"]) + (1.0 - leg) * 0.3, 0.001)
	var girth: float = float(g["body_girth"])
	g["leg_thickness"] = _jit(r2, props, "leg_thickness", 1.0 + (girth - 1.0) * 0.6, 0.07, spread)
	g["haunch_size"] = _jit(r2, props, "haunch", 1.0 + (girth - 1.0) * 0.5, 0.08, spread)
	g["cheek_width"] = _jit(r2, props, "cheek", 1.06 if style == "fuzzy" else 1.0, 0.07, spread)
	g["ear_size"] = snappedf(float(g["ear_size"]) + r2.randf_range(-0.04, 0.04) * spread, 0.001)
	var nf_c: float = 0.6 if style == "flat" else (1.0 if style == "medium" else 1.4)
	g["neck_fluff"] = _jit(r2, props, "neck_fluff", nf_c, 0.25, spread)
	var fl_c: float = 0.0 if style == "flat" else (0.85 if style == "medium" else 1.5)
	g["fur_style"] = style
	g["fur_length"] = _jit(r2, props, "fur_length", fl_c, 0.2 if style != "flat" else 0.0, spread)
	g["fur_density"] = snappedf(r2.randf_range(0.3, 0.44), 0.001)
	g["fur_jitter"] = snappedf(r2.randf_range(0.25, 0.65), 0.001)

	# Breeds lean into their silhouette.
	match g["breed"]:
		"sphynx":
			g["fur"] = "none"
			g["fur_style"] = "flat"
			g["fur_length"] = 0.0
			g["coat"] = "sphynx"
			g["ear_size"] = snappedf(rng.randf_range(1.25, 1.4), 0.001)
			g["tail_thickness"] = snappedf(r2.randf_range(0.68, 0.8), 0.001)
			g["leg_thickness"] = snappedf(r2.randf_range(0.85, 0.94), 0.001)
			g["body_girth"] = snappedf(r2.randf_range(0.88, 0.96), 0.001)
			g["cheek_width"] = snappedf(r2.randf_range(0.88, 0.96), 0.001)
			g["neck_fluff"] = 0.0
		"maine_coon":
			g["fur"] = "long"
			g["fur_style"] = "fuzzy"
			g["tail"] = "plume"
			g["body_length"] = snappedf(clampf(float(g["body_length"]), 1.12, 1.24), 0.001)
			g["body_girth"] = snappedf(r2.randf_range(1.06, 1.16), 0.001)
			g["leg_thickness"] = snappedf(r2.randf_range(1.1, 1.22), 0.001)
			g["haunch_size"] = snappedf(r2.randf_range(1.08, 1.2), 0.001)
			g["cheek_width"] = snappedf(r2.randf_range(1.1, 1.2), 0.001)
			g["neck_fluff"] = snappedf(r2.randf_range(1.4, 1.9), 0.001)
			g["fur_length"] = snappedf(r2.randf_range(1.6, 2.1), 0.001)
			g["fur_density"] = snappedf(r2.randf_range(0.38, 0.48), 0.001)
			g["ear_size"] = snappedf(rng.randf_range(1.05, 1.2), 0.001)
	if rarity == "rare" and g["breed"] == "domestic":
		g["tail_sway_deg"] = snappedf(float(g["tail_sway_deg"]) * 1.2, 0.01)
	# Eye shape: pool list (above) wins, else the weighted breed/coat/trait pick.
	if not g.has("eye_shape"):
		g["eye_shape"] = pick_eye_shape(str(g["breed"]), str(g["coat"]), seed, trait_ids)
	return normalize(g)

# center +- half * spread (or the pool's proportions[key] range, widened by spread).
static func _jit(r: RandomNumberGenerator, props: Dictionary, key: String, center: float, half: float, spread: float) -> float:
	var range_v: Variant = props.get(key, null)
	if range_v is Array and range_v.size() >= 2:
		var lo: float = _to_float(range_v[0], center - half)
		var hi: float = _to_float(range_v[1], center + half)
		center = (lo + hi) * 0.5
		half = absf(hi - lo) * 0.5
	return snappedf(center + r.randf_range(-half, half) * spread, 0.001)

static func _weighted(r: RandomNumberGenerator, weights: Dictionary, spread: float) -> String:
	var total: float = 0.0
	var w: Dictionary = {}
	for k in ["flat", "medium", "fuzzy"]:
		var v: float = maxf(0.0, _to_float(weights.get(k, 0.0), 0.0))
		if k == "fuzzy":
			v *= 1.0 + (spread - 1.0) * 2.0
		w[k] = v
		total += v
	if total <= 0.0:
		return "flat"
	var roll: float = r.randf() * total
	for k in ["flat", "medium", "fuzzy"]:
		roll -= float(w[k])
		if roll < 0.0:
			return k
	return "flat"
