extends RefCounted

## Procedural building blocks for the Town environment: cached materials, primitive mesh
## helpers, Label3D signs and small tileable ImageTextures generated in code (no image
## files). Used by Scripts/environments/town/*. Preload by path (no class_name, so it
## never collides with other environments' helpers).

const THEME_PATH: String = "res://UI/cozy_theme.tres"
const COL_TEXT := Color("4A3426")
const COL_TEXT_OUTLINE := Color("FFF6EA")

var _mats: Dictionary = {}
var _texs: Dictionary = {}
var _font: Font = null
var _font_loaded: bool = false

## Emissive materials whose glow follows the day/night tint: [{"mat", "base"}].
var glow_materials: Array = []
## Street/porch lights whose energy follows the day/night tint: [{"light", "base"}].
var lamp_lights: Array = []

# ------------------------------------------------------------------ materials

func mat(c: Color, rough: float = 0.85, emit: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s_%.2f_%.2f" % [c.to_html(), rough, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

## Emissive material registered for the day/night glow factor (window panes, lanterns).
func glow(c: Color, energy: float) -> StandardMaterial3D:
	var key: String = "glow_%s_%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_mats[key] = m
	glow_materials.append({"mat": m, "base": energy})
	return m

## World-space triplanar material: the texture tile covers tile_m metres on every axis.
func tri_mat(tex: Texture2D, tile_m: float, rough: float = 0.9, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key: String = "tri_%d_%.2f_%.2f_%s" % [tex.get_instance_id(), tile_m, rough, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	var s: float = 1.0 / maxf(0.01, tile_m)
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

## Per-instance-colour material (MultiMesh leaves, string lights).
func vertex_color_mat(rough: float = 0.9, emit: float = 0.0) -> StandardMaterial3D:
	var key: String = "vc_%.2f_%.2f" % [rough, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(1, 0.85, 0.6)
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

# ------------------------------------------------------------------ nodes

func node(parent: Node, node_name: String, pos: Vector3 = Vector3.ZERO, rot_y_deg: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	n.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	parent.add_child(n)
	return n

func box(parent: Node, center: Vector3, size: Vector3, m: Material, shadow: bool = true, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = m
	mi.position = center
	mi.rotation_degrees = rot_deg
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func cyl(parent: Node, center: Vector3, r: float, h: float, m: Material, top_r: float = -1.0, segs: int = 16, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r
	mesh.top_radius = r if top_r < 0.0 else top_r
	mesh.height = h
	mesh.radial_segments = segs
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = m
	mi.position = center
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func ball(parent: Node, center: Vector3, r: float, h: float, m: Material, segs: int = 16, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = h
	mesh.radial_segments = segs
	mesh.rings = maxi(4, segs / 2)
	mi.mesh = mesh
	mi.material_override = m
	mi.position = center
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Triangular prism (gable roof): triangle in the local XY plane, extruded along Z.
func prism(parent: Node, center: Vector3, size: Vector3, m: Material, rot_y_deg: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = 0.5
	mi.mesh = mesh
	mi.material_override = m
	mi.position = center
	mi.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	parent.add_child(mi)
	return mi

func label(parent: Node, text: String, pos: Vector3, rot_y_deg: float = 0.0, font_size: int = 64, col: Color = COL_TEXT, outline_col: Color = COL_TEXT_OUTLINE, pixel: float = 0.005, outline: int = 6) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = col
	l.outline_modulate = outline_col
	l.outline_size = outline
	var f: Font = font()
	if f != null:
		l.font = f
	l.position = pos
	l.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.shaded = false
	parent.add_child(l)
	return l

func font() -> Font:
	if not _font_loaded:
		_font_loaded = true
		if ResourceLoader.exists(THEME_PATH):
			var th = load(THEME_PATH)
			if th is Theme and (th as Theme).default_font != null:
				_font = (th as Theme).default_font
	return _font

func omni(parent: Node, pos: Vector3, c: Color, energy: float, light_range: float, register: bool = true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)
	if register:
		lamp_lights.append({"light": l, "base": energy})
	return l

## Applies the day/night factors to every registered glow material and lamp.
func apply_glow(window_factor: float, lamp_factor: float) -> void:
	for e in glow_materials:
		var m: StandardMaterial3D = e["mat"]
		m.emission_energy_multiplier = float(e["base"]) * window_factor
	for e in lamp_lights:
		var l: Light3D = e["light"]
		if is_instance_valid(l):
			l.light_energy = float(e["base"]) * lamp_factor
			l.visible = lamp_factor > 0.02

# ------------------------------------------------------------------ textures

func _cached(key: String) -> ImageTexture:
	return _texs.get(key, null)

func _finish(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_texs[key] = t
	return t

## Running-bond bricks. One tile = 1 m (rows rows, 3 bricks per row).
func tex_brick(base: Color, mortar: Color, rows: int = 7, seed: int = 11) -> ImageTexture:
	var key: String = "brick_%s_%s_%d" % [base.to_html(), mortar.to_html(), rows]
	if _cached(key) != null:
		return _cached(key)
	var n: int = 126
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var row_h: float = float(n) / float(rows)
	var bw: float = float(n) / 3.0
	for row in range(rows):
		var y0: int = int(round(row * row_h))
		var y1: int = int(round((row + 1) * row_h))
		var off: float = 0.0 if row % 2 == 0 else bw * 0.5
		var cols: Array[Color] = []
		for i in range(4):
			var c: Color = base.lightened(r.randf_range(-0.02, 0.08)) if r.randf() < 0.5 else base.darkened(r.randf_range(0.0, 0.12))
			cols.append(c)
		for py in range(y0, y1):
			for px in range(n):
				var lx: float = fposmod(float(px) + off, float(n))
				var bi: int = int(lx / bw)
				var in_x: float = lx - float(bi) * bw
				var c: Color = cols[bi % cols.size()]
				if py - y0 < 2 or in_x < 2.0:
					c = mortar
				elif py - y0 == 2:
					c = c.lightened(0.06)
				elif py == y1 - 1:
					c = c.darkened(0.08)
				img.set_pixel(px, py, c)
	return _finish(key, img)

## Horizontal clapboard siding. One tile = 1 m, boards_per_m boards.
func tex_siding(base: Color, boards_per_m: int = 6) -> ImageTexture:
	var key: String = "siding_%s_%d" % [base.to_html(), boards_per_m]
	if _cached(key) != null:
		return _cached(key)
	var n: int = 96
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var bh: float = float(n) / float(boards_per_m)
	for py in range(n):
		var t: float = fposmod(float(py), bh) / bh
		var c: Color = base
		if t < 0.12:
			c = base.darkened(0.22)
		elif t < 0.3:
			c = base.lightened(0.05)
		else:
			c = base.darkened(lerpf(0.0, 0.07, t))
		for px in range(n):
			var g: float = sin(float(px) * 0.21 + float(py) * 0.7) * 0.012
			img.set_pixel(px, py, c.darkened(g + 0.012))
	return _finish(key, img)

## Square pavers with grout. One tile = 1 m, cells per side.
func tex_pavers(base: Color, grout: Color, cells: int = 2, seed: int = 5) -> ImageTexture:
	var key: String = "pavers_%s_%s_%d" % [base.to_html(), grout.to_html(), cells]
	if _cached(key) != null:
		return _cached(key)
	var n: int = 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var cs: float = float(n) / float(cells)
	var cols: Array[Color] = []
	for i in range(cells * cells):
		cols.append(base.lightened(r.randf_range(-0.03, 0.05)).darkened(r.randf_range(0.0, 0.05)))
	for py in range(n):
		for px in range(n):
			var cx: int = int(float(px) / cs)
			var cy: int = int(float(py) / cs)
			var lx: float = float(px) - float(cx) * cs
			var ly: float = float(py) - float(cy) * cs
			var c: Color = cols[(cy * cells + cx) % cols.size()]
			var speck: float = fposmod(sin(float(px * 12.9898 + py * 78.233)) * 43758.5453, 1.0)
			c = c.darkened(speck * 0.05)
			if lx < 2.0 or ly < 2.0:
				c = grout
			elif lx < 4.0 or ly < 4.0:
				c = c.lightened(0.05)
			img.set_pixel(px, py, c)
	return _finish(key, img)

## Rounded cobbles in offset rows. One tile = 1 m.
func tex_cobble(base: Color, grout: Color, seed: int = 21) -> ImageTexture:
	var key: String = "cobble_%s_%s" % [base.to_html(), grout.to_html()]
	if _cached(key) != null:
		return _cached(key)
	var n: int = 120
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var rows: int = 6
	var per: int = 5
	var rh: float = float(n) / float(rows)
	var cw: float = float(n) / float(per)
	var cols: Array[Color] = []
	for i in range(rows * per):
		var c: Color = base.lightened(r.randf_range(-0.05, 0.07))
		c = c.lerp(Color("B98C6A"), r.randf_range(0.0, 0.18))
		cols.append(c)
	for py in range(n):
		var row: int = int(float(py) / rh)
		var ly: float = float(py) - float(row) * rh
		var off: float = 0.0 if row % 2 == 0 else cw * 0.5
		for px in range(n):
			var lxp: float = fposmod(float(px) + off, float(n))
			var ci: int = int(lxp / cw)
			var lx: float = lxp - float(ci) * cw
			var dx: float = (lx - cw * 0.5) / (cw * 0.5)
			var dy: float = (ly - rh * 0.5) / (rh * 0.5)
			var d: float = pow(absf(dx), 3.0) + pow(absf(dy), 3.0)
			var c: Color = cols[(row * per + ci) % cols.size()]
			if d > 0.78:
				c = grout
			else:
				c = c.lightened(0.08 * (1.0 - dy) * 0.5 - 0.02)
			img.set_pixel(px, py, c)
	return _finish(key, img)

## Warm asphalt with speckles. One tile = 2 m.
func tex_asphalt(base: Color, seed: int = 3) -> ImageTexture:
	var key: String = "asphalt_%s" % base.to_html()
	if _cached(key) != null:
		return _cached(key)
	var n: int = 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for py in range(n):
		for px in range(n):
			var v: float = r.randf()
			var c: Color = base
			if v < 0.08:
				c = base.lightened(0.1)
			elif v > 0.94:
				c = base.darkened(0.12)
			var w: float = sin(float(px) * 0.09) * sin(float(py) * 0.07) * 0.025
			img.set_pixel(px, py, c.lightened(w))
	return _finish(key, img)

## Autumn lawn: mottled greens with a few fallen-leaf flecks. One tile = 2 m.
func tex_grass(base: Color, seed: int = 8) -> ImageTexture:
	var key: String = "grass_%s" % base.to_html()
	if _cached(key) != null:
		return _cached(key)
	var n: int = 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var flecks: Array[Color] = [Color("D9893B"), Color("C9643A"), Color("E3B04B")]
	for py in range(n):
		for px in range(n):
			var m: float = sin(float(px) * 0.11 + sin(float(py) * 0.07) * 2.0) * 0.5 + 0.5
			var c: Color = base.lerp(base.lightened(0.12), m * 0.6)
			var v: float = r.randf()
			if v < 0.18:
				c = c.darkened(0.08)
			elif v < 0.26:
				c = c.lightened(0.07)
			img.set_pixel(px, py, c)
	for i in range(26):
		var x: int = r.randi_range(0, n - 3)
		var y: int = r.randi_range(0, n - 3)
		var fc: Color = flecks[r.randi_range(0, flecks.size() - 1)]
		img.set_pixel(x, y, fc)
		img.set_pixel(x + 1, y, fc)
		img.set_pixel(x, y + 1, fc.darkened(0.1))
	return _finish(key, img)

## Roof shingles (scalloped rows). One tile = 1 m.
func tex_shingles(base: Color, seed: int = 4) -> ImageTexture:
	var key: String = "shingle_%s" % base.to_html()
	if _cached(key) != null:
		return _cached(key)
	var n: int = 96
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var rows: int = 6
	var per: int = 6
	var rh: float = float(n) / float(rows)
	var cw: float = float(n) / float(per)
	var cols: Array[Color] = []
	for i in range(rows * per):
		cols.append(base.lightened(r.randf_range(-0.04, 0.06)).darkened(r.randf_range(0.0, 0.06)))
	for py in range(n):
		var row: int = int(float(py) / rh)
		var ly: float = float(py) - float(row) * rh
		var off: float = 0.0 if row % 2 == 0 else cw * 0.5
		for px in range(n):
			var lxp: float = fposmod(float(px) + off, float(n))
			var ci: int = int(lxp / cw)
			var lx: float = lxp - float(ci) * cw
			var c: Color = cols[(row * per + ci) % cols.size()]
			var edge_y: float = rh - 3.0 - 3.0 * sin(lx / cw * PI)
			if ly > edge_y:
				c = c.darkened(0.25)
			elif lx < 1.0:
				c = c.darkened(0.14)
			elif ly < 2.0:
				c = c.lightened(0.05)
			img.set_pixel(px, py, c)
	return _finish(key, img)

## Wood planks running along one axis (fences, stall counters). One tile = 1 m.
func tex_planks(base: Color, boards: int = 5, seed: int = 9) -> ImageTexture:
	var key: String = "planks_%s_%d" % [base.to_html(), boards]
	if _cached(key) != null:
		return _cached(key)
	var n: int = 96
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var bw: float = float(n) / float(boards)
	var cols: Array[Color] = []
	for i in range(boards):
		cols.append(base.lightened(r.randf_range(-0.04, 0.06)))
	for py in range(n):
		for px in range(n):
			var bi: int = int(float(px) / bw)
			var lx: float = float(px) - float(bi) * bw
			var c: Color = cols[bi % cols.size()]
			c = c.darkened(0.04 * (sin(float(py) * 0.3 + float(bi) * 2.0) * 0.5 + 0.5))
			if lx < 1.5:
				c = c.darkened(0.3)
			img.set_pixel(px, py, c)
	return _finish(key, img)
