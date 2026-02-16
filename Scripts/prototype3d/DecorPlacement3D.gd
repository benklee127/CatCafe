extends Node3D
class_name DecorPlacement3D

@export var selected_decor_id: String = "velvet_armchair"
@export var preview_valid_color: Color = Color(0.25, 0.95, 0.35, 0.55)
@export var preview_invalid_color: Color = Color(0.95, 0.25, 0.25, 0.55)

var level
var rotation_deg: int = 0
var hovered_grid: Vector2i = Vector2i.ZERO
var has_hover: bool = false
var available_decor_ids: Array[String] = []
var holding_decor_id: String = ""

var _preview_root: Node3D
var _preview_cells_root: Node3D
var _preview_mat: StandardMaterial3D
var _held_preview_root: Node3D
var _held_preview_active_id: String = ""

var _inspector_layer: CanvasLayer
var _inspector_panel: PanelContainer
var _inspector_viewport: SubViewport
var _inspector_preview_root: Node3D
var _inspector_name_label: Label
var _inspector_color_label: Label
var _inspector_durability_label: Label
var _inspector_selected_label: Label
var _inspector_remove_button: Button
var _menu_bar: HBoxContainer
var _build_button: Button
var _build_panel: PanelContainer
var _build_list: VBoxContainer
var _build_scroll: ScrollContainer
var _inspected_cell: Vector2i = Vector2i(-9999, -9999)

func _ready() -> void:
	level = get_parent()
	_create_preview()
	_create_inspector_ui()
	_create_menu_ui()
	call_deferred("_post_level_ready_init")

func _post_level_ready_init() -> void:
	available_decor_ids = level.get_available_decor_ids()
	if available_decor_ids.is_empty():
		available_decor_ids = [selected_decor_id]
	if not available_decor_ids.has(selected_decor_id):
		selected_decor_id = available_decor_ids[0]
	_rebuild_build_list()
	_update_selected_label()

func _process(_delta: float) -> void:
	_update_hover_from_screen_pos(level.get_viewport().get_mouse_position())
	_update_preview()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	_update_hover_from_screen_pos(event.position)
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			rotation_deg = (rotation_deg + 90) % 360
		MOUSE_BUTTON_WHEEL_DOWN:
			rotation_deg = (rotation_deg + 270) % 360
		MOUSE_BUTTON_LEFT:
			if has_hover and not holding_decor_id.is_empty():
				var reason: String = level.get_place_block_reason(hovered_grid, holding_decor_id, rotation_deg)
				var can_place: bool = reason.is_empty()
				var placed: bool = false
				if can_place:
					placed = level.place_decor(hovered_grid, holding_decor_id, rotation_deg)
				else:
					push_warning("Cannot place decor '%s' at %s (rotation=%d) reason=%s" % [holding_decor_id, str(hovered_grid), rotation_deg, reason])
				if placed:
					holding_decor_id = ""
					_refresh_held_preview()
					_update_selected_label()
		MOUSE_BUTTON_RIGHT:
			if has_hover:
				_open_inspector_for_cell(hovered_grid)

func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_hide_inspector()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var idx: int = int(event.keycode - KEY_1)
		if idx >= 0 and idx < available_decor_ids.size():
			holding_decor_id = available_decor_ids[idx]
			_refresh_held_preview()
			_update_selected_label()

func _create_menu_ui() -> void:
	_menu_bar = HBoxContainer.new()
	_menu_bar.name = "TopLeftMenuBar"
	_menu_bar.anchor_left = 0.0
	_menu_bar.anchor_top = 0.0
	_menu_bar.anchor_right = 0.0
	_menu_bar.anchor_bottom = 0.0
	_menu_bar.offset_left = 18.0
	_menu_bar.offset_top = 18.0
	_menu_bar.offset_right = 18.0 + 220.0
	_menu_bar.offset_bottom = 18.0 + 46.0
	_inspector_layer.add_child(_menu_bar)

	_build_button = Button.new()
	_build_button.text = "Build"
	_build_button.custom_minimum_size = Vector2(120, 34)
	_build_button.pressed.connect(_on_build_button_pressed)
	_menu_bar.add_child(_build_button)

	_build_panel = PanelContainer.new()
	_build_panel.name = "BuildPanel"
	_build_panel.anchor_left = 0.0
	_build_panel.anchor_top = 0.0
	_build_panel.anchor_right = 0.0
	_build_panel.anchor_bottom = 0.0
	_build_panel.offset_left = 18.0
	_build_panel.offset_top = 62.0
	_build_panel.offset_right = 18.0 + 300.0
	_build_panel.offset_bottom = 62.0 + 360.0
	_build_panel.visible = false
	_inspector_layer.add_child(_build_panel)

	var build_col := VBoxContainer.new()
	build_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_col.add_theme_constant_override("separation", 8)
	_build_panel.add_child(build_col)

	var title := Label.new()
	title.text = "Build Menu"
	build_col.add_child(title)

	var hint := Label.new()
	hint.text = "Select one item to hold. Next left click places it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_col.add_child(hint)

	_build_scroll = ScrollContainer.new()
	_build_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_col.add_child(_build_scroll)

	_build_list = VBoxContainer.new()
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_scroll.add_child(_build_list)

func _rebuild_build_list() -> void:
	if _build_list == null:
		return
	for child in _build_list.get_children():
		child.queue_free()
	for decor_id in available_decor_ids:
		var btn := Button.new()
		btn.text = decor_id
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_build_item_pressed.bind(decor_id))
		_build_list.add_child(btn)

func _on_build_button_pressed() -> void:
	if _build_panel == null:
		return
	available_decor_ids = level.get_available_decor_ids()
	if available_decor_ids.is_empty():
		available_decor_ids = [selected_decor_id]
	_rebuild_build_list()
	_build_panel.visible = not _build_panel.visible

func _on_build_item_pressed(decor_id: String) -> void:
	holding_decor_id = decor_id
	selected_decor_id = decor_id
	_refresh_held_preview()
	_update_selected_label()
	_build_panel.visible = false

func _create_preview() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "PlacementPreview"
	add_child(_preview_root)

	_preview_cells_root = Node3D.new()
	_preview_cells_root.name = "BlockingCellsPreview"
	_preview_root.add_child(_preview_cells_root)

	_preview_mat = StandardMaterial3D.new()
	_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mat.albedo_color = preview_valid_color

	_held_preview_root = Node3D.new()
	_held_preview_root.name = "HeldDecorPreview"
	_preview_root.add_child(_held_preview_root)

func _create_inspector_ui() -> void:
	_inspector_layer = CanvasLayer.new()
	_inspector_layer.layer = 10
	add_child(_inspector_layer)

	var panel := PanelContainer.new()
	panel.name = "DecorInspectorPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 18.0
	panel.offset_top = 18.0
	panel.offset_right = 18.0 + 560.0
	panel.offset_bottom = 18.0 + 280.0
	panel.visible = false
	_inspector_layer.add_child(panel)
	_inspector_panel = panel

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(row)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(250, 250)
	row.add_child(left_col)

	_inspector_viewport = SubViewport.new()
	_inspector_viewport.disable_3d = false
	_inspector_viewport.own_world_3d = true
	_inspector_viewport.transparent_bg = false
	_inspector_viewport.size = Vector2i(250, 250)
	_inspector_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(250, 250)
	viewport_container.stretch = true
	viewport_container.add_child(_inspector_viewport)
	left_col.add_child(viewport_container)

	var world := Node3D.new()
	_inspector_viewport.add_child(world)
	_inspector_preview_root = Node3D.new()
	world.add_child(_inspector_preview_root)

	var cam := Camera3D.new()
	cam.position = Vector3(2.4, 2.2, 2.4)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.7, 0.0), Vector3.UP)
	cam.current = true
	world.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy = 1.35
	world.add_child(light)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 10)
	row.add_child(right_col)

	var title := Label.new()
	title.text = "Decor Details"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right_col.add_child(title)

	_inspector_name_label = Label.new()
	right_col.add_child(_inspector_name_label)

	_inspector_color_label = Label.new()
	right_col.add_child(_inspector_color_label)

	_inspector_durability_label = Label.new()
	right_col.add_child(_inspector_durability_label)

	_inspector_selected_label = Label.new()
	right_col.add_child(_inspector_selected_label)

	_inspector_remove_button = Button.new()
	_inspector_remove_button.text = "Remove Decor"
	_inspector_remove_button.custom_minimum_size = Vector2(180, 34)
	_inspector_remove_button.pressed.connect(_on_remove_inspected_pressed)
	right_col.add_child(_inspector_remove_button)

	var hint := Label.new()
	hint.text = "Scroll: rotate  Left Click: place held item  Right Click: inspect  1-9: quick-hold decor"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(hint)

func _open_inspector_for_cell(cell: Vector2i) -> void:
	var info: Dictionary = level.get_decor_inspection_data(cell)
	if info.is_empty():
		_hide_inspector()
		return
	_inspected_cell = cell
	_inspector_name_label.text = "Name: %s" % String(info.get("name", "Unknown"))
	_inspector_color_label.text = "Color: %s" % String(info.get("color", "Unknown"))
	_inspector_durability_label.text = "Durability: %d" % int(info.get("durability", 0))
	_update_selected_label()
	_render_preview_mesh_scene(String(info.get("mesh_scene", "")))
	_inspector_panel.visible = true

func _hide_inspector() -> void:
	if _inspector_panel != null:
		_inspector_panel.visible = false
	_inspected_cell = Vector2i(-9999, -9999)

func _on_remove_inspected_pressed() -> void:
	if _inspected_cell.x <= -9999:
		return
	var removed: bool = level.remove_decor(_inspected_cell)
	if removed:
		_hide_inspector()

func _render_preview_mesh_scene(scene_path: String) -> void:
	for child in _inspector_preview_root.get_children():
		child.queue_free()
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		(inst as Node3D).position = Vector3.ZERO
		_inspector_preview_root.add_child(inst)

func _update_selected_label() -> void:
	if _inspector_selected_label == null:
		return
	if holding_decor_id.is_empty():
		_inspector_selected_label.text = "Holding: none"
		return
	var idx: int = available_decor_ids.find(holding_decor_id)
	var display_index: int = idx + 1 if idx >= 0 else 0
	_inspector_selected_label.text = "Holding: [%d] %s" % [display_index, holding_decor_id]

func _update_hover() -> void:
	_update_hover_from_screen_pos(level.get_viewport().get_mouse_position())

func _update_hover_from_screen_pos(screen_pos: Vector2) -> void:
	var cam: Camera3D = level.get_active_camera()
	if cam == null:
		has_hover = false
		return
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = plane.intersects_ray(origin, origin + dir * 500.0)
	if hit == null:
		has_hover = false
		return
	var bounds: Dictionary = level.get_floor_world_bounds()
	var min_x: float = float(bounds.get("min_x", 0.0))
	var max_x: float = float(bounds.get("max_x", 0.0))
	var min_z: float = float(bounds.get("min_z", 0.0))
	var max_z: float = float(bounds.get("max_z", 0.0))
	if hit.x < min_x or hit.x > max_x or hit.z < min_z or hit.z > max_z:
		has_hover = false
		return
	hovered_grid = level.world_to_map(hit)
	has_hover = level.is_in_cafe_floor(hovered_grid)

func _update_preview() -> void:
	if not has_hover:
		_preview_root.visible = false
		return
	if holding_decor_id.is_empty():
		_preview_root.visible = false
		return
	_preview_root.visible = true
	_preview_root.position = level.map_to_world(hovered_grid) + Vector3(0.0, 0.001, 0.0)
	_preview_root.rotation_degrees = Vector3.ZERO
	var ok: bool = level.can_place_decor(hovered_grid, holding_decor_id, rotation_deg)
	_preview_mat.albedo_color = preview_valid_color if ok else preview_invalid_color
	_rebuild_preview_cells()
	_refresh_held_preview()
	_held_preview_root.rotation_degrees = Vector3(0.0, float(rotation_deg), 0.0)
	var world_pos: Vector3 = level.get_decor_world_position(hovered_grid, holding_decor_id, rotation_deg)
	_held_preview_root.position = world_pos - _preview_root.position

func _rebuild_preview_cells() -> void:
	if _preview_cells_root == null:
		return
	for child in _preview_cells_root.get_children():
		child.queue_free()
	var cells: Array[Vector2i] = level.get_decor_blocking_cells(hovered_grid, holding_decor_id, rotation_deg)
	var gap_ratio: float = clampf(float(level.floor_tile_gap_ratio), 0.0, 0.2)
	var size_scale: float = 1.0 - gap_ratio
	for cell in cells:
		var cell_mesh := MeshInstance3D.new()
		var cell_plane := PlaneMesh.new()
		cell_plane.size = Vector2(level.cell_width_3d * size_scale, level.cell_depth_3d * size_scale)
		cell_mesh.mesh = cell_plane
		cell_mesh.rotation_degrees.x = -90.0
		cell_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cell_mesh.material_override = _preview_mat
		cell_mesh.position = level.map_to_world(cell) - _preview_root.position + Vector3(0.0, 0.002, 0.0)
		_preview_cells_root.add_child(cell_mesh)

func _refresh_held_preview() -> void:
	if _held_preview_root == null:
		return
	if _held_preview_active_id == holding_decor_id:
		return
	for child in _held_preview_root.get_children():
		child.queue_free()
	_held_preview_active_id = holding_decor_id
	if holding_decor_id.is_empty():
		return
	var mesh_entry: Dictionary = level.decor_mesh_by_id.get(holding_decor_id, {})
	var scene_path: String = String(mesh_entry.get("mesh_scene", ""))
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		_apply_ghost_material(inst)
		_held_preview_root.add_child(inst)

func _apply_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.92, 0.96, 1.0, 0.52)
		mesh_node.material_override = mat
	for child in node.get_children():
		_apply_ghost_material(child)
