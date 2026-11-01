extends Node2D

# Cat2D look-dev scene: one big cat driven by the controls on the left, plus a
# lineup of every coat preset along the bottom. "Roll" builds a real cat_def
# through CatFactory (seeded) so this doubles as a regression viewer.

const CatGenomeScript := preload("res://Scripts/prototype3d/CatGenome.gd")
const CatFactoryScript := preload("res://Scripts/data/CatFactory.gd")
const DataLoaderScript := preload("res://Scripts/data/DataLoader.gd")
const Cat2DScene := preload("res://Scenes/Prototype3D/Cat2D.tscn")
const CatPixelPipelineScript := preload("res://Scripts/prototype3d/CatPixelPipeline.gd")
const CatPixelFaceScript := preload("res://Scripts/prototype3d/CatPixelFace.gd")

# [genome key, label]; min/max come from CatGenome.SCALAR_RANGES / FUR_RANGES.
const SLIDERS: Array = [
	["body_length", "Body Length"],
	["body_girth", "Body Girth"],
	["leg_length", "Leg Length"],
	["leg_thickness", "Leg Thickness"],
	["haunch_size", "Haunch Size"],
	["head_size", "Head Size"],
	["cheek_width", "Cheek Width"],
	["ear_size", "Ear Size"],
	["neck_fluff", "Neck Fluff"],
	["tail_length", "Tail Length"],
	["tail_thickness", "Tail Thickness"],
	["fur_length", "Fur Length"],
	["fur_density", "Fur Density"],
	["fur_jitter", "Fur Jitter"],
	["tail_sway_deg", "Tail Sway Deg"],
	["tail_sway_speed", "Tail Sway Speed"],
]
const EXTRA_RANGES: Dictionary = {"tail_sway_deg": [0.0, 40.0], "tail_sway_speed": [0.2, 10.0]}
const OPTIONS: Array = [
	["coat", "Coat"],
	["fur_style", "Fur Style"],
	["fur", "Fur (legacy)"],
	["eye", "Eye"],
	["eye_shape", "Eye Shape"],
	["tail", "Tail"],
	["breed", "Breed"],
]
const POSES: Array[StringName] = [&"idle", &"walk", &"sit", &"sleep"]
const EXPRESSIONS: Array[StringName] = [&"open", &"happy", &"stressed", &"sleepy", &"angry", &"worried", &"sad", &"surprised", &"smug"]
const RENDER_MODES: Array[String] = ["pixel", "smooth", "both"]
const DENSITIES: Array[int] = [48, 56, 64, 80, 96]
const VIEW_UNITS: float = 76.8               # same window as the in-game Cat3D viewport
const FOOT_FRAC: float = 182.0 / 192.0

@export var background_color: Color = Color("#F3E6D6")
@export var floor_color: Color = Color("#E2CDB4")
@export var cat_view_scale: Vector2 = Vector2(7.0, 7.0)
@export var lineup_scale: float = 2.6
@export var panel_width: float = 330.0
## Big cat render: "pixel" = in-game low-res path (SubViewport at pixel_density,
## nearest upscale), "smooth" = vector rig, "both" = side by side.
@export_enum("pixel", "smooth", "both") var render_mode: String = "pixel"
@export var pixel_density: int = 56

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sliders: Dictionary = {}
var _slider_labels: Dictionary = {}
var _options: Dictionary = {}
var _face_left_toggle: CheckButton
var _walk_toggle: CheckButton
var _pose_option: OptionButton
var _seed_spin: SpinBox
var _info_label: Label
var _syncing: bool = false
var _lineup: Array[Node2D] = []
var _lineup_root: Node2D
var _data: Dictionary = {}
var _pix_vp: SubViewport
var _pix_cat: Node2D
var _pix_rect: TextureRect
var _pix_genome_hash: int = 0
var _pix_pipe: Node
var _render_option: OptionButton
var _density_option: OptionButton

@onready var cat_root: Node2D = $CatRoot
@onready var cat: Node2D = $CatRoot/Cat2D

func _ready() -> void:
	_rng.randomize()
	get_viewport().msaa_2d = Viewport.MSAA_4X
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build_lineup()
	_build_pixel_view()
	_build_ui()
	_on_reset_pressed()
	_apply_cmdline()
	_position_cat()
	queue_redraw()

# Optional look-dev args (after "--"): seed=N, pose=sit, walk, left.
func _apply_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a.begins_with("seed="):
			_seed_spin.value = int(a.substr(5))
			_roll(int(a.substr(5)))
		elif a.begins_with("pose="):
			cat.set_pose(StringName(a.substr(5)))
		elif a == "walk":
			cat.set_move_speed(1.0)
		elif a == "left":
			cat.set_facing_left(true)
		elif a.begins_with("render="):
			_set_render_mode(a.substr(7))
		elif a.begins_with("density="):
			_set_density(int(a.substr(8)))
	_sync_ui_from_cat()

func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
	var floor_y: float = size.y * 0.66
	draw_rect(Rect2(Vector2(0, floor_y), Vector2(size.x, size.y - floor_y)), floor_color, true)

func _on_viewport_resized() -> void:
	_position_cat()
	queue_redraw()

func _position_cat() -> void:
	var size: Vector2 = get_viewport_rect().size
	var left: float = panel_width + 32.0
	var avail: float = size.x - left
	var feet := Vector2(left + avail * 0.5, size.y * 0.66)
	var win: float = VIEW_UNITS * cat_view_scale.x
	var pix_feet: Vector2 = feet
	if render_mode == "both":
		feet.x -= win * 0.5
		pix_feet.x += win * 0.5
	cat_root.position = feet
	cat_root.scale = cat_view_scale
	cat_root.visible = render_mode != "pixel"
	if _pix_rect != null:
		var n: int = _pix_vp.size.x
		var k: float = win / float(n)
		_pix_rect.size = Vector2(n, n) * k
		_pix_rect.position = pix_feet - Vector2(float(n / 2), roundf(float(n) * FOOT_FRAC)) * k
		_pix_rect.visible = render_mode != "smooth"
	if _lineup_root != null:
		_lineup_root.position = Vector2(left, size.y * 0.95)
		var step: float = avail / float(maxi(1, _lineup.size()))
		for i in range(_lineup.size()):
			_lineup[i].position = Vector2(step * (float(i) + 0.5), 0.0)
			_lineup[i].scale = Vector2.ONE * lineup_scale

func _build_lineup() -> void:
	_lineup_root = Node2D.new()
	_lineup_root.name = "Lineup"
	add_child(_lineup_root)
	var coats: Array = CatGenomeScript.COAT_PRESETS.keys()
	var fur_for: Dictionary = {"calico": "medium", "ginger": "long", "sphynx": "none"}
	var tail_for: Dictionary = {"tuxedo": "long", "calico": "plume", "black": "stubby", "ginger": "plume"}
	var eye_for: Dictionary = {"tuxedo": "green", "calico": "hazel", "black": "gold", "siamese": "blue", "sphynx": "green"}
	for i in range(coats.size()):
		var c: Node2D = Cat2DScene.instantiate()
		_lineup_root.add_child(c)
		var coat: String = coats[i]
		c.apply_genome({
			"coat": coat, "seed": 100 + i,
			"breed": "sphynx" if coat == "sphynx" else "domestic",
			"fur": fur_for.get(coat, "short"), "tail": tail_for.get(coat, "classic"),
			"eye": eye_for.get(coat, "amber")})
		c.set_facing_left(i % 2 == 1)
		_lineup.append(c)

# ---------------------------------------------------------------- pixel view

# A second Cat2D rendered exactly like in game (low-res SubViewport, no MSAA,
# pixel_art rig) and shown upscaled with nearest filtering. It mirrors the
# main cat's genome, pose, facing and move speed every frame.
func _build_pixel_view() -> void:
	_pix_vp = SubViewport.new()
	_pix_vp.name = "PixelViewport"
	_pix_vp.disable_3d = true
	_pix_vp.transparent_bg = true
	_pix_vp.msaa_2d = Viewport.MSAA_DISABLED
	_pix_vp.snap_2d_transforms_to_pixel = true
	_pix_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_pix_vp)
	_pix_cat = Cat2DScene.instantiate()
	_pix_cat.set("pixel_art", true)
	_pix_vp.add_child(_pix_cat)
	# Same mask-outline compositor as in game.
	_pix_pipe = CatPixelPipelineScript.new()
	_pix_pipe.call("setup", self, _pix_vp, _pix_cat)
	_pix_pipe.call("set_pixel", true)
	_pix_rect = TextureRect.new()
	_pix_rect.name = "PixelView"
	_pix_rect.texture = _pix_pipe.call("get_texture")
	_pix_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pix_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pix_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_pix_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pix_rect)
	_set_density(pixel_density)

func _set_density(n: int) -> void:
	pixel_density = clampi(n, 32, 192)
	pixel_density += pixel_density % 2
	if _pix_vp == null:
		return
	_pix_vp.size = Vector2i(pixel_density, pixel_density)
	_pix_cat.position = Vector2(float(pixel_density / 2), roundf(float(pixel_density) * FOOT_FRAC))
	_pix_cat.scale = Vector2.ONE * float(pixel_density) / VIEW_UNITS
	_pix_genome_hash = 0
	if _pix_cat.is_inside_tree():
		_pix_cat.call("set_pixel_art", true)
	if _density_option != null:
		var i: int = DENSITIES.find(pixel_density)
		if i >= 0:
			_density_option.select(i)
	_position_cat()

func _set_render_mode(m: String) -> void:
	render_mode = m if m in RENDER_MODES else "pixel"
	if _render_option != null:
		_render_option.select(RENDER_MODES.find(render_mode))
	if is_node_ready():
		_position_cat()

func _process(_delta: float) -> void:
	if _pix_cat == null or cat == null:
		return
	var g: Dictionary = cat.get("genome")
	var h: int = hash(g)
	if h != _pix_genome_hash:
		_pix_genome_hash = h
		_pix_cat.apply_genome(g)
	_pix_cat.set_pose(cat.get("pose"))
	_pix_cat.set_facing_left(bool(cat.get("facing_left")))
	_pix_cat.set_move_speed(float(cat.get("move_speed")))
	_pix_cat.call("set_expression", cat.get("expression"))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 16.0 + panel_width
	panel.offset_bottom = -16.0
	layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 5)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "Cat Preview"
	col.add_child(title)

	var seed_row := HBoxContainer.new()
	col.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.custom_minimum_size = Vector2(60, 0)
	seed_row.add_child(seed_label)
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 999999
	_seed_spin.step = 1
	_seed_spin.value = 1
	_seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_spin)
	var roll_btn := Button.new()
	roll_btn.text = "Roll"
	roll_btn.pressed.connect(_on_roll_pressed)
	seed_row.add_child(roll_btn)
	var next_btn := Button.new()
	next_btn.text = "Next"
	next_btn.pressed.connect(_on_next_pressed)
	seed_row.add_child(next_btn)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.text = "Roll builds a cat via CatFactory."
	col.add_child(_info_label)

	col.add_child(HSeparator.new())
	for opt in OPTIONS:
		var key: String = opt[0]
		var values: Array = _option_values(key)
		_options[key] = _add_option(col, opt[1], values, _on_option_changed.bind(key))

	col.add_child(HSeparator.new())
	_pose_option = _add_option(col, "Pose", POSES.map(func(p: StringName) -> String: return String(p)), _on_pose_changed)
	_add_option(col, "Expression", EXPRESSIONS.map(func(e: StringName) -> String: return String(e)), func(i: int) -> void: cat.call("set_expression", EXPRESSIONS[i]))
	_walk_toggle = CheckButton.new()
	_walk_toggle.text = "Walk (move speed 1)"
	_walk_toggle.toggled.connect(_on_walk_toggled)
	col.add_child(_walk_toggle)
	_render_option = _add_option(col, "Render", RENDER_MODES, func(i: int) -> void: _set_render_mode(RENDER_MODES[i]))
	_render_option.select(RENDER_MODES.find(render_mode))
	_density_option = _add_option(col, "Pixel Density", DENSITIES.map(func(d: int) -> String: return "%d px" % d), func(i: int) -> void: _set_density(DENSITIES[i]))
	var di: int = DENSITIES.find(pixel_density)
	if di >= 0:
		_density_option.select(di)
	_face_left_toggle = CheckButton.new()
	_face_left_toggle.text = "Face Left"
	_face_left_toggle.toggled.connect(_on_face_left_toggled)
	col.add_child(_face_left_toggle)

	col.add_child(HSeparator.new())
	for s in SLIDERS:
		var lim: Array = _slider_range(s[0])
		_add_slider(col, s[0], s[1], float(lim[0]), float(lim[1]), 0.01)

	col.add_child(HSeparator.new())
	var button_row := HBoxContainer.new()
	col.add_child(button_row)
	var random_btn := Button.new()
	random_btn.text = "Randomize"
	random_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_btn.pressed.connect(_on_randomize_pressed)
	button_row.add_child(random_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_btn)

func _slider_range(key: String) -> Array:
	if CatGenomeScript.SCALAR_RANGES.has(key):
		return CatGenomeScript.SCALAR_RANGES[key]
	if CatGenomeScript.FUR_RANGES.has(key):
		return CatGenomeScript.FUR_RANGES[key]
	return EXTRA_RANGES.get(key, [0.0, 2.0])

func _option_values(key: String) -> Array:
	match key:
		"coat":
			return CatGenomeScript.COAT_PRESETS.keys()
		"fur_style":
			return CatGenomeScript.FUR_STYLES.keys()
		"fur":
			return CatGenomeScript.FUR_PRESETS.keys()
		"eye":
			return CatGenomeScript.EYE_COLORS.keys()
		"eye_shape":
			return Array(CatPixelFaceScript.EYE_SHAPES)
		"tail":
			return CatGenomeScript.TAIL_PRESETS.keys()
		"breed":
			return CatGenomeScript.BREED_PRESETS.keys()
	return []

func _add_option(parent: Control, label_text: String, values: Array, callback: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for v in values:
		ob.add_item(str(v))
	ob.item_selected.connect(callback)
	row.add_child(ob)
	return ob

func _add_slider(parent: Control, key: String, label_text: String, min_v: float, max_v: float, step_v: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider_changed.bind(key))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_sliders[key] = slider
	_slider_labels[key] = value_label

# ---------------------------------------------------------------- handlers

func _genome_from_ui() -> Dictionary:
	var g: Dictionary = cat.get_genome() if cat.has_method("get_genome") else {}
	for opt in OPTIONS:
		var key: String = opt[0]
		var ob: OptionButton = _options[key]
		if ob.selected >= 0:
			g[key] = ob.get_item_text(ob.selected)
	for s in SLIDERS:
		g[s[0]] = _slider_value(s[0])
	return g

func _slider_value(key: String) -> float:
	var s: HSlider = _sliders.get(key, null)
	return s.value if s != null else 1.0

func _apply_ui() -> void:
	if _syncing:
		return
	var g: Dictionary = _genome_from_ui()
	# Manual coat changes drop rolled colour overrides so presets show.
	g.erase("fur_primary")
	g.erase("fur_secondary")
	g.erase("eye_color")
	cat.apply_genome(g)

func _on_option_changed(_idx: int, key: String) -> void:
	if key == "fur":
		# The legacy fur key picks the matching fur style (and its default length).
		var ob: OptionButton = _options["fur"]
		var style: String = str(CatGenomeScript.LEGACY_FUR_STYLE.get(ob.get_item_text(ob.selected), "flat"))
		_select_option("fur_style", style)
	if key == "fur" or key == "fur_style":
		var st: OptionButton = _options["fur_style"]
		var preset: Dictionary = CatGenomeScript.FUR_STYLES.get(st.get_item_text(st.selected), {})
		for k in ["length", "density", "jitter"]:
			if preset.has(k):
				_set_slider("fur_" + k, float(preset[k]))
	_apply_ui()

func _select_option(key: String, value: String) -> void:
	var ob: OptionButton = _options.get(key, null)
	if ob == null:
		return
	for i in range(ob.item_count):
		if ob.get_item_text(i) == value:
			ob.select(i)

func _on_slider_changed(value: float, key: String) -> void:
	var l: Label = _slider_labels.get(key, null)
	if l != null:
		l.text = "%.2f" % value
	_apply_ui()

func _on_pose_changed(idx: int) -> void:
	cat.set_pose(POSES[clampi(idx, 0, POSES.size() - 1)])

func _on_walk_toggled(on: bool) -> void:
	cat.set_move_speed(1.0 if on else 0.0)

func _on_face_left_toggled(enabled: bool) -> void:
	cat.set_facing_left(enabled)

func _on_roll_pressed() -> void:
	_roll(int(_seed_spin.value))

func _on_next_pressed() -> void:
	_seed_spin.value = _seed_spin.value + 1
	_roll(int(_seed_spin.value))

func _roll(seed: int) -> void:
	if _data.is_empty():
		var loader: Node = DataLoaderScript.new()
		if loader.has_method("load_all_data"):
			_data = loader.load_all_data()
		loader.free()
	var factory = CatFactoryScript.new(_data)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var def: Dictionary = factory.generate_cat(rng, seed)
	cat.apply_genome(def)
	var g: Dictionary = def.get("genome", {})
	_info_label.text = "%s  [%s]  %s %s %s fur\ntraits: %s" % [
		def.get("display_name", "?"), def.get("rarity", "?"), g.get("breed", ""), g.get("coat", ""),
		g.get("fur_style", ""), ", ".join(PackedStringArray(def.get("trait_ids", [])))]
	_sync_ui_from_cat()

func _on_randomize_pressed() -> void:
	_roll(_rng.randi_range(0, 999999))

func _on_reset_pressed() -> void:
	cat.apply_genome({})
	cat.set_pose(&"idle")
	cat.set_move_speed(0.0)
	cat.set_facing_left(false)
	_sync_ui_from_cat()
	if _info_label != null:
		_info_label.text = "Default genome. Roll builds a cat via CatFactory."

func _sync_ui_from_cat() -> void:
	_syncing = true
	var g: Dictionary = cat.get_genome() if cat.has_method("get_genome") else {}
	for opt in OPTIONS:
		var key: String = opt[0]
		var ob: OptionButton = _options.get(key, null)
		if ob == null:
			continue
		var want: String = str(g.get(key, ""))
		for i in range(ob.item_count):
			if ob.get_item_text(i) == want:
				ob.select(i)
	for s in SLIDERS:
		_set_slider(s[0], float(g.get(s[0], 1.0)))
	if _face_left_toggle != null:
		_face_left_toggle.set_pressed_no_signal(bool(cat.get("facing_left")))
	if _walk_toggle != null:
		_walk_toggle.set_pressed_no_signal(float(cat.get("move_speed")) > 0.05)
	if _pose_option != null:
		_pose_option.select(maxi(0, POSES.find(StringName(str(cat.get("pose"))))))
	_syncing = false

func _set_slider(key: String, value: float) -> void:
	var slider: HSlider = _sliders.get(key, null)
	if slider != null:
		slider.set_value_no_signal(value)
	var l: Label = _slider_labels.get(key, null)
	if l != null:
		l.text = "%.2f" % value
