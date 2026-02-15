extends RefCounted
class_name GridIso3D

static func map_to_world(grid_pos: Vector2i, origin: Vector3, cell_width: float, cell_depth: float) -> Vector3:
	return origin + Vector3(float(grid_pos.x) * cell_width, 0.0, float(grid_pos.y) * cell_depth)

static func world_to_map(world_pos: Vector3, origin: Vector3, cell_width: float, cell_depth: float) -> Vector2i:
	var local: Vector3 = world_pos - origin
	var gx: int = int(floor(local.x / maxf(cell_width, 0.001) + 0.5))
	var gz: int = int(floor(local.z / maxf(cell_depth, 0.001) + 0.5))
	return Vector2i(gx, gz)
