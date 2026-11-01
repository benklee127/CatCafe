extends RefCounted

## Builds the town block: diorama plinth, roads with crosswalks and lane dashes, curbed
## sidewalks, lots, the back alley, the park, the market plaza with bus stop, street
## furniture (lampposts, planters, hydrant, signs), autumn trees and fallen leaves.
## Buildings come from TownFacades.gd. Everything is primitives + procedural textures.

const Kit := preload("res://Scripts/environments/common/town_proc_kit.gd")
const Facades := preload("res://Scripts/environments/town/TownFacades.gd")
const L := preload("res://Scripts/environments/town/TownLayout.gd")

const COL_PLINTH := Color("5A4034")
const COL_LIP := Color("7A5236")
const COL_ASPHALT := Color("5A5052")
const COL_PAVER := Color("CDB9A0")
const COL_GROUT := Color("A8917A")
const COL_CURB := Color("B8A48E")
const COL_LANE := Color("E8C56B")
const COL_ZEBRA := Color("EFE3CF")
const COL_GRASS := Color("7E9A5E")
const COL_IRON := Color("2F3A35")
const COL_TRUNK := Color("6B4A35")
const AUTUMN: Array[Color] = [Color("E0893C"), Color("C9643A"), Color("E8B04B"), Color("B5523B"), Color("D9A55A")]

var k: Kit
var f: Facades
var root: Node3D
## Building roots by hotspot id (cafe, shelter, home, shop, alley, park, market).
var buildings: Dictionary = {}
## Interesting world points (box spots, benches) for Town.gd.
var points: Dictionary = {}

func _init(kit: Kit) -> void:
	k = kit
	f = Facades.new(kit)

func build(parent: Node3D) -> void:
	root = k.node(parent, "TownGeometry")
	_build_ground()
	_build_roads()
	_build_sidewalks()
	_build_buildings()
	_build_alley()
	_build_garden_lot()
	_build_park()
	_build_plaza()
	_build_street_furniture()
	_build_leaves()

# ------------------------------------------------------------------ helpers

func _slab(parent: Node3D, r: Rect2, top: float, thick: float, m: Material, shadow: bool = false) -> MeshInstance3D:
	return k.box(parent, Vector3(r.get_center().x, top - thick * 0.5, r.get_center().y), Vector3(r.size.x, thick, r.size.y), m, shadow)

func _tree(parent: Node3D, pos: Vector3, scale: float, seed: int) -> void:
	var g := k.node(parent, "Tree", pos)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var trunk_h: float = 1.6 * scale
	k.cyl(g, Vector3(0, trunk_h * 0.5, 0), 0.14 * scale, trunk_h, k.mat(COL_TRUNK, 0.9), 0.1 * scale, 10)
	var br: MeshInstance3D = k.cyl(g, Vector3(0.22 * scale, trunk_h * 0.85, 0), 0.05 * scale, 0.7 * scale, k.mat(COL_TRUNK, 0.9), 0.03 * scale, 8)
	br.rotation_degrees.z = -40.0
	var base: Color = AUTUMN[r.randi_range(0, AUTUMN.size() - 1)]
	var blobs: Array = [
		[Vector3(0, trunk_h + 0.6 * scale, 0), 0.95],
		[Vector3(0.55, trunk_h + 0.35 * scale, 0.2), 0.7],
		[Vector3(-0.5, trunk_h + 0.4 * scale, -0.15), 0.7],
		[Vector3(0.1, trunk_h + 1.15 * scale, -0.1), 0.65],
		[Vector3(0.0, trunk_h + 0.3 * scale, 0.55), 0.6],
		[Vector3(-0.15, trunk_h + 0.35 * scale, -0.55), 0.6],
	]
	for b in blobs:
		var c: Color = base.lerp(AUTUMN[r.randi_range(0, AUTUMN.size() - 1)], 0.35).lightened(r.randf_range(-0.06, 0.08))
		var rad: float = float(b[1]) * scale
		k.ball(g, (b[0] as Vector3) * Vector3(scale, 1.0, scale), rad, rad * 1.7, k.mat(c, 0.95), 12)

func _hedge(parent: Node3D, from: Vector3, to: Vector3, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var seg_len: float = from.distance_to(to)
	var n: int = maxi(1, int(seg_len / 0.45))
	for i in range(n):
		var t: float = (float(i) + 0.5) / float(n)
		var p: Vector3 = from.lerp(to, t)
		var c: Color = Color("5E7F4E").lightened(r.randf_range(-0.05, 0.08))
		k.ball(parent, p + Vector3(0, 0.3, 0), 0.32, 0.6, k.mat(c, 0.95), 10)

func _lamppost(parent: Node3D, pos: Vector3) -> void:
	var g := k.node(parent, "Lamppost", pos)
	var iron: Material = k.mat(COL_IRON, 0.45)
	k.cyl(g, Vector3(0, 0.15, 0), 0.13, 0.3, iron, 0.1, 12)
	k.cyl(g, Vector3(0, 1.6, 0), 0.05, 2.7, iron, 0.04, 10)
	k.cyl(g, Vector3(0, 2.95, 0), 0.09, 0.08, iron, -1.0, 10)
	k.box(g, Vector3(0, 3.15, 0), Vector3(0.26, 0.32, 0.26), k.glow(Color("FFC98A"), 2.6), false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(g, Vector3(sx * 0.13, 3.15, sz * 0.13), Vector3(0.03, 0.34, 0.03), iron, false)
	k.cyl(g, Vector3(0, 3.36, 0), 0.24, 0.12, iron, 0.06, 10)
	k.ball(g, Vector3(0, 3.48, 0), 0.05, 0.1, iron, 8)
	k.omni(g, Vector3(0, 2.9, 0), Color("FFC98A"), 1.4, 6.5)

func _planter_box(parent: Node3D, c: Vector3, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	k.cyl(parent, c + Vector3(0, 0.25, 0), 0.32, 0.5, k.mat(Color("C47A5A"), 0.85), 0.26, 14)
	k.cyl(parent, c + Vector3(0, 0.5, 0), 0.34, 0.05, k.mat(Color("A65E46"), 0.85), -1.0, 14)
	k.ball(parent, c + Vector3(0, 0.72, 0), 0.32, 0.5, k.mat(Color("6F9468").darkened(r.randf_range(0.0, 0.15)), 0.9), 10)
	for i in range(4):
		var a: float = r.randf() * TAU
		k.ball(parent, c + Vector3(cos(a) * 0.2, 0.82 + r.randf() * 0.1, sin(a) * 0.2), 0.06, 0.1, k.mat(f.FLOWER_COLS[r.randi_range(0, f.FLOWER_COLS.size() - 1)], 0.8), 8, false)

func _pumpkin(parent: Node3D, c: Vector3, s: float) -> void:
	var p: MeshInstance3D = k.ball(parent, c + Vector3(0, s * 0.35, 0), s * 0.5, s * 0.7, k.mat(Color("E0893C"), 0.7), 14)
	p.scale = Vector3(1.0, 1.0, 1.0)
	for i in range(3):
		var rib: MeshInstance3D = k.ball(parent, c + Vector3(0, s * 0.35, 0), s * 0.5, s * 0.72, k.mat(Color("D0782E"), 0.7), 14, false)
		rib.scale = Vector3(0.35, 1.0, 1.02)
		rib.rotation_degrees.y = float(i) * 60.0
	k.cyl(parent, c + Vector3(0, s * 0.75, 0), s * 0.06, s * 0.18, k.mat(Color("5E6B3A"), 0.8), s * 0.04, 6)

func _crate(parent: Node3D, c: Vector3, s: Vector3, rot: float = 0.0) -> MeshInstance3D:
	var m: MeshInstance3D = k.box(parent, c + Vector3(0, s.y * 0.5, 0), s, k.tri_mat(k.tex_planks(Color("B07A4F"), 4), 0.5, 0.85), true, Vector3(0, rot, 0))
	return m

func _cardboard(parent: Node3D, c: Vector3, s: Vector3, rot: float = 0.0) -> MeshInstance3D:
	var m: MeshInstance3D = k.box(parent, c + Vector3(0, s.y * 0.5, 0), s, k.mat(Color("C9A27A"), 0.95), true, Vector3(0, rot, 0))
	var tape: MeshInstance3D = k.box(parent, c + Vector3(0, s.y + 0.003, 0), Vector3(s.x * 0.18, 0.006, s.z + 0.004), k.mat(Color("E3CDA8"), 0.8), false, Vector3(0, rot, 0))
	tape.name = "Tape"
	return m

func _wire(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var seg: float = a.distance_to(b)
	if seg < 0.001:
		return
	var mi: MeshInstance3D = k.box(parent, (a + b) * 0.5, Vector3(0.015, 0.015, seg), k.mat(Color("2A2422"), 0.8), false)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)

# ------------------------------------------------------------------ ground

func _build_ground() -> void:
	var g := k.node(root, "Ground")
	var gr: Rect2 = L.GROUND
	_slab(g, gr.grow(0.25), -0.16, 0.7, k.mat(COL_PLINTH, 0.9), true)
	_slab(g, gr.grow(0.06), -0.13, 0.04, k.mat(COL_LIP, 0.8))
	# Roads are the base surface; everything else sits on top of it.
	_slab(g, gr, -0.1, 0.05, k.tri_mat(k.tex_asphalt(COL_ASPHALT), 2.0, 0.92))
	# Lots behind the sidewalks: paved under the north row, grass in the west column gaps.
	var lot_mat: Material = k.tri_mat(k.tex_pavers(Color("BFA88E"), Color("9C866F"), 3), 1.0, 0.92)
	_slab(g, Rect2(-17.0, -13.0, 32.0, 7.0), 0.0, 0.12, lot_mat)
	_slab(g, Rect2(-17.0, -6.0, 7.0, 18.0), 0.0, 0.12, k.tri_mat(k.tex_grass(COL_GRASS), 2.0, 0.95))

func _build_roads() -> void:
	var g := k.node(root, "Roads")
	var lane: Material = k.mat(COL_LANE, 0.8)
	var zebra: Material = k.mat(COL_ZEBRA, 0.8)
	var y: float = -0.1 + 0.006
	# Main road centre dashes (skip the intersection and the crosswalk).
	var x: float = -3.6
	while x < 14.6:
		if not (x + 1.0 > L.CROSSWALK_MAIN.position.x - 0.3 and x < L.CROSSWALK_MAIN.end.x + 0.3):
			k.box(g, Vector3(x + 0.5, y, -2.0), Vector3(1.0, 0.012, 0.12), lane, false)
		x += 1.8
	var z: float = 0.6
	while z < 11.6:
		if not (z + 1.0 > L.CROSSWALK_CROSS.position.y - 0.3 and z < L.CROSSWALK_CROSS.end.y + 0.3):
			k.box(g, Vector3(-6.0, y, z + 0.5), Vector3(0.12, 0.012, 1.0), lane, false)
		z += 1.8
	# Zebra crossings.
	var cw: Rect2 = L.CROSSWALK_MAIN
	var sx: float = cw.position.x + 0.15
	while sx < cw.end.x - 0.1:
		k.box(g, Vector3(sx + 0.15, y, cw.get_center().y), Vector3(0.3, 0.012, cw.size.y - 0.2), zebra, false)
		sx += 0.55
	var cc: Rect2 = L.CROSSWALK_CROSS
	var sz: float = cc.position.y + 0.15
	while sz < cc.end.y - 0.1:
		k.box(g, Vector3(cc.get_center().x, y, sz + 0.15), Vector3(cc.size.x - 0.2, 0.012, 0.3), zebra, false)
		sz += 0.55
	# Stop lines + manhole + drains.
	k.box(g, Vector3(cw.position.x - 0.4, y, -1.0), Vector3(0.12, 0.012, 2.0), zebra, false)
	var mh: MeshInstance3D = k.cyl(g, Vector3(6.5, -0.095, -1.0), 0.38, 0.012, k.mat(Color("4A4245"), 0.6), -1.0, 18, false)
	mh.name = "Manhole"
	for p in [Vector3(-2.0, -0.095, -3.85), Vector3(9.5, -0.095, -0.15), Vector3(-7.85, -0.095, 8.0)]:
		k.box(g, p, Vector3(0.6, 0.012, 0.22), k.mat(Color("3A3436"), 0.5), false)

func _build_sidewalks() -> void:
	var g := k.node(root, "Sidewalks")
	var pav: Material = k.tri_mat(k.tex_pavers(COL_PAVER, COL_GROUT, 2), 1.0, 0.9)
	var curb: Material = k.mat(COL_CURB, 0.85)
	for r in [L.WALK_NORTH, L.WALK_WEST, L.WALK_SOUTH, L.WALK_EAST]:
		_slab(g, r, 0.0, 0.1, pav)
	# Curbs along the road edges.
	var t: float = 0.14
	_slab(g, Rect2(-8.0, -4.0 - t, 23.0, t), 0.012, 0.11, curb)
	_slab(g, Rect2(-8.0 - t, -4.0, t, 16.0), 0.012, 0.11, curb)
	_slab(g, Rect2(-4.0, 0.0, 19.0, t), 0.012, 0.11, curb)
	_slab(g, Rect2(-4.0, 0.0, t, 12.0), 0.012, 0.11, curb)

# ------------------------------------------------------------------ buildings

func _build_buildings() -> void:
	var g := k.node(root, "Buildings")
	var r: Rect2 = L.CAFE
	buildings["cafe"] = f.build_cafe(g, Vector3(r.get_center().x, 0, r.end.y), r.size.x, r.size.y)
	r = L.SHELTER
	buildings["shelter"] = f.build_shelter(g, Vector3(r.get_center().x, 0, r.end.y), r.size.x, r.size.y)
	r = L.CORNER_HOUSE
	f.build_corner_house(g, Vector3(r.get_center().x, 0, r.end.y), r.size.x, r.size.y)
	# West column faces +X: the facade width runs along Z.
	r = L.APARTMENT
	buildings["home"] = f.build_apartment(g, Vector3(r.end.x, 0, r.get_center().y), r.size.y, r.size.x, 90.0)
	r = L.PET_SHOP
	buildings["shop"] = f.build_pet_shop(g, Vector3(r.end.x, 0, r.get_center().y), r.size.y, r.size.x, 90.0)
	# Little shed-roof filler between the apartment and the corner house.
	var filler := k.node(g, "Filler", Vector3(-13.0, 0, -6.0))
	k.box(filler, Vector3(0, 1.2, 0), Vector3(5.0, 2.4, 0.6), k.tri_mat(k.tex_brick(Color("9C6B4A"), Color("D8C3A5")), 1.0, 0.9))
	# Garden wall south of the pet shop.
	k.box(g, Vector3(-13.0, 0.4, 11.6), Vector3(6.0, 0.8, 0.3), k.tri_mat(k.tex_brick(Color("A65E46"), Color("E3CDB0")), 1.0, 0.9))
	_tree(g, Vector3(-12.2, 0, 10.6), 1.0, 31)
	f._bench(g, Vector3(-10.9, 0, 10.6), 1.3, 90.0)

# ------------------------------------------------------------------ alley

func _build_alley() -> void:
	var g := k.node(root, "Alley")
	buildings["alley"] = g
	var a: Rect2 = L.ALLEY
	# Worn cobbles + a darker gutter down the middle.
	_slab(g, a, 0.006, 0.02, k.tri_mat(k.tex_cobble(Color("9A8A80"), Color("6A5E58")), 1.0, 0.95, Color(0.92, 0.9, 0.92)))
	k.box(g, Vector3(a.get_center().x, 0.008, a.get_center().y), Vector3(0.25, 0.01, a.size.y), k.mat(Color("6A5E58"), 0.5), false)
	var brick: Material = k.tri_mat(k.tex_brick(Color("8E4F3E"), Color("C7B29A")), 1.0, 0.92)
	# Back wall + a bricked-up arch + vines.
	k.box(g, Vector3(a.get_center().x, 1.9, a.position.y - 0.15), Vector3(a.size.x + 0.2, 3.8, 0.3), brick)
	k.box(g, Vector3(a.get_center().x, 3.85, a.position.y - 0.15), Vector3(a.size.x + 0.3, 0.12, 0.4), k.mat(Color("7A5236"), 0.8))
	k.box(g, Vector3(a.get_center().x + 0.4, 1.0, a.position.y + 0.02), Vector3(1.2, 2.0, 0.05), k.mat(Color("5E7F7B"), 0.8))
	k.box(g, Vector3(a.get_center().x + 0.4, 2.1, a.position.y + 0.02), Vector3(1.4, 0.15, 0.08), k.mat(Color("C7B29A"), 0.8))
	var vr := RandomNumberGenerator.new()
	vr.seed = 404
	for i in range(14):
		var vx: float = a.position.x + 0.3 + vr.randf() * 1.6
		var vy: float = 1.2 + vr.randf() * 2.4
		k.ball(g, Vector3(vx, vy, a.position.y + 0.05), 0.22, 0.3, k.mat(Color("6F8F55").lerp(Color("C9643A"), vr.randf() * 0.5), 0.95), 8, false)
	# East side: tall wooden fence with a gate.
	var fence: Material = k.tri_mat(k.tex_planks(Color("8A6446"), 6), 1.0, 0.9)
	k.box(g, Vector3(a.end.x + 0.05, 0.9, a.get_center().y - 0.3), Vector3(0.1, 1.8, a.size.y - 0.6), fence)
	k.box(g, Vector3(a.end.x + 0.05, 1.85, a.get_center().y - 0.3), Vector3(0.16, 0.08, a.size.y - 0.5), k.mat(Color("6B4A35"), 0.85))
	# Dumpster (back left) with a propped lid.
	var dz: float = a.position.y + 0.6
	var dx: float = a.position.x + 1.15
	k.box(g, Vector3(dx, 0.62, dz), Vector3(1.7, 1.0, 0.95), k.mat(Color("4F6E5A"), 0.6))
	k.box(g, Vector3(dx, 1.13, dz), Vector3(1.78, 0.05, 1.0), k.mat(Color("3E5A48"), 0.6))
	var lid: MeshInstance3D = k.box(g, Vector3(dx, 1.32, dz - 0.32), Vector3(1.7, 0.04, 0.55), k.mat(Color("3E5A48"), 0.6))
	lid.rotation_degrees.x = -50.0
	for wx in [-0.7, 0.7]:
		k.cyl(g, Vector3(dx + wx, 0.08, dz + 0.4), 0.08, 0.06, k.mat(Color("2A2A2A"), 0.6), -1.0, 10).rotation_degrees.z = 90.0
	k.box(g, Vector3(dx, 0.68, dz + 0.48), Vector3(0.9, 0.22, 0.01), k.mat(Color("E8C56B"), 0.7), false)
	# Trash cans with lids (back right).
	for p in [Vector3(a.end.x - 0.45, 0, a.position.y + 0.45), Vector3(a.end.x - 1.05, 0, a.position.y + 0.4)]:
		k.cyl(g, p + Vector3(0, 0.42, 0), 0.27, 0.84, k.mat(Color("8E8A86"), 0.4), 0.3, 14)
		k.cyl(g, p + Vector3(0, 0.87, 0), 0.32, 0.06, k.mat(Color("6E6A66"), 0.4), 0.3, 14)
		k.box(g, p + Vector3(0, 0.95, 0), Vector3(0.18, 0.05, 0.05), k.mat(Color("6E6A66"), 0.4))
	# Cardboard box stack along the fence + pallet + crates.
	_cardboard(g, Vector3(a.end.x - 0.4, 0, a.get_center().y - 0.2), Vector3(0.55, 0.45, 0.6), 8.0)
	_cardboard(g, Vector3(a.end.x - 0.42, 0.45, a.get_center().y - 0.2), Vector3(0.45, 0.38, 0.5), -6.0)
	_cardboard(g, Vector3(a.end.x - 0.45, 0, a.get_center().y + 0.55), Vector3(0.6, 0.35, 0.5), 15.0)
	var pallet: MeshInstance3D = k.box(g, Vector3(a.end.x - 0.2, 0.6, a.end.y - 1.1), Vector3(0.12, 1.2, 1.0), k.tri_mat(k.tex_planks(Color("C9A27A"), 5), 0.6, 0.85))
	pallet.rotation_degrees.z = 12.0
	_crate(g, Vector3(a.position.x + 0.45, 0, a.end.y - 1.3), Vector3(0.6, 0.5, 0.6), 5.0)
	_crate(g, Vector3(a.position.x + 0.45, 0.5, a.end.y - 1.3), Vector3(0.5, 0.42, 0.5), -10.0)
	# Puddle + food/water bowls someone leaves for the strays.
	var pd: MeshInstance3D = k.cyl(g, Vector3(a.get_center().x + 0.6, 0.02, a.get_center().y - 0.3), 0.4, 0.01, k.mat(Color("8A9AA8"), 0.05), -1.0, 20, false)
	pd.scale = Vector3(1.3, 1.0, 0.75)
	k.cyl(g, Vector3(a.position.x + 1.2, 0.04, a.get_center().y - 0.4), 0.16, 0.07, k.mat(Color("E07A5F"), 0.5), 0.2, 14)
	k.cyl(g, Vector3(a.position.x + 1.55, 0.04, a.get_center().y - 0.35), 0.16, 0.07, k.mat(Color("6F8FB8"), 0.5), 0.2, 14)
	k.ball(g, Vector3(a.position.x + 1.2, 0.08, a.get_center().y - 0.4), 0.11, 0.06, k.mat(Color("8A5A3E"), 0.9), 8, false)
	# String lights zig-zagging overhead (shelter wall -> fence).
	var bulb: Material = k.glow(Color("FFD27A"), 3.0)
	for seg in range(3):
		var z0: float = a.position.y + 1.0 + float(seg) * 1.5
		var p0 := Vector3(a.position.x + 0.05, 3.4, z0)
		var p1 := Vector3(a.end.x + 0.05, 2.1, z0 + 0.75)
		k.box(g, Vector3(p1.x + 0.05, 1.95, p1.z), Vector3(0.05, 0.3, 0.05), k.mat(Color("6B4A35"), 0.85))
		var prev: Vector3 = p0
		for i in range(13):
			var t: float = float(i) / 12.0
			var p: Vector3 = p0.lerp(p1, t) + Vector3(0, -sin(t * PI) * 0.35, 0)
			if i > 0:
				_wire(g, prev, p)
			if i % 2 == 1:
				k.ball(g, p + Vector3(0, -0.05, 0), 0.05, 0.08, bulb, 8, false)
			prev = p
	k.omni(g, Vector3(a.get_center().x, 2.6, a.get_center().y), Color("FFC98A"), 1.0, 5.0)
	# Street sign at the alley mouth.
	var post := Vector3(a.end.x - 0.15, 0, a.end.y - 0.1)
	k.cyl(g, post + Vector3(0, 1.2, 0), 0.04, 2.4, k.mat(COL_IRON, 0.5), -1.0, 8)
	k.box(g, post + Vector3(-0.55, 2.2, 0), Vector3(1.2, 0.3, 0.04), k.mat(Color("4F6E5A"), 0.7))
	k.label(g, "BACK ALLEY", post + Vector3(-0.55, 2.2, 0.03), 0.0, 36, Color("FFF6EA"), Color("4F6E5A"), 0.005, 0)
	points["alley_bowls"] = Vector3(a.position.x + 1.35, 0, a.get_center().y - 0.4)

func _build_garden_lot() -> void:
	var g := k.node(root, "GardenLot")
	var r: Rect2 = L.GARDEN_LOT
	_slab(g, r, 0.02, 0.03, k.tri_mat(k.tex_grass(COL_GRASS), 2.0, 0.95))
	# Picket fence along the front.
	var picket: Material = k.mat(Color("F3E6D3"), 0.8)
	var x: float = r.position.x + 0.15
	while x < r.end.x - 0.05:
		k.box(g, Vector3(x, 0.4, r.end.y - 0.2), Vector3(0.1, 0.8, 0.04), picket)
		x += 0.22
	k.box(g, Vector3(r.get_center().x, 0.55, r.end.y - 0.22), Vector3(r.size.x - 0.2, 0.06, 0.03), picket)
	k.box(g, Vector3(r.get_center().x, 0.25, r.end.y - 0.22), Vector3(r.size.x - 0.2, 0.06, 0.03), picket)
	# Raised beds with pumpkins, a big tree at the back.
	for i in range(2):
		var bc := Vector3(r.position.x + 1.2 + float(i) * 2.0, 0, r.end.y - 1.6)
		k.box(g, bc + Vector3(0, 0.15, 0), Vector3(1.5, 0.3, 0.9), k.tri_mat(k.tex_planks(Color("9C6B4A"), 6), 1.0, 0.85))
		k.box(g, bc + Vector3(0, 0.29, 0), Vector3(1.38, 0.04, 0.78), k.mat(Color("5A4034"), 0.95))
		_pumpkin(g, bc + Vector3(-0.35, 0.3, 0.05), 0.45)
		_pumpkin(g, bc + Vector3(0.35, 0.3, -0.1), 0.32)
	_tree(g, Vector3(r.get_center().x + 0.6, 0, r.position.y + 1.6), 1.25, 52)
	_tree(g, Vector3(r.position.x + 0.9, 0, r.position.y + 1.0), 0.9, 57)

# ------------------------------------------------------------------ park

func _build_park() -> void:
	var g := k.node(root, "Park")
	buildings["park"] = g
	var p: Rect2 = L.PARK
	_slab(g, p, -0.02, 0.08, k.tri_mat(k.tex_grass(COL_GRASS), 2.0, 0.95))
	# Path in from the south sidewalk, ending in a round paved nook with the bench.
	var path_mat: Material = k.tri_mat(k.tex_pavers(Color("D8C3A5"), Color("B09A80"), 3), 1.0, 0.9)
	_slab(g, L.PARK_PATH, 0.0, 0.05, path_mat)
	var nook: MeshInstance3D = k.cyl(g, Vector3(2.9, -0.025, 9.4), 1.6, 0.05, path_mat, -1.0, 28, false)
	nook.name = "Nook"
	k.cyl(g, Vector3(2.9, -0.03, 9.4), 1.72, 0.04, k.mat(COL_CURB, 0.85), -1.0, 28, false)
	# Hedges with an entrance gap at the path.
	_hedge(g, Vector3(p.position.x + 0.3, 0, p.position.y + 0.35), Vector3(L.PARK_PATH.position.x - 0.35, 0, p.position.y + 0.35), 1)
	_hedge(g, Vector3(L.PARK_PATH.end.x + 0.35, 0, p.position.y + 0.35), Vector3(p.end.x - 0.3, 0, p.position.y + 0.35), 2)
	_hedge(g, Vector3(p.position.x + 0.35, 0, p.position.y + 0.9), Vector3(p.position.x + 0.35, 0, p.end.y - 0.4), 3)
	# The big maple behind the bench + smaller trees.
	_tree(g, Vector3(1.0, 0, 8.0), 1.35, 11)
	_tree(g, Vector3(6.9, 0, 3.6), 0.9, 12)
	_tree(g, Vector3(0.0, 0, 4.0), 0.85, 13)
	_tree(g, Vector3(6.6, 0, 11.0), 0.8, 14)
	var bench: Node3D = f._bench(g, Vector3(1.55, 0, 9.4), 1.5, 90.0)
	points["park_bench"] = bench.global_position if bench.is_inside_tree() else Vector3(1.55, 0, 9.4)
	f._bench(g, Vector3(4.6, 0, 11.0), 1.3, 180.0)
	# Pond with lily pads and two ducks.
	var pond := Vector3(5.6, 0, 7.0)
	var rim: MeshInstance3D = k.cyl(g, pond + Vector3(0, 0.0, 0), 1.45, 0.08, k.mat(Color("A8917A"), 0.9), -1.0, 28)
	rim.scale = Vector3(1.2, 1.0, 0.85)
	var water: MeshInstance3D = k.cyl(g, pond + Vector3(0, 0.03, 0), 1.25, 0.04, k.mat(Color("6F9AA8"), 0.08), -1.0, 28, false)
	water.scale = Vector3(1.2, 1.0, 0.85)
	for lp in [Vector3(-0.6, 0.06, 0.2), Vector3(0.5, 0.06, -0.35), Vector3(0.2, 0.06, 0.45)]:
		k.cyl(g, pond + lp, 0.16, 0.01, k.mat(Color("7E9A5E"), 0.8), -1.0, 12, false)
	for dp in [Vector3(-0.2, 0.1, -0.2), Vector3(0.45, 0.1, 0.15)]:
		k.ball(g, pond + dp, 0.13, 0.16, k.mat(Color("FFF6EA"), 0.8), 10)
		k.ball(g, pond + dp + Vector3(0.1, 0.12, 0.0), 0.07, 0.12, k.mat(Color("FFF6EA"), 0.8), 10)
		k.box(g, pond + dp + Vector3(0.18, 0.12, 0.0), Vector3(0.07, 0.03, 0.04), k.mat(Color("E8B04B"), 0.6), false)
	# Flower bed + park sign at the entrance.
	for i in range(7):
		k.ball(g, Vector3(4.2 + float(i) * 0.3, 0.12, 2.95), 0.12, 0.2, k.mat(f.FLOWER_COLS[i % f.FLOWER_COLS.size()], 0.8), 8, false)
	var sg := k.node(g, "ParkSign", Vector3(1.6, 0, 2.6), 45.0)
	for sx in [-0.65, 0.65]:
		k.box(sg, Vector3(sx, 0.55, 0), Vector3(0.08, 1.1, 0.08), k.mat(Color("6B4A35"), 0.85))
	k.box(sg, Vector3(0, 1.05, 0), Vector3(1.55, 0.42, 0.06), k.mat(Color("4F6E5A"), 0.8))
	k.label(sg, "MAPLE PARK", Vector3(0, 1.05, 0.035), 0.0, 44, Color("FFF6EA"), Color("4F6E5A"), 0.005, 0)
	_lamppost(g, Vector3(4.0, 0, 9.0))
	points["park_ring"] = Vector3(2.6, 0, 9.4)

# ------------------------------------------------------------------ plaza (market + bus stop)

func _build_plaza() -> void:
	var g := k.node(root, "Plaza")
	var p: Rect2 = L.PLAZA
	_slab(g, p, 0.0, 0.1, k.tri_mat(k.tex_cobble(Color("C4AE96"), Color("9C866F")), 1.0, 0.92))
	_build_market(g, Vector3(11.6, 0, 7.6))
	_build_bus_stop(g, Vector3(11.8, 0, 2.7))
	_planter_box(g, Vector3(9.0, 0, 3.0), 71)
	_planter_box(g, Vector3(14.3, 0, 11.3), 72)
	_tree(g, Vector3(14.2, 0, 4.2), 0.95, 73)
	# Bike rack (half-buried hoops).
	for i in range(3):
		var hoop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.35
		hoop.mesh = tm
		hoop.material_override = k.mat(COL_IRON, 0.5)
		hoop.position = Vector3(9.2 + float(i) * 0.4, 0.05, 10.9)
		hoop.rotation_degrees = Vector3(90, 90, 0)
		g.add_child(hoop)
	# Bistro tables by the market.
	for tp in [Vector3(9.3, 0, 4.7), Vector3(14.0, 0, 7.8)]:
		_bistro_table(g, tp)

func _bistro_table(parent: Node3D, c: Vector3) -> void:
	var iron: Material = k.mat(COL_IRON, 0.5)
	k.cyl(parent, c + Vector3(0, 0.36, 0), 0.04, 0.72, iron, -1.0, 8)
	k.cyl(parent, c + Vector3(0, 0.02, 0), 0.22, 0.04, iron, -1.0, 12)
	k.cyl(parent, c + Vector3(0, 0.74, 0), 0.38, 0.04, k.mat(Color("FFF6EA"), 0.7), -1.0, 18)
	k.cyl(parent, c + Vector3(0.1, 0.8, 0.05), 0.05, 0.08, k.mat(Color("E07A5F"), 0.5), 0.045, 10)
	for a in [0.0, PI]:
		var sp: Vector3 = c + Vector3(cos(a) * 0.6, 0, sin(a) * 0.6)
		k.cyl(parent, sp + Vector3(0, 0.22, 0), 0.03, 0.44, iron, -1.0, 6)
		k.cyl(parent, sp + Vector3(0, 0.46, 0), 0.2, 0.05, k.mat(Color("C9643A"), 0.7), -1.0, 14)
	# Umbrella.
	k.cyl(parent, c + Vector3(0, 1.3, 0), 0.025, 1.2, iron, -1.0, 6)
	k.cyl(parent, c + Vector3(0, 1.95, 0), 0.95, 0.3, k.mat(Color("E07A5F"), 0.85), 0.05, 12)

func _build_market(parent: Node3D, c: Vector3) -> void:
	var g := k.node(parent, "MarketStall", c)
	buildings["market"] = g
	var wood: Material = k.tri_mat(k.tex_planks(Color("B07A4F"), 5), 1.0, 0.85)
	var w: float = 3.2
	var d: float = 1.3
	# Counter + back shelf + posts.
	k.box(g, Vector3(0, 0.5, 0.2), Vector3(w, 1.0, 0.7), wood)
	k.box(g, Vector3(0, 1.03, 0.25), Vector3(w + 0.1, 0.06, 0.85), k.mat(Color("8A5A3E"), 0.8))
	k.box(g, Vector3(0, 0.6, -0.55), Vector3(w, 1.2, 0.4), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-0.7, 0.6]:
			k.box(g, Vector3(sx * (w * 0.5 - 0.05), 1.2, sz), Vector3(0.09, 2.4, 0.09), k.mat(Color("8A5A3E"), 0.8))
	# Striped canopy (terracotta / cream) sloping toward the customer.
	f._awning(g, 0.0, 2.55, w + 0.3, d + 0.4, 0.35, Color("C9643A"), Color("FFF6EA"), 0.32)
	k.box(g, Vector3(0, 2.6, -0.7), Vector3(w + 0.3, 0.1, 0.12), k.mat(Color("8A5A3E"), 0.8))
	# Sign above the canopy.
	k.box(g, Vector3(0, 3.0, -0.65), Vector3(2.4, 0.5, 0.06), k.mat(Color("FFF6EA"), 0.8))
	k.box(g, Vector3(0, 3.0, -0.68), Vector3(2.52, 0.6, 0.04), k.mat(Color("C9643A"), 0.8))
	k.label(g, "CORNER MARKET", Vector3(0.12, 2.99, -0.615), 0.0, 52, Color("8A3E22"), Color("FFF6EA"), 0.005, 0)
	var bi := k.node(g, "BreadIcon", Vector3(-0.98, 3.0, -0.6))
	f._icon(bi, "bread", Color("D9A55A"), 0.36)
	# Goods: loaves + baguettes, apple basket, jars.
	var crust: Material = k.mat(Color("C98A4B"), 0.7)
	for i in range(4):
		var lf: MeshInstance3D = k.ball(g, Vector3(-1.2 + float(i) * 0.3, 1.13, 0.35), 0.13, 0.18, crust, 12)
		lf.scale = Vector3(1.0, 1.0, 0.75)
	for i in range(3):
		var bg: MeshInstance3D = k.cyl(g, Vector3(-0.3 + float(i) * 0.14, 1.12, 0.25), 0.05, 0.7, k.mat(Color("D9A55A"), 0.7), -1.0, 8)
		bg.rotation_degrees = Vector3(90, 0, 70)
	k.cyl(g, Vector3(0.55, 1.15, 0.35), 0.28, 0.18, k.mat(Color("A7805A"), 0.9), 0.32, 14)
	var ar := RandomNumberGenerator.new()
	ar.seed = 5
	for i in range(7):
		var a: float = float(i) / 7.0 * TAU
		k.ball(g, Vector3(0.55 + cos(a) * 0.15, 1.27, 0.35 + sin(a) * 0.12), 0.08, 0.15, k.mat(Color("B5523B").lightened(ar.randf_range(-0.05, 0.1)), 0.5), 10)
	for i in range(3):
		k.cyl(g, Vector3(1.0 + float(i) * 0.17, 1.15, 0.45), 0.06, 0.18, k.mat([Color("E8B04B"), Color("C9643A"), Color("B5523B")][i], 0.3), -1.0, 10)
	# Back shelf goods.
	for i in range(6):
		k.ball(g, Vector3(-1.3 + float(i) * 0.5, 1.32, -0.55), 0.14, 0.2, crust, 10).scale = Vector3(1.2, 1, 0.8)
	# Pumpkin crates in front.
	_crate(g, Vector3(-1.1, 0, 1.05), Vector3(0.75, 0.35, 0.55), 6.0)
	_pumpkin(g, Vector3(-1.25, 0.35, 1.0), 0.32)
	_pumpkin(g, Vector3(-0.92, 0.35, 1.12), 0.26)
	_pumpkin(g, Vector3(1.25, 0, 1.15), 0.5)
	_pumpkin(g, Vector3(0.85, 0, 1.35), 0.3)
	# Chalk price board.
	var cb := k.node(g, "PriceBoard", Vector3(1.85, 0, 0.6), -20.0)
	k.box(cb, Vector3(0, 0.45, 0), Vector3(0.55, 0.7, 0.05), k.mat(Color("3E3A36"), 0.9)).rotation_degrees.x = -10.0
	var lab: Label3D = k.label(cb, "bread\napples\npumpkins", Vector3(0, 0.48, 0.035), 0.0, 24, Color("FFF6EA"), Color("3E3A36"), 0.004, 0)
	lab.rotation_degrees.x = -10.0
	# Fairy lights under the canopy edge.
	for i in range(12):
		var t: float = float(i) / 11.0
		k.ball(g, Vector3(lerpf(-w * 0.5, w * 0.5, t), 2.05 - sin(t * PI) * 0.12, 1.6), 0.04, 0.07, k.glow(Color("FFD27A"), 3.2), 8, false)
	k.omni(g, Vector3(0, 2.0, 0.8), Color("FFC98A"), 0.9, 4.5)
	points["market_ring"] = c + Vector3(0, 0, 2.0)

func _build_bus_stop(parent: Node3D, c: Vector3) -> void:
	var g := k.node(parent, "BusStop", c)
	var iron: Material = k.mat(Color("4F6E5A"), 0.5)
	for sx in [-1.3, 1.3]:
		k.box(g, Vector3(sx, 1.15, 0.2), Vector3(0.08, 2.3, 0.08), iron)
	k.box(g, Vector3(0, 2.35, -0.05), Vector3(2.9, 0.08, 1.0), iron)
	k.box(g, Vector3(0, 2.42, -0.05), Vector3(2.7, 0.06, 0.85), k.mat(Color("FFF6EA"), 0.8))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.88, 0.92, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	k.box(g, Vector3(0, 1.2, 0.25), Vector3(2.6, 1.8, 0.03), glass, false)
	# Ad poster with a cat on the side panel.
	k.box(g, Vector3(1.3, 1.25, -0.2), Vector3(0.04, 1.3, 0.8), k.glow(Color("FFE2B0"), 1.0))
	var ad := k.node(g, "Ad", Vector3(1.33, 1.3, -0.2), 90.0)
	f._icon(ad, "cat", Color("E07A5F"), 0.5)
	k.label(g, "ADOPT", Vector3(1.33, 0.85, -0.2), 90.0, 30, Color("8A3E22"), Color("FFE2B0"), 0.004, 0)
	var bench: Node3D = f._bench(g, Vector3(0, 0, -0.1), 1.8, 180.0)
	bench.name = "BusBench"
	# Bus sign at the curb.
	var post := Vector3(-1.9, 0, -2.2)
	k.cyl(g, post + Vector3(0, 1.2, 0), 0.04, 2.4, k.mat(COL_IRON, 0.5), -1.0, 8)
	var disc: MeshInstance3D = k.cyl(g, post + Vector3(0, 2.4, 0), 0.28, 0.04, k.mat(Color("E8B04B"), 0.6), -1.0, 20)
	disc.rotation_degrees = Vector3(90, 45, 0)
	k.label(g, "BUS", post + Vector3(0.016, 2.4, 0.016), 45.0, 34, Color("4A3426"), Color("E8B04B"), 0.004, 0)

# ------------------------------------------------------------------ street furniture

func _build_street_furniture() -> void:
	var g := k.node(root, "StreetFurniture")
	for x in [-8.6, -2.2, 3.6, 9.1, 14.2]:
		_lamppost(g, Vector3(x, 0, -4.4))
	for x in [-1.5, 5.6, 12.6]:
		_lamppost(g, Vector3(x, 0, 0.4))
	for z in [1.6, 9.4]:
		_lamppost(g, Vector3(-8.4, 0, z))
	_lamppost(g, Vector3(-2.4, 0, 6.0))
	# Planters against the facades.
	for p in [Vector3(-1.95, 0, -5.6), Vector3(5.2, 0, -5.6), Vector3(-9.6, 0, 3.1), Vector3(-9.6, 0, -5.2)]:
		_planter_box(g, p, int(p.x * 13.0 + p.z * 7.0))
	# Fire hydrant.
	var hy := Vector3(-3.6, 0, 1.6)
	k.cyl(g, hy + Vector3(0, 0.3, 0), 0.12, 0.6, k.mat(Color("C9643A"), 0.5), 0.1, 12)
	k.ball(g, hy + Vector3(0, 0.62, 0), 0.12, 0.16, k.mat(Color("C9643A"), 0.5), 10)
	k.cyl(g, hy + Vector3(0, 0.35, 0), 0.05, 0.36, k.mat(Color("B5523B"), 0.5), -1.0, 8).rotation_degrees.z = 90.0
	# Street name signs at the corner.
	var corner := Vector3(-8.45, 0, -4.45)
	k.cyl(g, corner + Vector3(0, 1.4, 0) + Vector3(0.0, 0, 0.9), 0.04, 2.8, k.mat(COL_IRON, 0.5), -1.0, 8)
	var s1 := corner + Vector3(0, 2.6, 0.9)
	k.box(g, s1, Vector3(1.3, 0.24, 0.04), k.mat(Color("4F6E5A"), 0.7))
	k.label(g, "MAPLE ST", s1 + Vector3(0, 0, 0.025), 0.0, 32, Color("FFF6EA"), Color("4F6E5A"), 0.005, 0)
	k.box(g, s1 + Vector3(0, 0.3, 0), Vector3(0.04, 0.24, 1.3), k.mat(Color("4F6E5A"), 0.7))
	k.label(g, "BEAN AVE", s1 + Vector3(0.025, 0.3, 0), 90.0, 32, Color("FFF6EA"), Color("4F6E5A"), 0.005, 0)
	# Trash bin + newspaper box near the shelter.
	k.cyl(g, Vector3(6.4, 0.4, -4.55), 0.22, 0.8, k.mat(Color("4F6E5A"), 0.5), 0.24, 12)
	k.cyl(g, Vector3(6.4, 0.82, -4.55), 0.25, 0.05, k.mat(Color("3E5A48"), 0.5), -1.0, 12)
	k.box(g, Vector3(-0.6, 0.5, -5.55), Vector3(0.45, 1.0, 0.4), k.mat(Color("E8B04B"), 0.6))
	k.box(g, Vector3(-0.6, 0.75, -5.34), Vector3(0.35, 0.3, 0.02), k.mat(Color("FFF6EA"), 0.6), false)

## Fallen leaves on sidewalks, lots and the park (one MultiMesh, per-instance colour).
func _build_leaves() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := BoxMesh.new()
	quad.size = Vector3(0.16, 0.008, 0.11)
	mm.mesh = quad
	var r := RandomNumberGenerator.new()
	r.seed = 2024
	var spots: Array = []
	var areas: Array = [[L.WALK_NORTH, 70], [L.WALK_WEST, 40], [L.WALK_SOUTH, 50], [L.WALK_EAST, 25], [L.PARK, 140], [L.PLAZA, 40], [L.ALLEY, 30], [L.GARDEN_LOT, 30]]
	for a in areas:
		var rect: Rect2 = a[0]
		for i in range(int(a[1])):
			var p := Vector3(r.randf_range(rect.position.x, rect.end.x), 0.0, r.randf_range(rect.position.y, rect.end.y))
			if rect == L.PARK:
				p.y = -0.01
			spots.append(p)
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		var basis := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, r.randf_range(-0.2, 0.2))
		var s: float = r.randf_range(0.7, 1.3)
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, 1.0, s)), spots[i] + Vector3(0, 0.012, 0)))
		mm.set_instance_color(i, AUTUMN[r.randi_range(0, AUTUMN.size() - 1)].lightened(r.randf_range(-0.05, 0.1)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Leaves"
	mmi.multimesh = mm
	mmi.material_override = k.vertex_color_mat(0.9)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
