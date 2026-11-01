extends Node3D

## Builds the player's cozy one-room apartment diorama from primitives and procedural
## textures (no imported assets), in the same style as FloorBuilder3D / the cafe decor:
## plinth + plank floor, two back walls (north = -Z, west = -X; the camera looks from +X+Z),
## and zones:
##   NW  bed nook (bed, fairy lights, wall shelf) + wardrobe
##   N   desk under the big window with a city view (planner notebook) + bookshelf
##   NE  kitchenette (counter, sink, stove, open shelves, fridge) + small table, cat bowls
##   W   living area (sofa, rug, coffee table, floor lamp) + front door
##   SE  cat corner (bonding nest, nap bed, scratch post, cat tree, litter box)
## Warm evening lighting: dim moonlight key, lamps, window glow.
##
## After build(): `blockers` (world XZ Rect2s for the nav grid), `anchors` (hotspot
## highlight roots by id) and `points` (named world points) are filled.

const CELL: float = 0.7
const COLS: int = 14
const ROWS: int = 10
const X0: float = -4.9
const X1: float = 4.9
const Z0: float = -3.5
const Z1: float = 3.5
const WALL_H: float = 2.1
const WALL_T: float = 0.15
const FLOOR_H: float = 0.28
const PLINTH_MARGIN: float = 0.2
const PLINTH_DEPTH: float = 0.4

# Palette (style guide: warm neutrals, soft woods, muted greens; cocoa outline tones).
const COL_PLINTH := Color("5A4034")
const COL_FLOOR_SIDE := Color("8A6446")
const COL_PLANK_A := Color("B48A62")
const COL_PLANK_B := Color("A77D57")
const COL_WALL := Color("E8C3A6")
const COL_WALL_LOW := Color("A9B99A")
const COL_ACCENT_WALL := Color("C9A9B4")
const COL_CAP := Color("7A5236")
const COL_TRIM := Color("F3E6D3")
const COL_WALNUT := Color("7E5236")
const COL_WALNUT_L := Color("9C6B4A")
const COL_OAK := Color("C9A27A")
const COL_OAK_D := Color("A7805A")
const COL_CREAM := Color("FFF1DE")
const COL_SAGE := Color("9DB8A0")
const COL_SAGE_D := Color("7E9C84")
const COL_SAGE_L := Color("B5CBB4")
const COL_TERRACOTTA := Color("C47A5A")
const COL_ROSE := Color("D9A0A0")
const COL_MUSTARD := Color("E0A84E")
const COL_TEAL := Color("6E8F8A")
const COL_LAMP := Color("FFC98A")
const COL_TEXT := Color("4A3426")
const COL_LEAF_A := Color("6F9468")
const COL_LEAF_B := Color("86A97A")
const COL_LEAF_C := Color("5E8259")
const THEME_PATH: String = "res://UI/cozy_theme.tres"

var blockers: Array[Rect2] = []
var anchors: Dictionary = {}
var points: Dictionary = {}
var lamps: Array[Light3D] = []

var _materials: Dictionary = {}
var _font: Font = null
var _rng := RandomNumberGenerator.new()

func build() -> void:
	for c in get_children():
		c.queue_free()
	blockers.clear()
	anchors.clear()
	points.clear()
	lamps.clear()
	_rng.seed = 20261026
	var th = load(THEME_PATH)
	if th is Theme:
		_font = (th as Theme).default_font
	_build_plinth_and_floor()
	_build_walls()
	_build_bed_nook()
	_build_wardrobe()
	_build_desk_and_window()
	_build_bookshelf()
	_build_kitchen()
	_build_feed_station()
	_build_living()
	_build_door()
	_build_cat_corner()
	_build_lighting()

static func cell_center(g: Vector2i) -> Vector3:
	return Vector3(X0 + (float(g.x) + 0.5) * CELL, 0.0, Z0 + (float(g.y) + 0.5) * CELL)

# --- primitives ------------------------------------------------------------------------

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

## Soft fabric look (same rim trick as the cafe armchairs).
func _fabric(color: Color) -> StandardMaterial3D:
	var key: String = "fabric_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.4
	_materials[key] = m
	return m

func _group(node_name: String, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	(parent if parent != null else self).add_child(n)
	return n

func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, cast_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, center: Vector3, radius: float, height: float, mat: Material, top_radius: float = -1.0, segments: int = 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi

func _sphere(parent: Node3D, center: Vector3, radius: float, mat: Material, squash: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = 16
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi

func _torus(parent: Node3D, center: Vector3, inner: float, outer: float, mat: Material, y_scale: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 10
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	mi.scale = Vector3(1.0, y_scale, 1.0)
	parent.add_child(mi)
	return mi

func _capsule(parent: Node3D, center: Vector3, radius: float, length: float, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 4
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

## Flat textured quad lying on the floor (rugs, tile zones).
func _floor_quad(parent: Node3D, center: Vector3, size: Vector2, tex: Texture2D, uv_scale: Vector2 = Vector2.ONE, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	m.roughness = 0.95
	mi.material_override = m
	mi.position = center
	mi.rotation_degrees = Vector3(0, rot_y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Vertical textured quad facing +Z (north wall decals) or +X (west wall decals).
func _wall_quad(parent: Node3D, center: Vector3, size: Vector2, mat: Material, faces_x: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = mat
	mi.position = center
	if faces_x:
		mi.rotation_degrees = Vector3(0, 90, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _label(parent: Node3D, text: String, pos: Vector3, rot: Vector3, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.003
	l.modulate = color
	l.outline_size = 0
	if _font != null:
		l.font = _font
	l.position = pos
	l.rotation_degrees = rot
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l

func _block(x0: float, z0: float, x1: float, z1: float) -> void:
	blockers.append(Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0)))

func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, rng: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	l.position = pos
	parent.add_child(l)
	lamps.append(l)
	return l

func _plant(parent: Node3D, pos: Vector3, height: float, pot_color: Color = COL_TERRACOTTA, pot_r: float = 0.15) -> Node3D:
	var g: Node3D = _group("Plant", parent)
	g.position = pos
	_cyl(g, Vector3(0, pot_r * 0.95, 0), pot_r, pot_r * 1.9, _mat(pot_color, 0.85), pot_r * 1.18)
	_cyl(g, Vector3(0, pot_r * 1.88, 0), pot_r * 1.1, 0.02, _mat(Color("4A3426"), 1.0))
	var greens: Array[Color] = [COL_LEAF_A, COL_LEAF_B, COL_LEAF_C]
	var n: int = 5
	for i in range(n):
		var a: float = TAU * float(i) / float(n) + 0.4
		var rr: float = pot_r * (0.55 if i % 2 == 0 else 0.8)
		var h: float = height * (0.5 + 0.1 * float(i % 3))
		_sphere(g, Vector3(cos(a) * rr, h, sin(a) * rr), pot_r * 1.05 - 0.01 * float(i % 2), _mat(greens[i % 3], 0.9), 0.85)
	_sphere(g, Vector3(0, height * 0.8, 0), pot_r * 0.95, _mat(COL_LEAF_B, 0.9), 0.9)
	return g

func _small_plant(parent: Node3D, pos: Vector3, pot_color: Color = COL_TERRACOTTA, trailing: bool = false) -> void:
	_cyl(parent, pos + Vector3(0, 0.05, 0), 0.055, 0.1, _mat(pot_color, 0.85), 0.065)
	_sphere(parent, pos + Vector3(0, 0.15, 0), 0.08, _mat(COL_LEAF_B, 0.9), 0.85)
	_sphere(parent, pos + Vector3(0.04, 0.19, 0.02), 0.06, _mat(COL_LEAF_A, 0.9), 0.85)
	if trailing:
		for i in range(4):
			_sphere(parent, pos + Vector3(0.05 * float(i % 2) - 0.02, 0.06 - 0.07 * float(i), 0.07), 0.035, _mat(COL_LEAF_A if i % 2 == 0 else COL_LEAF_C, 0.9))

func _picture_north(parent: Node3D, pos: Vector3, size: Vector2, canvas: Color, motif: Color, kind: int = 0) -> void:
	var g: Node3D = _group("Picture", parent)
	g.position = pos
	_box(g, Vector3.ZERO, Vector3(size.x, size.y, 0.03), _mat(COL_WALNUT, 0.6))
	_box(g, Vector3(0, 0, 0.016), Vector3(size.x - 0.06, size.y - 0.06, 0.01), _mat(canvas, 0.9), false)
	_motif(g, Vector3(0, 0, 0.023), minf(size.x, size.y), motif, kind, false)

func _picture_west(parent: Node3D, pos: Vector3, size: Vector2, canvas: Color, motif: Color, kind: int = 0) -> void:
	var g: Node3D = _group("Picture", parent)
	g.position = pos
	_box(g, Vector3.ZERO, Vector3(0.03, size.y, size.x), _mat(COL_WALNUT, 0.6))
	_box(g, Vector3(0.016, 0, 0), Vector3(0.01, size.y - 0.06, size.x - 0.06), _mat(canvas, 0.9), false)
	_motif(g, Vector3(0.023, 0, 0), minf(size.x, size.y), motif, kind, true)

## 0 = sitting cat, 1 = mountains + sun, 2 = leaf.
func _motif(parent: Node3D, base: Vector3, s: float, color: Color, kind: int, on_x: bool) -> void:
	var m: StandardMaterial3D = _mat(color, 0.9)
	var t: float = 0.006
	var sz := func(w: float, h: float) -> Vector3:
		return Vector3(t, h, w) if on_x else Vector3(w, h, t)
	var off := func(a: float, b: float) -> Vector3:
		return base + (Vector3(0, b, a) if on_x else Vector3(a, b, 0))
	match kind:
		0:
			_box(parent, off.call(0, -s * 0.12), sz.call(s * 0.3, s * 0.34), m, false)
			_box(parent, off.call(0, s * 0.12), sz.call(s * 0.22, s * 0.2), m, false)
			_box(parent, off.call(s * 0.07, s * 0.25), sz.call(s * 0.06, s * 0.08), m, false)
			_box(parent, off.call(-s * 0.07, s * 0.25), sz.call(s * 0.06, s * 0.08), m, false)
		1:
			var tri := _box(parent, off.call(-s * 0.1, -s * 0.15), sz.call(s * 0.36, s * 0.36), m, false)
			tri.rotation_degrees = Vector3(45, 0, 0) if on_x else Vector3(0, 0, 45)
			tri.scale = Vector3(1, 0.6, 1)
			var tri2 := _box(parent, off.call(s * 0.16, -s * 0.2), sz.call(s * 0.24, s * 0.24), _mat(color.lightened(0.25), 0.9), false)
			tri2.rotation_degrees = tri.rotation_degrees
			tri2.scale = Vector3(1, 0.6, 1)
			_box(parent, off.call(s * 0.17, s * 0.2), sz.call(s * 0.12, s * 0.12), _mat(COL_MUSTARD, 0.9), false)
		_:
			var leaf := _box(parent, off.call(0, 0), sz.call(s * 0.22, s * 0.5), m, false)
			leaf.rotation_degrees = Vector3(-20, 0, 0) if on_x else Vector3(0, 0, 20)

# --- procedural textures ---------------------------------------------------------------

func _plank_texture() -> ImageTexture:
	var w: int = 256
	var h: int = 192
	var rows: int = 8
	var row_h: float = float(h) / float(rows)
	var r := RandomNumberGenerator.new()
	r.seed = 5511
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for row in range(rows):
		var y0: int = int(round(row * row_h))
		var y1: int = int(round((row + 1) * row_h))
		var joints: Array[int] = []
		var x: float = r.randf_range(0.0, float(w) * 0.5)
		while x < float(w) * 1.5:
			joints.append(int(x) % w)
			x += r.randf_range(float(w) * 0.35, float(w) * 0.65)
		joints.sort()
		var cols: Array[Color] = []
		for i in range(joints.size() + 1):
			var base: Color = COL_PLANK_A.lerp(COL_PLANK_B, r.randf())
			base = base.lightened(r.randf_range(0.0, 0.05)) if r.randf() < 0.5 else base.darkened(r.randf_range(0.0, 0.06))
			cols.append(base)
		var phase: float = r.randf_range(0.0, TAU)
		for py in range(y0, y1):
			var ly: float = float(py - y0) / maxf(1.0, row_h)
			for px in range(w):
				var seg: int = 0
				for j in joints:
					if px >= j:
						seg += 1
				var col: Color = cols[0] if seg == joints.size() else cols[seg]
				var grain: float = sin(float(px) * 0.05 + phase + sin(ly * 8.0 + float(px) * 0.012) * 1.7)
				col = col.darkened(0.04 * (grain * 0.5 + 0.5))
				if py == y0 or py == y1 - 1:
					col = col.darkened(0.3)
				elif py == y0 + 1:
					col = col.lightened(0.05)
				if joints.has(px):
					col = col.darkened(0.32)
				img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Checker tiles (kitchen floor): cream and terracotta with grout. One texel group = one tile.
func _checker_texture() -> ImageTexture:
	var n: int = 32
	var tiles: int = 4
	var size: int = n * tiles
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var a := Color("EBD9BE")
	var b := Color("C98A68")
	var grout := Color("A88C70")
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for ty in range(tiles):
		for tx in range(tiles):
			var base: Color = a if (tx + ty) % 2 == 0 else b
			base = base.lightened(r.randf_range(-0.03, 0.04))
			for y in range(n):
				for x in range(n):
					var col: Color = base
					if x == 0 or y == 0:
						col = grout
					elif x == 1 or y == 1:
						col = base.lightened(0.08)
					elif x == n - 1 or y == n - 1:
						col = base.darkened(0.08)
					img.set_pixel(tx * n + x, ty * n + y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Patterned living-room rug: border bands, diamond lattice, fringe-free.
func _rug_texture() -> ImageTexture:
	var w: int = 256
	var h: int = 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var field := Color("C9785D")
	var field2 := Color("B86A50")
	var cream := Color("F2E2C8")
	var sage := Color("8FA88A")
	var dark := Color("7A4A3A")
	for y in range(h):
		for x in range(w):
			var bx: int = mini(x, w - 1 - x)
			var by: int = mini(y, h - 1 - y)
			var b: int = mini(bx, by)
			var col: Color
			if b < 10:
				col = dark
			elif b < 18:
				col = cream
			elif b < 26:
				col = sage
			elif b < 30:
				col = cream
			else:
				var u: float = float(x - 128) / 26.0
				var v: float = float(y - 128) / 26.0
				var d: float = absf(fmod(absf(u + v), 2.0) - 1.0) + absf(fmod(absf(u - v), 2.0) - 1.0)
				col = field if d > 0.9 else field2
				if absf(d - 0.9) < 0.12:
					col = cream
				var cd: float = absf(float(x - 128)) + absf(float(y - 128))
				if cd < 34:
					col = sage if cd > 22 else cream
					if cd < 10:
						col = COL_MUSTARD
			# Woven texture: tiny alternating shade.
			if (x + y) % 2 == 0:
				col = col.darkened(0.03)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Soft wallpaper: faint vertical stripes and little dot flowers (bed nook accent wall).
func _wallpaper_texture() -> ImageTexture:
	var s: int = 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var base := COL_ACCENT_WALL
	for y in range(s):
		for x in range(s):
			var col: Color = base
			if x % 16 < 2:
				col = base.lightened(0.06)
			var dx: int = (x % 32) - 8
			var dy: int = (y % 32) - 8 if x % 64 < 32 else ((y + 16) % 32) - 8
			if dx * dx + dy * dy <= 4:
				col = Color("F3E1E3")
			if dx * dx + dy * dy <= 1:
				col = COL_MUSTARD.lightened(0.2)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Subway tile backsplash.
func _subway_texture() -> ImageTexture:
	var w: int = 64
	var h: int = 32
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var tile := Color("F4EBDD")
	var grout := Color("CDBCA6")
	for y in range(h):
		for x in range(w):
			var row: int = y / 8
			var xx: int = (x + (16 if row % 2 == 1 else 0)) % w
			var col: Color = tile
			if y % 8 == 0 or xx % 32 == 0:
				col = grout
			elif y % 8 == 1:
				col = tile.lightened(0.05)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Evening city skyline seen through the windows: dusk gradient, moon, stars, two layers of
## buildings with warm lit windows.
func _city_texture() -> ImageTexture:
	var w: int = 512
	var h: int = 160
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var top := Color("2E2A4F")
	var mid := Color("6B4E7A")
	var low := Color("E39A6E")
	for y in range(h):
		var t: float = float(y) / float(h - 1)
		var c: Color = top.lerp(mid, clampf(t / 0.55, 0.0, 1.0)) if t < 0.55 else mid.lerp(low, clampf((t - 0.55) / 0.4, 0.0, 1.0))
		for x in range(w):
			img.set_pixel(x, y, c)
	var r := RandomNumberGenerator.new()
	r.seed = 9001
	for _i in range(70):
		var sx: int = r.randi_range(0, w - 1)
		var sy: int = r.randi_range(0, int(h * 0.45))
		img.set_pixel(sx, sy, Color("FFF3D6").lerp(img.get_pixel(sx, sy), r.randf_range(0.0, 0.5)))
	# Moon.
	var mc := Vector2(w * 0.3, h * 0.22)
	for y in range(h):
		for x in range(w):
			var d: float = Vector2(x, y).distance_to(mc)
			if d < 9.0:
				img.set_pixel(x, y, Color("FFF2D2"))
			elif d < 15.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color("FFE7C0"), 0.25 * (15.0 - d) / 6.0))
	# Far buildings, then near buildings.
	for layer in range(2):
		var x: int = 0
		var bcol: Color = Color("4A3E62") if layer == 0 else Color("2F2738")
		var win_on: Color = Color("FFD08A") if layer == 0 else Color("FFC375")
		while x < w:
			var bw: int = r.randi_range(18, 46) if layer == 0 else r.randi_range(24, 60)
			var bh: int = r.randi_range(int(h * 0.25), int(h * 0.6)) if layer == 0 else r.randi_range(int(h * 0.18), int(h * 0.45))
			var y0: int = h - bh
			for yy in range(y0, h):
				for xx in range(x, mini(x + bw, w)):
					img.set_pixel(xx, yy, bcol)
			# Roof bits.
			if r.randf() < 0.4:
				var ax: int = x + bw / 2
				for yy in range(maxi(0, y0 - 8), y0):
					if ax < w:
						img.set_pixel(ax, yy, bcol)
			# Windows.
			var wy: int = y0 + 5
			while wy < h - 4:
				var wx: int = x + 4
				while wx < x + bw - 4 and wx < w - 3:
					if r.randf() < (0.35 if layer == 0 else 0.45):
						var wc: Color = win_on.lerp(Color("FFF0C8"), r.randf() * 0.4)
						for yy in range(wy, wy + 4):
							for xx in range(wx, wx + 3):
								img.set_pixel(xx, yy, wc)
					wx += 7
				wy += 8
			x += bw + r.randi_range(0, 6)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _plaster_material(color: Color) -> StandardMaterial3D:
	var key: String = "plaster_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var nimg: Image = noise.get_seamless_image(128, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var v: float = nimg.get_pixel(x, y).r
			img.set_pixel(x, y, color.lightened((v - 0.5) * 0.08))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.roughness = 0.95
	_materials[key] = m
	return m

func _triplanar(tex: Texture2D, scale: float, roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

# --- floor ---------------------------------------------------------------------------------

func _build_plinth_and_floor() -> void:
	var g: Node3D = _group("Floor")
	var w: float = X1 - X0
	var d: float = Z1 - Z0
	var cx: float = (X0 + X1) * 0.5
	var cz: float = (Z0 + Z1) * 0.5
	_box(g, Vector3(cx, -FLOOR_H - PLINTH_DEPTH * 0.5, cz), Vector3(w + (PLINTH_MARGIN + WALL_T) * 2.0, PLINTH_DEPTH, d + (PLINTH_MARGIN + WALL_T) * 2.0), _mat(COL_PLINTH, 0.9))
	_box(g, Vector3(cx, -FLOOR_H + 0.0125, cz), Vector3(w + 0.06, 0.035, d + 0.06), _mat(COL_CAP, 0.8))
	_box(g, Vector3(cx, -FLOOR_H * 0.5 - 0.004, cz), Vector3(w, FLOOR_H - 0.008, d), _mat(COL_FLOOR_SIDE, 0.9))
	var planks: MeshInstance3D = _floor_quad(g, Vector3(cx, 0.0, cz), Vector2(w, d), _plank_texture(), Vector2(w / 2.8, d / 2.1))
	planks.name = "Planks"
	# Kitchen tiles.
	var kx0: float = 0.85
	var kz1: float = -0.85
	var tiles: MeshInstance3D = _floor_quad(g, Vector3((kx0 + X1) * 0.5, 0.003, (Z0 + kz1) * 0.5), Vector2(X1 - kx0, kz1 - Z0), _checker_texture(), Vector2((X1 - kx0) / 1.4, (kz1 - Z0) / 1.4))
	tiles.name = "KitchenTiles"
	_box(g, Vector3(kx0 - 0.015, 0.006, (Z0 + kz1) * 0.5), Vector3(0.03, 0.012, kz1 - Z0), _mat(COL_OAK_D, 0.7), false)
	_box(g, Vector3((kx0 + X1) * 0.5, 0.006, kz1 + 0.015), Vector3(X1 - kx0, 0.012, 0.03), _mat(COL_OAK_D, 0.7), false)

# --- walls -----------------------------------------------------------------------------------

## North wall (along X at z = Z0) built from strips so the windows are real openings.
func _build_walls() -> void:
	var g: Node3D = _group("Walls")
	var plaster: StandardMaterial3D = _plaster_material(COL_WALL)
	var cap_mat: StandardMaterial3D = _mat(COL_CAP, 0.75)
	var holes: Array = [
		{"x0": -1.95, "x1": -0.35, "y0": 0.85, "y1": 1.85},
		{"x0": 1.5, "x1": 2.4, "y0": 1.12, "y1": 1.78},
	]
	var zc: float = Z0 - WALL_T * 0.5
	var xs: Array[float] = [X0 - WALL_T]
	for hdef in holes:
		xs.append(float(hdef["x0"]))
		xs.append(float(hdef["x1"]))
	xs.append(X1)
	for i in range(0, xs.size() - 1):
		var a: float = xs[i]
		var b: float = xs[i + 1]
		if b - a <= 0.001:
			continue
		if i % 2 == 0:
			_box(g, Vector3((a + b) * 0.5, WALL_H * 0.5, zc), Vector3(b - a, WALL_H, WALL_T), plaster)
		else:
			var hdef: Dictionary = holes[i / 2]
			var y0: float = float(hdef["y0"])
			var y1: float = float(hdef["y1"])
			_box(g, Vector3((a + b) * 0.5, y0 * 0.5, zc), Vector3(b - a, y0, WALL_T), plaster)
			_box(g, Vector3((a + b) * 0.5, (y1 + WALL_H) * 0.5, zc), Vector3(b - a, WALL_H - y1, WALL_T), plaster)
	# West wall.
	var west_len: float = (Z1 - Z0) + WALL_T
	var wcz: float = (Z0 + Z1) * 0.5 - WALL_T * 0.5
	_box(g, Vector3(X0 - WALL_T * 0.5, WALL_H * 0.5, wcz), Vector3(WALL_T, WALL_H, west_len), plaster)
	# Wall caps.
	_box(g, Vector3((X0 + X1) * 0.5 - WALL_T * 0.5, WALL_H + 0.03, Z0 - WALL_T * 0.5 + 0.01), Vector3(X1 - X0 + WALL_T + 0.04, 0.06, WALL_T + 0.06), cap_mat)
	_box(g, Vector3(X0 - WALL_T * 0.5 + 0.01, WALL_H + 0.03, wcz), Vector3(WALL_T + 0.06, 0.06, west_len + 0.04), cap_mat)
	# Lower wall: painted sage band with a chair rail (not behind the kitchen counter).
	var low_h: float = 0.62
	var low_mat: StandardMaterial3D = _plaster_material(COL_WALL_LOW)
	_box(g, Vector3((X0 + 0.85) * 0.5, low_h * 0.5, Z0 + 0.008), Vector3(0.85 - X0, low_h, 0.016), low_mat, false)
	_box(g, Vector3((X0 + 0.85) * 0.5, low_h + 0.015, Z0 + 0.022), Vector3(0.85 - X0, 0.035, 0.045), _mat(COL_TRIM, 0.7))
	_box(g, Vector3(X0 + 0.008, low_h * 0.5, (Z0 + Z1) * 0.5), Vector3(0.016, low_h, Z1 - Z0), low_mat, false)
	_box(g, Vector3(X0 + 0.022, low_h + 0.015, (Z0 + Z1) * 0.5), Vector3(0.045, 0.035, Z1 - Z0), _mat(COL_TRIM, 0.7))
	# Baseboards.
	_box(g, Vector3((X0 + X1) * 0.5, 0.05, Z0 + 0.02), Vector3(X1 - X0, 0.1, 0.04), _mat(COL_TRIM, 0.7))
	_box(g, Vector3(X0 + 0.02, 0.05, (Z0 + Z1) * 0.5), Vector3(0.04, 0.1, Z1 - Z0), _mat(COL_TRIM, 0.7))
	# Bed nook accent wallpaper above the chair rail (north wall, west end + west wall north end).
	var wp: StandardMaterial3D = _triplanar(_wallpaper_texture(), 1.6, 0.95)
	_box(g, Vector3((X0 + -2.05) * 0.5, (low_h + 0.04 + WALL_H) * 0.5, Z0 + 0.006), Vector3(-2.05 - X0, WALL_H - low_h - 0.04, 0.012), wp, false)
	_box(g, Vector3(X0 + 0.006, (low_h + 0.04 + WALL_H) * 0.5, (Z0 + -1.25) * 0.5), Vector3(0.012, WALL_H - low_h - 0.04, -1.25 - Z0), wp, false)
	_box(g, Vector3(-2.05, (low_h + WALL_H) * 0.5, Z0 + 0.016), Vector3(0.03, WALL_H - low_h, 0.03), _mat(COL_TRIM, 0.7))
	_box(g, Vector3(X0 + 0.016, (low_h + WALL_H) * 0.5, -1.25), Vector3(0.03, WALL_H - low_h, 0.03), _mat(COL_TRIM, 0.7))
	# Windows (frames, glass, city view behind).
	_build_window(g, holes[0], true)
	_build_window(g, holes[1], false)

func _build_window(parent: Node3D, hdef: Dictionary, big: bool) -> void:
	var g: Node3D = _group("Window", parent)
	var x0: float = float(hdef["x0"])
	var x1: float = float(hdef["x1"])
	var y0: float = float(hdef["y0"])
	var y1: float = float(hdef["y1"])
	var w: float = x1 - x0
	var h: float = y1 - y0
	var cx: float = (x0 + x1) * 0.5
	var cy: float = (y0 + y1) * 0.5
	var trim: StandardMaterial3D = _mat(COL_TRIM, 0.7)
	# City view: unshaded backdrop a little behind the wall, only visible through the opening.
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var bw: float = w + 0.9
	var bh: float = h + 0.53
	qm.size = Vector2(bw, bh)
	back.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_texture = _city_texture() if not _materials.has("city_tex") else _materials["city_tex"]
	_materials["city_tex"] = bm.albedo_texture
	bm.uv1_scale = Vector3(bw / 8.0, 1.0, 1.0)
	bm.uv1_offset = Vector3((cx + 4.0) / 8.0, 0.0, 0.0)
	bm.texture_repeat = true
	back.material_override = bm
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position = Vector3(cx - 0.45, (y1 - 0.32 + y0 - 0.85) * 0.5, Z0 - WALL_T - 0.4)
	g.add_child(back)
	# Reveal (inner faces of the opening).
	var rev: StandardMaterial3D = _mat(COL_TRIM.darkened(0.05), 0.8)
	_box(g, Vector3(cx, y0 - 0.01, Z0 - WALL_T * 0.5), Vector3(w, 0.02, WALL_T), rev)
	_box(g, Vector3(cx, y1 + 0.01, Z0 - WALL_T * 0.5), Vector3(w, 0.02, WALL_T), rev)
	_box(g, Vector3(x0 - 0.01, cy, Z0 - WALL_T * 0.5), Vector3(0.02, h, WALL_T), rev)
	_box(g, Vector3(x1 + 0.01, cy, Z0 - WALL_T * 0.5), Vector3(0.02, h, WALL_T), rev)
	# Glass: faint tint so the city reads clearly.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.82, 0.95, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic_specular = 0.8
	var gl := _box(g, Vector3(cx, cy, Z0 - WALL_T * 0.6), Vector3(w, h, 0.01), glass, false)
	gl.name = "Glass"
	# Frame + muntins.
	var f: float = 0.06
	_box(g, Vector3(cx, y1 + f * 0.5, Z0 + 0.03), Vector3(w + f * 2.0, f, 0.06), trim)
	_box(g, Vector3(cx, y0 - f * 0.5, Z0 + 0.06), Vector3(w + f * 2.0 + 0.1, f, 0.14), trim)
	_box(g, Vector3(x0 - f * 0.5, cy, Z0 + 0.03), Vector3(f, h, 0.06), trim)
	_box(g, Vector3(x1 + f * 0.5, cy, Z0 + 0.03), Vector3(f, h, 0.06), trim)
	_box(g, Vector3(cx, cy, Z0 - WALL_T * 0.55), Vector3(0.035, h, 0.03), trim)
	_box(g, Vector3(cx, y0 + h * 0.55, Z0 - WALL_T * 0.55), Vector3(w, 0.03, 0.03), trim)
	if big:
		# Curtains + rod.
		var cm: StandardMaterial3D = _fabric(COL_SAGE)
		for side in [-1.0, 1.0]:
			var px: float = cx + side * (w * 0.5 + 0.14)
			var c := _box(g, Vector3(px, y0 + h * 0.48, Z0 + 0.09), Vector3(0.26, h + 0.4, 0.06), cm)
			c.name = "Curtain"
			for k in range(3):
				_box(g, Vector3(px - 0.08 + 0.08 * float(k), y0 + h * 0.48, Z0 + 0.125), Vector3(0.02, h + 0.38, 0.012), _mat(COL_SAGE_D, 0.95), false)
			_box(g, Vector3(px, y0 + h * 0.3, Z0 + 0.13), Vector3(0.28, 0.04, 0.03), _mat(COL_MUSTARD, 0.8), false)
		_box(g, Vector3(cx, y1 + 0.16, Z0 + 0.1), Vector3(w + 0.8, 0.03, 0.03), _mat(COL_CAP, 0.5))
		_sphere(g, Vector3(cx - w * 0.5 - 0.42, y1 + 0.16, Z0 + 0.1), 0.03, _mat(COL_CAP, 0.5))
		_sphere(g, Vector3(cx + w * 0.5 + 0.42, y1 + 0.16, Z0 + 0.1), 0.03, _mat(COL_CAP, 0.5))
		# Plants on the sill.
		_small_plant(g, Vector3(x0 + 0.18, y0 + 0.0, Z0 + 0.07), COL_TERRACOTTA)
		_small_plant(g, Vector3(x1 - 0.2, y0 + 0.0, Z0 + 0.07), COL_CREAM, true)
	else:
		# Café curtain + herb pots.
		_box(g, Vector3(cx, y0 + h * 0.25, Z0 + 0.07), Vector3(w, h * 0.5, 0.02), _fabric(Color("F2E4CF")))
		_box(g, Vector3(cx, y0 + h * 0.5, Z0 + 0.08), Vector3(w + 0.1, 0.02, 0.02), _mat(COL_CAP, 0.5))
		for i in range(3):
			_small_plant(g, Vector3(x0 + 0.18 + 0.27 * float(i), y0, Z0 + 0.07), [COL_TERRACOTTA, COL_CREAM, COL_SAGE][i])
	# Cool moonlight spilling in.
	var spill := SpotLight3D.new()
	spill.light_color = Color("A9B8E8")
	spill.light_energy = 1.4 if big else 0.8
	spill.spot_range = 5.0
	spill.spot_angle = 38.0
	spill.spot_attenuation = 0.8
	spill.shadow_enabled = big
	spill.position = Vector3(cx, y1 + 0.2, Z0 - 0.2)
	spill.rotation_degrees = Vector3(-52, 0, 0)
	g.add_child(spill)

# --- bed nook ---------------------------------------------------------------------------------

func _build_bed_nook() -> void:
	var g: Node3D = _group("BedNook")
	var bx0: float = X0 + 0.05
	var bx1: float = -3.35
	var bz0: float = Z0 + 0.02
	var bz1: float = -1.4
	var cx: float = (bx0 + bx1) * 0.5
	var cz: float = (bz0 + bz1) * 0.5
	var bw: float = bx1 - bx0
	var bl: float = bz1 - bz0
	var bed: Node3D = _group("Bed", g)
	var wood: StandardMaterial3D = _mat(COL_WALNUT_L, 0.7)
	# Frame + legs.
	_box(bed, Vector3(cx, 0.2, cz + 0.04), Vector3(bw, 0.2, bl - 0.08), wood)
	for lx in [bx0 + 0.06, bx1 - 0.06]:
		_box(bed, Vector3(lx, 0.05, bz1 - 0.06), Vector3(0.08, 0.1, 0.08), _mat(COL_WALNUT, 0.7))
	# Headboard (upholstered, against the north wall).
	_box(bed, Vector3(cx, 0.55, bz0 + 0.05), Vector3(bw + 0.06, 0.9, 0.1), _fabric(Color("B98C8F")))
	var hb := _cyl(bed, Vector3(cx, 1.0, bz0 + 0.05), 0.05, bw + 0.06, _fabric(Color("B98C8F")))
	hb.rotation_degrees = Vector3(0, 0, 90)
	for i in range(4):
		_box(bed, Vector3(bx0 + bw * (0.2 + 0.2 * float(i)), 0.6, bz0 + 0.105), Vector3(0.02, 0.7, 0.01), _mat(Color("A57C7F"), 0.95), false)
	# Footboard.
	_box(bed, Vector3(cx, 0.3, bz1 - 0.03), Vector3(bw, 0.4, 0.06), wood)
	# Mattress + sheet.
	_box(bed, Vector3(cx, 0.38, cz + 0.05), Vector3(bw - 0.08, 0.17, bl - 0.22), _fabric(COL_CREAM))
	# Duvet (covers the lower part) with a folded band.
	var dz0: float = bz0 + bl * 0.36
	_box(bed, Vector3(cx, 0.47, (dz0 + bz1 - 0.06) * 0.5), Vector3(bw - 0.02, 0.06, bz1 - 0.06 - dz0), _fabric(COL_ROSE))
	_box(bed, Vector3(cx, 0.505, dz0 + 0.08), Vector3(bw - 0.01, 0.05, 0.18), _fabric(Color("F2E2D6")))
	var side := _box(bed, Vector3(bx1 - 0.0, 0.36, (dz0 + bz1 - 0.06) * 0.5), Vector3(0.03, 0.25, bz1 - 0.06 - dz0), _fabric(COL_ROSE))
	side.name = "DuvetDrape"
	# Knit throw at the foot.
	_box(bed, Vector3(cx, 0.51, bz1 - 0.32), Vector3(bw + 0.04, 0.035, 0.32), _fabric(COL_SAGE))
	for k in range(5):
		_box(bed, Vector3(bx0 + bw * (0.1 + 0.2 * float(k)), 0.53, bz1 - 0.32), Vector3(0.025, 0.01, 0.3), _mat(COL_SAGE_L, 0.95), false)
	# Pillows.
	_capsule(bed, Vector3(cx - 0.33, 0.52, bz0 + 0.3), 0.1, 0.55, _fabric(Color("FBF4EA")), Vector3(0, 0, 90)).scale = Vector3(1, 1, 1.6)
	_capsule(bed, Vector3(cx + 0.33, 0.52, bz0 + 0.3), 0.1, 0.55, _fabric(Color("FBF4EA")), Vector3(0, 0, 90)).scale = Vector3(1, 1, 1.6)
	var cushion := _box(bed, Vector3(cx, 0.6, bz0 + 0.44), Vector3(0.36, 0.26, 0.08), _fabric(COL_MUSTARD))
	cushion.rotation_degrees = Vector3(-18, 8, 0)
	# Book left on the bed.
	var book := _box(bed, Vector3(cx + 0.3, 0.515, cz + 0.55), Vector3(0.22, 0.03, 0.16), _mat(COL_TEAL, 0.8))
	book.rotation_degrees = Vector3(0, 25, 0)
	anchors["bed"] = bed
	points["bed"] = Vector3(cx, 0.0, cz)
	_block(bx0, bz0, bx1, bz1)
	# Wall shelf above the bed with a lamp, books and a trailing plant (west wall).
	var shelf: Node3D = _group("BedShelf", g)
	_box(shelf, Vector3(X0 + 0.12, 1.32, -2.45), Vector3(0.22, 0.04, 1.0), _mat(COL_OAK, 0.7))
	for z in [-2.85, -2.05]:
		_box(shelf, Vector3(X0 + 0.05, 1.26, z), Vector3(0.08, 0.1, 0.03), _mat(COL_CAP, 0.6))
	_small_plant(shelf, Vector3(X0 + 0.12, 1.34, -2.8), COL_CREAM, true)
	for i in range(4):
		var bh: float = 0.15 + 0.03 * float(i % 2)
		_box(shelf, Vector3(X0 + 0.12, 1.34 + bh * 0.5, -2.45 + 0.045 * float(i)), Vector3(0.15, bh, 0.04), _mat([COL_TERRACOTTA, COL_SAGE_D, COL_MUSTARD, COL_ROSE][i], 0.85))
	# Bedside lamp on the shelf.
	_cyl(shelf, Vector3(X0 + 0.12, 1.37, -2.1), 0.05, 0.06, _mat(COL_CREAM, 0.6))
	_cyl(shelf, Vector3(X0 + 0.12, 1.44, -2.1), 0.012, 0.12, _mat(COL_CAP, 0.5))
	var shade := _cyl(shelf, Vector3(X0 + 0.12, 1.55, -2.1), 0.1, 0.13, _mat(COL_LAMP, 0.6, 1.6), 0.07)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni(shelf, Vector3(X0 + 0.4, 1.5, -2.1), Color("FFC07A"), 0.9, 3.0)
	# Fairy lights across the north wall above the headboard.
	var fl: Node3D = _group("FairyLights", g)
	var n: int = 11
	for i in range(n):
		var t: float = float(i) / float(n - 1)
		var x: float = lerpf(X0 + 0.15, -2.2, t)
		var y: float = 1.72 - sin(t * PI) * 0.16 + (0.04 * sin(t * PI * 3.0))
		var bulb := _sphere(fl, Vector3(x, y, Z0 + 0.03), 0.028, _mat([COL_LAMP, Color("FFE3A8"), Color("FFB38A")][i % 3], 0.4, 2.4))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i < n - 1:
			var t2: float = float(i + 1) / float(n - 1)
			var x2: float = lerpf(X0 + 0.15, -2.2, t2)
			var y2: float = 1.72 - sin(t2 * PI) * 0.16 + (0.04 * sin(t2 * PI * 3.0))
			var seg := _box(fl, Vector3((x + x2) * 0.5, (y + y2) * 0.5 + 0.02, Z0 + 0.02), Vector3(Vector2(x2 - x, y2 - y).length(), 0.006, 0.006), _mat(Color("3E3A2E"), 0.9), false)
			seg.rotation_degrees = Vector3(0, 0, rad_to_deg(atan2(y2 - y, x2 - x)))
	_omni(fl, Vector3(-3.5, 1.6, Z0 + 0.4), Color("FFC98A"), 0.5, 2.6)
	# Little framed prints on the accent wall.
	_picture_north(g, Vector3(-3.95, 1.32, Z0 + 0.02), Vector2(0.34, 0.42), Color("F2E4CF"), COL_TERRACOTTA, 0)
	# Bedside rug.
	var rug := _box(g, Vector3(-3.05, 0.008, -2.35), Vector3(0.55, 0.014, 1.0), _fabric(Color("EFE3CF")), false)
	rug.name = "BedsideRug"
	_box(g, Vector3(-3.05, 0.01, -2.35), Vector3(0.45, 0.015, 0.9), _fabric(Color("E3D2B8")), false)

# --- wardrobe ---------------------------------------------------------------------------------

func _build_wardrobe() -> void:
	var g: Node3D = _group("Wardrobe")
	var x0: float = -3.2
	var x1: float = -2.15
	var z0: float = Z0 + 0.02
	var z1: float = Z0 + 0.6
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var w: float = x1 - x0
	var d: float = z1 - z0
	var h: float = 1.86
	var body: StandardMaterial3D = _mat(COL_WALNUT, 0.65)
	var panel: StandardMaterial3D = _mat(COL_WALNUT_L, 0.65)
	_box(g, Vector3(cx, 0.06, cz), Vector3(w - 0.08, 0.12, d - 0.06), _mat(COL_CAP, 0.7))
	_box(g, Vector3(cx, 0.12 + (h - 0.12) * 0.5, cz), Vector3(w, h - 0.12, d), body)
	_box(g, Vector3(cx, h + 0.03, cz + 0.01), Vector3(w + 0.08, 0.06, d + 0.06), _mat(COL_CAP, 0.65))
	# Two doors with inset panels.
	for side in [-1.0, 1.0]:
		var dx: float = cx + side * w * 0.25
		_box(g, Vector3(dx, 0.98, z1 + 0.01), Vector3(w * 0.5 - 0.05, 1.6, 0.02), panel)
		_box(g, Vector3(dx, 1.3, z1 + 0.025), Vector3(w * 0.5 - 0.16, 0.7, 0.01), _mat(COL_WALNUT, 0.6), false)
		_box(g, Vector3(dx, 0.62, z1 + 0.025), Vector3(w * 0.5 - 0.16, 0.6, 0.01), _mat(COL_WALNUT, 0.6), false)
		_sphere(g, Vector3(cx + side * 0.05, 1.0, z1 + 0.04), 0.022, _mat(Color("D9B36A"), 0.3))
	# A scarf hanging from a knob, hat box + basket on top.
	_box(g, Vector3(cx + 0.06, 0.82, z1 + 0.05), Vector3(0.07, 0.36, 0.02), _fabric(COL_MUSTARD))
	_box(g, Vector3(cx + 0.06, 0.62, z1 + 0.05), Vector3(0.09, 0.05, 0.022), _fabric(COL_TERRACOTTA))
	_cyl(g, Vector3(cx - 0.2, h + 0.15, cz), 0.17, 0.2, _mat(Color("D9C2A0"), 0.95))
	_cyl(g, Vector3(cx - 0.2, h + 0.26, cz), 0.18, 0.03, _mat(COL_ROSE, 0.9))
	_box(g, Vector3(cx + 0.24, h + 0.11, cz), Vector3(0.36, 0.14, 0.32), _mat(Color("C9A27A"), 0.95))
	anchors["wardrobe"] = g
	points["wardrobe"] = Vector3(cx, 0.0, cz)
	_block(x0, z0, x1, z1)

# --- desk under the big window ---------------------------------------------------------------

func _build_desk_and_window() -> void:
	var g: Node3D = _group("Desk")
	var x0: float = -1.9
	var x1: float = -0.4
	var z0: float = Z0 + 0.02
	var z1: float = Z0 + 0.56
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var top_y: float = 0.74
	var oak: StandardMaterial3D = _mat(COL_OAK, 0.6)
	_box(g, Vector3(cx, top_y - 0.02, cz), Vector3(x1 - x0, 0.04, z1 - z0), oak)
	for lx in [x0 + 0.05, x1 - 0.05]:
		for lz in [z0 + 0.05, z1 - 0.05]:
			_box(g, Vector3(lx, (top_y - 0.04) * 0.5, lz), Vector3(0.05, top_y - 0.04, 0.05), _mat(COL_OAK_D, 0.6))
	# Drawer unit.
	_box(g, Vector3(x1 - 0.25, top_y - 0.14, cz), Vector3(0.42, 0.2, z1 - z0 - 0.04), _mat(COL_OAK_D, 0.6))
	_box(g, Vector3(x1 - 0.25, top_y - 0.14, z1 - 0.01), Vector3(0.12, 0.025, 0.02), _mat(Color("D9B36A"), 0.3))
	# Planner notebook (open), pencil, mug with steam, cat-shaped paperweight-ish sticky notes.
	var nb: Node3D = _group("Notebook", g)
	nb.position = Vector3(cx - 0.12, top_y, cz + 0.08)
	nb.rotation_degrees = Vector3(0, -8, 0)
	_box(nb, Vector3(0, 0.01, 0), Vector3(0.5, 0.02, 0.34), _mat(COL_TERRACOTTA, 0.8))
	var lp := _box(nb, Vector3(-0.12, 0.028, 0), Vector3(0.23, 0.016, 0.31), _mat(Color("FFF8EC"), 0.9))
	lp.rotation_degrees = Vector3(0, 0, 3)
	var rp := _box(nb, Vector3(0.12, 0.028, 0), Vector3(0.23, 0.016, 0.31), _mat(Color("FFF8EC"), 0.9))
	rp.rotation_degrees = Vector3(0, 0, -3)
	for i in range(5):
		_box(nb, Vector3(-0.12, 0.038, -0.1 + 0.05 * float(i)), Vector3(0.17, 0.003, 0.008), _mat(Color("C9B49A"), 0.9), false)
		_box(nb, Vector3(0.12, 0.038, -0.1 + 0.05 * float(i)), Vector3(0.12 if i % 2 == 0 else 0.17, 0.003, 0.008), _mat(Color("C9B49A"), 0.9), false)
	_box(nb, Vector3(0.0, 0.04, 0.0), Vector3(0.012, 0.004, 0.3), _mat(COL_ROSE, 0.9), false)
	_box(nb, Vector3(0.14, 0.041, -0.06), Vector3(0.05, 0.004, 0.05), _mat(COL_MUSTARD, 0.9), false)
	var pencil := _cyl(nb, Vector3(0.18, 0.045, 0.1), 0.008, 0.2, _mat(Color("F2C14E"), 0.7))
	pencil.rotation_degrees = Vector3(90, 30, 0)
	# Mug.
	_cyl(g, Vector3(x0 + 0.22, top_y + 0.05, cz + 0.05), 0.045, 0.1, _mat(COL_SAGE, 0.6))
	_torus(g, Vector3(x0 + 0.27, top_y + 0.05, cz + 0.05), 0.02, 0.035, _mat(COL_SAGE, 0.6)).rotation_degrees = Vector3(90, 0, 0)
	_cyl(g, Vector3(x0 + 0.22, top_y + 0.098, cz + 0.05), 0.038, 0.004, _mat(Color("6B4A35"), 0.4))
	# Desk lamp.
	var lb := Vector3(x1 - 0.18, top_y, z0 + 0.14)
	_cyl(g, lb + Vector3(0, 0.015, 0), 0.07, 0.03, _mat(COL_MUSTARD, 0.5))
	var arm := _cyl(g, lb + Vector3(0.0, 0.17, 0.04), 0.012, 0.32, _mat(COL_MUSTARD, 0.5))
	arm.rotation_degrees = Vector3(15, 0, 0)
	var head := _cyl(g, lb + Vector3(0, 0.32, 0.12), 0.05, 0.1, _mat(COL_MUSTARD, 0.5), 0.09)
	head.rotation_degrees = Vector3(-40, 0, 0)
	_sphere(g, lb + Vector3(0, 0.29, 0.15), 0.03, _mat(Color("FFE7B8"), 0.3, 3.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dl := _omni(g, lb + Vector3(0.0, 0.3, 0.3), Color("FFD39A"), 0.8, 2.0)
	dl.name = "DeskLampLight"
	# Small stack of books.
	for i in range(3):
		_box(g, Vector3(x0 + 0.5, top_y + 0.025 + 0.045 * float(i), z0 + 0.12), Vector3(0.24 - 0.02 * float(i), 0.04, 0.17), _mat([COL_TEAL, COL_ROSE, COL_CREAM][i], 0.85))
	# Chair (pulled out a little).
	var ch: Node3D = _group("Chair", g)
	ch.position = Vector3(cx - 0.1, 0.0, z1 + 0.32)
	ch.rotation_degrees = Vector3(0, 8, 0)
	_box(ch, Vector3(0, 0.44, 0), Vector3(0.42, 0.04, 0.4), _mat(COL_OAK, 0.6))
	_box(ch, Vector3(0, 0.475, 0), Vector3(0.36, 0.04, 0.34), _fabric(COL_MUSTARD))
	for lx in [-0.18, 0.18]:
		for lz in [-0.17, 0.17]:
			_box(ch, Vector3(lx, 0.21, lz), Vector3(0.035, 0.42, 0.035), _mat(COL_OAK_D, 0.6))
	_box(ch, Vector3(0, 0.72, -0.18), Vector3(0.42, 0.22, 0.03), _mat(COL_OAK, 0.6))
	for lx in [-0.18, 0.18]:
		_box(ch, Vector3(lx, 0.62, -0.18), Vector3(0.035, 0.36, 0.035), _mat(COL_OAK_D, 0.6))
	anchors["planner"] = g
	points["planner"] = Vector3(cx, 0.0, cz)
	_block(x0, z0, x1, z1)
	_block(cx - 0.35, z1 + 0.1, cx + 0.15, z1 + 0.52)
	# Calendar above the desk on the wall.
	_box(g, Vector3(x1 + 0.0, 1.95, Z0 + 0.01), Vector3(0.02, 0.02, 0.02), _mat(COL_CAP, 0.5))

# --- bookshelf ---------------------------------------------------------------------------------

func _build_bookshelf() -> void:
	var g: Node3D = _group("Bookshelf")
	var x0: float = -0.15
	var x1: float = 0.72
	var z0: float = Z0 + 0.02
	var z1: float = Z0 + 0.36
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var h: float = 1.72
	var wood: StandardMaterial3D = _mat(COL_WALNUT_L, 0.65)
	_box(g, Vector3(cx, h * 0.5, z0 + 0.015), Vector3(x1 - x0, h, 0.03), _mat(COL_WALNUT, 0.7))
	_box(g, Vector3(x0 + 0.02, h * 0.5, cz), Vector3(0.04, h, z1 - z0), wood)
	_box(g, Vector3(x1 - 0.02, h * 0.5, cz), Vector3(0.04, h, z1 - z0), wood)
	var shelf_ys: Array[float] = [0.04, 0.45, 0.86, 1.27, h - 0.02]
	for y in shelf_ys:
		_box(g, Vector3(cx, y, cz), Vector3(x1 - x0, 0.04, z1 - z0), wood)
	var palette: Array[Color] = [COL_TERRACOTTA, COL_SAGE_D, COL_MUSTARD, COL_ROSE, COL_TEAL, COL_CREAM, Color("8E86B8"), Color("B86A50")]
	for si in range(3):
		var y: float = shelf_ys[si] + 0.02
		var x: float = x0 + 0.06
		var limit: float = x1 - 0.06
		if si == 1:
			limit = cx + 0.05
		while x < limit - 0.04:
			var bw: float = _rng.randf_range(0.035, 0.06)
			var bh: float = _rng.randf_range(0.25, 0.34)
			var b := _box(g, Vector3(x + bw * 0.5, y + bh * 0.5, cz + 0.02), Vector3(bw, bh, 0.22), _mat(palette[_rng.randi_range(0, palette.size() - 1)], 0.85))
			if _rng.randf() < 0.12:
				b.rotation_degrees = Vector3(0, 0, -10)
			x += bw + 0.006
		if si == 1:
			# Framed photo + a tiny ceramic cat on the middle shelf.
			var fr := _box(g, Vector3(x1 - 0.18, y + 0.12, cz + 0.04), Vector3(0.18, 0.22, 0.02), _mat(COL_OAK, 0.6))
			fr.rotation_degrees = Vector3(-8, 0, 0)
			_box(g, Vector3(x1 - 0.18, y + 0.12, cz + 0.052), Vector3(0.14, 0.17, 0.005), _mat(Color("9DB8C8"), 0.9), false)
			_sphere(g, Vector3(x1 - 0.32, y + 0.05, cz + 0.06), 0.045, _mat(Color("2F2A2E"), 0.5), 1.0)
			_sphere(g, Vector3(x1 - 0.32, y + 0.11, cz + 0.07), 0.032, _mat(Color("2F2A2E"), 0.5), 1.0)
	# Bottom shelf: woven storage baskets.
	_box(g, Vector3(x0 + 0.22, 0.2, cz + 0.02), Vector3(0.36, 0.3, 0.28), _mat(Color("C9A77E"), 0.95))
	_box(g, Vector3(x1 - 0.22, 0.2, cz + 0.02), Vector3(0.36, 0.3, 0.28), _mat(Color("B8956B"), 0.95))
	# Top: trailing plant + a candle.
	_small_plant(g, Vector3(x0 + 0.2, h, cz), COL_CREAM, true)
	_cyl(g, Vector3(x1 - 0.2, h + 0.07, cz), 0.04, 0.14, _mat(COL_CREAM, 0.7))
	_block(x0, z0, x1, z1)

# --- kitchen -----------------------------------------------------------------------------------

func _build_kitchen() -> void:
	var g: Node3D = _group("Kitchen")
	var x0: float = 1.0
	var x1: float = 3.85
	var z0: float = Z0 + 0.02
	var z1: float = Z0 + 0.62
	var cz: float = (z0 + z1) * 0.5
	var ch: float = 0.88
	var cab: StandardMaterial3D = _mat(Color("8FA88A"), 0.7)
	var cab_d: StandardMaterial3D = _mat(Color("7E9879"), 0.7)
	var top: StandardMaterial3D = _mat(Color("C9955E"), 0.5)
	# Backsplash.
	var bs: StandardMaterial3D = _triplanar(_subway_texture(), 3.2, 0.4)
	_box(g, Vector3((x0 + 4.85) * 0.5, ch + 0.36, Z0 + 0.008), Vector3(4.85 - x0, 0.7, 0.016), bs, false)
	# Base cabinets.
	_box(g, Vector3((x0 + x1) * 0.5, 0.05, cz - 0.03), Vector3(x1 - x0 - 0.04, 0.1, z1 - z0 - 0.06), _mat(COL_CAP, 0.7))
	_box(g, Vector3((x0 + x1) * 0.5, 0.1 + (ch - 0.1) * 0.5, cz), Vector3(x1 - x0, ch - 0.1, z1 - z0), cab)
	var n_doors: int = 5
	var dw: float = (x1 - x0) / float(n_doors)
	for i in range(n_doors):
		var dx: float = x0 + dw * (float(i) + 0.5)
		if i == 3:
			continue  # oven
		_box(g, Vector3(dx, 0.48, z1 + 0.008), Vector3(dw - 0.05, 0.62, 0.016), cab_d, false)
		_box(g, Vector3(dx, 0.48, z1 + 0.018), Vector3(dw - 0.15, 0.5, 0.01), cab, false)
		_box(g, Vector3(dx, ch - 0.1, z1 + 0.008), Vector3(dw - 0.05, 0.1, 0.016), cab_d, false)
		_sphere(g, Vector3(dx + (dw * 0.32 if i % 2 == 0 else -dw * 0.32), 0.66, z1 + 0.03), 0.018, _mat(COL_CREAM, 0.4))
	# Counter top.
	_box(g, Vector3((x0 + x1) * 0.5, ch + 0.025, cz + 0.02), Vector3(x1 - x0 + 0.04, 0.05, z1 - z0 + 0.04), top)
	# Sink (under the kitchen window).
	var sx: float = 1.95
	_box(g, Vector3(sx, ch + 0.03, cz + 0.02), Vector3(0.52, 0.04, 0.38), _mat(Color("C7CCD0"), 0.25))
	_box(g, Vector3(sx, ch + 0.035, cz + 0.02), Vector3(0.44, 0.04, 0.3), _mat(Color("5E6468"), 0.3), false)
	_cyl(g, Vector3(sx, ch + 0.15, z0 + 0.08), 0.015, 0.24, _mat(Color("C7CCD0"), 0.2))
	var spout := _cyl(g, Vector3(sx, ch + 0.26, z0 + 0.15), 0.013, 0.16, _mat(Color("C7CCD0"), 0.2))
	spout.rotation_degrees = Vector3(80, 0, 0)
	# Dish rack with plates.
	_box(g, Vector3(sx + 0.48, ch + 0.06, cz + 0.02), Vector3(0.3, 0.06, 0.26), _mat(Color("D8D2C4"), 0.6))
	for i in range(3):
		var p := _cyl(g, Vector3(sx + 0.4 + 0.07 * float(i), ch + 0.16, cz + 0.02), 0.1, 0.012, _mat([COL_CREAM, COL_SAGE_L, COL_CREAM][i], 0.4))
		p.rotation_degrees = Vector3(0, 0, 90)
	# Stove + oven.
	var ox: float = x0 + dw * 3.5
	_box(g, Vector3(ox, 0.48, z1 + 0.008), Vector3(dw - 0.04, 0.68, 0.016), _mat(Color("F2E8DA"), 0.4), false)
	_box(g, Vector3(ox, 0.46, z1 + 0.02), Vector3(dw - 0.16, 0.32, 0.01), _mat(Color("3A3236"), 0.2), false)
	_box(g, Vector3(ox, 0.72, z1 + 0.04), Vector3(dw - 0.18, 0.025, 0.025), _mat(Color("C7CCD0"), 0.2))
	_box(g, Vector3(ox, ch + 0.055, cz + 0.02), Vector3(dw - 0.02, 0.012, z1 - z0 - 0.04), _mat(Color("3A3236"), 0.4))
	for bxo in [-0.13, 0.13]:
		for bzo in [-0.1, 0.1]:
			_torus(g, Vector3(ox + bxo, ch + 0.065, cz + 0.02 + bzo), 0.045, 0.07, _mat(Color("1E1A1C"), 0.5), 0.4)
	# Kettle on the stove.
	var kp := Vector3(ox - 0.13, ch + 0.07, cz + 0.12)
	_sphere(g, kp + Vector3(0, 0.08, 0), 0.1, _mat(Color("C9584A"), 0.35), 0.8)
	_cyl(g, kp + Vector3(0, 0.15, 0), 0.03, 0.03, _mat(Color("3A3236"), 0.4))
	var sp := _cyl(g, kp + Vector3(0.1, 0.1, 0), 0.015, 0.1, _mat(Color("C9584A"), 0.35), 0.01)
	sp.rotation_degrees = Vector3(0, 0, -55)
	# Fruit bowl + cutting board + jars on the counter.
	var fb := Vector3(x0 + 0.28, ch + 0.05, cz + 0.06)
	_cyl(g, fb + Vector3(0, 0.03, 0), 0.13, 0.06, _mat(COL_CREAM, 0.6), 0.16)
	for i in range(4):
		var a: float = TAU * float(i) / 4.0
		_sphere(g, fb + Vector3(cos(a) * 0.06, 0.09, sin(a) * 0.06), 0.045, _mat(Color("E8913A") if i != 2 else Color("B8C24A"), 0.6))
	var board := _box(g, Vector3(x1 - 0.32, ch + 0.06, cz + 0.05), Vector3(0.34, 0.025, 0.24), _mat(Color("D9A86E"), 0.6))
	board.rotation_degrees = Vector3(0, -12, 0)
	# Open shelves with jars/plates above the counter.
	for y in [1.5, 1.82]:
		_box(g, Vector3(3.3, y, Z0 + 0.13), Vector3(1.0, 0.035, 0.24), _mat(COL_OAK, 0.6))
		for bx in [2.88, 3.72]:
			var br := _box(g, Vector3(bx, y - 0.06, Z0 + 0.04), Vector3(0.03, 0.12, 0.06), _mat(COL_CAP, 0.6))
			br.name = "Bracket"
	var jar_cols: Array[Color] = [Color("E8C99A"), Color("C98A5E"), Color("B5CBB4"), Color("F2E4CF")]
	for i in range(4):
		var jx: float = 2.95 + 0.14 * float(i)
		var jh: float = 0.16 + 0.03 * float(i % 2)
		_cyl(g, Vector3(jx, 1.52 + jh * 0.5, Z0 + 0.13), 0.05, jh, _mat(jar_cols[i], 0.35))
		_cyl(g, Vector3(jx, 1.52 + jh + 0.012, Z0 + 0.13), 0.052, 0.024, _mat(COL_WALNUT_L, 0.5))
	for i in range(3):
		_cyl(g, Vector3(3.55, 1.53 + 0.025 * float(i), Z0 + 0.13), 0.1, 0.02, _mat(COL_CREAM, 0.4))
	for i in range(3):
		var mug := _cyl(g, Vector3(2.98 + 0.16 * float(i), 1.89, Z0 + 0.13), 0.04, 0.09, _mat([COL_TERRACOTTA, COL_SAGE, COL_MUSTARD][i], 0.5))
		mug.name = "Mug"
	_small_plant(g, Vector3(3.6, 1.84, Z0 + 0.13), COL_CREAM, true)
	# Warm under-shelf strip light.
	var strip := _box(g, Vector3(3.3, 1.475, Z0 + 0.2), Vector3(0.9, 0.012, 0.02), _mat(Color("FFE2B0"), 0.3, 2.2), false)
	strip.name = "UnderShelfLight"
	_omni(g, Vector3(3.0, 1.3, Z0 + 0.55), Color("FFD39A"), 0.9, 2.6)
	# Wall clock between window and shelves.
	var clock := _cyl(g, Vector3(2.62, 1.68, Z0 + 0.025), 0.14, 0.03, _mat(COL_CREAM, 0.5))
	clock.rotation_degrees = Vector3(90, 0, 0)
	_torus(g, Vector3(2.62, 1.68, Z0 + 0.03), 0.13, 0.155, _mat(COL_WALNUT, 0.5)).rotation_degrees = Vector3(90, 0, 0)
	var hh := _box(g, Vector3(2.6, 1.715, Z0 + 0.045), Vector3(0.012, 0.07, 0.005), _mat(COL_TEXT, 0.5), false)
	hh.rotation_degrees = Vector3(0, 0, 30)
	var mh := _box(g, Vector3(2.65, 1.69, Z0 + 0.046), Vector3(0.01, 0.1, 0.005), _mat(COL_TEXT, 0.5), false)
	mh.rotation_degrees = Vector3(0, 0, -70)
	_block(x0, z0, x1, z1)
	# Fridge.
	var fr: Node3D = _group("Fridge", g)
	var fx0: float = 3.95
	var fx1: float = 4.85
	var fz1: float = Z0 + 0.66
	var fcx: float = (fx0 + fx1) * 0.5
	var fcz: float = (z0 + fz1) * 0.5
	var fh: float = 1.82
	var enamel: StandardMaterial3D = _mat(Color("EDE3D2"), 0.35)
	_box(fr, Vector3(fcx, fh * 0.5 + 0.04, fcz), Vector3(fx1 - fx0, fh - 0.08, fz1 - z0), enamel)
	var topr := _cyl(fr, Vector3(fcx, fh - 0.04, fcz), (fz1 - z0) * 0.5, fx1 - fx0, enamel)
	topr.rotation_degrees = Vector3(0, 0, 90)
	topr.scale = Vector3(1, 1, 0.999)
	_box(fr, Vector3(fcx, 0.03, fcz), Vector3(fx1 - fx0 - 0.08, 0.06, fz1 - z0 - 0.04), _mat(Color("C7CCD0"), 0.3))
	_box(fr, Vector3(fcx, 1.25, fz1 + 0.004), Vector3(fx1 - fx0 - 0.02, 0.012, 0.01), _mat(Color("CFC4B2"), 0.4), false)
	for hy in [1.45, 0.9]:
		_box(fr, Vector3(fx0 + 0.1, hy, fz1 + 0.03), Vector3(0.03, 0.26 if hy < 1.0 else 0.16, 0.03), _mat(Color("C7CCD0"), 0.2))
	# Magnets, a shopping list and a kid's cat drawing.
	_box(fr, Vector3(fcx + 0.12, 1.5, fz1 + 0.006), Vector3(0.2, 0.26, 0.004), _mat(Color("FFFDF6"), 0.9), false)
	for i in range(4):
		_box(fr, Vector3(fcx + 0.12, 1.58 - 0.05 * float(i), fz1 + 0.009), Vector3(0.13, 0.008, 0.002), _mat(Color("8FA3C9"), 0.9), false)
	_box(fr, Vector3(fcx + 0.08, 0.95, fz1 + 0.006), Vector3(0.3, 0.24, 0.004), _mat(Color("FFF3D6"), 0.9), false)
	_motif(fr, Vector3(fcx + 0.08, 0.95, fz1 + 0.01), 0.24, COL_TERRACOTTA, 0, false)
	for mp in [Vector3(fcx + 0.12, 1.63, fz1 + 0.012), Vector3(fcx + 0.08, 1.07, fz1 + 0.012), Vector3(fcx - 0.18, 1.1, fz1 + 0.012)]:
		_sphere(fr, mp, 0.022, _mat([COL_ROSE, COL_MUSTARD, COL_TEAL][int(mp.y * 10) % 3], 0.5))
	_block(fx0, z0, fx1, fz1)
	# Small round dining table with two chairs.
	var tb: Node3D = _group("DiningTable", g)
	var tc := Vector3(2.45, 0.0, -1.62)
	_cyl(tb, tc + Vector3(0, 0.71, 0), 0.42, 0.04, _mat(COL_OAK, 0.55))
	_cyl(tb, tc + Vector3(0, 0.36, 0), 0.04, 0.7, _mat(COL_WALNUT_L, 0.6))
	_cyl(tb, tc + Vector3(0, 0.02, 0), 0.2, 0.04, _mat(COL_WALNUT_L, 0.6))
	_cyl(tb, tc + Vector3(0.0, 0.73, 0.0), 0.2, 0.004, _fabric(Color("F2E4CF")))
	_cyl(tb, tc + Vector3(0.08, 0.8, -0.05), 0.04, 0.14, _mat(Color("8FB0C4"), 0.2))
	for i in range(4):
		var a: float = TAU * float(i) / 4.0
		_sphere(tb, tc + Vector3(0.08 + cos(a) * 0.035, 0.9, -0.05 + sin(a) * 0.035), 0.028, _mat([COL_ROSE, COL_MUSTARD, Color("F2E4CF"), COL_TERRACOTTA][i], 0.8))
	_cyl(tb, tc + Vector3(-0.12, 0.76, 0.08), 0.03, 0.06, _mat(COL_CREAM, 0.6))
	_sphere(tb, tc + Vector3(-0.12, 0.81, 0.08), 0.012, _mat(Color("FFC060"), 0.3, 3.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		var cp: Vector3 = tc + Vector3(side * 0.55, 0, 0.05)
		_box(tb, cp + Vector3(0, 0.44, 0), Vector3(0.38, 0.04, 0.38), _mat(COL_OAK, 0.6))
		_cyl(tb, cp + Vector3(0, 0.475, 0), 0.16, 0.035, _fabric(COL_ROSE))
		for lx in [-0.16, 0.16]:
			for lz in [-0.16, 0.16]:
				_box(tb, cp + Vector3(lx, 0.21, lz), Vector3(0.03, 0.42, 0.03), _mat(COL_OAK_D, 0.6))
		_box(tb, cp + Vector3(side * 0.17, 0.7, 0), Vector3(0.03, 0.5, 0.38), _mat(COL_OAK, 0.6))
	_block(tc.x - 0.75, tc.z - 0.35, tc.x + 0.75, tc.z + 0.35)

# --- cat feeding station -----------------------------------------------------------------------

func _build_feed_station() -> void:
	var g: Node3D = _group("FeedStation")
	# Placemat in front of the fridge (cells (12,1) and (13,1)); cats eat standing at those cells.
	var c1: Vector3 = cell_center(Vector2i(12, 1))
	var c2: Vector3 = cell_center(Vector2i(13, 1))
	var mz: float = c1.z - 0.18
	var mat_c := Vector3((c1.x + c2.x) * 0.5, 0.008, mz)
	_box(g, mat_c, Vector3(1.05, 0.012, 0.36), _fabric(Color("D98C7A")), false)
	_box(g, mat_c + Vector3(0, 0.003, 0), Vector3(0.97, 0.012, 0.28), _fabric(Color("E8A897")), false)
	# Food bowl (with kibble) and water bowl.
	var b1 := Vector3(c1.x, 0.0, mz)
	_cyl(g, b1 + Vector3(0, 0.04, 0), 0.11, 0.08, _mat(COL_TEAL, 0.35), 0.14)
	_cyl(g, b1 + Vector3(0, 0.081, 0), 0.115, 0.004, _mat(Color("8B5E3C"), 0.9))
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		_sphere(g, b1 + Vector3(cos(a) * 0.05, 0.088, sin(a) * 0.05), 0.018, _mat(Color("9A6A44"), 0.9))
	var b2 := Vector3(c2.x - 0.1, 0.0, mz)
	_cyl(g, b2 + Vector3(0, 0.04, 0), 0.11, 0.08, _mat(COL_CREAM, 0.3), 0.14)
	_cyl(g, b2 + Vector3(0, 0.07, 0), 0.12, 0.004, _mat(Color("8EC3D9"), 0.1))
	# Kibble tin with a paw label + scoop.
	var tin := Vector3(c2.x + 0.22, 0.0, mz - 0.02)
	_cyl(g, tin + Vector3(0, 0.15, 0), 0.1, 0.3, _mat(Color("E8C99A"), 0.4))
	_cyl(g, tin + Vector3(0, 0.31, 0), 0.105, 0.03, _mat(COL_TERRACOTTA, 0.4))
	_sphere(g, tin + Vector3(0, 0.335, 0), 0.025, _mat(COL_WALNUT, 0.4))
	_sphere(g, tin + Vector3(0.0, 0.15, 0.1), 0.03, _mat(COL_WALNUT_L, 0.8), 0.3)
	var scoop := _cyl(g, tin + Vector3(-0.18, 0.02, 0.12), 0.03, 0.04, _mat(Color("C9584A"), 0.4))
	scoop.name = "Scoop"
	anchors["feed"] = g
	points["feed"] = Vector3(mat_c.x, 0.0, mz)
	points["bowl_cell_a"] = c1
	points["bowl_cell_b"] = c2

# --- living area -------------------------------------------------------------------------------

func _build_living() -> void:
	var g: Node3D = _group("Living")
	# Patterned rug.
	var rc := Vector3(-2.55, 0.006, 0.0)
	var rug := _floor_quad(g, rc, Vector2(2.5, 2.4), _rug_texture())
	rug.name = "LivingRug"
	_box(g, rc + Vector3(0, -0.002, 0), Vector3(2.52, 0.01, 2.42), _mat(Color("7A4A3A"), 1.0), false)
	# Sofa against the west wall, facing +X.
	var sofa: Node3D = _group("Sofa", g)
	var sx0: float = X0 + 0.05
	var sx1: float = -3.95
	var sz0: float = -1.12
	var sz1: float = 0.92
	var scx: float = (sx0 + sx1) * 0.5
	var scz: float = (sz0 + sz1) * 0.5
	var sl: float = sz1 - sz0
	var fab: StandardMaterial3D = _fabric(COL_TEAL)
	var fab_l: StandardMaterial3D = _fabric(COL_TEAL.lightened(0.1))
	_box(sofa, Vector3(scx, 0.2, scz), Vector3(sx1 - sx0, 0.24, sl), fab)
	for i in range(2):
		var cz: float = sz0 + 0.22 + (sl - 0.44) * (0.25 + 0.5 * float(i))
		_box(sofa, Vector3(scx + 0.07, 0.39, cz), Vector3(sx1 - sx0 - 0.2, 0.14, (sl - 0.44) * 0.5 - 0.02), fab_l)
		_box(sofa, Vector3(sx0 + 0.15, 0.62, cz), Vector3(0.2, 0.4, (sl - 0.44) * 0.5 - 0.02), fab_l)
	_box(sofa, Vector3(sx0 + 0.06, 0.5, scz), Vector3(0.12, 0.62, sl), fab)
	for zz in [sz0 + 0.11, sz1 - 0.11]:
		_box(sofa, Vector3(scx, 0.4, zz), Vector3(sx1 - sx0, 0.4, 0.22), fab)
		var roll := _cyl(sofa, Vector3(scx, 0.6, zz), 0.11, sx1 - sx0, fab)
		roll.rotation_degrees = Vector3(0, 0, 90)
	for lx in [sx0 + 0.08, sx1 - 0.08]:
		for lz in [sz0 + 0.08, sz1 - 0.08]:
			_cyl(sofa, Vector3(lx, 0.04, lz), 0.03, 0.08, _mat(COL_WALNUT, 0.6), 0.022)
	var p1 := _box(sofa, Vector3(sx0 + 0.3, 0.6, sz0 + 0.38), Vector3(0.1, 0.3, 0.3), _fabric(COL_MUSTARD))
	p1.rotation_degrees = Vector3(0, 0, -16)
	var p2 := _box(sofa, Vector3(sx0 + 0.3, 0.6, sz1 - 0.4), Vector3(0.1, 0.28, 0.28), _fabric(COL_ROSE))
	p2.rotation_degrees = Vector3(8, 0, -14)
	# Knit throw over the arm.
	_box(sofa, Vector3(scx + 0.05, 0.72, sz1 - 0.12), Vector3(sx1 - sx0 - 0.1, 0.03, 0.26), _fabric(COL_CREAM))
	_box(sofa, Vector3(sx1 + 0.02, 0.5, sz1 - 0.12), Vector3(0.03, 0.4, 0.25), _fabric(COL_CREAM))
	_block(sx0, sz0, sx1, sz1)
	# Wall shelf with plants + prints above the sofa (west wall).
	_box(g, Vector3(X0 + 0.1, 1.42, scz), Vector3(0.18, 0.035, 1.2), _mat(COL_OAK, 0.6))
	_small_plant(g, Vector3(X0 + 0.1, 1.44, scz - 0.45), COL_TERRACOTTA, true)
	_small_plant(g, Vector3(X0 + 0.1, 1.44, scz + 0.42), COL_CREAM)
	_picture_west(g, Vector3(X0 + 0.04, 1.62, scz - 0.05), Vector2(0.42, 0.32), Color("F2E4CF"), COL_TEAL, 1)
	_picture_west(g, Vector3(X0 + 0.04, 1.08, scz - 0.35), Vector2(0.3, 0.3), Color("E8A87C"), Color("6B4A35"), 0)
	_picture_west(g, Vector3(X0 + 0.04, 1.06, scz + 0.32), Vector2(0.28, 0.38), Color("A9BFA4"), Color("F2E4CF"), 2)
	# Coffee table.
	var tbl: Node3D = _group("CoffeeTable", g)
	var tcen := Vector3(-2.75, 0.0, -0.1)
	_box(tbl, tcen + Vector3(0, 0.36, 0), Vector3(0.6, 0.05, 1.0), _mat(COL_WALNUT_L, 0.5))
	_box(tbl, tcen + Vector3(0, 0.12, 0), Vector3(0.5, 0.03, 0.9), _mat(COL_WALNUT_L, 0.5))
	for lx in [-0.25, 0.25]:
		for lz in [-0.44, 0.44]:
			_box(tbl, tcen + Vector3(lx, 0.17, lz), Vector3(0.04, 0.34, 0.04), _mat(COL_WALNUT, 0.6))
	# Tea for one, a book, a candle, magazines underneath.
	_cyl(tbl, tcen + Vector3(0.05, 0.43, -0.25), 0.045, 0.09, _mat(COL_CREAM, 0.4))
	_cyl(tbl, tcen + Vector3(0.05, 0.476, -0.25), 0.038, 0.004, _mat(Color("A8683E"), 0.3))
	var bk := _box(tbl, tcen + Vector3(-0.05, 0.4, 0.15), Vector3(0.2, 0.03, 0.28), _mat(COL_TERRACOTTA, 0.8))
	bk.rotation_degrees = Vector3(0, 20, 0)
	_cyl(tbl, tcen + Vector3(0.1, 0.43, 0.35), 0.05, 0.1, _mat(Color("F2E4CF"), 0.6))
	_sphere(tbl, tcen + Vector3(0.1, 0.5, 0.35), 0.014, _mat(Color("FFC060"), 0.3, 3.5)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni(tbl, tcen + Vector3(0.1, 0.7, 0.35), Color("FFB46A"), 0.35, 1.4)
	_box(tbl, tcen + Vector3(0, 0.15, -0.1), Vector3(0.36, 0.03, 0.5), _mat(COL_SAGE, 0.8))
	_block(tcen.x - 0.3, tcen.z - 0.5, tcen.x + 0.3, tcen.z + 0.5)
	# Floor lamp beside the sofa.
	var lamp: Node3D = _group("FloorLamp", g)
	var lp := Vector3(X0 + 0.3, 0.0, 1.22)
	_cyl(lamp, lp + Vector3(0, 0.02, 0), 0.16, 0.04, _mat(COL_CAP, 0.5))
	_cyl(lamp, lp + Vector3(0, 0.75, 0), 0.016, 1.46, _mat(COL_CAP, 0.5))
	var sh := _cyl(lamp, lp + Vector3(0, 1.52, 0), 0.24, 0.3, _mat(Color("FFD9A0"), 0.7, 1.3), 0.17)
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni(lamp, lp + Vector3(0.25, 1.35, 0.0), Color("FFC07A"), 1.6, 4.2, true)
	_block(lp.x - 0.16, lp.z - 0.16, lp.x + 0.16, lp.z + 0.16)
	# Floor cushion + a basket of yarn at the rug edge.
	var cush := _box(g, Vector3(-1.6, 0.06, 0.75), Vector3(0.5, 0.12, 0.5), _fabric(COL_MUSTARD))
	cush.rotation_degrees = Vector3(0, 20, 0)
	_cyl(g, Vector3(-1.6, 0.125, 0.75), 0.04, 0.01, _mat(COL_MUSTARD.darkened(0.2), 0.9))
	_cyl(g, Vector3(-1.55, 0.1, -0.95), 0.15, 0.2, _mat(Color("C9A77E"), 0.95), 0.17)
	_sphere(g, Vector3(-1.58, 0.2, -0.95), 0.07, _fabric(COL_ROSE))
	_sphere(g, Vector3(-1.5, 0.21, -0.9), 0.06, _fabric(COL_SAGE))
	# Front: a record crate with a little turntable, a big leafy plant, a laundry basket.
	var rec: Node3D = _group("RecordCrate", g)
	var rp := Vector3(-2.35, 0.0, 3.12)
	_box(rec, rp + Vector3(0, 0.2, 0), Vector3(0.7, 0.4, 0.42), _mat(COL_OAK, 0.7))
	_box(rec, rp + Vector3(0, 0.21, 0.212), Vector3(0.62, 0.3, 0.01), _mat(COL_OAK_D, 0.7), false)
	for i in range(7):
		_box(rec, rp + Vector3(-0.27 + 0.09 * float(i), 0.3, 0.0), Vector3(0.02, 0.28, 0.32), _mat([COL_TERRACOTTA, COL_TEAL, COL_MUSTARD, COL_ROSE, COL_SAGE_D, COL_CREAM, Color("8E86B8")][i], 0.8))
	_box(rec, rp + Vector3(0, 0.44, 0), Vector3(0.5, 0.06, 0.36), _mat(COL_WALNUT, 0.6))
	_cyl(rec, rp + Vector3(-0.04, 0.48, 0), 0.14, 0.012, _mat(Color("2A2428"), 0.3))
	_cyl(rec, rp + Vector3(-0.04, 0.488, 0), 0.04, 0.006, _mat(COL_TERRACOTTA, 0.6))
	var arm := _box(rec, rp + Vector3(0.14, 0.49, -0.04), Vector3(0.015, 0.012, 0.2), _mat(Color("C7CCD0"), 0.3))
	arm.rotation_degrees = Vector3(0, 25, 0)
	_block(rp.x - 0.35, rp.z - 0.21, rp.x + 0.35, rp.z + 0.21)
	_plant(g, Vector3(-3.55, 0.0, 3.1), 0.95, COL_CREAM, 0.17)
	_block(-3.75, 2.9, -3.35, 3.3)
	_cyl(g, Vector3(-1.45, 0.14, 3.15), 0.2, 0.28, _mat(Color("C9A77E"), 0.95), 0.23)
	_box(g, Vector3(-1.45, 0.29, 3.15), Vector3(0.3, 0.06, 0.26), _fabric(Color("F2E4CF")))
	_box(g, Vector3(-1.42, 0.31, 3.08), Vector3(0.2, 0.05, 0.12), _fabric(COL_SAGE))
	_block(-1.65, 2.95, -1.25, 3.35)

# --- front door --------------------------------------------------------------------------------

func _build_door() -> void:
	var g: Node3D = _group("FrontDoor")
	var dz0: float = 1.6
	var dz1: float = 2.6
	var dcz: float = (dz0 + dz1) * 0.5
	var dh: float = 1.95
	var x: float = X0
	var trim: StandardMaterial3D = _mat(COL_TRIM, 0.7)
	# Casing.
	_box(g, Vector3(x + 0.03, dh * 0.5, dz0 - 0.04), Vector3(0.06, dh, 0.08), trim)
	_box(g, Vector3(x + 0.03, dh * 0.5, dz1 + 0.04), Vector3(0.06, dh, 0.08), trim)
	_box(g, Vector3(x + 0.03, dh + 0.04, dcz), Vector3(0.06, 0.08, dz1 - dz0 + 0.16), trim)
	# Door slab (warm terracotta) with panels, window, knob.
	var door_col := Color("B5654A")
	_box(g, Vector3(x + 0.025, dh * 0.5, dcz), Vector3(0.04, dh, dz1 - dz0), _mat(door_col, 0.6))
	for py in [0.45, 1.05]:
		_box(g, Vector3(x + 0.05, py, dcz), Vector3(0.012, 0.42, dz1 - dz0 - 0.3), _mat(door_col.darkened(0.12), 0.6), false)
	var win := _box(g, Vector3(x + 0.05, 1.58, dcz), Vector3(0.012, 0.36, 0.5), _mat(Color("FFE2B0"), 0.2, 0.6), false)
	win.name = "DoorWindow"
	_box(g, Vector3(x + 0.056, 1.58, dcz), Vector3(0.01, 0.36, 0.025), _mat(door_col, 0.6), false)
	_sphere(g, Vector3(x + 0.08, 0.98, dz1 - 0.12), 0.03, _mat(Color("D9B36A"), 0.3))
	_box(g, Vector3(x + 0.055, 0.98, dz1 - 0.12), Vector3(0.012, 0.12, 0.05), _mat(Color("D9B36A"), 0.3), false)
	# Little wreath of leaves on the door.
	_torus(g, Vector3(x + 0.07, 1.25, dcz), 0.1, 0.15, _mat(COL_LEAF_A, 0.9)).rotation_degrees = Vector3(0, 0, 90)
	_sphere(g, Vector3(x + 0.1, 1.12, dcz), 0.03, _mat(COL_TERRACOTTA, 0.7))
	# Door mat.
	var mat_c := Vector3(x + 0.38, 0.008, dcz)
	_box(g, mat_c, Vector3(0.6, 0.014, 0.95), _fabric(Color("A65F48")), false)
	_box(g, mat_c + Vector3(0, 0.003, 0), Vector3(0.48, 0.014, 0.83), _fabric(Color("C9785D")), false)
	var hello := _label(g, "HOME", mat_c + Vector3(0, 0.012, 0), Vector3(-90, 90, 0), 64, Color("FFF6EA"))
	hello.name = "MatLabel"
	# Coat hooks with a scarf and tote, shoe bench, umbrella stand.
	_box(g, Vector3(x + 0.03, 1.5, 3.05), Vector3(0.04, 0.08, 0.7), _mat(COL_OAK, 0.6))
	for i in range(3):
		_cyl(g, Vector3(x + 0.08, 1.48, 2.82 + 0.23 * float(i)), 0.015, 0.08, _mat(COL_CAP, 0.4)).rotation_degrees = Vector3(0, 0, 90)
	_box(g, Vector3(x + 0.1, 1.2, 2.82), Vector3(0.06, 0.55, 0.12), _fabric(COL_MUSTARD))
	_box(g, Vector3(x + 0.12, 1.22, 3.28), Vector3(0.1, 0.36, 0.3), _fabric(Color("D9C2A0")))
	_box(g, Vector3(x + 0.13, 1.42, 3.28), Vector3(0.02, 0.12, 0.2), _mat(COL_WALNUT_L, 0.7), false)
	var bench_z: float = 3.08
	_box(g, Vector3(x + 0.2, 0.32, bench_z), Vector3(0.36, 0.04, 0.68), _mat(COL_OAK, 0.6))
	_box(g, Vector3(x + 0.2, 0.12, bench_z), Vector3(0.34, 0.03, 0.66), _mat(COL_OAK, 0.6))
	for lz in [bench_z - 0.31, bench_z + 0.31]:
		_box(g, Vector3(x + 0.2, 0.16, lz), Vector3(0.34, 0.32, 0.03), _mat(COL_OAK_D, 0.6))
	for i in range(2):
		_box(g, Vector3(x + 0.22, 0.17, bench_z - 0.14 + 0.25 * float(i)), Vector3(0.24, 0.07, 0.1), _mat([Color("5E6E86"), COL_TERRACOTTA][i], 0.8))
	_cyl(g, Vector3(x + 0.18, 0.4, bench_z + 0.15), 0.04, 0.12, _mat(COL_SAGE, 0.8))
	_block(x, bench_z - 0.36, x + 0.4, bench_z + 0.36)
	# Calendar by the door (planning flavour).
	_box(g, Vector3(x + 0.02, 1.15, 1.32), Vector3(0.02, 0.36, 0.28), _mat(Color("FFFDF6"), 0.9))
	_box(g, Vector3(x + 0.03, 1.29, 1.32), Vector3(0.01, 0.07, 0.28), _mat(COL_TERRACOTTA, 0.9), false)
	for r in range(3):
		for c in range(4):
			var cell_col: Color = Color("D9C2A0") if not (r == 1 and c == 2) else COL_TERRACOTTA
			_box(g, Vector3(x + 0.032, 1.2 - 0.07 * float(r), 1.22 + 0.065 * float(c)), Vector3(0.004, 0.05, 0.05), _mat(cell_col, 0.9), false)
	anchors["door"] = g
	points["door"] = Vector3(x + 0.1, 0.0, dcz)
	points["door_inside"] = Vector3(x + 0.6, 0.0, dcz)
	# Entry lamp (small sconce) above the door.
	var sc := _cyl(g, Vector3(x + 0.12, dh + 0.12, dcz), 0.07, 0.1, _mat(COL_LAMP, 0.6, 1.5), 0.045)
	sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni(g, Vector3(x + 0.4, dh, dcz), Color("FFC98A"), 0.6, 2.6)

# --- cat corner --------------------------------------------------------------------------------

func _build_cat_corner() -> void:
	var g: Node3D = _group("CatCorner")
	# Round sage rug.
	var rc := Vector3(2.8, 0.0, 1.6)
	_cyl(g, rc + Vector3(0, 0.006, 0), 1.25, 0.012, _fabric(COL_SAGE_D), -1.0, 40).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(g, rc + Vector3(0, 0.008, 0), 1.16, 0.014, _fabric(COL_SAGE), -1.0, 40).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(g, rc + Vector3(0, 0.0095, 0), 0.92, 0.014, _fabric(COL_SAGE_L), -1.0, 40).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(g, rc + Vector3(0, 0.011, 0), 0.84, 0.014, _fabric(COL_SAGE), -1.0, 40).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Paw prints across the rug.
	var paw: StandardMaterial3D = _mat(COL_SAGE_D, 1.0)
	for i in range(3):
		var pp := rc + Vector3(-0.55 + 0.22 * float(i), 0.0, 0.55 - 0.18 * float(i) + (0.06 if i % 2 == 0 else -0.06))
		_cyl(g, pp + Vector3(0, 0.019, 0), 0.04, 0.004, paw).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in range(3):
			var ang: float = deg_to_rad(-135.0 + 45.0 * float(k))
			_cyl(g, pp + Vector3(cos(ang) * 0.06, 0.019, sin(ang) * 0.06), 0.018, 0.004, paw).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Bonding nest: a big plush donut bed with a knit blanket, a human floor cushion beside it,
	# a feather wand and a treat jar. The cat sits at the bond cell; you sit on the cushion.
	var bond_cell := Vector2i(10, 7)
	var bc: Vector3 = cell_center(bond_cell)
	var nest: Node3D = _group("BondingNest", g)
	_cyl(nest, bc + Vector3(0, 0.04, 0), 0.36, 0.08, _fabric(Color("E8C29A").darkened(0.08)))
	_torus(nest, bc + Vector3(0, 0.1, 0), 0.26, 0.4, _fabric(Color("E8C29A")), 1.3)
	var blanket := _box(nest, bc + Vector3(0.05, 0.085, -0.04), Vector3(0.36, 0.02, 0.3), _fabric(COL_ROSE))
	blanket.rotation_degrees = Vector3(0, 25, 0)
	var hc := bc + Vector3(-0.72, 0.0, -0.3)
	var hcush := _cyl(nest, hc + Vector3(0, 0.07, 0), 0.27, 0.14, _fabric(Color("B5A3CC")))
	hcush.name = "HumanCushion"
	_cyl(nest, hc + Vector3(0, 0.142, 0), 0.04, 0.01, _mat(Color("9A87B5"), 0.9))
	var wand := _cyl(nest, bc + Vector3(-0.4, 0.05, 0.35), 0.008, 0.6, _mat(COL_WALNUT_L, 0.6))
	wand.rotation_degrees = Vector3(80, 40, 0)
	_sphere(nest, bc + Vector3(-0.19, 0.05, 0.57), 0.05, _mat(Color("E07A82"), 0.9), 0.6)
	_cyl(nest, bc + Vector3(-0.55, 0.08, 0.2), 0.06, 0.16, _mat(Color("D9EEF2"), 0.15))
	_cyl(nest, bc + Vector3(-0.55, 0.17, 0.2), 0.065, 0.03, _mat(COL_TERRACOTTA, 0.5))
	anchors["bond"] = nest
	points["bond"] = bc
	points["bond_cell"] = Vector3(bond_cell.x, 0, bond_cell.y)
	_block(hc.x - 0.25, hc.z - 0.25, hc.x + 0.25, hc.z + 0.25)
	# Nap bed (heated pad look) closer to the kitchen: a cat's favourite nap cell.
	var nap_cell := Vector2i(13, 5)
	var nc: Vector3 = cell_center(nap_cell)
	_cyl(g, nc + Vector3(0, 0.03, 0), 0.3, 0.06, _fabric(Color("EFE3CF").darkened(0.06)))
	_torus(g, nc + Vector3(0, 0.08, 0), 0.22, 0.33, _fabric(Color("EFE3CF")), 1.2)
	points["nap_bed"] = nc
	points["nap_cell"] = Vector3(nap_cell.x, 0, nap_cell.y)
	# Scratch post (sisal rope bands) with a top perch.
	var sp: Vector3 = cell_center(Vector2i(13, 7))
	_box(g, sp + Vector3(0, 0.03, 0), Vector3(0.5, 0.06, 0.5), _fabric(COL_SAGE_L))
	_cyl(g, sp + Vector3(0, 0.45, 0), 0.08, 0.8, _mat(Color("D8C3A0"), 0.95))
	for i in range(8):
		_torus(g, sp + Vector3(0, 0.12 + 0.09 * float(i), 0), 0.075, 0.088, _mat(Color("C4AD86"), 0.95), 0.6)
	_cyl(g, sp + Vector3(0, 0.87, 0), 0.22, 0.05, _mat(COL_OAK, 0.8))
	_cyl(g, sp + Vector3(0, 0.9, 0), 0.2, 0.025, _fabric(COL_SAGE_L))
	_cyl(g, sp + Vector3(0.18, 0.72, 0.0), 0.004, 0.3, _mat(COL_TEXT, 0.9))
	_sphere(g, sp + Vector3(0.18, 0.56, 0.0), 0.035, _mat(Color("E07A82"), 0.8))
	_block(sp.x - 0.25, sp.z - 0.25, sp.x + 0.25, sp.z + 0.25)
	# Two-tier cat tree at the front edge (clear of the bowls and the nest).
	var ct: Vector3 = cell_center(Vector2i(10, 9))
	_box(g, ct + Vector3(0, 0.03, 0), Vector3(0.56, 0.06, 0.56), _fabric(COL_SAGE_L))
	_cyl(g, ct + Vector3(-0.08, 0.6, -0.06), 0.065, 1.2, _mat(Color("D8C3A0"), 0.95))
	_cyl(g, ct + Vector3(0.12, 0.3, 0.1), 0.05, 0.56, _mat(Color("D8C3A0"), 0.95))
	_cyl(g, ct + Vector3(0.05, 0.58, 0.05), 0.25, 0.04, _mat(COL_OAK, 0.8))
	_cyl(g, ct + Vector3(0.05, 0.605, 0.05), 0.22, 0.02, _fabric(COL_SAGE_L))
	_cyl(g, ct + Vector3(-0.05, 1.2, -0.05), 0.24, 0.04, _mat(COL_OAK, 0.8))
	_torus(g, ct + Vector3(-0.05, 1.25, -0.05), 0.13, 0.22, _fabric(COL_SAGE_L), 1.0)
	_block(ct.x - 0.28, ct.z - 0.28, ct.x + 0.28, ct.z + 0.28)
	# Litter box with a mat, scoop and a little privacy plant.
	var lb := Vector3(4.3, 0.0, 3.08)
	_box(g, lb + Vector3(0, 0.008, 0.02), Vector3(0.95, 0.012, 0.6), _fabric(Color("D9C2A0")), false)
	_box(g, lb + Vector3(0, 0.1, 0), Vector3(0.7, 0.2, 0.46), _mat(Color("A9BFC9"), 0.5))
	_box(g, lb + Vector3(0, 0.19, 0), Vector3(0.6, 0.02, 0.36), _mat(Color("E6DCC8"), 1.0), false)
	_box(g, lb + Vector3(0, 0.2, -0.22), Vector3(0.72, 0.06, 0.04), _mat(Color("93ABB6"), 0.5))
	var sc := _box(g, lb + Vector3(0.45, 0.05, 0.12), Vector3(0.08, 0.02, 0.22), _mat(COL_TEAL, 0.5))
	sc.rotation_degrees = Vector3(0, 20, 0)
	_block(lb.x - 0.38, lb.z - 0.26, lb.x + 0.38, lb.z + 0.26)
	_plant(g, Vector3(3.55, 0.0, 3.15), 0.6, COL_CREAM, 0.13)
	_block(3.42, 3.02, 3.68, 3.28)
	# Toys: yarn ball and a toy mouse.
	_sphere(g, Vector3(1.45, 0.06, 2.6), 0.06, _fabric(Color("E07A82")))
	var tail := _cyl(g, Vector3(1.53, 0.05, 2.62), 0.004, 0.18, _mat(Color("E07A82"), 0.9))
	tail.rotation_degrees = Vector3(0, 0, 80)
	_sphere(g, Vector3(3.3, 0.04, 0.55), 0.045, _mat(Color("A9A2A0"), 0.8), 0.8)
	_sphere(g, Vector3(3.27, 0.075, 0.55), 0.015, _mat(Color("E8B0B0"), 0.8))
	# Small radiator-warm glow for the corner.
	_omni(g, Vector3(3.1, 1.3, 1.6), Color("FFC98A"), 0.45, 3.5)

# --- lighting ------------------------------------------------------------------------------------

func _build_lighting() -> void:
	var g: Node3D = _group("Lighting")
	# Big indoor fill so the whole room reads at night (style: warm, calm, readable).
	_omni(g, Vector3(-0.5, 2.4, 0.0), Color("FFD7A8"), 0.9, 9.0)
	_omni(g, Vector3(2.8, 2.2, 1.5), Color("FFD2A0"), 0.5, 6.0)
	# Cool moon rim from the windows' side.
	_omni(g, Vector3(-1.1, 1.4, Z0 + 0.9), Color("B3C1EE"), 0.5, 3.5)
