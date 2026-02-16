extends Node3D
class_name FloorBuilder3D

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
				wall.position = (a + b) * 0.5 + Vector3(0.0, 0.33, 0.0)
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

	var bounds: Dictionary = level.get_floor_world_bounds()
	var min_x: float = float(bounds.get("min_x", 0.0))
	var max_x: float = float(bounds.get("max_x", 0.0))
	var min_z: float = float(bounds.get("min_z", 0.0))
	var max_z: float = float(bounds.get("max_z", 0.0))
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
	var bounds: Dictionary = level.get_floor_world_bounds()
	var min_x: float = float(bounds.get("min_x", 0.0))
	var max_x: float = float(bounds.get("max_x", 0.0))
	var min_z: float = float(bounds.get("min_z", 0.0))
	var max_z: float = float(bounds.get("max_z", 0.0))
	var wall_height: float = maxf(1.3, level.rest_tile_height_3d * 5.0)
	var wall_thickness: float = maxf(0.12, minf(level.cell_width_3d, level.cell_depth_3d) * 0.22)
	var wall_center_y: float = wall_height * 0.5 - maxf(level.floor_tile_height_3d, level.rest_tile_height_3d) * 0.15

	for gx in range(level.cafe_floor_rect.position.x, level.cafe_floor_rect.end.x):
		var cell_center: Vector3 = level.map_to_world(Vector2i(gx, level.cafe_floor_rect.position.y))
		var north_center := Vector3(cell_center.x, wall_center_y, min_z - wall_thickness * 0.5)
		_add_wall_segment_box(north_center, Vector3(level.cell_width_3d, wall_height, wall_thickness))

	for gy in range(level.cafe_floor_rect.position.y, level.cafe_floor_rect.end.y):
		var cell_center: Vector3 = level.map_to_world(Vector2i(level.cafe_floor_rect.position.x, gy))
		var west_center := Vector3(min_x - wall_thickness * 0.5, wall_center_y, cell_center.z)
		_add_wall_segment_box(west_center, Vector3(wall_thickness, wall_height, level.cell_depth_3d))

	var corner_center := Vector3(min_x - wall_thickness * 0.5, wall_center_y, min_z - wall_thickness * 0.5)
	_add_wall_segment_box(corner_center, Vector3(wall_thickness, wall_height, wall_thickness))

func _add_wall_segment_box(center: Vector3, size: Vector3) -> void:
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = size
	wall.mesh = wall_mesh
	wall.material_override = _wall_material
	wall.position = center
	add_child(wall)
