extends SceneTree

# Eye contact / spacing check on RENDERED faces (needs a window, not --headless).
#   godot --path . --script res://Tools/check_eye_contacts.gd -- <sheet_png> [suite=all|focus|full|random]
#
# Every case is rendered twice: normally (focus suite only, for the sheet) and
# with Cat2D.feature_ids on, where each face feature is a flat id colour and the
# pixel cases go through CatPixelPipeline exactly like in game (so outline
# pixels added by the mask-outline pass count). Then every eye pixel (near or
# far eye footprint: stamp, lid lines, lashes, arcs, tear) is checked against
# its 8 neighbours. A contact is an eye pixel touching: the other eye, the head
# / ear outline, empty space, the nose/mouth, a whisker or an expression mark.
# Inner gap = fur columns between the two eyes' footprints (whole face bbox).
#   pixel: gap >= CatPixelFace.MIN_EYE_GAP_PX[bucket] art px
#   smooth: gap / head size >= CatPixelFace.MIN_EYE_GAP_UNITS (rig units)
# Suites:
#   focus   big_slit/almond/big/slit/wide x open/happy/angry/sad/surprised x
#           56/80/smooth x fuzzy ginger / small head / big head  (+ sheet)
#   full    all shapes x all expressions x 56/80/smooth x the 3 genomes
#   xs      all shapes x all expressions x 56/80 x the 3 genomes with the
#           compact fallback stamps forced (Cat2D.debug_stamp_bucket = "XS" / "XXS")
#   dens    (separate run) all shapes x all expressions x 48/64/96 x the 3 genomes
#   random  40 CatFactory seeds x 56/80 x all expressions, cycling the four
#           poses and facing left / right
#   pupils  black / tuxedo (fuzzy) / siamese (blue eyes) x all shapes x all
#           expressions x 56/80/smooth, plus the same at 56/80 with the XS /
#           XXS fallback stamps forced
# Prints a gap table and "EYE CONTACT CHECK PASS|FAIL"; exits 1 on failure.
# (Add --strict-pupils after the suite to also exit 1 on a pupil failure.)
#
# PUPIL VISIBILITY (every case whose eyes are open, i.e. not closed / happy /
# blink / sleeping): the id render also splits each eye into part ids
# (Cat2D.feature_eye_parts: line+lid / pupil (or bead) / iris+white / glint)
# and a second, normal render gives the real colours. Per eye:
#   size        pupil bbox >= PUPIL_MIN_PX[stamp bucket] (W x H art px) and
#               pupil + glints inside its bbox >= W*H pixels; smooth: bbox >=
#               PUPIL_MIN_UNITS x head size (rig units). Slit pupils: SLIT_MIN.
#   separation  no pupil pixel has an eye-line / lid pixel directly left,
#               right or below it (the top may touch the lid)
#   glint       >= 1 glint pixel inside the pupil bbox or touching the pupil
#   contrast    WCAG ratio of the mean rendered pupil colour vs the iris
#               touching it >= PUPIL_MIN_CONTRAST (bead eyes have no iris:
#               skipped). Pupil vs the fur around the eye is reported only.
#   lid cover   smooth lid expressions keep >= SMOOTH_LID_KEEP of the same
#               cat's open-eye pupil area visible.
# Prints a per-shape pupil table and "PUPIL VISIBILITY CHECK PASS|FAIL".

const Cat2DScene := preload("res://Scenes/Prototype3D/Cat2D.tscn")
const CatFactoryScript := preload("res://Scripts/data/CatFactory.gd")
const DataLoaderScript := preload("res://Scripts/data/DataLoader.gd")
const CatPixelPipelineScript := preload("res://Scripts/prototype3d/CatPixelPipeline.gd")
const CatPixelFaceScript := preload("res://Scripts/prototype3d/CatPixelFace.gd")
const Cat2DScript := preload("res://Scripts/prototype3d/Cat2D.gd")

const VIEW_UNITS: float = 76.8
const FOOT_FRAC: float = 182.0 / 192.0
const SMOOTH_N: int = 384
const FOCUS_SHAPES: Array[String] = ["big_slit", "almond", "big", "slit", "wide"]
const FOCUS_EXPRS: Array[String] = ["open", "happy", "angry", "sad", "surprised"]
const MODES: Array = [56, 80, 0]    # 0 = smooth
const GENOMES: Array = [
	["fuzzy ginger", {"coat": "ginger", "fur": "long", "fur_style": "fuzzy", "fur_length": 2.0, "tail": "plume", "eye": "amber", "seed": 31}],
	["small head", {"coat": "tabby", "fur": "short", "eye": "green", "head_size": 0.8, "cheek_width": 0.8, "seed": 32}],
	["big head", {"coat": "tabby", "fur": "short", "eye": "green", "head_size": 1.25, "cheek_width": 1.3, "seed": 33}],
]
# Extra genomes for the pupil suite (dark coats, blue eyes).
const PUPIL_GENOMES: Array = [
	["black", {"coat": "black", "fur": "short", "eye": "gold", "seed": 42}],
	["tuxedo fuzzy", {"coat": "tuxedo", "fur": "long", "fur_style": "fuzzy", "fur_length": 2.0, "tail": "plume", "eye": "amber", "seed": 41}],
	["siamese", {"coat": "siamese", "fur": "short", "eye": "blue", "seed": 43}],
]
const PUPIL_MIN_PX: Dictionary = {"L": [4, 4], "M": [3, 3], "S": [2, 2], "XS": [2, 1], "XXS": [1, 1]}
const SLIT_MIN: Dictionary = {"L": [2, 4], "M": [2, 3], "S": [2, 2], "XS": [1, 2], "XXS": [1, 1]}
const PUPIL_MIN_UNITS: Array = [2.0, 2.0]
const SLIT_MIN_UNITS: Array = [1.2, 2.0]
const PUPIL_MIN_CONTRAST: float = 2.0
const SMOOTH_LID_KEEP: float = 0.45
const LID_EXPRS: Array[String] = ["angry", "sleepy", "smug", "sad", "worried"]
const CROP: Rect2 = Rect2(0.46, 0.33, 0.46, 0.43)
const CELL: int = 120
const BATCH: int = 80

enum {EMPTY, FUR, NEAR, FAR, MOUTH, WHISKER, MARK, OUTLINE}
# Eye part codes (pupil metric): eye line / lid, pupil, iris, glint; + side * 4.
enum {P_LINE, P_PUPIL, P_IRIS, P_GLINT}
const KIND_NAMES: Array[String] = ["empty", "fur", "near", "far", "mouth", "whisker", "mark", "outline"]

var _out: String = "user://eyes_fix_check.png"
var _suite: String = "all"
# The pupil visibility metric is unfinished: it is reported but only fails the
# run (exit 1) with the --strict-pupils user arg.
var _strict_pupils: bool = false
var _jobs: Array = []
var _live: Array = []
var _next: int = 0
var _wait: int = 0
var _results: Array = []
var _sheet_cells: Dictionary = {}
var _phase: int = 0
var _sheet_vp: SubViewport
var _sheet_wait: int = 0

func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() >= 1:
		_out = a[0]
	_strict_pupils = a.has("--strict-pupils")
	if a.size() >= 2 and a[1] != "--strict-pupils":
		_suite = a[1]
	if _suite in ["all", "focus"]:
		for gi in range(GENOMES.size()):
			for shape in FOCUS_SHAPES:
				for ex in FOCUS_EXPRS:
					for m in MODES:
						var g: Dictionary = GENOMES[gi][1].duplicate()
						g["eye_shape"] = shape
						_jobs.append({"group": "focus", "genome": g, "gname": GENOMES[gi][0], "shape": shape, "expr": ex, "mode": m, "sheet": true,
							"row": gi * FOCUS_SHAPES.size() + FOCUS_SHAPES.find(shape), "col": FOCUS_EXPRS.find(ex) * MODES.size() + MODES.find(m)})
	if _suite in ["all", "full"]:
		for gi in range(GENOMES.size()):
			for shape in CatPixelFaceScript.EYE_SHAPES:
				for ex in CatPixelFaceScript.EXPRESSIONS:
					for m in MODES:
						var g: Dictionary = GENOMES[gi][1].duplicate()
						g["eye_shape"] = shape
						_jobs.append({"group": "full", "genome": g, "gname": GENOMES[gi][0], "shape": shape, "expr": ex, "mode": m, "sheet": false,
							"left": CatPixelFaceScript.EXPRESSIONS.find(ex) % 2 == 1})
	if _suite in ["dens"]:
		# The other supported densities (48 / 64 / 96), facing alternating.
		for gi in range(GENOMES.size()):
			for shape in CatPixelFaceScript.EYE_SHAPES:
				for xi in range(CatPixelFaceScript.EXPRESSIONS.size()):
					for m in [48, 64, 96]:
						var g: Dictionary = GENOMES[gi][1].duplicate()
						g["eye_shape"] = shape
						_jobs.append({"group": "dens", "genome": g, "gname": GENOMES[gi][0], "shape": shape, "expr": CatPixelFaceScript.EXPRESSIONS[xi], "mode": m, "sheet": false, "left": xi % 2 == 0})
	if _suite in ["all", "xs"]:
		for gi in range(GENOMES.size()):
			for shape in CatPixelFaceScript.EYE_SHAPES:
				for ex in CatPixelFaceScript.EXPRESSIONS:
					for m in [56, 80]:
						for st in ["XS", "XXS"]:
							var g: Dictionary = GENOMES[gi][1].duplicate()
							g["eye_shape"] = shape
							_jobs.append({"group": "xs", "genome": g, "gname": GENOMES[gi][0], "shape": shape + "/" + st, "expr": ex, "mode": m, "sheet": false, "stamp": st})
	if _suite in ["all", "pupils"]:
		for gi in range(PUPIL_GENOMES.size()):
			for shape in CatPixelFaceScript.EYE_SHAPES:
				for xi in range(CatPixelFaceScript.EXPRESSIONS.size()):
					var ex: String = CatPixelFaceScript.EXPRESSIONS[xi]
					for m in MODES:
						var g: Dictionary = PUPIL_GENOMES[gi][1].duplicate()
						g["eye_shape"] = shape
						_jobs.append({"group": "pupils", "genome": g, "gname": PUPIL_GENOMES[gi][0], "shape": shape, "expr": ex, "mode": m, "sheet": false, "left": xi % 2 == 1})
					for m in [56, 80]:
						for st in ["XS", "XXS"]:
							var g2: Dictionary = PUPIL_GENOMES[gi][1].duplicate()
							g2["eye_shape"] = shape
							_jobs.append({"group": "pupils", "genome": g2, "gname": PUPIL_GENOMES[gi][0], "shape": shape + "/" + st, "expr": ex, "mode": m, "sheet": false, "stamp": st})
	if _suite in ["all", "random"]:
		var loader: Node = DataLoaderScript.new()
		var data: Dictionary = loader.load_all_data()
		loader.free()
		var factory = CatFactoryScript.new(data)
		for i in range(40):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + i * 7919
			var def: Dictionary = factory.generate_cat(rng, i)
			var g: Dictionary = def.get("genome", {})
			for xi in range(CatPixelFaceScript.EXPRESSIONS.size()):
				var ex: String = CatPixelFaceScript.EXPRESSIONS[xi]
				for m in [56, 80]:
					_jobs.append({"group": "random", "genome": g, "gname": "seed%d" % (1000 + i * 7919), "shape": str(g.get("eye_shape", "")), "expr": ex, "mode": m, "sheet": false,
						"pose": [&"idle", &"walk", &"sit", &"sleep"][(i + xi) % 4], "left": (i + xi) % 2 == 1})
	print("eye contact check: %d cases (%s)" % [_jobs.size(), _suite])

func _make(job: Dictionary, ids: bool) -> Dictionary:
	var pixel: bool = int(job["mode"]) > 0
	var n: int = int(job["mode"]) if pixel else SMOOTH_N
	var sub := SubViewport.new()
	sub.size = Vector2i(n, n)
	sub.transparent_bg = true
	sub.disable_3d = true
	sub.msaa_2d = Viewport.MSAA_4X if (not pixel and not ids) else Viewport.MSAA_DISABLED
	sub.snap_2d_transforms_to_pixel = pixel
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var cat: Node2D = Cat2DScene.instantiate()
	cat.position = Vector2(n / 2, roundf(float(n) * FOOT_FRAC))
	cat.scale = Vector2.ONE * float(n) / VIEW_UNITS
	cat.set("pixel_art", pixel)
	cat.set("animate", false)
	cat.set("feature_ids", ids)
	cat.set("feature_eye_parts", ids)
	cat.set("debug_stamp_bucket", str(job.get("stamp", "")))
	sub.add_child(cat)
	cat.apply_genome(job["genome"])
	cat.call("set_pixel_art", pixel)
	cat.set_pose(job.get("pose", &"idle"))
	cat.set_facing_left(bool(job.get("left", false)))
	if job.get("pose", &"idle") == &"walk":
		cat.set_move_speed(1.0)
	cat.call("set_expression", job["expr"])
	var pipe: Node = null
	if pixel:
		pipe = CatPixelPipelineScript.new()
		pipe.call("setup", root, sub, cat)
		pipe.call("set_pixel", true)
	return {"sub": sub, "pipe": pipe, "cat": cat, "n": n, "pixel": pixel}

func _image(r: Dictionary) -> Image:
	var tex: Texture2D = r["pipe"].call("get_texture") if r["pipe"] != null else r["sub"].get_texture()
	return tex.get_image()

func _free(r: Dictionary) -> void:
	if r["pipe"] != null:
		r["pipe"].queue_free()
	r["sub"].queue_free()

func _kind(c: Color) -> int:
	if c.a < 0.5:
		return EMPTY
	var ids: Array = [[Cat2DScript.FID_NEAR, NEAR], [Cat2DScript.FID_FAR, FAR],
		[Cat2DScript.FID_PUPIL[0], NEAR], [Cat2DScript.FID_PUPIL[1], FAR], [Cat2DScript.FID_IRIS[0], NEAR], [Cat2DScript.FID_IRIS[1], FAR],
		[Cat2DScript.FID_GLINT[0], NEAR], [Cat2DScript.FID_GLINT[1], FAR], [Cat2DScript.FID_MOUTH, MOUTH],
		[Cat2DScript.FID_WHISKER, WHISKER], [Cat2DScript.FID_MARK, MARK], [Cat2DScript.FID_OUTLINE, OUTLINE]]
	for e in ids:
		var f: Color = e[0]
		if absf(c.r - f.r) < 0.06 and absf(c.g - f.g) < 0.06 and absf(c.b - f.b) < 0.06:
			return e[1]
	return FUR

# -> {contacts: {"near-outline": k, ...}, gap: px, near: count, far: count}
func _analyze(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var k: PackedInt32Array = PackedInt32Array()
	k.resize(w * h)
	var parts: PackedInt32Array = PackedInt32Array()
	parts.resize(w * h)
	var min_near: int = 1 << 20
	var max_near: int = -1
	var min_far: int = 1 << 20
	var max_far: int = -1
	var n_near: int = 0
	var n_far: int = 0
	for y in range(h):
		for x in range(w):
			var px: Color = img.get_pixel(x, y)
			var kk: int = _kind(px)
			k[y * w + x] = kk
			parts[y * w + x] = _part_code(px) if (kk == NEAR or kk == FAR) else -1
			if kk == NEAR:
				n_near += 1
				min_near = mini(min_near, x)
				max_near = maxi(max_near, x)
			elif kk == FAR:
				n_far += 1
				min_far = mini(min_far, x)
				max_far = maxi(max_far, x)
	var contacts: Dictionary = {}
	for y in range(h):
		for x in range(w):
			var me: int = k[y * w + x]
			if me != NEAR and me != FAR:
				continue
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var xx: int = x + dx
					var yy: int = y + dy
					var other: int = EMPTY
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						other = k[yy * w + xx]
					if other == FUR or other == me:
						continue
					if me == FAR and other == NEAR:
						continue   # counted once from the near side
					var key: String = "%s-%s" % [KIND_NAMES[me], KIND_NAMES[other]]
					contacts[key] = int(contacts.get(key, 0)) + 1
	var gap: int = 999
	if n_near > 0 and n_far > 0:
		# Facing right the near eye is on the right; facing left, on the left.
		gap = (min_near - max_far - 1) if min_near > min_far else (min_far - max_near - 1)
	return {"contacts": contacts, "gap": gap, "near": n_near, "far": n_far, "k": k, "parts": parts, "w": w, "h": h}

# Eye part code of an id pixel: side * 4 + P_LINE / P_PUPIL / P_IRIS / P_GLINT.
func _part_code(c: Color) -> int:
	for side in range(2):
		var ids: Array = [[Cat2DScript.FID_PUPIL[side], P_PUPIL], [Cat2DScript.FID_IRIS[side], P_IRIS], [Cat2DScript.FID_GLINT[side], P_GLINT],
			[Cat2DScript.FID_NEAR if side == 0 else Cat2DScript.FID_FAR, P_LINE]]
		for e in ids:
			var f: Color = e[0]
			if absf(c.r - f.r) < 0.06 and absf(c.g - f.g) < 0.06 and absf(c.b - f.b) < 0.06:
				return side * 4 + int(e[1])
	return -1

static func _lum(c: Color) -> float:
	var l: Color = c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b

static func _ratio(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)

# Pupil metric for one rendered case (both eyes). Empty dict = eyes not open.
func _pupil_case(e: Dictionary, res: Dictionary, hs: float) -> Dictionary:
	var job: Dictionary = e["job"]
	var cat: Node2D = e["ids"]["cat"]
	var pixel: bool = bool(e["ids"]["pixel"])
	var ex: String = str(job["expr"])
	if pixel:
		ex = str(cat.call("_pixel_expression"))
	elif bool(cat.get("_eyes_closed")):
		ex = "closed"
	if ex in ["closed", "happy"]:
		return {}
	var pal: Dictionary = cat.get("_pal")
	var shape: String = str(pal.get("eye_shape", "round"))
	var bucket: String = "smooth"
	if pixel:
		bucket = CatPixelFaceScript.base_set(str(cat.call("_pixel_face_layout")["stamp_bucket"]))
	var vis: Image = _image(e["vis"])
	var n: int = int(e["ids"]["n"])
	var eyes: Array = []
	for side in range(2):
		eyes.append(_pupil_eye(res, vis, side, pixel))
	var mins: Array
	var upx: float = VIEW_UNITS / float(n) / maxf(0.01, hs)   # rig units / head size per render px
	if pixel:
		mins = (SLIT_MIN if shape in ["slit", "big_slit"] else PUPIL_MIN_PX)[bucket]
	else:
		mins = SLIT_MIN_UNITS if shape in ["slit", "big_slit"] else PUPIL_MIN_UNITS
	var why: Array = []
	for side in range(2):
		var m: Dictionary = eyes[side]
		var bw: float = float(m["bw"]) * (1.0 if pixel else upx)
		var bh: float = float(m["bh"]) * (1.0 if pixel else upx)
		m["bw_u"] = bw
		m["bh_u"] = bh
		var small: bool = int(m["n"]) == 0 or bw < float(mins[0]) - 0.001 or bh < float(mins[1]) - 0.001
		if pixel and int(m["vis"]) < int(mins[0]) * int(mins[1]):
			small = true
		if small and not why.has("size"):
			why.append("size")
		if int(m["sep"]) > 0 and not why.has("sep"):
			why.append("sep")
		if not bool(m["glint"]) and not why.has("glint"):
			why.append("glint")
		if float(m["c_iris"]) >= 0.0 and float(m["c_iris"]) < PUPIL_MIN_CONTRAST and not why.has("contrast"):
			why.append("contrast")
	var area: float = (float(eyes[0]["n"]) + float(eyes[1]["n"])) * 0.5 * (1.0 if pixel else upx * upx)
	return {"eyes": eyes, "bucket": bucket, "shape": shape, "expr": ex, "fail": why, "area": area}

func _pupil_eye(res: Dictionary, vis: Image, side: int, pixel: bool) -> Dictionary:
	var parts: PackedInt32Array = res["parts"]
	var k: PackedInt32Array = res["k"]
	var w: int = res["w"]
	var h: int = res["h"]
	var base: int = side * 4
	var pup: Array = []
	var eye_px: Array = []
	var x0: int = 1 << 20
	var y0: int = 1 << 20
	var x1: int = -1
	var y1: int = -1
	for i in range(w * h):
		var pc: int = parts[i]
		if pc < base or pc >= base + 4:
			continue
		eye_px.append(i)
		if pc == base + P_PUPIL:
			pup.append(i)
			var x: int = i % w
			var y: int = i / w
			x0 = mini(x0, x)
			x1 = maxi(x1, x)
			y0 = mini(y0, y)
			y1 = maxi(y1, y)
	var out: Dictionary = {"n": pup.size(), "bw": 0, "bh": 0, "vis": 0, "sep": 0, "glint": false, "c_iris": -1.0, "c_fur": -1.0, "fur_adj": 0}
	if pup.is_empty():
		return out
	out["bw"] = x1 - x0 + 1
	out["bh"] = y1 - y0 + 1
	var vis_n: int = pup.size()
	var glint: bool = false
	for i in eye_px:
		if parts[i] != base + P_GLINT:
			continue
		var x: int = i % w
		var y: int = i / w
		if x >= x0 and x <= x1 and y >= y0 and y <= y1:
			vis_n += 1
			glint = true
	var sep: int = 0
	var fur_adj: int = 0
	var iris_adj: Dictionary = {}
	var core: Array = []
	for i in pup:
		var x: int = i % w
		var y: int = i / w
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var xx: int = x + d.x
			var yy: int = y + d.y
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var q: int = parts[yy * w + xx]
			if q == P_LINE or q == 4 + P_LINE:
				sep += 1
			elif q < 0 and k[yy * w + xx] == FUR:
				fur_adj += 1
		var all_p: bool = true
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var xx: int = x + dx
				var yy: int = y + dy
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					all_p = false
					continue
				var q: int = parts[yy * w + xx]
				if q != base + P_PUPIL:
					all_p = false
				if q == base + P_GLINT:
					glint = true
				if q == base + P_IRIS:
					iris_adj[yy * w + xx] = true
		if all_p:
			core.append(i)
	out["vis"] = vis_n
	out["sep"] = sep
	out["glint"] = glint
	out["fur_adj"] = fur_adj
	# Rendered colours: pupil (smooth: core pixels, away from antialiasing)
	# vs the iris around it vs the fur around the eye.
	var pl: Array = core if (not pixel and core.size() >= 3) else pup
	var lp: float = 0.0
	for i in pl:
		lp += _lum(vis.get_pixel(i % w, i / w))
	lp /= float(pl.size())
	var iris_px: Array = []
	if pixel:
		iris_px = iris_adj.keys()
	else:
		# Iris pixels within 3 px of the pupil whose 8 neighbours are iris.
		var seen: Dictionary = {}
		for i in pup:
			var x: int = i % w
			var y: int = i / w
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var xx: int = x + dx
					var yy: int = y + dy
					if xx < 1 or yy < 1 or xx >= w - 1 or yy >= h - 1:
						continue
					var j: int = yy * w + xx
					if seen.has(j) or parts[j] != base + P_IRIS:
						continue
					seen[j] = true
					var ok: bool = true
					for ey in [-1, 0, 1]:
						for ex2 in [-1, 0, 1]:
							if parts[(yy + ey) * w + xx + ex2] != base + P_IRIS:
								ok = false
					if ok:
						iris_px.append(j)
		if iris_px.is_empty():
			iris_px = iris_adj.keys()
	if not iris_px.is_empty():
		var li: float = 0.0
		for i in iris_px:
			li += _lum(vis.get_pixel(int(i) % w, int(i) / w))
		li /= float(iris_px.size())
		out["c_iris"] = _ratio(lp, li)
	# Fur ring around the eye footprint (pixel: 1-2 px out; smooth: 3-4 px).
	var r0: int = 1 if pixel else 3
	var r1: int = 2 if pixel else 4
	var fur_seen: Dictionary = {}
	var lf: float = 0.0
	for i in eye_px:
		var x: int = i % w
		var y: int = i / w
		for dy in [-r1, -r0, 0, r0, r1]:
			for dx in [-r1, -r0, 0, r0, r1]:
				var xx: int = x + dx
				var yy: int = y + dy
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var j: int = yy * w + xx
				if k[j] != FUR or fur_seen.has(j):
					continue
				fur_seen[j] = true
				lf += _lum(vis.get_pixel(xx, yy))
	if not fur_seen.is_empty():
		out["c_fur"] = _ratio(lp, lf / float(fur_seen.size()))
	return out


func _process(_d: float) -> bool:
	if _phase == 0:
		if _live.is_empty():
			if _next >= _jobs.size():
				_phase = 1
				_build_sheet()
				return false
			var end: int = mini(_next + BATCH, _jobs.size())
			for i in range(_next, end):
				var job: Dictionary = _jobs[i]
				var entry: Dictionary = {"job": job, "ids": _make(job, true)}
				if bool(job["sheet"]) or not (str(job["expr"]) in ["closed", "happy"]):
					entry["vis"] = _make(job, false)
				_live.append(entry)
			_next = end
			_wait = 5
			return false
		_wait -= 1
		if _wait > 0:
			return false
		for e in _live:
			var job: Dictionary = e["job"]
			var res: Dictionary = _analyze(_image(e["ids"]))
			var pixel: bool = int(job["mode"]) > 0
			var n: int = e["ids"]["n"]
			var units: float = float(res["gap"]) * VIEW_UNITS / float(n)
			var hs: float = float(e["ids"]["cat"].get("_hs"))
			var min_gap: float = float(CatPixelFaceScript.min_eye_gap(str(e["ids"]["cat"].call("_pixel_face_layout")["bucket"]))) if pixel else CatPixelFaceScript.MIN_EYE_GAP_UNITS
			var gap_v: float = float(res["gap"]) if pixel else units / maxf(0.01, hs)
			var fail: bool = not (res["contacts"] as Dictionary).is_empty() or gap_v < min_gap
			if res["near"] == 0 or res["far"] == 0:
				fail = true
			var pup: Dictionary = {}
			if e.has("vis"):
				pup = _pupil_case(e, res, hs)
			_results.append({"job": job, "res": res, "gap": gap_v, "min": min_gap, "fail": fail, "pupil": pup})
			if e.has("vis") and bool(job["sheet"]):
				var img: Image = _image(e["vis"])
				var rect := Rect2i((Vector2(n, n) * CROP.position).floor(), (Vector2(n, n) * CROP.size).floor())
				var crop: Image = img.get_region(rect)
				crop.resize(CELL, int(float(CELL) * float(rect.size.y) / float(rect.size.x)), Image.INTERPOLATE_NEAREST if pixel else Image.INTERPOLATE_BILINEAR)
				_sheet_cells[[int(job["row"]), int(job["col"])]] = [crop, gap_v, fail]
			if e.has("vis"):
				_free(e["vis"])
			_free(e["ids"])
		_live.clear()
		return false
	if _phase == 1:
		_sheet_wait -= 1
		if _sheet_wait > 0:
			return false
		if _sheet_vp != null:
			_sheet_vp.get_texture().get_image().save_png(_out)
			print("Saved %s" % _out)
		return _report()
	return true

func _build_sheet() -> void:
	if _sheet_cells.is_empty():
		_sheet_wait = 1
		return
	var rows: int = GENOMES.size() * FOCUS_SHAPES.size()
	var cols: int = FOCUS_EXPRS.size() * MODES.size()
	var ch: int = CELL + 16
	_sheet_vp = SubViewport.new()
	_sheet_vp.size = Vector2i(cols * CELL + 110, rows * ch + 20)
	_sheet_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sheet_vp)
	var bg := ColorRect.new()
	bg.color = Color("#F3E6D6")
	bg.size = Vector2(_sheet_vp.size)
	_sheet_vp.add_child(bg)
	for c in range(cols):
		var m: int = MODES[c % MODES.size()]
		_label("%s %s" % [FOCUS_EXPRS[c / MODES.size()], ("%dpx" % m) if m > 0 else "smooth"], Vector2(110 + c * CELL + 2, 2), Color(0.25, 0.18, 0.15))
	for r in range(rows):
		_label("%s\n%s" % [FOCUS_SHAPES[r % FOCUS_SHAPES.size()], GENOMES[r / FOCUS_SHAPES.size()][0]], Vector2(4, 20 + r * ch + 40), Color(0.25, 0.18, 0.15))
	for key in _sheet_cells.keys():
		var v: Array = _sheet_cells[key]
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(v[0])
		tr.position = Vector2(110 + int(key[1]) * CELL, 20 + int(key[0]) * ch)
		_sheet_vp.add_child(tr)
		var mode: int = MODES[int(key[1]) % MODES.size()]
		_label(("gap %d" % int(v[1])) if mode > 0 else ("gap %.1fu" % float(v[1])), tr.position + Vector2(2, float(ch) - 18), Color(0.75, 0.1, 0.1) if bool(v[2]) else Color(0.2, 0.45, 0.2))
	_sheet_wait = 4

func _label(t: String, p: Vector2, col: Color) -> void:
	var l := Label.new()
	l.text = t
	l.position = p
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col)
	_sheet_vp.add_child(l)

func _report() -> bool:
	# Gap table: min gap per shape x mode (over genomes / expressions / groups).
	var table: Dictionary = {}
	var contacts_total: int = 0
	var contact_kinds: Dictionary = {}
	var fails: Array = []
	for r in _results:
		var job: Dictionary = r["job"]
		var mode: int = int(job["mode"])
		var key: String = "%s|%s" % [job["shape"], ("%dpx" % mode) if mode > 0 else "smooth"]
		var cur: Array = table.get(key, [INF, 0, 0])
		cur[0] = minf(float(cur[0]), float(r["gap"]))
		cur[1] = int(cur[1]) + 1
		var cn: int = 0
		for ck in (r["res"]["contacts"] as Dictionary).keys():
			cn += int(r["res"]["contacts"][ck])
			contact_kinds[ck] = int(contact_kinds.get(ck, 0)) + int(r["res"]["contacts"][ck])
		cur[2] = int(cur[2]) + (1 if bool(r["fail"]) else 0)
		table[key] = cur
		contacts_total += cn
		if bool(r["fail"]):
			fails.append(r)
	print("shape      mode     cases  min_gap  failing")
	var keys: Array = table.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = str(key).split("|")
		var v: Array = table[key]
		print("%-10s %-8s %5d  %7.1f  %d" % [parts[0], parts[1], int(v[1]), float(v[0]), int(v[2])])
	print("contact pixels by kind: %s" % str(contact_kinds))
	var by_shape: Dictionary = {}
	for r in _results:
		var sk: String = str(r["job"]["shape"])
		var cc: int = 0
		for ck in (r["res"]["contacts"] as Dictionary).keys():
			cc += int(r["res"]["contacts"][ck])
		by_shape[sk] = int(by_shape.get(sk, 0)) + cc
	print("contact pixels by shape: %s" % str(by_shape))
	var shown: int = 0
	for r in fails:
		if shown >= 60:
			break
		var job: Dictionary = r["job"]
		print("  FAIL %s %s %s %s mode=%s gap=%.1f (min %.1f) contacts=%s" % [job["group"], job["gname"], job["shape"], job["expr"], str(job["mode"]), float(r["gap"]), float(r["min"]), str(r["res"]["contacts"])])
		shown += 1
	print("cases %d, failing cases %d, contact pixels %d" % [_results.size(), fails.size(), contacts_total])
	var pupils_ok: bool = _pupil_report()
	print("EYE CONTACT CHECK %s" % ("PASS" if fails.is_empty() else "FAIL"))
	print("PUPIL VISIBILITY CHECK %s%s" % ["PASS" if pupils_ok else "FAIL", "" if _strict_pupils else " (informational: the pupil metric is unfinished; pass --strict-pupils to gate the exit code on it)"])
	quit(0 if (fails.is_empty() and (pupils_ok or not _strict_pupils)) else 1)
	return true

# Pupil visibility tables; returns true when no open-eye case fails.
func _pupil_report() -> bool:
	var modes: Array[String] = ["56px", "80px", "smooth"]
	var by: Dictionary = {}        # shape -> mode -> stats
	var buckets: Dictionary = {}   # shape -> stamp bucket -> min box
	var open_area: Dictionary = {}
	var fails: Array = []
	var n_cases: int = 0
	for r in _results:
		var pm: Dictionary = r.get("pupil", {})
		if pm.is_empty():
			continue
		n_cases += 1
		var job: Dictionary = r["job"]
		var mode: int = int(job["mode"])
		var mk: String = ("%dpx" % mode) if mode > 0 else "smooth"
		if not modes.has(mk):
			modes.append(mk)
		var shape: String = str(pm["shape"])
		var st: Dictionary = (by.get(shape, {}) as Dictionary).get(mk, {"cases": 0, "min_n": 1 << 30, "box": [999.0, 999.0], "size": 0, "sep": 0, "glint": 0, "contrast": 0, "lid": 0, "c_iris": 999.0, "c_fur": 999.0})
		st["cases"] = int(st["cases"]) + 1
		for e in pm["eyes"]:
			st["min_n"] = mini(int(st["min_n"]), int(e["n"]))
			if float(e["bw_u"]) * float(e["bh_u"]) < float(st["box"][0]) * float(st["box"][1]):
				st["box"] = [float(e["bw_u"]), float(e["bh_u"])]
			if float(e["c_iris"]) >= 0.0:
				st["c_iris"] = minf(float(st["c_iris"]), float(e["c_iris"]))
			if float(e["c_fur"]) >= 0.0:
				st["c_fur"] = minf(float(st["c_fur"]), float(e["c_fur"]))
			if mode > 0:
				var bk: String = str(pm["bucket"])
				var bd: Dictionary = buckets.get(shape, {})
				var cur: Array = bd.get(bk, [999, 999, 1 << 30])
				if int(e["bw"]) * int(e["bh"]) < int(cur[0]) * int(cur[1]):
					cur = [int(e["bw"]), int(e["bh"]), cur[2]]
				cur[2] = mini(int(cur[2]), int(e["n"]))
				bd[bk] = cur
				buckets[shape] = bd
		for f in pm["fail"]:
			st[f] = int(st[f]) + 1
		if not (pm["fail"] as Array).is_empty():
			fails.append(r)
		if not by.has(shape):
			by[shape] = {}
		by[shape][mk] = st
		if mode == 0 and str(pm["expr"]) == "open":
			open_area["%s|%s" % [job["gname"], shape]] = float(pm["area"])
	# Smooth lid cover: lidded pupil area vs the same cat's open pupil area.
	for r in _results:
		var pm: Dictionary = r.get("pupil", {})
		if pm.is_empty() or int(r["job"]["mode"]) != 0 or not LID_EXPRS.has(str(pm["expr"])):
			continue
		var key: String = "%s|%s" % [r["job"]["gname"], pm["shape"]]
		if not open_area.has(key):
			continue
		var keep: float = float(pm["area"]) / maxf(0.0001, float(open_area[key]))
		pm["keep"] = keep
		var st: Dictionary = by[pm["shape"]]["smooth"]
		st["min_keep"] = minf(float(st.get("min_keep", 9.0)), keep)
		if keep < SMOOTH_LID_KEEP:
			st["lid"] = int(st["lid"]) + 1
			if (pm["fail"] as Array).is_empty():
				fails.append(r)
			(pm["fail"] as Array).append("lid")
	print("")
	print("PUPIL VISIBILITY (%d open-eye cases). Per eye: min pupil px / min pupil box (px, smooth: rig units / head size)," % n_cases)
	print("min contrast pupil:iris and pupil:fur, smooth min lid keep, failing cases by reason (size/sep/glint/contrast/lid)")
	var shapes: Array = by.keys()
	shapes.sort()
	print("%-8s %-6s %5s %6s %9s %6s %6s %5s  %s" % ["shape", "mode", "cases", "min_px", "min_box", "c_iris", "c_fur", "keep", "fails"])
	for shape in shapes:
		for mk in modes:
			if not (by[shape] as Dictionary).has(mk):
				continue
			var st: Dictionary = by[shape][mk]
			var box: Array = st["box"]
			var bs: String = ("%dx%d" % [int(box[0]), int(box[1])]) if mk != "smooth" else ("%.1fx%.1f" % [float(box[0]), float(box[1])])
			print("%-8s %-6s %5d %6d %9s %6.2f %6.2f %5s  size %d sep %d glint %d contrast %d lid %d" % [shape, mk, int(st["cases"]), int(st["min_n"]), bs,
				float(st["c_iris"]) if float(st["c_iris"]) < 900.0 else -1.0, float(st["c_fur"]) if float(st["c_fur"]) < 900.0 else -1.0,
				("%.2f" % float(st["min_keep"])) if st.has("min_keep") else "-", int(st["size"]), int(st["sep"]), int(st["glint"]), int(st["contrast"]), int(st["lid"])])
	print("min pupil box (px) / min pupil px per stamp set:")
	for shape in shapes:
		var line: String = "  %-8s" % shape
		for bk in ["L", "M", "S", "XS", "XXS"]:
			var bd: Dictionary = buckets.get(shape, {})
			if bd.has(bk):
				line += "  %s %dx%d/%d" % [bk, int(bd[bk][0]), int(bd[bk][1]), int(bd[bk][2])]
		print(line)
	var shown: int = 0
	for r in fails:
		if shown >= 60:
			break
		var job: Dictionary = r["job"]
		var pm: Dictionary = r["pupil"]
		var ed: Array = []
		for e in pm["eyes"]:
			ed.append("n%d %dx%d sep%d g%s c%.2f" % [int(e["n"]), int(e["bw"]), int(e["bh"]), int(e["sep"]), "y" if bool(e["glint"]) else "n", float(e["c_iris"])])
		print("  PUPIL FAIL %s %s %s %s mode=%s set=%s %s %s%s" % [job["group"], job["gname"], job["shape"], pm["expr"], str(job["mode"]), pm["bucket"], str(pm["fail"]), " | ".join(ed),
			(" keep %.2f" % float(pm["keep"])) if pm.has("keep") else ""])
		shown += 1
	print("pupil cases %d, failing %d" % [n_cases, fails.size()])
	return fails.is_empty()
