extends SceneTree

# Renders Cat2D sheets to PNG for visual regression checks (needs a window, not --headless).
#
# Seed sheet (6x4 grid of CatFactory seeds, in-game framing):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> [first_seed=1] [pose=idle|walk|sit|sleep] [rarity filter]
#   Each cell is 192x192 with Cat2D at (96,182), scale 2.5: the same framing the
#   in-game Cat3D SubViewport uses, so anything clipped here clips in game too.
#
# Reference lineup (the six art-direction coats, large, 3x2 like the reference sheet):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> ref6 [pose=idle] [scale=6]
#   ginger tabby, calico, tuxedo / grey tabby, siamese, black. Always faces right
#   (pose "left" mirrors all of them).
#
# Walk phase strip (each of the WALK_PHASES frames of one coat, frozen):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> phases [coat_index 0..5] [scale=4]
#
# Random kitties (24 CatFactory cats, in-game framing at 1.5x, label shows breed/fur;
# the last two columns are forced uncommon / rare):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> random [first_seed=1] [pose=idle]
#
# Fur comparison (one cat: rows flat/medium/fuzzy, columns fur_length 0.8/1.5/2.2):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> fur [pose=idle] [scale=4]
#
# Extremes (min and max of every proportion/fur knob, plus all-min/all-max,
# in-game framing at 1.25x so clipping shows; label shows the fit-guard scale):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> extremes [pose=idle]
#
# Pixel-art sheets (each cat rendered at the in-game low-res density, then upscaled
# with nearest filtering, exactly like the in-game Sprite3D path):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> pixel [ref6|random|seeds] [pose=idle] [density=56] [zoom=auto] [first_seed=1]
#   density = the Cat3D pixel_density (viewport edge in art pixels for the 76.8-unit window).
#   Every pixel cell goes through CatPixelPipeline.gd (layered mask outline), like in game.
#   Extra pixel sets:
#     faces  rows = every eye shape (CatPixelFace.EYE_SHAPES) at the given density
#            (no density arg = 56 and 80 stacked); columns = every expression
#            + blink (ginger tabby). Cells are zoomed head crops. Prints
#            CatPixelFace.validate().
#     faces_coats  same rows; columns = old vs new eye spacing, then black /
#            siamese / tuxedo with a few expressions.
#     pupils rows = every eye shape x dark coats (tuxedo / black / ginger;
#            env PUPIL_COATS=tuxedo,black narrows it), columns = the open-eye
#            expressions. Smooth version: faces pupils.
#
# Smooth face sheets (same rows/columns, smooth renderer, head crops):
#   godot --path . --script res://Tools/render_cat_seeds.gd -- <out_png> faces [coats]
#     fur    rows = flat / medium / fuzzy, columns = fur_length 0.8 / 1.5 / 2.2
#     poses  rows = idle / walk / sit / sleep, columns = the six reference coats

const Cat2DScene := preload("res://Scenes/Prototype3D/Cat2D.tscn")
const CatFactoryScript := preload("res://Scripts/data/CatFactory.gd")
const CatGenomeScript := preload("res://Scripts/prototype3d/CatGenome.gd")
const DataLoaderScript := preload("res://Scripts/data/DataLoader.gd")
const CatPixelPipelineScript := preload("res://Scripts/prototype3d/CatPixelPipeline.gd")
const CatPixelFaceScript := preload("res://Scripts/prototype3d/CatPixelFace.gd")

const VIEW_UNITS: float = 76.8   # Cat2D units across the in-game viewport (192 / 2.5)
const FOOT_FRAC: float = 182.0 / 192.0
const COLS: int = 6
const ROWS: int = 4
const CELL: int = 192

const REF6: Array[Dictionary] = [
	{"coat": "ginger", "fur": "short", "tail": "classic", "eye": "amber", "seed": 11, "_label": "ginger tabby"},
	{"coat": "calico", "fur": "short", "tail": "classic", "eye": "amber", "seed": 12, "_label": "calico"},
	{"coat": "tuxedo", "fur": "short", "tail": "classic", "eye": "amber", "seed": 13, "_label": "tuxedo"},
	{"coat": "tabby", "fur": "short", "tail": "classic", "eye": "amber", "seed": 14, "fur_primary": "#9A948D", "fur_secondary": "#5F5853", "_label": "grey tabby"},
	{"coat": "siamese", "fur": "short", "tail": "classic", "eye": "blue", "seed": 15, "_label": "siamese"},
	{"coat": "black", "fur": "short", "tail": "classic", "eye": "amber", "seed": 16, "_label": "black"},
]

var _out_path: String = "user://cat_seeds.png"
var _mode: String = "seeds"
var _first_seed: int = 1
var _pose: StringName = &"idle"
var _rarity_filter: String = ""
var _scale: float = 6.0
var _coat_index: int = 0
var _frames_left: int = 30
var _vp: SubViewport
var _cats: Array[Node2D] = []
var _fit_labels: Array = []
var _pixel_set: String = "ref6"
var _density: int = 56
var _zoom: int = 0
var _density_given: bool = false
var _face_coats: bool = false

const EXTREME_KEYS: Array[String] = ["body_length", "body_girth", "leg_length", "leg_thickness", "tail_length", "tail_thickness", "head_size", "cheek_width", "ear_size", "neck_fluff", "haunch_size", "fur_length", "fur_density", "fur_jitter"]
const EXTREME_BASE: Dictionary = {"coat": "ginger", "fur": "medium", "fur_style": "medium", "fur_length": 1.0, "tail": "classic", "eye": "amber", "seed": 21}

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_path = args[0]
	if args.size() >= 2:
		if args[1] in ["ref6", "phases", "random", "fur", "extremes", "pixel", "faces"]:
			_mode = args[1]
		else:
			_first_seed = int(args[1])
	match _mode:
		"ref6":
			if args.size() >= 3:
				_pose = StringName(args[2])
			if args.size() >= 4:
				_scale = float(args[3])
			_build_ref6()
		"phases":
			if args.size() >= 3:
				_coat_index = clampi(int(args[2]), 0, REF6.size() - 1)
			_scale = 4.0
			if args.size() >= 4:
				_scale = float(args[3])
			_build_phases()
		"random":
			if args.size() >= 3:
				_first_seed = int(args[2])
			if args.size() >= 4:
				_pose = StringName(args[3])
			_build_random()
		"fur":
			if args.size() >= 3:
				_pose = StringName(args[2])
			_scale = 4.0
			if args.size() >= 4:
				_scale = float(args[3])
			_build_fur()
		"extremes":
			if args.size() >= 3:
				_pose = StringName(args[2])
			_build_extremes()
		"faces":
			_face_coats = args.size() >= 3 and args[2] == "coats"
			if args.size() >= 3 and args[2] == "pupils":
				_build_pupil_faces(false, 384)
			else:
				_build_smooth_faces()
		"pixel":
			if args.size() >= 3:
				_pixel_set = args[2]
			if args.size() >= 4:
				_pose = StringName(args[3])
			if args.size() >= 5:
				_density = maxi(16, int(args[4]))
				_density_given = true
			if args.size() >= 6:
				_zoom = int(args[5])
			if args.size() >= 7:
				_first_seed = int(args[6])
			_build_pixel()
		_:
			if args.size() >= 3:
				_pose = StringName(args[2])
			if args.size() >= 4:
				_rarity_filter = args[3]
			_build_seeds()

func _make_vp(size: Vector2i) -> void:
	_vp = SubViewport.new()
	_vp.size = size
	_vp.transparent_bg = false
	_vp.disable_3d = true
	_vp.msaa_2d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color("#F3E6D6")
	bg.size = Vector2(_vp.size)
	_vp.add_child(bg)

func _add_label(text: String, pos: Vector2, size: int = 11) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.25, 0.18, 0.15))
	_vp.add_child(label)

func _genome_of(d: Dictionary) -> Dictionary:
	var g: Dictionary = d.duplicate()
	g.erase("_label")
	return g

func _build_ref6() -> void:
	var cw: int = int(68.0 * _scale)
	var chh: int = int(64.0 * _scale)
	_make_vp(Vector2i(cw * 3, chh * 2))
	for i in range(REF6.size()):
		var cx: int = (i % 3) * cw
		var cy: int = (i / 3) * chh
		var cat: Node2D = Cat2DScene.instantiate()
		cat.position = Vector2(cx + cw * 0.5, cy + chh - 6.0 * _scale)
		cat.scale = Vector2.ONE * _scale
		_vp.add_child(cat)
		cat.apply_genome(_genome_of(REF6[i]))
		var p: StringName = _pose
		if p == &"left":
			p = &"idle"
			cat.set_facing_left(true)
		cat.set_pose(p)
		if p == &"walk":
			cat.set_move_speed(1.0)
		_cats.append(cat)
		_add_label(str(REF6[i]["_label"]), Vector2(cx + 6, cy + 4), 14)

func _build_phases() -> void:
	var n: int = 8
	var cw: int = int(64.0 * _scale)
	var chh: int = int(64.0 * _scale)
	_make_vp(Vector2i(cw * 4, chh * (n / 4)))
	for i in range(n):
		var cx: int = (i % 4) * cw
		var cy: int = (i / 4) * chh
		var cat: Node2D = Cat2DScene.instantiate()
		cat.position = Vector2(cx + cw * 0.5, cy + chh - 6.0 * _scale)
		cat.scale = Vector2.ONE * _scale
		_vp.add_child(cat)
		cat.apply_genome(_genome_of(REF6[_coat_index]))
		cat.set_pose(&"walk")
		cat.set_move_speed(1.0)
		cat.set_meta("phase_index", i)
		_cats.append(cat)
		_add_label("phase %d" % i, Vector2(cx + 6, cy + 4), 14)
		var ground := ColorRect.new()
		ground.color = Color(0.5, 0.35, 0.25, 0.25)
		ground.position = Vector2(cx, cy + chh - 6.0 * _scale)
		ground.size = Vector2(cw, 1)
		_vp.add_child(ground)

func _build_seeds() -> void:
	var loader: Node = DataLoaderScript.new()
	var data: Dictionary = loader.load_all_data()
	loader.free()
	var factory = CatFactoryScript.new(data)
	_make_vp(Vector2i(COLS * CELL, ROWS * CELL))
	var seed: int = _first_seed - 1
	for i in range(COLS * ROWS):
		seed += 1
		var def: Dictionary = _make_def(factory, seed)
		while not _rarity_filter.is_empty() and str(def.get("rarity", "")) != _rarity_filter and seed < _first_seed + 100000:
			seed += 1
			def = _make_def(factory, seed)
		var cx: int = (i % COLS) * CELL
		var cy: int = (i / COLS) * CELL
		var frame := ReferenceRect.new()
		frame.position = Vector2(cx, cy)
		frame.size = Vector2(CELL, CELL)
		frame.border_color = Color(0.6, 0.45, 0.35, 0.35)
		frame.editor_only = false
		_vp.add_child(frame)

		var cat: Node2D = Cat2DScene.instantiate()
		cat.position = Vector2(cx + 96, cy + 182)
		cat.scale = Vector2(2.5, 2.5)
		_vp.add_child(cat)
		cat.apply_genome(def)
		cat.set_pose(_pose)
		if _pose == &"walk":
			cat.set_move_speed(1.0)
		cat.set_facing_left(i % 2 == 1)

		var g: Dictionary = def.get("genome", {})
		_add_label("#%d %s %s/%s" % [seed, def.get("rarity", ""), g.get("coat", ""), g.get("breed", "")], Vector2(cx + 4, cy + 2))

# One in-game-framed cell (192x192 * k) with a cat in it.
func _cell_cat(cx: int, cy: int, k: float, genome: Variant, pose: StringName, left: bool) -> Node2D:
	var frame := ReferenceRect.new()
	frame.position = Vector2(cx, cy)
	frame.size = Vector2(CELL, CELL) * k
	frame.border_color = Color(0.6, 0.45, 0.35, 0.35)
	frame.editor_only = false
	_vp.add_child(frame)
	var cat: Node2D = Cat2DScene.instantiate()
	cat.position = Vector2(cx + 96.0 * k, cy + 182.0 * k)
	cat.scale = Vector2(2.5, 2.5) * k
	_vp.add_child(cat)
	cat.apply_genome(genome)
	cat.set_pose(pose)
	if pose == &"walk":
		cat.set_move_speed(1.0)
	cat.set_facing_left(left)
	_cats.append(cat)
	return cat

func _build_random() -> void:
	var loader: Node = DataLoaderScript.new()
	var data: Dictionary = loader.load_all_data()
	loader.free()
	var factory = CatFactoryScript.new(data)
	var k: float = 1.5
	var cell: int = int(CELL * k)
	_make_vp(Vector2i(COLS * cell, ROWS * cell))
	var pick := RandomNumberGenerator.new()
	pick.seed = _first_seed
	for i in range(COLS * ROWS):
		# Columns 5/6 of every row are forced uncommon/rare so breeds show up.
		var want: String = ["", "", "", "", "uncommon", "rare"][i % COLS]
		var seed: int = pick.randi_range(1, 999999)
		var def: Dictionary = _make_def(factory, seed)
		while not want.is_empty() and str(def.get("rarity", "")) != want:
			seed = pick.randi_range(1, 999999)
			def = _make_def(factory, seed)
		var cx: int = (i % COLS) * cell
		var cy: int = (i / COLS) * cell
		_cell_cat(cx, cy, k, def, _pose, i % 2 == 1)
		var g: Dictionary = def.get("genome", {})
		_add_label("#%d %s %s %s" % [seed, def.get("rarity", ""), g.get("breed", ""), g.get("coat", "")], Vector2(cx + 4, cy + 2))
		_add_label("eyes: %s  %s" % [g.get("eye_shape", ""), ",".join(def.get("trait_ids", []))], Vector2(cx + 4, cy + 30), 10)
		_add_label("%s fur %.1f  body %.2fx%.2f  leg %.2f head %.2f" % [g.get("fur_style", ""), float(g.get("fur_length", 0.0)), float(g.get("body_length", 1.0)), float(g.get("body_girth", 1.0)), float(g.get("leg_length", 1.0)), float(g.get("head_size", 1.0))], Vector2(cx + 4, cy + 16), 10)

func _build_fur() -> void:
	var styles: Array[String] = ["flat", "medium", "fuzzy"]
	var lengths: Array[float] = [0.8, 1.5, 2.2]
	var cw: int = int(70.0 * _scale)
	var chh: int = int(66.0 * _scale)
	_make_vp(Vector2i(cw * 3, chh * 3))
	for r in range(3):
		for c in range(3):
			var cx: int = c * cw
			var cy: int = r * chh
			var g: Dictionary = {"coat": "ginger", "fur": "short", "tail": "classic", "eye": "amber", "seed": 11,
				"fur_style": styles[r], "fur_length": lengths[c]}
			var cat: Node2D = Cat2DScene.instantiate()
			cat.position = Vector2(cx + cw * 0.5, cy + chh - 6.0 * _scale)
			cat.scale = Vector2.ONE * _scale
			_vp.add_child(cat)
			cat.apply_genome(g)
			cat.set_pose(_pose)
			if _pose == &"walk":
				cat.set_move_speed(1.0)
			_cats.append(cat)
			_add_label("%s  fur_length %.1f" % [styles[r], lengths[c]], Vector2(cx + 6, cy + 4), 14)

func _build_extremes() -> void:
	var k: float = 1.25
	var cell: int = int(CELL * k)
	var cells: Array = []
	var lo_all: Dictionary = EXTREME_BASE.duplicate()
	var hi_all: Dictionary = EXTREME_BASE.duplicate()
	for key in EXTREME_KEYS:
		var lim: Array = _limits(key)
		for which in [0, 1]:
			var g: Dictionary = EXTREME_BASE.duplicate()
			g[key] = lim[which]
			cells.append([g, "%s %s %.2f" % [key, "min" if which == 0 else "max", float(lim[which])]])
		lo_all[key] = lim[0]
		hi_all[key] = lim[1]
	cells.append([lo_all, "ALL min"])
	cells.append([hi_all, "ALL max"])
	var rows: int = int(ceil(float(cells.size()) / float(COLS)))
	_make_vp(Vector2i(COLS * cell, rows * cell))
	for i in range(cells.size()):
		var cx: int = (i % COLS) * cell
		var cy: int = (i / COLS) * cell
		var cat: Node2D = _cell_cat(cx, cy, k, cells[i][0], _pose, false)
		_add_label(str(cells[i][1]), Vector2(cx + 4, cy + 2))
		_add_label("fit %.2f" % float(cat.call("fit_scale")), Vector2(cx + 4, cy + 16), 10)

# Low-res pixel cell: a density x density SubViewport framed like Cat3D's, run
# through CatPixelPipeline (mask outline) and shown upscaled by `zoom` with
# nearest filtering.
func _pixel_cat(cx: int, cy: int, zoom: int, genome: Variant, pose: StringName, left: bool, density: int = 0) -> Node2D:
	var n: int = density if density > 0 else _density
	var sub := SubViewport.new()
	sub.size = Vector2i(n, n)
	sub.transparent_bg = true
	sub.disable_3d = true
	sub.msaa_2d = Viewport.MSAA_DISABLED
	sub.snap_2d_transforms_to_pixel = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var cat: Node2D = Cat2DScene.instantiate()
	cat.position = Vector2(n / 2, roundf(float(n) * FOOT_FRAC))
	cat.scale = Vector2.ONE * float(n) / VIEW_UNITS
	cat.set("pixel_art", true)
	sub.add_child(cat)
	cat.apply_genome(genome)
	cat.call("set_pixel_art", true)
	cat.set_pose(pose)
	if pose == &"walk":
		cat.set_move_speed(1.0)
	cat.set_facing_left(left)
	_cats.append(cat)
	var pipe: Node = CatPixelPipelineScript.new()
	pipe.call("setup", root, sub, cat)
	pipe.call("set_pixel", true)
	var tr := TextureRect.new()
	tr.texture = pipe.call("get_texture")
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = Vector2(cx, cy)
	tr.size = Vector2(n, n) * float(zoom)
	_vp.add_child(tr)
	return cat

# Face sheet columns: [label, expression, blink, genome overrides, legacy spacing].
const FACE_COLS: Array = [
	["open", &"open", false, {}, false],
	["blink", &"open", true, {}, false],
	["happy", &"happy", false, {}, false],
	["stressed", &"stressed", false, {}, false],
	["sleepy", &"sleepy", false, {}, false],
	["angry", &"angry", false, {}, false],
	["worried", &"worried", false, {}, false],
	["sad", &"sad", false, {}, false],
	["surprised", &"surprised", false, {}, false],
	["smug", &"smug", false, {}, false],
]
# Coat / spacing sheet: old (pre-v4) vs new eye spacing, then other coats.
const FACE_COAT_COLS: Array = [
	["OLD spacing", &"open", false, {}, true],
	["NEW spacing", &"open", false, {}, false],
	["black", &"open", false, {"coat": "black", "eye": "gold"}, false],
	["black angry", &"angry", false, {"coat": "black", "eye": "gold"}, false],
	["siamese", &"open", false, {"coat": "siamese", "eye": "blue"}, false],
	["siamese sad", &"sad", false, {"coat": "siamese", "eye": "blue"}, false],
	["tuxedo", &"open", false, {"coat": "tuxedo", "eye": "green"}, false],
	["tuxedo surprised", &"surprised", false, {"coat": "tuxedo", "eye": "green"}, false],
]
const FACE_BASE: Dictionary = {"coat": "ginger", "fur": "short", "tail": "classic", "eye": "amber", "seed": 11}
# Head crop (fractions of the in-game viewport) for face sheets.
const FACE_CROP: Rect2 = Rect2(0.46, 0.33, 0.46, 0.43)
var _crop: Rect2 = FACE_CROP
const FACE_CELL_DEFAULT: int = 168
var FACE_CELL: int = FACE_CELL_DEFAULT

# rows = every eye shape (x each density), columns = FACE_COLS (or
# FACE_COAT_COLS when _face_coats); each cell is a zoomed head crop of the
# in-game pixel render. density 0 = 56 and 80.
func _build_pixel_faces() -> void:
	var problems: Array[String] = CatPixelFaceScript.validate()
	for pr in problems:
		push_warning("CatPixelFace: " + pr)
	print("CatPixelFace.validate(): %d problems" % problems.size())
	var dens: Array = [_density] if _density_given else [56, 80]
	var shapes: Array = CatPixelFaceScript.EYE_SHAPES
	var cols: Array = FACE_COAT_COLS if _face_coats else FACE_COLS
	_make_vp(Vector2i(FACE_CELL * cols.size(), FACE_CELL * shapes.size() * dens.size()))
	var row: int = 0
	for d in dens:
		for shape in shapes:
			for c in range(cols.size()):
				_face_col_cell(cols[c], c, row, shape, true, d, "%s %s %dpx" % [shape, cols[c][0], d])
			row += 1

# Pupil sheet: rows = eye shape x coat, columns = open-eye expressions.
const PUPIL_COATS: Array = [
	["tuxedo", {"coat": "tuxedo", "fur": "long", "fur_style": "fuzzy", "fur_length": 2.0, "tail": "plume", "eye": "amber", "seed": 41}],
	["black", {"coat": "black", "fur": "short", "tail": "classic", "eye": "gold", "seed": 42}],
	["ginger", {"coat": "ginger", "fur": "short", "tail": "classic", "eye": "amber", "seed": 11}],
]
const PUPIL_EXPRS: Array = [&"open", &"stressed", &"sleepy", &"angry", &"worried", &"sad", &"surprised", &"smug"]

func _build_pupil_faces(pixel: bool, n: int) -> void:
	FACE_CELL = 128
	_crop = Rect2(0.44, 0.43, 0.46, 0.32)
	var coats: Array = []
	var want: String = OS.get_environment("PUPIL_COATS")
	for c in PUPIL_COATS:
		if want.is_empty() or str(c[0]) in want.split(","):
			coats.append(c)
	var shapes: Array = CatPixelFaceScript.EYE_SHAPES
	_make_vp(Vector2i(FACE_CELL * PUPIL_EXPRS.size(), FACE_CELL * shapes.size() * coats.size()))
	var row: int = 0
	for shape in shapes:
		for co in coats:
			for c in range(PUPIL_EXPRS.size()):
				var g: Dictionary = (co[1] as Dictionary).duplicate()
				g["eye_shape"] = shape
				var cat: Node2D = _face_cell(c * FACE_CELL, row * FACE_CELL, g, pixel, n)
				cat.call("set_expression", PUPIL_EXPRS[c])
				_add_label("%s %s %s" % [shape, co[0], PUPIL_EXPRS[c]], Vector2(c * FACE_CELL + 3, row * FACE_CELL + 1), 10)
			row += 1

# Smooth renderer version of the face sheets (rows = eye shapes).
func _build_smooth_faces() -> void:
	var shapes: Array = CatPixelFaceScript.EYE_SHAPES
	var cols: Array = FACE_COAT_COLS if _face_coats else FACE_COLS
	_make_vp(Vector2i(FACE_CELL * cols.size(), FACE_CELL * shapes.size()))
	for r in range(shapes.size()):
		for c in range(cols.size()):
			_face_col_cell(cols[c], c, r, shapes[r], false, 384, "%s %s" % [shapes[r], cols[c][0]])

func _face_col_cell(col: Array, c: int, row: int, shape: String, pixel: bool, n: int, label: String) -> void:
	var g: Dictionary = FACE_BASE.duplicate()
	g.merge(col[3], true)
	g["eye_shape"] = shape
	var cat: Node2D = _face_cell(c * FACE_CELL, row * FACE_CELL, g, pixel, n, bool(col[4]))
	cat.call("set_expression", col[1])
	if bool(col[2]):
		cat.set_meta("force_blink", true)
	_add_label(label, Vector2(c * FACE_CELL + 3, row * FACE_CELL + 1), 10)

# One head-crop cell: the cat rendered in its own n x n viewport (in-game
# framing), pixel cells through CatPixelPipeline, cropped to FACE_CROP.
func _face_cell(cx: int, cy: int, genome: Dictionary, pixel: bool, n: int, legacy: bool = false) -> Node2D:
	var sub := SubViewport.new()
	sub.size = Vector2i(n, n)
	sub.transparent_bg = true
	sub.disable_3d = true
	sub.msaa_2d = Viewport.MSAA_DISABLED if pixel else Viewport.MSAA_4X
	sub.snap_2d_transforms_to_pixel = pixel
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var cat: Node2D = Cat2DScene.instantiate()
	cat.position = Vector2(n / 2, roundf(float(n) * FOOT_FRAC))
	cat.scale = Vector2.ONE * float(n) / VIEW_UNITS
	cat.set("pixel_art", pixel)
	cat.set("legacy_eye_spacing", legacy)
	cat.set("animate", false)   # no random blinks in face sheets
	sub.add_child(cat)
	cat.apply_genome(genome)
	cat.call("set_pixel_art", pixel)
	cat.set_pose(&"idle")
	_cats.append(cat)
	var tex: Texture2D = sub.get_texture()
	if pixel:
		var pipe: Node = CatPixelPipelineScript.new()
		pipe.call("setup", root, sub, cat)
		pipe.call("set_pixel", true)
		tex = pipe.call("get_texture")
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(Vector2(n, n) * _crop.position, Vector2(n, n) * _crop.size).abs()
	at.region = Rect2(at.region.position.floor(), at.region.size.floor())
	var tr := TextureRect.new()
	tr.texture = at
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = Vector2(cx, cy + 12)
	tr.size = Vector2(FACE_CELL, FACE_CELL - 12)
	_vp.add_child(tr)
	var frame := ReferenceRect.new()
	frame.position = Vector2(cx, cy)
	frame.size = Vector2(FACE_CELL, FACE_CELL)
	frame.border_color = Color(0.6, 0.45, 0.35, 0.35)
	frame.editor_only = false
	_vp.add_child(frame)
	return cat

func _build_pixel_fur() -> void:
	var styles: Array[String] = ["flat", "medium", "fuzzy"]
	var lengths: Array[float] = [0.8, 1.5, 2.2]
	var n: int = _density
	var z: int = _zoom if _zoom > 0 else maxi(1, int(round(400.0 / float(n))))
	var cell: int = n * z
	_make_vp(Vector2i(cell * 3, cell * 3))
	for r in range(3):
		for c in range(3):
			var g: Dictionary = {"coat": "ginger", "fur": "short", "tail": "classic", "eye": "amber", "seed": 11,
				"fur_style": styles[r], "fur_length": lengths[c]}
			_pixel_cat(c * cell, r * cell, z, g, _pose, false)
			_add_label("%s  fur_length %.1f  (%dpx)" % [styles[r], lengths[c], n], Vector2(c * cell + 6, r * cell + 4), 13)

func _build_pixel_poses() -> void:
	var poses: Array[StringName] = [&"idle", &"walk", &"sit", &"sleep"]
	var n: int = _density
	var z: int = _zoom if _zoom > 0 else maxi(1, int(round(260.0 / float(n))))
	var cell: int = n * z
	_make_vp(Vector2i(cell * REF6.size(), cell * poses.size()))
	for r in range(poses.size()):
		for c in range(REF6.size()):
			_pixel_cat(c * cell, r * cell, z, _genome_of(REF6[c]), poses[r], false)
			_add_label("%s %s" % [REF6[c]["_label"], poses[r]], Vector2(c * cell + 4, r * cell + 2), 11)

func _build_pixel() -> void:
	var n: int = _density
	match _pixel_set:
		"faces", "faces_coats":
			_face_coats = _pixel_set == "faces_coats"
			_build_pixel_faces()
			return
		"fur":
			_build_pixel_fur()
			return
		"pupils":
			_build_pupil_faces(true, _density)
			return
		"poses":
			_build_pixel_poses()
			return
	if _pixel_set == "ref6":
		var z: int = _zoom if _zoom > 0 else maxi(1, int(round(440.0 / float(n))))
		var cell: int = n * z
		_make_vp(Vector2i(cell * 3, cell * 2))
		for i in range(REF6.size()):
			var cx: int = (i % 3) * cell
			var cy: int = (i / 3) * cell
			var p: StringName = _pose
			_pixel_cat(cx, cy, z, _genome_of(REF6[i]), &"idle" if p == &"left" else p, p == &"left")
			_add_label("%s  (%dpx)" % [REF6[i]["_label"], n], Vector2(cx + 6, cy + 4), 14)
		return
	var loader: Node = DataLoaderScript.new()
	var data: Dictionary = loader.load_all_data()
	loader.free()
	var factory = CatFactoryScript.new(data)
	var z2: int = _zoom if _zoom > 0 else maxi(1, int(round(224.0 / float(n))))
	var cell2: int = n * z2
	_make_vp(Vector2i(COLS * cell2, ROWS * cell2))
	var pick := RandomNumberGenerator.new()
	pick.seed = _first_seed
	for i in range(COLS * ROWS):
		var seed: int = _first_seed + i
		var def: Dictionary
		if _pixel_set == "random":
			var want: String = ["", "", "", "", "uncommon", "rare"][i % COLS]
			seed = pick.randi_range(1, 999999)
			def = _make_def(factory, seed)
			while not want.is_empty() and str(def.get("rarity", "")) != want:
				seed = pick.randi_range(1, 999999)
				def = _make_def(factory, seed)
		else:
			def = _make_def(factory, seed)
		var cx: int = (i % COLS) * cell2
		var cy: int = (i / COLS) * cell2
		var frame := ReferenceRect.new()
		frame.position = Vector2(cx, cy)
		frame.size = Vector2(cell2, cell2)
		frame.border_color = Color(0.6, 0.45, 0.35, 0.35)
		frame.editor_only = false
		_vp.add_child(frame)
		_pixel_cat(cx, cy, z2, def, _pose, i % 2 == 1)
		var g: Dictionary = def.get("genome", {})
		_add_label("#%d %s %s %s" % [seed, def.get("rarity", ""), g.get("breed", ""), g.get("coat", "")], Vector2(cx + 4, cy + 2), 10)
		_add_label("eyes: %s  %s" % [g.get("eye_shape", ""), ",".join(def.get("trait_ids", []))], Vector2(cx + 4, cy + 14), 10)

func _limits(key: String) -> Array:
	if CatGenomeScript.SCALAR_RANGES.has(key):
		return CatGenomeScript.SCALAR_RANGES[key]
	return CatGenomeScript.FUR_RANGES[key]

func _make_def(factory: Object, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return factory.generate_cat(rng, seed)

func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _mode == "phases" and _frames_left == 4:
		# Freeze each cat on its own walk phase index.
		for cat in _cats:
			var i: int = int(cat.get_meta("phase_index", 0))
			cat.set_process(false)
			cat.set("_w_walk", 1.0)
			cat.set("_phase", (float(i) + 0.5) / 8.0 * TAU)
			cat.call("_process", 0.0)
	if _frames_left == 6:
		for cat in _cats:
			if cat.has_meta("force_blink"):
				cat.set("animate", false)
				cat.set("_blink_left", 10.0)
	if _frames_left > 0:
		return false
	var img: Image = _vp.get_texture().get_image()
	var err: int = img.save_png(_out_path)
	print("Saved cat sheet to %s (err=%d)" % [_out_path, err])
	return true
