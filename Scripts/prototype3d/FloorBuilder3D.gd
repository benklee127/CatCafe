extends Node3D
class_name FloorBuilder3D

const KAYKIT_WALL_SCENE: String = "res://Art_Assets/3d/kaykit/core_subset/Primitive_Wall.gltf"
const WALL_BASE_LENGTH: float = 4.0
const WALL_BASE_THICKNESS: float = 1.0
const WALL_BASE_HEIGHT: float = 4.0

var _floor_material: StandardMaterial3D
var _rest_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _grid_line_material: StandardMaterial3D

func rebuild(level) -> void:
	for child in get_children():
		child.queue_free()
	_ensure_materials()

	for y in range(level.cafe_floor_rect.position.y, level.cafe_floor_rect.end.y):
		for x in range(level.cafe_floor_rect.position.x, level.cafe_floor_rect.end.x):
			var cell: Vector2i = Vector2i(x, y)
			var is_rest: bool = level.is_in_rest_area(cell)
			var height: float = level.rest_tile_height_3d if is_rest else level.floor_tile_height_3d
			var box := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			var gap_ratio: float = clampf(float(level.floor_tile_gap_ratio), 0.0, 0.2)
			var size_scale: float = 1.0 - gap_ratio
			mesh.size = Vector3(level.cell_width_3d * size_scale, height, level.cell_depth_3d * size_scale)
			box.mesh = mesh
			box.material_override = _rest_material if is_rest else _floor_material
			var top_center: Vector3 = level.map_to_world(cell)
			box.position = top_center + Vector3(0.0, -height * 0.5, 0.0)
			add_child(box)

	_build_grid_lines(level)
	_build_rest_partition(level)
	_build_back_walls(level)

func _build_rest_partition(level) -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(level.rest_area_rect.position.y, level.rest_area_rect.end.y):
		for x in range(level.rest_area_rect.position.x, level.rest_area_rect.end.x):
			var rest_cell: Vector2i = Vector2i(x, y)
			for d in dirs:
				var n: Vector2i = rest_cell + d
				if not level.is_in_cafe_floor(n) or level.is_in_rest_area(n):
					continue
				var wall := MeshInstance3D.new()
				var wall_mesh := BoxMesh.new()
				wall_mesh.size = Vector3(level.cell_width_3d * 0.08, 0.65, level.cell_depth_3d * 0.92)
				if d.y != 0:
					wall_mesh.size = Vector3(level.cell_width_3d * 0.92, 0.65, level.cell_depth_3d * 0.08)
				wall.mesh = wall_mesh
				wall.material_override = _wall_material
				var a: Vector3 = level.map_to_world(rest_cell)
				var b: Vector3 = level.map_to_world(n)
				wall.position = (a + b) * 0.5 + Vector3(0.02, 0.33, 0.02)
				add_child(wall)

func _ensure_materials() -> void:
	if _floor_material == null:
		_floor_material = StandardMaterial3D.new()
		_floor_material.albedo_color = Color(0.86, 0.78, 0.63)
	if _rest_material == null:
		_rest_material = StandardMaterial3D.new()
		_rest_material.albedo_color = Color(0.93, 0.73, 0.42)
	if _wall_material == null:
		_wall_material = StandardMaterial3D.new()
		_wall_material.albedo_color = Color(0.40, 0.30, 0.21)
	if _grid_line_material == null:
		_grid_line_material = StandardMaterial3D.new()
		_grid_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_grid_line_material.albedo_color = Color(0.72, 0.66, 0.55, 1.0)

func _build_grid_lines(level) -> void:
	if not bool(level.show_grid_lines):
		return
	_grid_line_material.albedo_color = level.grid_line_color
	var line_width: float = maxf(0.01, minf(level.cell_width_3d, level.cell_depth_3d) * float(level.grid_line_width_ratio))
	var y_offset: float = float(level.grid_line_height_offset)

	var min_cell: Vector2i = level.cafe_floor_rect.position
	var max_cell: Vector2i = level.cafe_floor_rect.end - Vector2i.ONE
	var a: Vector3 = level.map_to_world(min_cell)
	var b: Vector3 = level.map_to_world(max_cell)
	var min_x: float = minf(a.x, b.x) - level.cell_width_3d * 0.5
	var max_x: float = maxf(a.x, b.x) + level.cell_width_3d * 0.5
	var min_z: float = minf(a.z, b.z) - level.cell_depth_3d * 0.5
	var max_z: float = maxf(a.z, b.z) + level.cell_depth_3d * 0.5
	var width: float = max_x - min_x
	var depth: float = max_z - min_z

	for gx in range(level.cafe_floor_rect.size.x + 1):
		var x: float = min_x + float(gx) * level.cell_width_3d
		_add_grid_line(Vector3(x, y_offset, (min_z + max_z) * 0.5), Vector3(line_width, 0.02, depth + line_width))
	for gy in range(level.cafe_floor_rect.size.y + 1):
		var z: float = min_z + float(gy) * level.cell_depth_3d
		_add_grid_line(Vector3((min_x + max_x) * 0.5, y_offset, z), Vector3(width + line_width, 0.02, line_width))

func _add_grid_line(center: Vector3, size: Vector3) -> void:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	line.mesh = mesh
	line.material_override = _grid_line_material
	line.position = center
	add_child(line)

func _build_back_walls(level) -> void:
	var wall_scene: PackedScene = load(KAYKIT_WALL_SCENE)
	if wall_scene == null:
		return

	var min_cell: Vector2i = level.cafe_floor_rect.position
	var max_cell: Vector2i = level.cafe_floor_rect.end - Vector2i.ONE
	var a: Vector3 = level.map_to_world(min_cell)
	var b: Vector3 = level.map_to_world(max_cell)

	var min_x: float = minf(a.x, b.x) - level.cell_width_3d * 0.5
	var max_x: float = maxf(a.x, b.x) + level.cell_width_3d * 0.5
	var min_z: float = minf(a.z, b.z) - level.cell_depth_3d * 0.5
	var max_z: float = maxf(a.z, b.z) + level.cell_depth_3d * 0.5

	var span_x: float = max_x - min_x
	var span_z: float = max_z - min_z
	var wall_height: float = maxf(1.3, level.rest_tile_height_3d * 3.0)
	var wall_thickness: float = maxf(0.25, minf(level.cell_width_3d, level.cell_depth_3d) * 0.38)
	var drop_down: float = maxf(level.floor_tile_height_3d, level.rest_tile_height_3d) * 0.55

	var north_center := Vector3((min_x + max_x) * 0.5, -drop_down, min_z - wall_thickness * 0.5)
	_spawn_kaykit_wall(wall_scene, north_center, span_x, wall_thickness, wall_height, false)

	var west_center := Vector3(min_x - wall_thickness * 0.5, -drop_down, (min_z + max_z) * 0.5)
	_spawn_kaykit_wall(wall_scene, west_center, span_z, wall_thickness, wall_height, true)
	_build_back_corner_cap(wall_scene, Vector3(min_x - wall_thickness * 0.5, -drop_down, min_z - wall_thickness * 0.5), wall_thickness, wall_height)

func _spawn_kaykit_wall(scene: PackedScene, center: Vector3, length: float, thickness: float, height: float, rotate_90: bool) -> void:
	var wall: Node3D = scene.instantiate()
	wall.position = center
	if rotate_90:
		wall.rotation_degrees.y = 90.0
	wall.scale = Vector3(
		length / WALL_BASE_LENGTH,
		height / WALL_BASE_HEIGHT,
		thickness / WALL_BASE_THICKNESS
	)
	add_child(wall)

func _build_back_corner_cap(scene: PackedScene, corner_center: Vector3, thickness: float, height: float) -> void:
	var cap: Node3D = scene.instantiate()
	cap.position = corner_center
	cap.scale = Vector3(
		thickness / WALL_BASE_LENGTH,
		height / WALL_BASE_HEIGHT,
		thickness / WALL_BASE_THICKNESS
	)
	add_child(cap)
