extends Node3D
class_name FloorBuilder3D

## Builds the cozy diorama room: plinth, plank floor, peach walls with wainscot, windows,
## sconces, the sage rest rug with an oak fence (gap at the rest door cells) and the
## build-mode grid. Everything is procedural (no imported textures).

const COL_PLINTH := Color("5A4034")
const COL_FLOOR_SIDE := Color("8A6446")
const COL_PLANK_A := Color("B8916B")
const COL_PLANK_B := Color("AE8763")
const COL_WALL := Color("E3B9A0")
const COL_WAINSCOT := Color("9C6B4A")
const COL_CAP := Color("7A5236")
const COL_TRIM := Color("F3E6D3")
const COL_RUG := Color("9DB8A0")
const COL_RUG_BORDER := Color("7E9C84")
const COL_RUG_STRIPE := Color("B5CBB4")
const COL_FENCE := Color("C9A27A")
const COL_FENCE_DARK := Color("A7805A")
const COL_TEXT := Color("4A3426")
const COL_TEXT_OUTLINE := Color("FFF6EA")
const COL_GLASS := Color("FFE2B0")
const COL_CURTAIN := Color("A9BFA4")
const COL_LAMP := Color("FFC98A")
const COL_GRID := Color(1.0, 0.965, 0.918, 0.35)
const COL_NO_BUILD := Color(0.75, 0.35, 0.3, 0.18)
const THEME_PATH: String = "res://UI/cozy_theme.tres"

const WALL_HEIGHT: float = 2.0
const WALL_THICKNESS: float = 0.15
const WAINSCOT_HEIGHT: float = 0.5
const FENCE_HEIGHT: float = 0.45
const PLINTH_MARGIN: float = 0.2
const PLINTH_DEPTH: float = 0.4

var _materials: Dictionary = {}
var _grid_root: Node3D
var _grid_visible: bool = false
var _label_font: Font = null
var _label_font_loaded: bool = false

func rebuild(level) -> void:
	for child in get_children():
		child.queue_free()
	_grid_root = null
	var b: Dictionary = level.get_floor_world_bounds()
	var min_x: float = float(b.get("min_x", 0.0))
	var max_x: float = float(b.get("max_x", 0.0))
	var min_z: float = float(b.get("min_z", 0.0))
	var max_z: float = float(b.get("max_z", 0.0))
	var bounds := Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))

	_build_plinth(level, bounds)
	_build_floor(level, bounds)
	_build_walls(level, bounds)
	_build_rest_area(level)
	_build_rest_partition(level)
	_build_entrance(level)
	_build_grid_lines(level, bounds)

## Shows the build grid (build mode only).
func set_grid_visible(on: bool) -> void:
	_grid_visible = on
	if _grid_root != null and is_instance_valid(_grid_root):
		_grid_root.visible = on

func is_grid_visible() -> bool:
	return _grid_visible

# --- Helpers -------------------------------------------------------------------------

func _mat(color: Color, roughness: float = 0.85, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s_%.2f_%.2f" % [color.to_html(), roughness, emission_energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	_materials[key] = m
	return m

func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, node_name: String = "", cast_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	if not node_name.is_empty():
		mi.name = node_name
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _cylinder(parent: Node3D, center: Vector3, radius: float, height: float, mat: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 20
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi

func _group(node_name: String, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	(parent if parent != null else self).add_child(n)
	return n

func _label(parent: Node3D, text: String, pos: Vector3, rot_y_deg: float, font_size: int = 48) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.004
	l.modulate = COL_TEXT
	# V5: same typeface as the HUD (cozy_theme SystemFont).
	var f: Font = _hud_font()
	if f != null:
		l.font = f
	l.outline_size = 4
	l.outline_modulate = COL_TEXT_OUTLINE
	l.position = pos
	l.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	l.double_sided = false
	parent.add_child(l)
	return l

func _hud_font() -> Font:
	if not _label_font_loaded:
		_label_font_loaded = true
		if ResourceLoader.exists(THEME_PATH):
			var th = load(THEME_PATH)
			if th is Theme and (th as Theme).default_font != null:
				_label_font = (th as Theme).default_font
	return _label_font

# --- Plinth + floor --------------------------------------------------------------------

func _build_plinth(level, bounds: Rect2) -> void:
	var g: Node3D = _group("Plinth")
	var floor_h: float = float(level.floor_tile_height_3d)
	var w: float = bounds.size.x + (PLINTH_MARGIN + WALL_THICKNESS) * 2.0
	var d: float = bounds.size.y + (PLINTH_MARGIN + WALL_THICKNESS) * 2.0
	var c: Vector2 = bounds.get_center()
	_box(g, Vector3(c.x, -floor_h - PLINTH_DEPTH * 0.5, c.y), Vector3(w, PLINTH_DEPTH, d), _mat(COL_PLINTH, 0.9))
	# Slim lighter lip where the floor meets the plinth.
	_box(g, Vector3(c.x, -floor_h + 0.0125, c.y), Vector3(bounds.size.x + 0.06, 0.035, bounds.size.y + 0.06), _mat(COL_CAP, 0.8))

func _build_floor(level, bounds: Rect2) -> void:
	var g: Node3D = _group("Floor")
	var floor_h: float = float(level.floor_tile_height_3d)
	var c: Vector2 = bounds.get_center()
	# Body of the floor (visible on the cutaway edges).
	_box(g, Vector3(c.x, -floor_h * 0.5 - 0.004, c.y), Vector3(bounds.size.x, floor_h - 0.008, bounds.size.y), _mat(COL_FLOOR_SIDE, 0.9))
	# Plank surface: one plane with a small procedural tileable texture.
	var cell: float = float(level.cell_width_3d)
	var tile_cells := Vector2i(6, 4)
	var tile_size := Vector2(cell * tile_cells.x, cell * tile_cells.y)
	var plane := PlaneMesh.new()
	plane.size = bounds.size
	var mi := MeshInstance3D.new()
	mi.name = "Planks"
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_texture = _make_plank_texture(tile_size, 3)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_scale = Vector3(bounds.size.x / tile_size.x, bounds.size.y / tile_size.y, 1.0)
	m.roughness = 0.85
	mi.material_override = m
	mi.position = Vector3(c.x, 0.0, c.y)
	g.add_child(mi)

## Tileable plank texture: boards run along X, rows_per_cell boards per cell depth.
func _make_plank_texture(tile_size: Vector2, rows_per_cell: int) -> ImageTexture:
	var ppm: float = 64.0
	var w: int = int(round(tile_size.x * ppm))
	var h: int = int(round(tile_size.y * ppm))
	var rows: int = int(round(tile_size.y / (tile_size.x / 6.0) * float(rows_per_cell)))
	rows = maxi(1, rows)
	var row_h: float = float(h) / float(rows)
	var r := RandomNumberGenerator.new()
	r.seed = 9127
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for row in range(rows):
		var y0: int = int(round(row * row_h))
		var y1: int = int(round((row + 1) * row_h))
		# Board joints for this row (wrap around so the texture tiles).
		var joints: Array[int] = []
		var x: float = r.randf_range(0.0, float(w) * 0.5)
		while x < float(w) + float(w) * 0.5:
			joints.append(int(x) % w)
			x += r.randf_range(float(w) * 0.32, float(w) * 0.6)
		joints.sort()
		var seg_colors: Array[Color] = []
		for i in range(joints.size() + 1):
			var base: Color = COL_PLANK_A.lerp(COL_PLANK_B, r.randf())
			base = base.lightened(r.randf_range(-0.04, 0.05)) if r.randf() < 0.5 else base.darkened(r.randf_range(0.0, 0.06))
			seg_colors.append(base)
		var grain_phase: float = r.randf_range(0.0, TAU)
		var grain_freq: float = r.randf_range(0.6, 1.4)
		for py in range(y0, y1):
			var local_y: float = float(py - y0) / maxf(1.0, row_h)
			for px in range(w):
				var seg: int = 0
				for j in joints:
					if px >= j:
						seg += 1
				var col: Color = seg_colors[seg % seg_colors.size()]
				if seg == joints.size():
					col = seg_colors[0]
				var grain: float = sin(float(px) * 0.045 * grain_freq + grain_phase + sin(local_y * 9.0 + float(px) * 0.01) * 1.6)
				col = col.darkened(0.035 * (grain * 0.5 + 0.5))
				if py == y0 or py == y1 - 1:
					col = col.darkened(0.28)
				elif py == y0 + 1:
					col = col.lightened(0.05)
				if joints.has(px):
					col = col.darkened(0.3)
				img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# --- Walls -------------------------------------------------------------------------------

func _build_walls(level, bounds: Rect2) -> void:
	var g: Node3D = _group("Walls")
	var min_x: float = bounds.position.x
	var min_z: float = bounds.position.y
	var max_x: float = bounds.end.x
	var max_z: float = bounds.end.y
	var t: float = WALL_THICKNESS
	var wall_mat: StandardMaterial3D = _mat(COL_WALL, 0.95)
	var wains_mat: StandardMaterial3D = _mat(COL_WAINSCOT, 0.8)
	var cap_mat: StandardMaterial3D = _mat(COL_CAP, 0.75)
	var trim_mat: StandardMaterial3D = _mat(COL_TRIM, 0.8)
	var north_len: float = (max_x - min_x) + t
	var west_len: float = (max_z - min_z) + t
	var north_cx: float = (min_x + max_x) * 0.5 - t * 0.5
	var west_cz: float = (min_z + max_z) * 0.5 - t * 0.5
	# North wall (runs along X at min_z).
	_box(g, Vector3(north_cx, WALL_HEIGHT * 0.5, min_z - t * 0.5), Vector3(north_len, WALL_HEIGHT, t), wall_mat, "NorthWall")
	_box(g, Vector3(north_cx + t * 0.5, WAINSCOT_HEIGHT * 0.5, min_z + 0.01), Vector3(north_len - t, WAINSCOT_HEIGHT, 0.02), wains_mat)
	_box(g, Vector3(north_cx + t * 0.5, WAINSCOT_HEIGHT + 0.02, min_z + 0.025), Vector3(north_len - t, 0.04, 0.05), cap_mat)
	_box(g, Vector3(north_cx + t * 0.5, 0.05, min_z + 0.03), Vector3(north_len - t, 0.1, 0.03), cap_mat)
	_box(g, Vector3(north_cx, WALL_HEIGHT + 0.03, min_z - t * 0.5 + 0.01), Vector3(north_len + 0.04, 0.06, t + 0.06), cap_mat)
	# West wall (runs along Z at min_x).
	_box(g, Vector3(min_x - t * 0.5, WALL_HEIGHT * 0.5, west_cz), Vector3(t, WALL_HEIGHT, west_len), wall_mat, "WestWall")
	_box(g, Vector3(min_x + 0.01, WAINSCOT_HEIGHT * 0.5, west_cz + t * 0.5), Vector3(0.02, WAINSCOT_HEIGHT, west_len - t), wains_mat)
	_box(g, Vector3(min_x + 0.025, WAINSCOT_HEIGHT + 0.02, west_cz + t * 0.5), Vector3(0.05, 0.04, west_len - t), cap_mat)
	_box(g, Vector3(min_x + 0.03, 0.05, west_cz + t * 0.5), Vector3(0.03, 0.1, west_len - t), cap_mat)
	_box(g, Vector3(min_x - t * 0.5 + 0.01, WALL_HEIGHT + 0.03, west_cz), Vector3(t + 0.06, 0.06, west_len + 0.04), cap_mat)
	# Wainscot panel grooves (vertical battens).
	var batten_mat: StandardMaterial3D = _mat(COL_WAINSCOT.darkened(0.12), 0.8)
	var x: float = min_x + 0.35
	while x < max_x - 0.1:
		_box(g, Vector3(x, WAINSCOT_HEIGHT * 0.5, min_z + 0.025), Vector3(0.025, WAINSCOT_HEIGHT - 0.12, 0.015), batten_mat, "", false)
		x += 0.7
	var z: float = min_z + 0.35
	while z < max_z - 0.1:
		_box(g, Vector3(min_x + 0.025, WAINSCOT_HEIGHT * 0.5, z), Vector3(0.015, WAINSCOT_HEIGHT - 0.12, 0.025), batten_mat, "", false)
		z += 0.7

	var w_total: float = max_x - min_x
	var d_total: float = max_z - min_z
	# Windows on the north wall: over the rest area and over the cafe.
	_add_north_window(g, Vector3(min_x + w_total * 0.17, 0.0, min_z), 1.5, trim_mat)
	_add_north_window(g, Vector3(min_x + w_total * 0.5, 0.0, min_z), 1.5, trim_mat)
	# Chalkboard menu + sconces.
	_add_chalkboard(g, Vector3(min_x + w_total * 0.33, 1.3, min_z + 0.03))
	_add_sconce(g, Vector3(min_x + w_total * 0.33 - 0.75, 1.45, min_z + 0.02), Vector3(0, 0, 1))
	_add_sconce(g, Vector3(min_x + w_total * 0.71, 1.45, min_z + 0.02), Vector3(0, 0, 1))
	_add_sconce(g, Vector3(min_x + 0.02, 1.45, min_z + d_total * 0.62), Vector3(1, 0, 0))
	# Framed cat pictures on the west wall (above the rest area, where tall decor never goes).
	_add_picture(g, Vector3(min_x + 0.03, 1.2, min_z + d_total * 0.11), Vector2(0.55, 0.45), Color("E8A87C"), Color("6B4A35"))
	_add_picture(g, Vector3(min_x + 0.03, 1.32, min_z + d_total * 0.21), Vector2(0.4, 0.55), Color("8FA88A"), Color("2F2A2E"))
	_add_picture(g, Vector3(min_x + 0.03, 1.15, min_z + d_total * 0.3), Vector2(0.35, 0.35), Color("A99BC4"), Color("C9874A"))
	# Small framed print on the north wall over the far right.
	_add_picture_north(g, Vector3(min_x + w_total * 0.88, 1.3, min_z + 0.03), Vector2(0.6, 0.45), Color("7FA3A1"), Color("F2E4CF"))
	# Soft warm fill near the windows.
	var fill := OmniLight3D.new()
	fill.name = "WindowGlow"
	fill.light_color = COL_LAMP
	fill.light_energy = 1.0
	fill.omni_range = 8.0
	fill.position = Vector3(min_x + w_total * 0.5, 1.4, min_z + 1.2)
	g.add_child(fill)

func _add_north_window(parent: Node3D, base: Vector3, width: float, trim_mat: StandardMaterial3D) -> void:
	var g: Node3D = _group("Window", parent)
	g.position = base
	var h: float = 0.95
	var y0: float = 0.85
	var glass := _box(g, Vector3(0.0, y0 + h * 0.5, 0.005), Vector3(width, h, 0.02), _mat(COL_GLASS, 0.2, 0.9), "Glass", false)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var f: float = 0.07
	_box(g, Vector3(0.0, y0 + h + f * 0.5, 0.04), Vector3(width + f * 2.0, f, 0.06), trim_mat)
	_box(g, Vector3(0.0, y0 - f * 0.5, 0.06), Vector3(width + f * 2.0 + 0.08, f, 0.12), trim_mat)
	_box(g, Vector3(-width * 0.5 - f * 0.5, y0 + h * 0.5, 0.04), Vector3(f, h, 0.06), trim_mat)
	_box(g, Vector3(width * 0.5 + f * 0.5, y0 + h * 0.5, 0.04), Vector3(f, h, 0.06), trim_mat)
	_box(g, Vector3(0.0, y0 + h * 0.5, 0.03), Vector3(0.035, h, 0.04), trim_mat)
	_box(g, Vector3(0.0, y0 + h * 0.55, 0.03), Vector3(width, 0.035, 0.04), trim_mat)
	# Curtains + rod.
	var curtain_mat: StandardMaterial3D = _mat(COL_CURTAIN, 0.95)
	_box(g, Vector3(-width * 0.5 - 0.12, y0 + h * 0.45, 0.09), Vector3(0.26, h + 0.3, 0.06), curtain_mat)
	_box(g, Vector3(width * 0.5 + 0.12, y0 + h * 0.45, 0.09), Vector3(0.26, h + 0.3, 0.06), curtain_mat)
	_box(g, Vector3(0.0, y0 + h + 0.14, 0.1), Vector3(width + 0.7, 0.03, 0.03), _mat(COL_CAP, 0.5))
	# Little potted plant on the sill.
	_cylinder(g, Vector3(width * 0.3, y0 + 0.07, 0.1), 0.06, 0.12, _mat(Color("C47A5A"), 0.8), 0.075)
	var leaf := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.16
	leaf.mesh = sphere
	leaf.material_override = _mat(Color("6F9468"), 0.9)
	leaf.position = Vector3(width * 0.3, y0 + 0.2, 0.1)
	g.add_child(leaf)

func _add_chalkboard(parent: Node3D, pos: Vector3) -> void:
	var g: Node3D = _group("Chalkboard", parent)
	g.position = pos
	_box(g, Vector3.ZERO, Vector3(1.0, 0.62, 0.04), _mat(COL_CAP, 0.7))
	_box(g, Vector3(0, 0, 0.022), Vector3(0.9, 0.52, 0.01), _mat(Color("33403A"), 0.95))
	var l := _label(g, "MENU", Vector3(0, 0, 0.03), 0.0, 56)
	l.modulate = Color("F2EDE4")
	l.outline_size = 0

func _add_sconce(parent: Node3D, pos: Vector3, normal: Vector3) -> void:
	var g: Node3D = _group("Sconce", parent)
	g.position = pos
	var plate_size := Vector3(0.12, 0.18, 0.03) if normal.z != 0.0 else Vector3(0.03, 0.18, 0.12)
	_box(g, Vector3.ZERO, plate_size, _mat(COL_CAP, 0.5))
	var shade := _cylinder(g, normal * 0.12 + Vector3(0, 0.04, 0), 0.08, 0.14, _mat(COL_LAMP, 0.6, 1.6), 0.05)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = COL_LAMP
	light.light_energy = 0.7
	light.omni_range = 3.2
	light.position = normal * 0.3
	g.add_child(light)

func _add_picture(parent: Node3D, pos: Vector3, size: Vector2, canvas: Color, motif: Color) -> void:
	var g: Node3D = _group("Picture", parent)
	g.position = pos
	_box(g, Vector3.ZERO, Vector3(0.03, size.y, size.x), _mat(COL_CAP, 0.6))
	_box(g, Vector3(0.016, 0, 0), Vector3(0.01, size.y - 0.08, size.x - 0.08), _mat(canvas, 0.9))
	_add_cat_silhouette(g, Vector3(0.024, -size.y * 0.12, 0), minf(size.x, size.y) * 0.5, motif, true)

func _add_picture_north(parent: Node3D, pos: Vector3, size: Vector2, canvas: Color, motif: Color) -> void:
	var g: Node3D = _group("Picture", parent)
	g.position = pos
	_box(g, Vector3.ZERO, Vector3(size.x, size.y, 0.03), _mat(COL_CAP, 0.6))
	_box(g, Vector3(0, 0, 0.016), Vector3(size.x - 0.08, size.y - 0.08, 0.01), _mat(canvas, 0.9))
	_add_cat_silhouette(g, Vector3(0, -size.y * 0.12, 0.024), minf(size.x, size.y) * 0.5, motif, false)

## Tiny sitting-cat silhouette (body, head, ears) on a picture canvas.
func _add_cat_silhouette(parent: Node3D, base: Vector3, s: float, color: Color, on_x: bool) -> void:
	var m: StandardMaterial3D = _mat(color, 0.9)
	var thin: float = 0.006
	var body := Vector3(thin, s * 0.5, s * 0.42) if on_x else Vector3(s * 0.42, s * 0.5, thin)
	var head := Vector3(thin, s * 0.3, s * 0.3) if on_x else Vector3(s * 0.3, s * 0.3, thin)
	var ear := Vector3(thin, s * 0.1, s * 0.08) if on_x else Vector3(s * 0.08, s * 0.1, thin)
	_box(parent, base, body, m, "", false)
	_box(parent, base + Vector3(0, s * 0.38, 0), head, m, "", false)
	var side := Vector3(0, 0, s * 0.1) if on_x else Vector3(s * 0.1, 0, 0)
	_box(parent, base + Vector3(0, s * 0.56, 0) + side, ear, m, "", false)
	_box(parent, base + Vector3(0, s * 0.56, 0) - side, ear, m, "", false)

# --- Rest area -------------------------------------------------------------------------------

func _build_rest_area(level) -> void:
	var rect: Rect2i = level.rest_area_rect
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var g: Node3D = _group("RestArea")
	var cw: float = float(level.cell_width_3d)
	var cd: float = float(level.cell_depth_3d)
	var a: Vector3 = level.map_to_world(rect.position)
	var bpos: Vector3 = level.map_to_world(rect.end - Vector2i.ONE)
	var min_x: float = a.x - cw * 0.5
	var max_x: float = bpos.x + cw * 0.5
	var min_z: float = a.z - cd * 0.5
	var max_z: float = bpos.z + cd * 0.5
	var w: float = max_x - min_x
	var d: float = max_z - min_z
	var cx: float = (min_x + max_x) * 0.5
	var cz: float = (min_z + max_z) * 0.5
	var inset: float = 0.22
	# Rug: border, field and two soft stripes.
	_box(g, Vector3(cx, 0.006, cz), Vector3(w - inset * 2.0, 0.012, d - inset * 2.0), _mat(COL_RUG_BORDER, 1.0), "RugBorder", false)
	_box(g, Vector3(cx, 0.008, cz), Vector3(w - inset * 2.0 - 0.16, 0.014, d - inset * 2.0 - 0.16), _mat(COL_RUG, 1.0), "Rug", false)
	_box(g, Vector3(cx, 0.0095, cz), Vector3(w - inset * 2.0 - 0.5, 0.014, d - inset * 2.0 - 0.5), _mat(COL_RUG_STRIPE, 1.0), "", false)
	_box(g, Vector3(cx, 0.011, cz), Vector3(w - inset * 2.0 - 0.62, 0.014, d - inset * 2.0 - 0.62), _mat(COL_RUG, 1.0), "", false)
	# Cat beds and cushions (decorative, low enough to walk over).
	_add_cat_bed(g, Vector3(min_x + w * 0.24, 0.0, min_z + d * 0.26), 0.36, Color("D9A0A0"))
	_add_cat_bed(g, Vector3(min_x + w * 0.70, 0.0, min_z + d * 0.72), 0.32, Color("EFE3CF"))
	_add_cat_bed(g, Vector3(min_x + w * 0.26, 0.0, min_z + d * 0.74), 0.30, Color("E8C29A"))
	_add_cushion(g, Vector3(min_x + w * 0.62, 0.0, min_z + d * 0.30), Color("B5A3CC"))
	# Corner plant.
	_add_plant(g, Vector3(min_x + 0.35, 0.0, min_z + 0.35), 0.75)
	# V7: height and detail. Cat tree in the opposite back corner (its cell is blocked so
	# nobody walks through it), a folded blanket under the back window, paw-print trail.
	var tree_cell: Vector2i = Vector2i(rect.end.x - 1, rect.position.y)
	var door_rest = level.get("_door_rest_cells")
	var tree_ok: bool = not (door_rest is Array and (door_rest as Array).has(tree_cell))
	if tree_ok and level.has_method("set_blocked"):
		level.set_blocked(tree_cell, true)
		var tp: Vector3 = level.map_to_world(tree_cell)
		_add_cat_tree(g, Vector3(tp.x, 0.0, tp.z))
	var blanket := _box(g, Vector3(min_x + w * 0.5, 0.03, min_z + 0.42), Vector3(0.7, 0.05, 0.45), _mat(Color("C9B6D9"), 0.95), "Blanket")
	blanket.rotation_degrees = Vector3(0, -6, 0)
	_box(g, Vector3(min_x + w * 0.5, 0.058, min_z + 0.42), Vector3(0.62, 0.008, 0.06), _mat(Color("B3A0C6"), 0.95), "", false)
	var paw_mat: StandardMaterial3D = _mat(COL_RUG_BORDER, 1.0)
	for i in range(4):
		var t: float = 0.36 + 0.07 * float(i)
		var side: float = 0.07 if i % 2 == 0 else -0.07
		var pp := Vector3(min_x + w * t + side, 0.0, min_z + d * (1.0 - t) - side)
		var pad := _cylinder(g, pp + Vector3(0, 0.017, 0), 0.05, 0.004, paw_mat)
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in range(3):
			var ang: float = deg_to_rad(-135.0 + 45.0 * float(k))
			var toe := _cylinder(g, pp + Vector3(cos(ang) * 0.07, 0.017, sin(ang) * 0.07), 0.022, 0.004, paw_mat)
			toe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Low night lamp.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("FFB878")
	lamp.light_energy = 0.45
	lamp.omni_range = 3.5
	lamp.position = Vector3(cx, 1.2, cz)
	g.add_child(lamp)

func _add_cat_tree(parent: Node3D, pos: Vector3) -> void:
	var g: Node3D = _group("CatTree", parent)
	g.position = pos
	var wood: StandardMaterial3D = _mat(COL_FENCE, 0.8)
	var carpet: StandardMaterial3D = _mat(COL_RUG_STRIPE, 1.0)
	_box(g, Vector3(0, 0.03, 0), Vector3(0.6, 0.06, 0.6), carpet, "Base")
	_cylinder(g, Vector3(0, 0.45, 0), 0.07, 0.9, _mat(Color("D8C3A0"), 0.95))
	_cylinder(g, Vector3(0.12, 0.25, 0.1), 0.05, 0.4, _mat(Color("D8C3A0"), 0.95))
	_cylinder(g, Vector3(0.0, 0.45, 0.0), 0.26, 0.04, wood)
	_cylinder(g, Vector3(0.0, 0.47, 0.0), 0.23, 0.02, carpet)
	_cylinder(g, Vector3(0.0, 0.85, 0.0), 0.22, 0.04, wood)
	_cylinder(g, Vector3(0.0, 0.87, 0.0), 0.19, 0.02, carpet)
	# A dangling toy.
	_cylinder(g, Vector3(0.2, 0.62, 0.0), 0.004, 0.22, _mat(COL_TEXT, 0.9))
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.035
	sph.height = 0.07
	ball.mesh = sph
	ball.material_override = _mat(Color("E07A82"), 0.8)
	ball.position = Vector3(0.2, 0.5, 0.0)
	g.add_child(ball)

func _add_cat_bed(parent: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	var g: Node3D = _group("CatBed", parent)
	g.position = pos
	_cylinder(g, Vector3(0, 0.035, 0), radius, 0.07, _mat(color.darkened(0.08), 0.95))
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.72
	torus.outer_radius = radius * 1.05
	torus.rings = 24
	torus.ring_segments = 10
	rim.mesh = torus
	rim.material_override = _mat(color, 0.95)
	rim.position = Vector3(0, 0.08, 0)
	rim.scale = Vector3(1.0, 1.25, 1.0)
	g.add_child(rim)

func _add_cushion(parent: Node3D, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.09, 0.5)
	mi.mesh = mesh
	mi.material_override = _mat(color, 0.95)
	mi.position = pos + Vector3(0, 0.045, 0)
	mi.rotation_degrees = Vector3(0, 18, 0)
	parent.add_child(mi)
	var tuft := _cylinder(parent, pos + Vector3(0, 0.092, 0), 0.04, 0.01, _mat(color.darkened(0.2), 0.95))
	tuft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_plant(parent: Node3D, pos: Vector3, height: float) -> void:
	var g: Node3D = _group("Plant", parent)
	g.position = pos
	_cylinder(g, Vector3(0, 0.14, 0), 0.15, 0.28, _mat(Color("C47A5A"), 0.85), 0.18)
	_cylinder(g, Vector3(0, 0.275, 0), 0.165, 0.02, _mat(Color("4A3426"), 1.0))
	var greens: Array[Color] = [Color("6F9468"), Color("86A97A"), Color("5E8259")]
	var offsets: Array[Vector3] = [Vector3(0, height * 0.55, 0), Vector3(0.12, height * 0.42, 0.06), Vector3(-0.1, height * 0.45, -0.07), Vector3(0.02, height * 0.75, -0.04)]
	for i in range(offsets.size()):
		var leaf := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.17 - 0.02 * float(i % 2)
		s.height = s.radius * 1.7
		leaf.mesh = s
		leaf.material_override = _mat(greens[i % greens.size()], 0.9)
		leaf.position = offsets[i]
		g.add_child(leaf)

# --- Rest partition (fence with a doorway) -------------------------------------------------

func _build_rest_partition(level) -> void:
	var rect: Rect2i = level.rest_area_rect
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var g: Node3D = _group("RestFence")
	var door_cells: Array = []
	if level.has_method("get_rest_door_cells"):
		door_cells = level.get_rest_door_cells()
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# runs[key] = {"axis": "x"|"z", "line": world coord of the fence line, "spans": [[a,b]...]}
	var runs: Dictionary = {}
	var door_spans: Array = []
	var cw: float = float(level.cell_width_3d)
	var cd: float = float(level.cell_depth_3d)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var rc := Vector2i(x, y)
			for d in dirs:
				var n: Vector2i = rc + d
				if not level.is_in_cafe_floor(n) or level.is_in_rest_area(n):
					continue
				var a: Vector3 = level.map_to_world(rc)
				var m: Vector3 = (a + level.map_to_world(n)) * 0.5
				var key: String
				var info: Dictionary
				if d.x != 0:
					key = "x_%d" % (x + maxi(d.x, 0))
					info = {"axis": "z", "line": m.x, "a": a.z - cd * 0.5, "b": a.z + cd * 0.5}
				else:
					key = "z_%d" % (y + maxi(d.y, 0))
					info = {"axis": "x", "line": m.z, "a": a.x - cw * 0.5, "b": a.x + cw * 0.5}
				if door_cells.has(n):
					door_spans.append(info)
					continue
				if not runs.has(key):
					runs[key] = {"axis": info["axis"], "line": info["line"], "spans": []}
				(runs[key]["spans"] as Array).append([float(info["a"]), float(info["b"])])
	for key in runs.keys():
		var run: Dictionary = runs[key]
		var spans: Array = run["spans"]
		spans.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
		var merged: Array = []
		for s in spans:
			if not merged.is_empty() and absf(float(merged[-1][1]) - float(s[0])) < 0.01:
				merged[-1][1] = s[1]
			else:
				merged.append([s[0], s[1]])
		for s in merged:
			_add_fence_segment(g, String(run["axis"]), float(run["line"]), float(s[0]), float(s[1]))
	if not door_spans.is_empty():
		_add_door_arch(g, door_spans)

func _add_fence_segment(parent: Node3D, axis: String, line: float, a: float, b: float) -> void:
	var fence_mat: StandardMaterial3D = _mat(COL_FENCE, 0.8)
	var post_mat: StandardMaterial3D = _mat(COL_FENCE_DARK, 0.8)
	var length: float = b - a
	var mid: float = (a + b) * 0.5
	var along := func(t: float, y: float, off: float = 0.0) -> Vector3:
		return Vector3(t, y, line + off) if axis == "x" else Vector3(line + off, y, t)
	var size_along := func(len_v: float, h: float, thick: float) -> Vector3:
		return Vector3(len_v, h, thick) if axis == "x" else Vector3(thick, h, len_v)
	# Rails.
	_box(parent, along.call(mid, FENCE_HEIGHT - 0.03), size_along.call(length, 0.05, 0.08), fence_mat)
	_box(parent, along.call(mid, 0.14), size_along.call(length, 0.04, 0.05), fence_mat)
	# Pickets.
	var n_pickets: int = maxi(1, int(round(length / 0.175)))
	var step: float = length / float(n_pickets)
	for i in range(n_pickets):
		var t: float = a + step * (float(i) + 0.5)
		_box(parent, along.call(t, (FENCE_HEIGHT - 0.06) * 0.5), size_along.call(0.07, FENCE_HEIGHT - 0.06, 0.03), fence_mat)
	# Posts at the ends and every two cells.
	var n_posts: int = maxi(1, int(round(length / 1.4)))
	for i in range(n_posts + 1):
		var t: float = a + length * float(i) / float(n_posts)
		_box(parent, along.call(t, (FENCE_HEIGHT + 0.06) * 0.5), size_along.call(0.09, FENCE_HEIGHT + 0.06, 0.09), post_mat)
		_box(parent, along.call(t, FENCE_HEIGHT + 0.045), size_along.call(0.11, 0.03, 0.11), fence_mat)

## Tall posts and a little beam with a sign over the cat door.
func _add_door_arch(parent: Node3D, door_spans: Array) -> void:
	var axis: String = String(door_spans[0]["axis"])
	var line: float = float(door_spans[0]["line"])
	var a: float = INF
	var b: float = -INF
	for s in door_spans:
		if String(s["axis"]) != axis:
			continue
		a = minf(a, float(s["a"]))
		b = maxf(b, float(s["b"]))
	var post_mat: StandardMaterial3D = _mat(COL_FENCE_DARK, 0.8)
	var fence_mat: StandardMaterial3D = _mat(COL_FENCE, 0.8)
	var arch_h: float = 1.15
	var at := func(t: float, y: float) -> Vector3:
		return Vector3(t, y, line) if axis == "x" else Vector3(line, y, t)
	var sz := func(len_v: float, h: float, thick: float) -> Vector3:
		return Vector3(len_v, h, thick) if axis == "x" else Vector3(thick, h, len_v)
	_box(parent, at.call(a, arch_h * 0.5), sz.call(0.1, arch_h, 0.1), post_mat, "DoorPost")
	_box(parent, at.call(b, arch_h * 0.5), sz.call(0.1, arch_h, 0.1), post_mat, "DoorPost")
	_box(parent, at.call((a + b) * 0.5, arch_h + 0.03), sz.call(b - a + 0.3, 0.07, 0.12), fence_mat, "DoorBeam")
	# Hanging plaque.
	var plaque_center: Vector3 = at.call((a + b) * 0.5, arch_h - 0.17)
	var plaque_size: Vector3 = sz.call(1.4, 0.32, 0.04)
	_box(parent, plaque_center, plaque_size, _mat(COL_TRIM, 0.8), "RestSign")
	var face_off := Vector3(0, 0, 0.03) if axis == "x" else Vector3(0.03, 0, 0)
	var rot: float = 0.0 if axis == "x" else 90.0
	var l := _label(parent, "Cat Nap Zone", plaque_center + face_off, rot, 64)
	l.name = "RestLabel"
	# Garland of little lights along the beam.
	for i in range(5):
		var t: float = lerpf(a + 0.15, b - 0.15, float(i) / 4.0)
		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.035
		s.height = 0.07
		bulb.mesh = s
		bulb.material_override = _mat(COL_LAMP, 0.4, 2.2)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = at.call(t, arch_h - 0.02)
		parent.add_child(bulb)

# --- Entrance --------------------------------------------------------------------------------

func _build_entrance(level) -> void:
	var ent = level.get("entrance_cell")
	if not (ent is Vector2i):
		return
	var cell: Vector2i = ent
	if not level.is_in_cafe_floor(cell):
		return
	var g: Node3D = _group("Entrance")
	var p: Vector3 = level.map_to_world(cell)
	var cw: float = float(level.cell_width_3d)
	var east_edge: bool = cell.x == level.cafe_floor_rect.end.x - 1
	var mat_size := Vector3(cw * 1.2, 0.014, cw * 2.0) if east_edge else Vector3(cw * 2.0, 0.014, cw * 1.2)
	var center: Vector3 = p + (Vector3(-cw * 0.1, 0.007, cw * 0.5) if east_edge else Vector3(cw * 0.5, 0.007, -cw * 0.1))
	_box(g, center, mat_size, _mat(Color("A65F48"), 1.0), "DoorMat", false)
	_box(g, center + Vector3(0, 0.002, 0), mat_size - Vector3(0.12, 0.0, 0.12), _mat(Color("C9785D"), 1.0), "", false)
	var l := _label(g, "WELCOME", center + Vector3(0, 0.012, 0), 0.0, 56)
	l.rotation_degrees = Vector3(-90, 90 if east_edge else 0, 0)
	l.modulate = Color("FFF6EA")
	l.outline_size = 0

# --- Build grid --------------------------------------------------------------------------------

func _build_grid_lines(level, bounds: Rect2) -> void:
	_grid_root = _group("GridLines")
	var cw: float = float(level.cell_width_3d)
	var cd: float = float(level.cell_depth_3d)
	var width: float = maxf(0.012, minf(cw, cd) * 0.035)
	var y: float = 0.02
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var nx: int = int(level.cafe_floor_rect.size.x)
	var nz: int = int(level.cafe_floor_rect.size.y)
	var origin: Vector2i = level.cafe_floor_rect.position
	# V8: only edges that touch a buildable cell (cafe floor outside the nap zone).
	var buildable := func(gx: int, gz: int) -> bool:
		var c := Vector2i(origin.x + gx, origin.y + gz)
		return level.is_in_cafe_floor(c) and not level.is_in_rest_area(c)
	for gx in range(nx + 1):
		var x: float = bounds.position.x + float(gx) * cw
		for gz in range(nz):
			if buildable.call(gx - 1, gz) or buildable.call(gx, gz):
				var z0: float = bounds.position.y + float(gz) * cd
				_quad(st, Vector3(x - width * 0.5, y, z0), Vector3(x + width * 0.5, y, z0 + cd))
	for gz in range(nz + 1):
		var z: float = bounds.position.y + float(gz) * cd
		for gx in range(nx):
			if buildable.call(gx, gz - 1) or buildable.call(gx, gz):
				var x0: float = bounds.position.x + float(gx) * cw
				_quad(st, Vector3(x0, y, z - width * 0.5), Vector3(x0 + cw, y, z + width * 0.5))
	var mi := MeshInstance3D.new()
	mi.name = "GridMesh"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = COL_GRID
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_root.add_child(mi)
	# V8: translucent no-build tint over the nap zone, build mode only.
	var rr: Rect2i = level.rest_area_rect
	if rr.size.x > 0 and rr.size.y > 0:
		var ra: Vector3 = level.map_to_world(rr.position)
		var rb: Vector3 = level.map_to_world(rr.end - Vector2i.ONE)
		var ov := MeshInstance3D.new()
		ov.name = "NoBuildOverlay"
		var pm := PlaneMesh.new()
		pm.size = Vector2(absf(rb.x - ra.x) + cw, absf(rb.z - ra.z) + cd)
		ov.mesh = pm
		ov.position = Vector3((ra.x + rb.x) * 0.5, y + 0.005, (ra.z + rb.z) * 0.5)
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		om.albedo_color = COL_NO_BUILD
		ov.material_override = om
		ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_grid_root.add_child(ov)
	_grid_root.visible = _grid_visible

func _quad(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var p0 := Vector3(a.x, a.y, a.z)
	var p1 := Vector3(b.x, a.y, a.z)
	var p2 := Vector3(b.x, a.y, b.z)
	var p3 := Vector3(a.x, a.y, b.z)
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)
