extends RefCounted

## Cozy building facades for the Town, built from primitives in a local frame:
## facade plane at z = 0 facing +Z, the body spans x in [-w/2, w/2] and z in [-d, 0].
## A building group is rotated 90 deg for the west column (facing +X); local +X then
## runs toward world -Z. Every build_* returns its root Node3D; Town.gd hooks the
## hotspots to those roots (hover highlight).

const Kit := preload("res://Scripts/environments/common/town_proc_kit.gd")

const COL_TRIM := Color("F3E6D3")
const COL_CREAM := Color("FFF6EA")
const COL_WALNUT := Color("9C6B4A")
const COL_DARK_WOOD := Color("6B4A35")
const COL_OAK := Color("C9A27A")
const COL_GLASS_LIT := Color("FFD49A")
const COL_GLASS_DIM := Color("4B5566")
const COL_SILHOUETTE := Color("8A5A3E")
const COL_IRON := Color("33393A")
const COL_TEXT := Color("4A3426")
const COL_BRASS := Color("D9A84E")
const FLOWER_COLS: Array[Color] = [Color("E07A5F"), Color("F2C14E"), Color("E8A0B4"), Color("FFF6EA"), Color("C9643A")]

var k: Kit

func _init(kit: Kit) -> void:
	k = kit

# ================================================================== shared pieces

func _body(g: Node3D, w: float, d: float, h: float, wall: Material, base_col: Color, cornice_col: Color) -> void:
	k.box(g, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, d), wall)
	k.box(g, Vector3(0, 0.2, -d * 0.5), Vector3(w + 0.08, 0.4, d + 0.08), k.mat(base_col, 0.9))
	k.box(g, Vector3(0, h + 0.09, -d * 0.5), Vector3(w + 0.24, 0.18, d + 0.24), k.mat(cornice_col, 0.8))
	k.box(g, Vector3(0, h - 0.05, -d * 0.5), Vector3(w + 0.12, 0.08, d + 0.12), k.mat(cornice_col.lightened(0.15), 0.8))

func _band(g: Node3D, w: float, d: float, y: float, col: Color, t: float = 0.1) -> void:
	k.box(g, Vector3(0, y, -d * 0.5), Vector3(w + 0.06, t, d + 0.06), k.mat(col, 0.8))

## Upper-floor window: frame, sill, panes (lit or dim), optional shutters / flower box.
func _window(g: Node3D, x: float, y: float, ww: float, wh: float, frame: Color, lit: bool, opts: Dictionary = {}) -> void:
	var fm: Material = k.mat(frame, 0.75)
	var glass: Material = k.glow(COL_GLASS_LIT, 1.5) if lit else k.mat(COL_GLASS_DIM, 0.2)
	k.box(g, Vector3(x, y, 0.01), Vector3(ww, wh, 0.04), glass, false)
	var f: float = 0.07
	k.box(g, Vector3(x, y + wh * 0.5 + f * 0.5, 0.04), Vector3(ww + f * 2.0, f, 0.08), fm)
	k.box(g, Vector3(x, y - wh * 0.5 - 0.04, 0.07), Vector3(ww + f * 2.0 + 0.1, 0.08, 0.14), fm)
	k.box(g, Vector3(x - ww * 0.5 - f * 0.5, y, 0.04), Vector3(f, wh, 0.08), fm)
	k.box(g, Vector3(x + ww * 0.5 + f * 0.5, y, 0.04), Vector3(f, wh, 0.08), fm)
	k.box(g, Vector3(x, y, 0.035), Vector3(0.04, wh, 0.03), fm, false)
	k.box(g, Vector3(x, y + wh * 0.12, 0.035), Vector3(ww, 0.04, 0.03), fm, false)
	if lit:
		var cc: Color = opts.get("curtain", Color("E8A0A0"))
		k.box(g, Vector3(x - ww * 0.36, y + wh * 0.05, 0.03), Vector3(ww * 0.22, wh * 0.9, 0.02), k.mat(cc, 0.95), false)
		k.box(g, Vector3(x + ww * 0.36, y + wh * 0.05, 0.03), Vector3(ww * 0.22, wh * 0.9, 0.02), k.mat(cc, 0.95), false)
	else:
		k.box(g, Vector3(x, y + wh * 0.25, 0.03), Vector3(ww * 0.95, wh * 0.45, 0.02), k.mat(opts.get("blind", Color("D8C3A5")), 0.95), false)
	if opts.has("shutter"):
		var sc: Color = opts["shutter"]
		for s in [-1.0, 1.0]:
			var sx: float = x + s * (ww * 0.5 + f + 0.17)
			k.box(g, Vector3(sx, y, 0.05), Vector3(0.3, wh + 0.1, 0.05), k.mat(sc, 0.8))
			for i in range(4):
				k.box(g, Vector3(sx, y - wh * 0.35 + float(i) * wh * 0.23, 0.08), Vector3(0.24, 0.025, 0.02), k.mat(sc.darkened(0.18), 0.8), false)
	if bool(opts.get("flowers", false)):
		_flower_box(g, Vector3(x, y - wh * 0.5 - 0.2, 0.18), ww + 0.1, int(opts.get("seed", 1)))

func _flower_box(g: Node3D, c: Vector3, w: float, seed: int) -> void:
	k.box(g, c, Vector3(w, 0.2, 0.22), k.mat(COL_DARK_WOOD, 0.85))
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var n: int = int(w / 0.16)
	for i in range(n):
		var fx: float = c.x - w * 0.5 + 0.1 + float(i) * (w - 0.2) / maxf(1.0, float(n - 1))
		k.ball(g, Vector3(fx, c.y + 0.14, c.z + r.randf_range(-0.04, 0.04)), 0.09, 0.14, k.mat(Color("6F9468").darkened(r.randf_range(0.0, 0.2)), 0.9), 8, false)
		if r.randf() < 0.75:
			k.ball(g, Vector3(fx + r.randf_range(-0.03, 0.03), c.y + 0.22, c.z + 0.05), 0.045, 0.07, k.mat(FLOWER_COLS[r.randi_range(0, FLOWER_COLS.size() - 1)], 0.8), 8, false)

## Big glowing shop window with mullions; returns the glass center z for silhouettes.
func _shop_window(g: Node3D, x: float, y0: float, ww: float, wh: float, frame: Color, glass_col: Color = COL_GLASS_LIT) -> void:
	var fm: Material = k.mat(frame, 0.75)
	k.box(g, Vector3(x, y0 + wh * 0.5, 0.02), Vector3(ww, wh, 0.04), k.glow(glass_col, 1.35), false)
	var f: float = 0.09
	k.box(g, Vector3(x, y0 + wh + f * 0.5, 0.06), Vector3(ww + f * 2.0, f, 0.1), fm)
	k.box(g, Vector3(x, y0 - f * 0.5, 0.1), Vector3(ww + f * 2.0 + 0.08, f, 0.2), fm)
	k.box(g, Vector3(x - ww * 0.5 - f * 0.5, y0 + wh * 0.5, 0.06), Vector3(f, wh, 0.1), fm)
	k.box(g, Vector3(x + ww * 0.5 + f * 0.5, y0 + wh * 0.5, 0.06), Vector3(f, wh, 0.1), fm)
	k.box(g, Vector3(x, y0 + wh * 0.5, 0.05), Vector3(0.05, wh, 0.04), fm, false)
	k.box(g, Vector3(x, y0 + wh * 0.78, 0.05), Vector3(ww, 0.05, 0.04), fm, false)
	# Stall-riser panel under the window.
	k.box(g, Vector3(x, y0 * 0.5, 0.05), Vector3(ww + f * 2.0, y0, 0.1), k.mat(frame.darkened(0.1), 0.8))
	k.box(g, Vector3(x, y0 * 0.5, 0.11), Vector3(ww * 0.8, y0 * 0.5, 0.02), k.mat(frame.lightened(0.08), 0.8), false)

func _door(g: Node3D, x: float, dw: float, dh: float, col: Color, frame: Color, glass: bool = true, double_door: bool = false) -> void:
	var fm: Material = k.mat(frame, 0.75)
	k.box(g, Vector3(x, dh * 0.5, 0.01), Vector3(dw + 0.1, dh + 0.05, 0.03), k.mat(Color("3A2A22"), 0.9), false)
	var leaves: int = 2 if double_door else 1
	var lw: float = dw / float(leaves)
	for i in range(leaves):
		var lx: float = x - dw * 0.5 + lw * (float(i) + 0.5)
		k.box(g, Vector3(lx, dh * 0.5, 0.04), Vector3(lw - 0.04, dh - 0.04, 0.05), k.mat(col, 0.7))
		if glass:
			k.box(g, Vector3(lx, dh * 0.66, 0.07), Vector3(lw * 0.62, dh * 0.4, 0.02), k.glow(COL_GLASS_LIT, 1.3), false)
		k.box(g, Vector3(lx, dh * 0.24, 0.07), Vector3(lw * 0.62, dh * 0.26, 0.02), k.mat(col.darkened(0.12), 0.7), false)
		var kx: float = lx + (lw * 0.36 if i == 0 else -lw * 0.36)
		k.ball(g, Vector3(kx, dh * 0.48, 0.09), 0.04, 0.08, k.mat(COL_BRASS, 0.3), 8, false)
	var f: float = 0.1
	k.box(g, Vector3(x, dh + f * 0.5, 0.06), Vector3(dw + f * 2.0, f, 0.12), fm)
	k.box(g, Vector3(x - dw * 0.5 - f * 0.5, dh * 0.5, 0.06), Vector3(f, dh, 0.12), fm)
	k.box(g, Vector3(x + dw * 0.5 + f * 0.5, dh * 0.5, 0.06), Vector3(f, dh, 0.12), fm)
	# Stone step.
	k.box(g, Vector3(x, 0.04, 0.25), Vector3(dw + 0.5, 0.08, 0.5), k.mat(Color("BBA58C"), 0.9))

## Striped awning sloping out from the facade, with a scalloped valance.
func _awning(g: Node3D, x: float, y_top: float, w: float, depth: float, drop: float, c1: Color, c2: Color, stripe_w: float = 0.32) -> void:
	var ang: float = atan2(drop, depth)
	var length: float = sqrt(depth * depth + drop * drop)
	var piv := k.node(g, "Awning", Vector3(x, y_top, 0.0))
	piv.rotation.x = ang
	var n: int = maxi(2, int(round(w / stripe_w)))
	var sw: float = w / float(n)
	for i in range(n):
		var sx: float = -w * 0.5 + sw * (float(i) + 0.5)
		var col: Color = c1 if i % 2 == 0 else c2
		k.box(piv, Vector3(sx, 0.0, length * 0.5), Vector3(sw + 0.002, 0.05, length), k.mat(col, 0.9))
	var edge := Vector3(x, y_top - drop, depth)
	for i in range(n):
		var sx: float = x - w * 0.5 + sw * (float(i) + 0.5)
		var col: Color = c1 if i % 2 == 0 else c2
		k.box(g, Vector3(sx, edge.y - 0.09, edge.z + 0.01), Vector3(sw + 0.002, 0.18, 0.03), k.mat(col, 0.9), false)
		var sc: MeshInstance3D = k.cyl(g, Vector3(sx, edge.y - 0.18, edge.z + 0.01), sw * 0.5, 0.03, k.mat(col, 0.9), -1.0, 12, false)
		sc.rotation_degrees.x = 90.0
	# Side brackets.
	for s in [-1.0, 1.0]:
		var b: MeshInstance3D = k.box(g, Vector3(x + s * (w * 0.5 - 0.03), y_top - drop * 0.5, depth * 0.5), Vector3(0.03, 0.03, length), k.mat(COL_IRON, 0.5), false)
		b.rotation.x = ang

func _sign_board(g: Node3D, pos: Vector3, size: Vector2, board: Color, border: Color, text: String, text_col: Color, font_size: int = 72) -> MeshInstance3D:
	k.box(g, pos + Vector3(0, 0, -0.01), Vector3(size.x + 0.14, size.y + 0.14, 0.06), k.mat(border, 0.7))
	var b: MeshInstance3D = k.box(g, pos + Vector3(0, 0, 0.02), Vector3(size.x, size.y, 0.06), k.mat(board, 0.8))
	k.label(g, text, pos + Vector3(0, -0.01, 0.055), 0.0, font_size, text_col, board.lightened(0.2), 0.005, 2)
	return b

## Hanging blade sign perpendicular to the facade (readable from both sides).
func _blade_sign(g: Node3D, pos: Vector3, size: Vector2, board: Color, border: Color, icon: String, icon_col: Color) -> void:
	k.box(g, Vector3(pos.x, pos.y + size.y * 0.5 + 0.12, pos.z * 0.5), Vector3(0.04, 0.04, pos.z), k.mat(COL_IRON, 0.5), false)
	k.box(g, pos, Vector3(0.06, size.y + 0.1, size.x + 0.1), k.mat(border, 0.7))
	k.box(g, pos, Vector3(0.08, size.y, size.x), k.mat(board, 0.8))
	for s in [-1.0, 1.0]:
		var ic := k.node(g, "BladeIcon", pos + Vector3(s * 0.05, 0.0, 0.0), 90.0 * s)
		_icon(ic, icon, icon_col, minf(size.x, size.y) * 0.8)

## Flat icons in an XY plane facing +Z (cat head, paw, bone, house, bread, leaf).
func _icon(parent: Node3D, kind: String, col: Color, s: float) -> void:
	var m: Material = k.mat(col, 0.7)
	match kind:
		"cat":
			_disc(parent, Vector3(0, -s * 0.05, 0), s * 0.36, m)
			for sx in [-1.0, 1.0]:
				var ear: MeshInstance3D = k.prism(parent, Vector3(sx * s * 0.22, s * 0.28, 0), Vector3(s * 0.26, s * 0.3, 0.03), m)
				ear.rotation_degrees.z = -sx * 14.0
				_disc(parent, Vector3(sx * s * 0.13, 0.0, 0.02), s * 0.06, k.mat(COL_CREAM, 0.6))
			_disc(parent, Vector3(0, -s * 0.12, 0.02), s * 0.04, k.mat(Color("E8A0B4"), 0.6))
		"paw":
			_disc(parent, Vector3(0, -s * 0.12, 0), s * 0.26, m)
			for i in range(4):
				var a: float = deg_to_rad(-60.0 + 40.0 * float(i))
				_disc(parent, Vector3(sin(a) * s * 0.36, cos(a) * s * 0.3 + s * 0.02, 0), s * 0.1, m)
		"bone":
			k.box(parent, Vector3.ZERO, Vector3(s * 0.62, s * 0.16, 0.03), m, false)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_disc(parent, Vector3(sx * s * 0.33, sy * s * 0.09, 0), s * 0.11, m)
		"house":
			k.box(parent, Vector3(0, -s * 0.12, 0), Vector3(s * 0.5, s * 0.4, 0.03), m, false)
			k.prism(parent, Vector3(0, s * 0.2, 0), Vector3(s * 0.7, s * 0.28, 0.03), m)
			k.box(parent, Vector3(0, -s * 0.2, 0.02), Vector3(s * 0.14, s * 0.24, 0.02), k.mat(COL_CREAM, 0.6), false)
		"bread":
			var loaf: MeshInstance3D = k.ball(parent, Vector3.ZERO, s * 0.36, s * 0.4, m, 16, false)
			loaf.scale = Vector3(1.0, 0.75, 0.15)
			for i in range(3):
				k.box(parent, Vector3(-s * 0.15 + float(i) * s * 0.15, s * 0.04, 0.03), Vector3(s * 0.04, s * 0.16, 0.01), k.mat(COL_CREAM, 0.6), false, Vector3(0, 0, 25))
		"leaf":
			var lf: MeshInstance3D = k.ball(parent, Vector3.ZERO, s * 0.3, s * 0.6, m, 12, false)
			lf.scale = Vector3(1.0, 1.0, 0.12)
			lf.rotation_degrees.z = 35.0
		_:
			_disc(parent, Vector3.ZERO, s * 0.3, m)

func _disc(parent: Node3D, c: Vector3, r: float, m: Material) -> MeshInstance3D:
	var d: MeshInstance3D = k.cyl(parent, c, r, 0.03, m, -1.0, 20, false)
	d.rotation_degrees.x = 90.0
	return d

## Gable roof (ridge along local X) with wall-coloured gable ends and a chimney.
func _gable_roof(g: Node3D, w: float, d: float, h: float, roof_h: float, roof: Material, wall: Material, overhang: float = 0.3) -> void:
	k.prism(g, Vector3(0, h + roof_h * 0.5, -d * 0.5), Vector3(d, roof_h, w), wall, 90.0)
	var ang: float = atan2(roof_h, d * 0.5)
	var half: float = d * 0.5 + overhang
	var length: float = half / cos(ang)
	var ridge := Vector3(0, h + roof_h + 0.06, -d * 0.5)
	var front: MeshInstance3D = k.box(g, ridge + Vector3(0, -length * 0.5 * sin(ang), length * 0.5 * cos(ang)), Vector3(w + overhang * 2.0, 0.12, length), roof)
	front.rotation.x = ang
	var back: MeshInstance3D = k.box(g, ridge + Vector3(0, -length * 0.5 * sin(ang), -length * 0.5 * cos(ang)), Vector3(w + overhang * 2.0, 0.12, length), roof)
	back.rotation.x = -ang
	k.box(g, ridge + Vector3(0, 0.04, 0), Vector3(w + overhang * 2.0 + 0.04, 0.1, 0.16), k.mat(COL_DARK_WOOD, 0.8))
	# Fascia boards on the eaves.
	k.box(g, Vector3(0, h + 0.02, overhang * 0.9), Vector3(w + overhang * 2.0, 0.1, 0.06), k.mat(COL_TRIM, 0.8))

func _chimney(g: Node3D, pos: Vector3, h: float, brick: Material) -> void:
	k.box(g, pos + Vector3(0, h * 0.5, 0), Vector3(0.55, h, 0.55), brick)
	k.box(g, pos + Vector3(0, h + 0.05, 0), Vector3(0.68, 0.1, 0.68), k.mat(Color("7A5236"), 0.8))
	k.cyl(g, pos + Vector3(0.08, h + 0.22, 0.0), 0.08, 0.25, k.mat(Color("8A5A3E"), 0.8))

func _sconce(g: Node3D, pos: Vector3, light: bool = true) -> void:
	k.box(g, pos + Vector3(0, 0, 0.04), Vector3(0.1, 0.18, 0.08), k.mat(COL_IRON, 0.5), false)
	k.box(g, pos + Vector3(0, 0.02, 0.15), Vector3(0.16, 0.22, 0.16), k.glow(Color("FFC98A"), 2.2), false)
	k.box(g, pos + Vector3(0, 0.16, 0.15), Vector3(0.22, 0.05, 0.22), k.mat(COL_IRON, 0.5), false)
	if light:
		k.omni(g, pos + Vector3(0, 0.0, 0.5), Color("FFC98A"), 0.9, 3.2)

func _planter(g: Node3D, c: Vector3, w: float, seed: int, tall: bool = false) -> void:
	k.box(g, c + Vector3(0, 0.22, 0), Vector3(w, 0.44, 0.45), k.mat(COL_WALNUT, 0.85))
	k.box(g, c + Vector3(0, 0.45, 0), Vector3(w + 0.06, 0.05, 0.5), k.mat(COL_DARK_WOOD, 0.85))
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var n: int = maxi(1, int(w / 0.28))
	for i in range(n):
		var px: float = c.x - w * 0.5 + w * (float(i) + 0.5) / float(n)
		var hh: float = 0.5 if tall else 0.3
		k.ball(g, Vector3(px, c.y + 0.5 + hh * 0.4, c.z + r.randf_range(-0.05, 0.05)), 0.2, hh, k.mat(Color("6F9468").darkened(r.randf_range(0.0, 0.25)), 0.9), 10)
		if r.randf() < 0.7:
			k.ball(g, Vector3(px + 0.06, c.y + 0.55 + hh * 0.6, c.z + 0.12), 0.06, 0.1, k.mat(FLOWER_COLS[r.randi_range(0, FLOWER_COLS.size() - 1)], 0.8), 8, false)

## A small dark silhouette cat sitting in a lit window (reads against the glow).
func _window_cat(g: Node3D, pos: Vector3, col: Color) -> void:
	var m: Material = k.mat(col, 0.9)
	var body: MeshInstance3D = k.ball(g, pos + Vector3(0, 0.17, 0), 0.15, 0.36, m, 12, false)
	body.scale = Vector3(1.0, 1.0, 0.25)
	k.ball(g, pos + Vector3(0.02, 0.4, 0.0), 0.11, 0.2, m, 12, false).scale = Vector3(1.0, 1.0, 0.3)
	for sx in [-1.0, 1.0]:
		k.prism(g, pos + Vector3(0.02 + sx * 0.065, 0.53, 0), Vector3(0.08, 0.1, 0.03), m)
	var tail: MeshInstance3D = k.box(g, pos + Vector3(0.17, 0.08, 0), Vector3(0.22, 0.05, 0.03), m, false)
	tail.rotation_degrees.z = 25.0

# ================================================================== buildings

## The player's cat cafe: peach plaster over a walnut storefront, sage awning, cat sign.
func build_cafe(parent: Node3D, pos: Vector3, w: float, d: float) -> Node3D:
	var g := k.node(parent, "CatCafe", pos)
	var h: float = 5.6
	var wall: Material = k.mat(Color("E3B9A0"), 0.95)
	_body(g, w, d, h, wall, Color("7A5236"), Color("F3E6D3"))
	# Walnut storefront panel on the ground floor.
	k.box(g, Vector3(0, 1.55, 0.03), Vector3(w - 0.2, 3.1, 0.06), k.mat(COL_WALNUT, 0.8))
	k.box(g, Vector3(0, 3.15, 0.06), Vector3(w - 0.1, 0.12, 0.12), k.mat(COL_DARK_WOOD, 0.8))
	_band(g, w, d, 3.95, Color("F3E6D3"), 0.1)
	_shop_window(g, -2.15, 0.62, 2.5, 1.85, COL_DARK_WOOD)
	_shop_window(g, 2.15, 0.62, 2.5, 1.85, COL_DARK_WOOD)
	# Window life: a silhouette cat, a cake stand, pendant lamps, a plant.
	_window_cat(g, Vector3(-2.75, 0.66, 0.07), Color("6B4A35"))
	k.cyl(g, Vector3(-1.6, 0.78, 0.07), 0.12, 0.25, k.mat(Color("C47A5A"), 0.8), 0.14, 10, false)
	k.ball(g, Vector3(-1.6, 1.08, 0.07), 0.24, 0.42, k.mat(Color("6F9468"), 0.9), 10, false).scale = Vector3(1, 1, 0.4)
	k.cyl(g, Vector3(2.15, 0.8, 0.07), 0.04, 0.3, k.mat(Color("8A5A3E"), 0.6), -1.0, 8, false)
	k.cyl(g, Vector3(2.15, 0.96, 0.07), 0.3, 0.03, k.mat(Color("8A5A3E"), 0.6), -1.0, 16, false)
	k.cyl(g, Vector3(2.15, 1.08, 0.08), 0.2, 0.2, k.mat(Color("F2E4CF"), 0.8), -1.0, 16, false)
	k.cyl(g, Vector3(2.15, 1.2, 0.08), 0.2, 0.05, k.mat(Color("E8A0B4"), 0.8), -1.0, 16, false)
	for lx in [-2.6, -1.7, 1.7, 2.6]:
		k.box(g, Vector3(lx, 2.27, 0.07), Vector3(0.015, 0.2, 0.015), k.mat(COL_IRON, 0.5), false)
		k.ball(g, Vector3(lx, 2.13, 0.08), 0.08, 0.1, k.glow(Color("FFE7B8"), 3.0), 10, false)
	_door(g, 0.0, 1.05, 2.2, Color("8FA88A"), COL_DARK_WOOD, true)
	# "Open" sign on the door.
	k.box(g, Vector3(0, 1.75, 0.09), Vector3(0.42, 0.16, 0.02), k.mat(COL_CREAM, 0.7), false)
	k.label(g, "OPEN", Vector3(0, 1.745, 0.105), 0.0, 32, Color("C9643A"), COL_CREAM, 0.004, 0)
	_awning(g, 0.0, 3.05, w - 0.3, 0.78, 0.3, Color("9DB8A0"), COL_CREAM, 0.38)
	# String lights along the awning edge.
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in range(19):
		var t: float = float(i) / 18.0
		var lx: float = lerpf(-w * 0.5 + 0.2, w * 0.5 - 0.2, t)
		var sag: float = sin(fposmod(t * 3.0, 1.0) * PI) * 0.12
		k.ball(g, Vector3(lx, 2.5 - sag, 0.8), 0.045, 0.07, k.glow(Color("FFD27A"), 3.2), 8, false)
	_sign_board(g, Vector3(0.35, 3.55, 0.02), Vector2(3.6, 0.62), COL_CREAM, COL_WALNUT, "THE CAT CAFE", COL_WALNUT, 74)
	var plaque := k.node(g, "CatIcon", Vector3(-1.85, 3.55, 0.08))
	_disc(plaque, Vector3(0, 0, -0.02), 0.38, k.mat(COL_WALNUT, 0.7))
	_disc(plaque, Vector3(0, 0, 0.0), 0.33, k.mat(COL_CREAM, 0.7))
	var ic := k.node(plaque, "Glyph", Vector3(0, -0.02, 0.03))
	_icon(ic, "cat", Color("6B4A35"), 0.52)
	# Upper floor: three windows with sage shutters and flower boxes.
	var shut := Color("8FA88A")
	_window(g, -2.5, 4.75, 0.95, 1.05, COL_TRIM, true, {"shutter": shut, "flowers": true, "seed": 3, "curtain": Color("E8A0B4")})
	_window(g, 0.0, 4.75, 0.95, 1.05, COL_TRIM, false, {"shutter": shut, "flowers": true, "seed": 5})
	_window(g, 2.5, 4.75, 0.95, 1.05, COL_TRIM, true, {"shutter": shut, "flowers": true, "seed": 7, "curtain": Color("F2C14E")})
	var roof_mat: Material = k.tri_mat(k.tex_shingles(Color("B5634B")), 1.0, 0.85)
	_gable_roof(g, w, d, h + 0.18, 2.1, roof_mat, wall)
	_chimney(g, Vector3(2.4, h + 1.2, -d * 0.7), 1.6, k.tri_mat(k.tex_brick(Color("A65E46"), Color("D8C3A5")), 1.0))
	_blade_sign(g, Vector3(w * 0.5 - 0.15, 2.65, 0.7), Vector2(0.7, 0.7), COL_CREAM, COL_WALNUT, "cat", Color("6B4A35"))
	_sconce(g, Vector3(-0.9, 2.45, 0.06))
	_sconce(g, Vector3(0.9, 2.45, 0.06), false)
	# Sidewalk dressing: bench under the left window, planters, chalk A-board.
	_bench(g, Vector3(-2.3, 0, 0.55), 1.4, 0.0)
	_planter(g, Vector3(-3.55, 0, 0.35), 0.5, 41, true)
	_planter(g, Vector3(3.55, 0, 0.35), 0.5, 43, true)
	_a_board(g, Vector3(-0.95, 0, 1.25), "Cats & cocoa")
	return g

## Partner animal shelter: teal clapboard, rooftop paw sign, door canopy, adoption board.
func build_shelter(parent: Node3D, pos: Vector3, w: float, d: float) -> Node3D:
	var g := k.node(parent, "Shelter", pos)
	var h: float = 5.4
	var wall: Material = k.tri_mat(k.tex_siding(Color("87AAA6")), 1.0, 0.9)
	_body(g, w, d, h, wall, Color("5E7F7B"), COL_TRIM)
	_band(g, w, d, 3.05, COL_TRIM, 0.12)
	# Parapet.
	k.box(g, Vector3(0, h + 0.45, -0.1), Vector3(w + 0.1, 0.7, 0.2), k.mat(Color("7B9E9A"), 0.9))
	k.box(g, Vector3(w * 0.5 - 0.05, h + 0.45, -d * 0.5), Vector3(0.2, 0.7, d), k.mat(Color("7B9E9A"), 0.9))
	k.box(g, Vector3(0, h + 0.83, -0.1), Vector3(w + 0.2, 0.08, 0.3), k.mat(COL_TRIM, 0.8))
	_shop_window(g, -2.35, 0.7, 1.9, 1.6, COL_TRIM, Color("FFE2B0"))
	_shop_window(g, 2.35, 0.7, 1.9, 1.6, COL_TRIM, Color("FFE2B0"))
	# Window life: cat tree on the left, kennel grid + sleeping silhouette on the right.
	k.box(g, Vector3(-2.75, 1.2, 0.07), Vector3(0.08, 1.0, 0.02), k.mat(Color("C9A27A"), 0.8), false)
	k.box(g, Vector3(-2.75, 1.45, 0.075), Vector3(0.6, 0.06, 0.02), k.mat(Color("A7805A"), 0.8), false)
	k.box(g, Vector3(-2.75, 0.95, 0.075), Vector3(0.5, 0.06, 0.02), k.mat(Color("A7805A"), 0.8), false)
	_window_cat(g, Vector3(-2.85, 1.48, 0.08), Color("5E4A42"))
	for i in range(3):
		k.box(g, Vector3(2.35 - 0.6 + float(i) * 0.6, 1.5, 0.07), Vector3(0.03, 1.6, 0.02), k.mat(Color("8E8A86"), 0.5), false)
	k.box(g, Vector3(2.35, 1.5, 0.07), Vector3(1.9, 0.03, 0.02), k.mat(Color("8E8A86"), 0.5), false)
	var sleep: MeshInstance3D = k.ball(g, Vector3(2.65, 0.85, 0.08), 0.22, 0.2, k.mat(Color("6B4A35"), 0.9), 12, false)
	sleep.scale = Vector3(1.0, 1.0, 0.2)
	_door(g, 0.0, 1.5, 2.25, Color("F3E6D3"), Color("5E7F7B"), true, true)
	# Door canopy on brackets.
	k.box(g, Vector3(0, 2.65, 0.45), Vector3(2.1, 0.1, 0.9), k.mat(Color("4F6E6A"), 0.8))
	k.box(g, Vector3(0, 2.72, 0.45), Vector3(2.0, 0.05, 0.8), k.mat(COL_TRIM, 0.8), false)
	for s in [-1.0, 1.0]:
		var br: MeshInstance3D = k.box(g, Vector3(s * 0.95, 2.4, 0.3), Vector3(0.05, 0.05, 0.6), k.mat(COL_IRON, 0.5), false)
		br.rotation_degrees.x = 35.0
	_sign_board(g, Vector3(0, 3.55, 0.02), Vector2(4.6, 0.6), COL_CREAM, Color("4F6E6A"), "ANIMAL SHELTER", Color("4F6E6A"), 70)
	# Rooftop sign: big paw + name on posts.
	for sx in [-1.6, 1.6]:
		k.box(g, Vector3(sx, h + 1.1, -0.5), Vector3(0.08, 1.3, 0.08), k.mat(COL_IRON, 0.5))
	_sign_board(g, Vector3(0.45, h + 1.45, -0.45), Vector2(3.4, 0.62), Color("E07A5F"), COL_CREAM, "PAWS & HEARTS", COL_CREAM, 66)
	var paw := k.node(g, "PawSign", Vector3(-2.0, h + 1.45, -0.38))
	_disc(paw, Vector3(0, 0, -0.03), 0.48, k.mat(COL_CREAM, 0.7))
	_disc(paw, Vector3(0, 0, -0.01), 0.42, k.mat(Color("E07A5F"), 0.7))
	var pic := k.node(paw, "Glyph", Vector3(0, 0, 0.02))
	_icon(pic, "paw", COL_CREAM, 0.62)
	# Upper windows with flower boxes.
	for i in range(4):
		var wx: float = -2.7 + float(i) * 1.8
		_window(g, wx, 4.3, 0.85, 0.95, COL_TRIM, i % 2 == 0, {"flowers": true, "seed": 20 + i, "curtain": Color("F2C14E")})
	# Adoption notice board with posters.
	var nb := Vector3(-1.45, 1.45, 0.08)
	k.box(g, nb, Vector3(0.62, 0.8, 0.05), k.mat(COL_DARK_WOOD, 0.8))
	k.box(g, nb + Vector3(0, 0, 0.03), Vector3(0.54, 0.72, 0.02), k.mat(Color("C9A27A"), 0.9), false)
	var poster_cols: Array[Color] = [Color("FFF6EA"), Color("F2C14E"), Color("E8A0B4"), Color("9DB8A0")]
	for i in range(4):
		var px: float = -0.13 + float(i % 2) * 0.26
		var py: float = 0.16 - float(i >> 1) * 0.32
		k.box(g, nb + Vector3(px, py, 0.05), Vector3(0.2, 0.26, 0.01), k.mat(poster_cols[i], 0.9), false)
		k.box(g, nb + Vector3(px, py + 0.03, 0.057), Vector3(0.12, 0.1, 0.005), k.mat(Color("6B4A35"), 0.9), false)
	_sconce(g, Vector3(1.25, 2.3, 0.06))
	# Painted paw prints leading to the door.
	for i in range(5):
		var pp := k.node(g, "PawPrint", Vector3(0.25 * (1.0 if i % 2 == 0 else -1.0), 0.012, 0.75 + float(i) * 0.38))
		pp.rotation_degrees.x = -90.0
		_icon(pp, "paw", Color("E8C3A0"), 0.28)
	# Bench + donation box outside.
	_bench(g, Vector3(2.4, 0, 0.6), 1.3, 0.0)
	k.box(g, Vector3(-2.35 + 1.15, 0.45, 0.3), Vector3(0.3, 0.9, 0.3), k.mat(Color("E07A5F"), 0.8))
	k.box(g, Vector3(-1.2, 0.92, 0.3), Vector3(0.34, 0.06, 0.34), k.mat(COL_TRIM, 0.8))
	# Alley side (east wall, faces +X): side door, bare bulb, drainpipe.
	var side := k.node(g, "AlleySide", Vector3(w * 0.5, 0, -d * 0.5), 90.0)
	_door(side, 1.2, 0.9, 2.0, Color("5E7F7B"), COL_TRIM, false)
	_sconce(side, Vector3(1.2, 2.35, 0.04), false)
	k.cyl(side, Vector3(-2.6, h * 0.5, 0.1), 0.06, h, k.mat(Color("8E8A86"), 0.5), -1.0, 10)
	for i in range(3):
		_window(side, -0.9 + float(i) * 1.6 - 0.8, 4.3, 0.75, 0.9, COL_TRIM, i == 1, {"curtain": Color("9DB8A0")})
	return g

## The player's home: brick walk-up with a stoop, cream trim and a rooftop water tank.
func build_apartment(parent: Node3D, pos: Vector3, w: float, d: float, rot: float) -> Node3D:
	var g := k.node(parent, "Apartment", pos, rot)
	var h: float = 8.2
	var brick: Material = k.tri_mat(k.tex_brick(Color("A65E46"), Color("E3CDB0")), 1.0, 0.9)
	_body(g, w, d, h, brick, Color("6B4A35"), COL_TRIM)
	_band(g, w, d, 2.85, COL_TRIM, 0.1)
	_band(g, w, d, 5.55, COL_TRIM, 0.08)
	# Ground floor: stoop door in the middle, two windows per side.
	_door(g, 0.0, 1.1, 2.3, Color("4F6E5A"), COL_TRIM, true)
	k.box(g, Vector3(0, 2.6, 0.08), Vector3(1.0, 0.24, 0.04), k.glow(COL_GLASS_LIT, 1.2), false)
	k.label(g, "12", Vector3(0, 2.59, 0.11), 0.0, 40, COL_TEXT, COL_CREAM, 0.004, 0)
	# Stoop: three steps + iron railings.
	for i in range(3):
		k.box(g, Vector3(0, 0.035 * float(i + 1), 0.3 + 0.28 * float(2 - i)), Vector3(1.7, 0.07 * float(i + 1), 0.28), k.mat(Color("BBA58C").darkened(0.04 * float(i)), 0.9))
	for s in [-1.0, 1.0]:
		k.box(g, Vector3(s * 0.8, 0.75, 0.75), Vector3(0.04, 0.04, 0.9), k.mat(COL_IRON, 0.5), false, Vector3(-20, 0, 0))
		for j in range(3):
			k.box(g, Vector3(s * 0.8, 0.5, 0.4 + float(j) * 0.3), Vector3(0.03, 0.55 - float(j) * 0.1, 0.03), k.mat(COL_IRON, 0.5), false)
	_sconce(g, Vector3(-0.85, 2.25, 0.06))
	_sign_board(g, Vector3(0, 3.25, 0.02), Vector2(2.4, 0.45), Color("4F6E5A"), COL_TRIM, "MAPLE COURT", COL_CREAM, 58)
	var house := k.node(g, "HomeIcon", Vector3(-1.55, 3.25, 0.06))
	_disc(house, Vector3(0, 0, -0.01), 0.26, k.mat(COL_TRIM, 0.7))
	_icon(k.node(house, "Glyph", Vector3(0, 0, 0.02)), "house", Color("4F6E5A"), 0.36)
	var lit_pattern: Array = [true, false, true, true, false, true, false, true, true, false, true, true]
	var idx: int = 0
	for floor_i in range(3):
		var wy: float = 1.45 + float(floor_i) * 2.7
		for wx in [-3.1, -1.75, 1.75, 3.1]:
			if floor_i == 0:
				_window(g, wx, wy, 0.85, 1.25, COL_TRIM, lit_pattern[idx % lit_pattern.size()], {"curtain": Color("E8A0B4") if idx % 3 == 0 else Color("9DB8A0")})
			else:
				_window(g, wx, wy, 0.85, 1.35, COL_TRIM, lit_pattern[idx % lit_pattern.size()], {"flowers": idx % 2 == 0, "seed": 60 + idx, "curtain": Color("F2C14E") if idx % 2 == 0 else Color("E8A0B4")})
			idx += 1
		if floor_i > 0:
			_window(g, 0.0, wy, 0.75, 1.35, COL_TRIM, floor_i == 2, {"curtain": Color("9DB8A0")})
	# Roof: parapet + water tank on legs.
	k.box(g, Vector3(0, h + 0.4, -0.1), Vector3(w + 0.1, 0.6, 0.2), brick)
	k.box(g, Vector3(0, h + 0.73, -0.1), Vector3(w + 0.2, 0.08, 0.3), k.mat(COL_TRIM, 0.8))
	var tank := Vector3(1.6, h + 0.2, -d * 0.55)
	for lx in [-0.45, 0.45]:
		for lz in [-0.45, 0.45]:
			k.box(g, tank + Vector3(lx, 0.6, lz), Vector3(0.08, 1.2, 0.08), k.mat(COL_IRON, 0.6))
	k.cyl(g, tank + Vector3(0, 1.8, 0), 0.75, 1.2, k.tri_mat(k.tex_planks(Color("9C6B4A"), 8), 1.0, 0.85), -1.0, 18)
	k.cyl(g, tank + Vector3(0, 2.6, 0), 0.82, 0.45, k.mat(Color("6E7480"), 0.7), 0.05, 18)
	_chimney(g, Vector3(-2.6, h, -d * 0.6), 1.0, brick)
	# Mailbox + planters by the stoop.
	_planter(g, Vector3(-1.5, 0, 0.35), 0.7, 61)
	_planter(g, Vector3(1.5, 0, 0.35), 0.7, 63)
	k.box(g, Vector3(2.35, 0.95, 0.12), Vector3(0.5, 0.36, 0.14), k.mat(Color("6F8FB8").darkened(0.2), 0.6))
	return g

## Pet supply shop: mustard clapboard, teal awning, stacked kibble bags, bone blade sign.
func build_pet_shop(parent: Node3D, pos: Vector3, w: float, d: float, rot: float) -> Node3D:
	var g := k.node(parent, "PetShop", pos, rot)
	var h: float = 5.2
	var wall: Material = k.tri_mat(k.tex_siding(Color("D9A55A")), 1.0, 0.9)
	_body(g, w, d, h, wall, Color("7A5236"), COL_TRIM)
	_band(g, w, d, 3.05, COL_TRIM, 0.1)
	_shop_window(g, -1.75, 0.6, 2.2, 1.75, COL_TRIM)
	_shop_window(g, 1.85, 0.6, 1.6, 1.75, COL_TRIM)
	# Shelves of colourful goods + a fishbowl.
	var goods: Array[Color] = [Color("E07A5F"), Color("6F8FB8"), Color("F2C14E"), Color("9DB8A0"), Color("E8A0B4"), Color("C9643A")]
	var r := RandomNumberGenerator.new()
	r.seed = 91
	for row in range(2):
		var sy: float = 0.95 + float(row) * 0.65
		k.box(g, Vector3(-1.75, sy - 0.04, 0.07), Vector3(2.1, 0.04, 0.03), k.mat(COL_DARK_WOOD, 0.8), false)
		var x: float = -2.75
		while x < -0.85:
			var bw: float = r.randf_range(0.14, 0.26)
			var bh: float = r.randf_range(0.2, 0.38)
			k.box(g, Vector3(x + bw * 0.5, sy + bh * 0.5 - 0.02, 0.075), Vector3(bw - 0.02, bh, 0.03), k.mat(goods[r.randi_range(0, goods.size() - 1)], 0.8), false)
			x += bw
	var bowl: MeshInstance3D = k.ball(g, Vector3(1.85, 1.0, 0.1), 0.3, 0.55, k.mat(Color("BFE0E6"), 0.1), 16, false)
	bowl.scale = Vector3(1, 1, 0.3)
	k.ball(g, Vector3(1.8, 0.98, 0.17), 0.06, 0.06, k.mat(Color("F29E4C"), 0.5), 8, false)
	k.cyl(g, Vector3(1.85, 0.7, 0.08), 0.3, 0.08, k.mat(COL_DARK_WOOD, 0.8), -1.0, 16, false)
	_window_cat(g, Vector3(2.25, 1.45, 0.08), Color("5E4A42"))
	_door(g, 0.0, 0.95, 2.15, Color("5E8C8A"), COL_TRIM, true)
	_awning(g, 0.0, 2.72, w - 0.3, 0.65, 0.25, Color("5E8C8A"), COL_CREAM, 0.34)
	_sign_board(g, Vector3(0.0, 3.72, 0.02), Vector2(3.4, 0.55), Color("5E8C8A"), COL_TRIM, "KIBBLE & CO.", COL_CREAM, 66)
	k.label(g, "PET SUPPLIES  ·  TREATS  ·  TOYS", Vector3(0, 3.24, 0.1), 0.0, 32, COL_TEXT, COL_CREAM, 0.005, 3)
	_window(g, -1.6, 4.58, 0.9, 0.8, COL_TRIM, true, {"shutter": Color("5E8C8A"), "curtain": Color("E8A0B4")})
	_window(g, 1.6, 4.58, 0.9, 0.8, COL_TRIM, false, {"shutter": Color("5E8C8A")})
	var roof_mat: Material = k.tri_mat(k.tex_shingles(Color("6E7480")), 1.0, 0.85)
	_gable_roof(g, w, d, h + 0.18, 1.8, roof_mat, wall)
	_blade_sign(g, Vector3(w * 0.5 - 0.15, 2.6, 0.7), Vector2(0.75, 0.55), COL_CREAM, Color("5E8C8A"), "bone", Color("D9A55A"))
	_sconce(g, Vector3(0.75, 2.35, 0.06))
	# Stacked kibble bags + a dog water bowl out front.
	for i in range(3):
		var bag: MeshInstance3D = k.box(g, Vector3(-2.55 + float(i) * 0.42, 0.3, 0.45), Vector3(0.36, 0.6, 0.22), k.mat(goods[(i + 1) % goods.size()], 0.85))
		bag.rotation_degrees.y = r.randf_range(-8.0, 8.0)
		k.box(g, Vector3(-2.55 + float(i) * 0.42, 0.36, 0.565), Vector3(0.2, 0.16, 0.01), k.mat(COL_CREAM, 0.8), false)
	k.box(g, Vector3(-2.15, 0.7, 0.45), Vector3(0.36, 0.2, 0.22), k.mat(goods[4], 0.85))
	k.cyl(g, Vector3(1.0, 0.05, 0.5), 0.18, 0.1, k.mat(Color("6F8FB8"), 0.4), 0.22, 16)
	return g

## Decorative backdrop townhouse at the far corner (mostly roof + upper floors are seen).
func build_corner_house(parent: Node3D, pos: Vector3, w: float, d: float) -> Node3D:
	var g := k.node(parent, "CornerHouse", pos)
	var h: float = 7.4
	var wall: Material = k.tri_mat(k.tex_brick(Color("8A5A48"), Color("D8C3A5")), 1.0, 0.9)
	_body(g, w, d, h, wall, Color("5A4034"), COL_TRIM)
	for floor_i in range(3):
		for wx in [-1.9, 0.0, 1.9]:
			_window(g, wx, 1.6 + float(floor_i) * 2.4, 0.8, 1.1, COL_TRIM, (floor_i + int(wx)) % 2 == 0, {"curtain": Color("F2C14E")})
	_gable_roof(g, w, d, h + 0.18, 2.0, k.tri_mat(k.tex_shingles(Color("5E5560")), 1.0, 0.85), wall)
	_chimney(g, Vector3(-1.8, h + 0.9, -d * 0.4), 1.8, wall)
	return g

# ================================================================== small props

func _bench(g: Node3D, c: Vector3, w: float, rot_y: float) -> Node3D:
	var b := k.node(g, "Bench", c, rot_y)
	var wood: Material = k.mat(Color("B07A4F"), 0.8)
	var iron: Material = k.mat(COL_IRON, 0.5)
	for i in range(3):
		k.box(b, Vector3(0, 0.44, -0.06 + float(i) * 0.13), Vector3(w, 0.05, 0.11), wood)
	for i in range(2):
		k.box(b, Vector3(0, 0.62 + float(i) * 0.16, -0.22), Vector3(w, 0.1, 0.04), wood)
	for s in [-1.0, 1.0]:
		k.box(b, Vector3(s * (w * 0.5 - 0.1), 0.21, 0.06), Vector3(0.05, 0.42, 0.05), iron)
		k.box(b, Vector3(s * (w * 0.5 - 0.1), 0.42, -0.2), Vector3(0.05, 0.84, 0.05), iron)
		k.box(b, Vector3(s * (w * 0.5 - 0.1), 0.6, -0.05), Vector3(0.05, 0.05, 0.36), iron)
	return b

func _a_board(g: Node3D, c: Vector3, text: String) -> void:
	var b := k.node(g, "ABoard", c, 0.0)
	var face: MeshInstance3D = k.box(b, Vector3(0, 0.5, 0.12), Vector3(0.6, 0.9, 0.04), k.mat(Color("3E3A36"), 0.9))
	face.rotation_degrees.x = -12.0
	var back: MeshInstance3D = k.box(b, Vector3(0, 0.5, -0.12), Vector3(0.6, 0.9, 0.04), k.mat(COL_WALNUT, 0.9))
	back.rotation_degrees.x = 12.0
	var lab: Label3D = k.label(b, text, Vector3(0, 0.62, 0.155), 0.0, 30, COL_CREAM, Color("3E3A36"), 0.004, 0)
	lab.rotation_degrees.x = -12.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD
	lab.width = 120.0
	var heart: Label3D = k.label(b, "today!", Vector3(0, 0.34, 0.2), 0.0, 28, Color("E8A0B4"), Color("3E3A36"), 0.004, 0)
	heart.rotation_degrees.x = -12.0
