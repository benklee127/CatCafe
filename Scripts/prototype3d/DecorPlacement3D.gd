extends Node3D
class_name DecorPlacement3D

@export var selected_decor_id: String = "velvet_armchair"
@export var preview_valid_color: Color = Color(0.25, 0.95, 0.35, 0.55)
@export var preview_invalid_color: Color = Color(0.95, 0.25, 0.25, 0.55)

var level
var rotation_deg: int = 0
var hovered_grid: Vector2i = Vector2i.ZERO
var has_hover: bool = false

var _preview_root: Node3D
var _preview_mesh: MeshInstance3D
var _preview_mat: StandardMaterial3D

func _ready() -> void:
	level = get_parent()
	_create_preview()

func _process(_delta: float) -> void:
	_update_hover()
	_update_preview()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
			rotation_deg = (rotation_deg + 90) % 360
	if event.is_action_pressed("place_decor") and has_hover:
		level.place_decor(hovered_grid, selected_decor_id, rotation_deg)
	if event.is_action_pressed("remove_decor") and has_hover:
		level.remove_decor(hovered_grid)

func _create_preview() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "PlacementPreview"
	add_child(_preview_root)

	_preview_mesh = MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	var gap_ratio: float = clampf(float(level.floor_tile_gap_ratio), 0.0, 0.2)
	var size_scale: float = 1.0 - gap_ratio
	mesh.size = Vector2(level.cell_width_3d * size_scale, level.cell_depth_3d * size_scale)
	_preview_mesh.mesh = mesh
	_preview_mesh.rotation_degrees.x = -90.0
	_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_root.add_child(_preview_mesh)

	_preview_mat = StandardMaterial3D.new()
	_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mat.albedo_color = preview_valid_color
	_preview_mesh.material_override = _preview_mat

func _update_hover() -> void:
	var cam: Camera3D = level.get_active_camera()
	if cam == null:
		has_hover = false
		return
	var mouse: Vector2 = level.get_viewport().get_mouse_position()
	var origin: Vector3 = cam.project_ray_origin(mouse)
	var dir: Vector3 = cam.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = plane.intersects_ray(origin, origin + dir * 500.0)
	if hit == null:
		has_hover = false
		return
	hovered_grid = level.world_to_map(hit)
	has_hover = level.is_in_cafe_floor(hovered_grid)

func _update_preview() -> void:
	if not has_hover:
		_preview_root.visible = false
		return
	_preview_root.visible = true
	_preview_root.position = level.map_to_world(hovered_grid) + Vector3(0.0, 0.001, 0.0)
	_preview_root.rotation_degrees = Vector3(0.0, float(rotation_deg), 0.0)
	var ok: bool = level.can_place_decor(hovered_grid, selected_decor_id, rotation_deg)
	_preview_mat.albedo_color = preview_valid_color if ok else preview_invalid_color
