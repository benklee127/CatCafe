extends Node3D
class_name DecorPlacement3D

## World-side interaction for the main level: holding / rotating / placing decor (with a
## tinted ghost, footprint tiles, slot markers and a cursor reason label), plus world clicks
## (cat pick, decor inspect) forwarded as signals. All panels live in the HUD (UI/HUD3D.tscn).

signal hold_changed(decor_id: String)
signal decor_placed(decor_id: String, anchor: Vector2i)
signal cat_clicked(cat)
signal decor_clicked(cell: Vector2i, info: Dictionary)
signal empty_clicked()

const THEME_PATH: String = "res://UI/cozy_theme.tres"
const CAT_PICK_RADIUS_PX: float = 40.0
const TILE_Y: float = 0.03
const REASON_REFRESH_SEC: float = 0.1

@export var selected_decor_id: String = "velvet_armchair"
@export var preview_valid_color: Color = Color(0.45, 0.85, 0.5, 0.5)
@export var preview_invalid_color: Color = Color(0.95, 0.35, 0.3, 0.55)
@export var ghost_valid_color: Color = Color(0.9, 1.0, 0.92, 0.6)
@export var ghost_invalid_color: Color = Color(1.0, 0.55, 0.5, 0.6)

var level
var rotation_deg: int = 0
var hovered_grid: Vector2i = Vector2i.ZERO
var has_hover: bool = false
var available_decor_ids: Array[String] = []
var holding_decor_id: String = ""
var last_block_reason: String = ""
## Tools/probes only: when x >= 0 this replaces the mouse position for hover/preview.
var pointer_override: Vector2 = Vector2(-1, -1)

var _preview_root: Node3D
var _preview_cells_root: Node3D
var _preview_slots_root: Node3D
var _tile_mat_valid: StandardMaterial3D
var _tile_mat_invalid: StandardMaterial3D
var _ghost_mat_valid: StandardMaterial3D
var _ghost_mat_invalid: StandardMaterial3D
var _slot_mat_patron: StandardMaterial3D
var _slot_mat_cat: StandardMaterial3D
var _held_preview_root: Node3D
var _held_preview_active_id: String = ""
var _preview_key: String = ""
var _preview_valid: bool = true
var _ghost_valid_applied: int = -1
var _reason_timer: float = 0.0

var _cursor_layer: CanvasLayer
var _cursor_panel: PanelContainer
var _cursor_label: Label
var _cursor_style_ok: StyleBoxFlat
var _cursor_style_bad: StyleBoxFlat

func _ready() -> void:
	level = get_parent()
	_create_preview()
	_create_cursor_ui()
	call_deferred("_post_level_ready_init")

func _post_level_ready_init() -> void:
	if level != null and level.has_method("get_available_decor_ids"):
		available_decor_ids = level.get_available_decor_ids()
	if available_decor_ids.is_empty():
		available_decor_ids = [selected_decor_id]
	if not available_decor_ids.has(selected_decor_id):
		selected_decor_id = available_decor_ids[0]

func _process(delta: float) -> void:
	if level == null:
		return
	_update_hover_from_screen_pos(_pointer_pos())
	_update_preview(delta)

# ---------------------------------------------------------------- public API

func is_holding() -> bool:
	return not holding_decor_id.is_empty()

func get_holding_id() -> String:
	return holding_decor_id

func begin_hold(decor_id: String) -> void:
	if decor_id.is_empty():
		cancel_hold()
		return
	holding_decor_id = decor_id
	selected_decor_id = decor_id
	_preview_key = ""
	_refresh_held_preview()
	hold_changed.emit(holding_decor_id)

func cancel_hold() -> void:
	if holding_decor_id.is_empty():
		return
	holding_decor_id = ""
	_preview_key = ""
	_refresh_held_preview()
	_set_cursor_text("")
	hold_changed.emit("")

func rotate_held(step: int) -> void:
	rotation_deg = posmod(rotation_deg + 90 * step, 360)
	_preview_key = ""

## Human-readable text for a level block reason ("occupied_by_decor:(3, 4)" etc.).
func describe_block_reason(reason: String, decor_id: String = "") -> String:
	var key: String = reason.get_slice(":", 0)
	match key:
		"":
			return ""
		"insufficient_funds":
			var cost: int = int(level.get_decor_cost(decor_id)) if level != null and level.has_method("get_decor_cost") else 0
			var money_v = level.get("money") if level != null else null
			var short: int = cost - int(money_v) if (money_v is int) else cost
			return "Need $%d more" % maxi(1, short)
		"out_of_cafe_floor":
			return "Must fit on the cafe floor"
		"blocked_by_back_wall":
			return "Too close to the wall"
		"inside_rest_area":
			return "The nap zone is for cats only"
		"occupied_by_decor":
			return "Overlaps other decor"
		"blocked_cell":
			return "Space is blocked"
		"blocks_rest_door":
			return "Would block the nap zone door"
		"blocks_entrance":
			return "Would block the entrance"
		"blocks_slot":
			return "Blocks another item's seat"
		"would_block_path":
			return "Would cut off part of the cafe or the nap zone"
		"occupied_by_actor":
			return "Someone is standing there"
		"slot_blocked":
			return "Its seat would be blocked"
		"rotation_not_allowed":
			return "Can't face that way - rotate (R)"
		"missing_mesh_map":
			return "Item not available"
		_:
			return key.capitalize()

# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if level == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and _is_pointer_over_gui():
			return
		if _handle_mouse_button(mb):
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if _handle_key(event as InputEventKey):
			get_viewport().set_input_as_handled()

func _is_pointer_over_gui() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null or not vp.has_method("gui_get_hovered_control"):
		return false
	var c: Control = vp.gui_get_hovered_control()
	return c != null and c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	if not event.pressed:
		return false
	_update_hover_from_screen_pos(event.position)
	var holding: bool = is_holding()
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if holding:
				rotate_held(1)
				return true
			return false
		MOUSE_BUTTON_WHEEL_DOWN:
			if holding:
				rotate_held(-1)
				return true
			return false
		MOUSE_BUTTON_LEFT:
			if holding:
				_try_place(event.shift_pressed)
				return true
			var cat: Node3D = pick_cat_at(event.position)
			if cat != null:
				cat_clicked.emit(cat)
				return true
			if has_hover and _emit_decor_click(hovered_grid):
				return true
			empty_clicked.emit()
			return false
		MOUSE_BUTTON_RIGHT:
			if holding:
				cancel_hold()
				return true
			if has_hover and _emit_decor_click(hovered_grid):
				return true
			empty_clicked.emit()
			return false
	return false

func _handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_ESCAPE:
			if is_holding():
				cancel_hold()
				return true
			empty_clicked.emit()
			return false
		KEY_R, KEY_E:
			if is_holding():
				rotate_held(1)
				return true
		KEY_Q:
			if is_holding():
				rotate_held(-1)
				return true
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var idx: int = int(event.keycode - KEY_1)
		if level.has_method("get_available_decor_ids"):
			available_decor_ids = level.get_available_decor_ids()
		if idx >= 0 and idx < available_decor_ids.size():
			begin_hold(available_decor_ids[idx])
			return true
	return false

func _try_place(keep_holding: bool) -> void:
	if not has_hover:
		_flash_cursor("Point at the cafe floor")
		return
	var id: String = holding_decor_id
	var reason: String = _block_reason(hovered_grid, id, rotation_deg)
	if not reason.is_empty():
		_flash_cursor(describe_block_reason(reason, id))
		return
	var placed: bool = false
	if level.has_method("purchase_decor"):
		placed = bool(level.purchase_decor(hovered_grid, id, rotation_deg))
	else:
		placed = bool(level.place_decor(hovered_grid, id, rotation_deg))
	if not placed:
		_flash_cursor(describe_block_reason(_block_reason(hovered_grid, id, rotation_deg), id))
		return
	decor_placed.emit(id, hovered_grid)
	_preview_key = ""
	if not keep_holding:
		cancel_hold()

func _block_reason(cell: Vector2i, id: String, rot: int) -> String:
	if level.has_method("get_purchase_block_reason"):
		return String(level.get_purchase_block_reason(cell, id, rot))
	return String(level.get_place_block_reason(cell, id, rot))

func _emit_decor_click(cell: Vector2i) -> bool:
	if not level.has_method("get_decor_inspection_data"):
		return false
	var info: Dictionary = level.get_decor_inspection_data(cell)
	if info.is_empty():
		return false
	decor_clicked.emit(cell, info)
	return true

## Screen-space cat pick: nearest cat whose body center projects within 40 px.
func pick_cat_at(screen_pos: Vector2) -> Node3D:
	var cam: Camera3D = level.get_active_camera()
	if cam == null or not level.has_method("get_cat_nodes"):
		return null
	var best: Node3D = null
	var best_d: float = CAT_PICK_RADIUS_PX
	for cat in level.get_cat_nodes():
		for h in [0.12, 0.3, 0.5]:
			var wp: Vector3 = cat.global_position + Vector3(0, h, 0)
			if cam.is_position_behind(wp):
				continue
			var d: float = cam.unproject_position(wp).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = cat
	return best

# ---------------------------------------------------------------- hover + preview

func _update_hover_from_screen_pos(screen_pos: Vector2) -> void:
	var cam: Camera3D = level.get_active_camera()
	if cam == null:
		has_hover = false
		return
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		has_hover = false
		return
	var bounds: Dictionary = level.get_floor_world_bounds()
	var p: Vector3 = hit
	if p.x < float(bounds.get("min_x", 0.0)) or p.x > float(bounds.get("max_x", 0.0)) \
			or p.z < float(bounds.get("min_z", 0.0)) or p.z > float(bounds.get("max_z", 0.0)):
		has_hover = false
		return
	hovered_grid = level.world_to_map(p)
	has_hover = level.is_in_cafe_floor(hovered_grid)

func _create_preview() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "PlacementPreview"
	add_child(_preview_root)
	_preview_cells_root = Node3D.new()
	_preview_cells_root.name = "BlockingCellsPreview"
	_preview_root.add_child(_preview_cells_root)
	_preview_slots_root = Node3D.new()
	_preview_slots_root.name = "SlotPreview"
	_preview_root.add_child(_preview_slots_root)
	_held_preview_root = Node3D.new()
	_held_preview_root.name = "HeldDecorPreview"
	_preview_root.add_child(_held_preview_root)

	_tile_mat_valid = _make_flat_mat(preview_valid_color)
	_tile_mat_invalid = _make_flat_mat(preview_invalid_color)
	_slot_mat_patron = _make_flat_mat(Color(0.43, 0.56, 0.72, 0.85))
	_slot_mat_cat = _make_flat_mat(Color(0.95, 0.75, 0.45, 0.9))
	_ghost_mat_valid = _make_flat_mat(ghost_valid_color)
	_ghost_mat_invalid = _make_flat_mat(ghost_invalid_color)
	_ghost_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_ghost_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_ghost_mat_valid.cull_mode = BaseMaterial3D.CULL_BACK
	_ghost_mat_invalid.cull_mode = BaseMaterial3D.CULL_BACK
	_ghost_mat_valid.emission_enabled = true
	_ghost_mat_valid.emission = Color(0.2, 0.45, 0.25)
	_ghost_mat_invalid.emission_enabled = true
	_ghost_mat_invalid.emission = Color(0.5, 0.12, 0.1)

func _make_flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.no_depth_test = false
	return m

func _update_preview(delta: float) -> void:
	if not has_hover or holding_decor_id.is_empty():
		_preview_root.visible = false
		if not holding_decor_id.is_empty():
			_set_cursor_text("")
		return
	_preview_root.visible = true
	_preview_root.position = level.map_to_world(hovered_grid)
	_preview_root.rotation_degrees = Vector3.ZERO
	var key: String = "%d_%d|%s|%d" % [hovered_grid.x, hovered_grid.y, holding_decor_id, rotation_deg]
	_reason_timer -= delta
	if key != _preview_key or _reason_timer <= 0.0:
		_reason_timer = REASON_REFRESH_SEC
		last_block_reason = _block_reason(hovered_grid, holding_decor_id, rotation_deg)
		var valid: bool = last_block_reason.is_empty()
		if key != _preview_key:
			_preview_key = key
			_rebuild_preview_cells(valid)
		elif valid != _preview_valid:
			_set_tiles_valid(valid)
		_preview_valid = valid
		_apply_ghost_validity(valid)
		_update_cursor_text()
	_refresh_held_preview()
	_held_preview_root.rotation_degrees = Vector3(0.0, float(rotation_deg), 0.0)
	var world_pos: Vector3 = level.get_decor_world_position(hovered_grid, holding_decor_id, rotation_deg)
	_held_preview_root.position = world_pos - _preview_root.position + Vector3(0, 0.01, 0)
	_position_cursor()

func _rebuild_preview_cells(valid: bool) -> void:
	for child in _preview_cells_root.get_children():
		child.queue_free()
	for child in _preview_slots_root.get_children():
		child.queue_free()
	var cells: Array[Vector2i] = level.get_decor_blocking_cells(hovered_grid, holding_decor_id, rotation_deg)
	var cw: float = float(level.cell_width_3d)
	var cd: float = float(level.cell_depth_3d)
	var tile := PlaneMesh.new()
	tile.size = Vector2(cw * 0.92, cd * 0.92)
	for cell in cells:
		var m := MeshInstance3D.new()
		m.mesh = tile
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_override = _tile_mat_valid if valid else _tile_mat_invalid
		m.position = level.map_to_world(cell) - _preview_root.position + Vector3(0.0, TILE_Y, 0.0)
		_preview_cells_root.add_child(m)
	if level.has_method("get_decor_slot_cells"):
		var disc := CylinderMesh.new()
		disc.top_radius = minf(cw, cd) * 0.22
		disc.bottom_radius = disc.top_radius
		disc.height = 0.01
		disc.radial_segments = 20
		for slot in level.get_decor_slot_cells(hovered_grid, holding_decor_id, rotation_deg):
			if not (slot is Dictionary):
				continue
			var m := MeshInstance3D.new()
			m.mesh = disc
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.material_override = _slot_mat_cat if StringName(str(slot.get("kind", ""))) == &"cat" else _slot_mat_patron
			var sc: Vector2i = slot.get("cell", Vector2i.ZERO)
			m.position = level.map_to_world(sc) - _preview_root.position + Vector3(0.0, TILE_Y + 0.01, 0.0)
			_preview_slots_root.add_child(m)

func _set_tiles_valid(valid: bool) -> void:
	for child in _preview_cells_root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = _tile_mat_valid if valid else _tile_mat_invalid

func _refresh_held_preview() -> void:
	if _held_preview_root == null:
		return
	if _held_preview_active_id == holding_decor_id:
		return
	for child in _held_preview_root.get_children():
		child.queue_free()
	_held_preview_active_id = holding_decor_id
	_ghost_valid_applied = -1
	if holding_decor_id.is_empty():
		return
	var mesh_entry: Dictionary = level.decor_mesh_by_id.get(holding_decor_id, {})
	var scene_path: String = String(mesh_entry.get("mesh_scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		if level.has_method("get_decor_scale"):
			(inst as Node3D).scale = level.get_decor_scale(holding_decor_id)
		_held_preview_root.add_child(inst)
		_apply_ghost_validity(_preview_valid)

func _apply_ghost_validity(valid: bool) -> void:
	var flag: int = 1 if valid else 0
	if flag == _ghost_valid_applied:
		return
	_ghost_valid_applied = flag
	for child in _held_preview_root.get_children():
		_apply_ghost_material(child, valid)

func _apply_ghost_material(node: Node, valid: bool) -> void:
	var tint: Color = ghost_valid_color if valid else ghost_invalid_color
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _ghost_mat_valid if valid else _ghost_mat_invalid
	elif node is Label3D:
		(node as Label3D).modulate = Color(tint, 0.7)
		(node as Label3D).outline_modulate = Color(tint.darkened(0.6), 0.5)
	elif node is SpriteBase3D:
		(node as SpriteBase3D).modulate = Color(tint, 0.6)
	elif node is Light3D:
		(node as Light3D).visible = false
	for child in node.get_children():
		_apply_ghost_material(child, valid)

# ---------------------------------------------------------------- cursor label

func _create_cursor_ui() -> void:
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.name = "PlacementCursorLayer"
	_cursor_layer.layer = 12
	add_child(_cursor_layer)
	_cursor_panel = PanelContainer.new()
	_cursor_panel.name = "CursorReason"
	_cursor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(THEME_PATH):
		_cursor_panel.theme = load(THEME_PATH)
	_cursor_panel.theme_type_variation = &"CursorPanel"
	_cursor_panel.visible = false
	_cursor_layer.add_child(_cursor_panel)
	_cursor_style_ok = _make_cursor_style(Color("#4F7A55"))
	_cursor_style_bad = _make_cursor_style(Color("#B5523B"))
	_cursor_label = Label.new()
	_cursor_label.theme_type_variation = &"CursorLabel"
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_panel.add_child(_cursor_label)

var _flash_timer: float = 0.0

func _flash_cursor(text: String) -> void:
	_flash_timer = 1.2
	_set_cursor_text(text, true)

func _update_cursor_text() -> void:
	if _flash_timer > 0.0:
		return
	if holding_decor_id.is_empty():
		_set_cursor_text("")
		return
	if last_block_reason.is_empty():
		var cost: int = int(level.get_decor_cost(holding_decor_id)) if level.has_method("get_decor_cost") else 0
		_set_cursor_text("Place  $%d" % cost if cost > 0 else "Place", false)
	else:
		_set_cursor_text(describe_block_reason(last_block_reason, holding_decor_id), true)

func _set_cursor_text(text: String, bad: bool = false) -> void:
	if _cursor_panel == null:
		return
	_cursor_panel.visible = not text.is_empty()
	_cursor_label.text = text
	_cursor_panel.add_theme_stylebox_override("panel", _cursor_style_bad if bad else _cursor_style_ok)

func _make_cursor_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg, 0.94)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = bg.darkened(0.35)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 5.0
	sb.shadow_color = Color(0, 0, 0, 0.2)
	sb.shadow_size = 3
	return sb

func _pointer_pos() -> Vector2:
	if pointer_override.x >= 0.0:
		return pointer_override
	return get_viewport().get_mouse_position()

func _position_cursor() -> void:
	if _cursor_panel == null or not _cursor_panel.visible:
		return
	if _flash_timer > 0.0:
		_flash_timer -= get_process_delta_time()
		if _flash_timer <= 0.0:
			_update_cursor_text()
	var vp: Viewport = get_viewport()
	var mp: Vector2 = _pointer_pos()
	var vs: Vector2 = vp.get_visible_rect().size
	var sz: Vector2 = _cursor_panel.get_combined_minimum_size()
	var pos: Vector2 = mp + Vector2(20, 22)
	pos.x = minf(pos.x, vs.x - sz.x - 8.0)
	pos.y = minf(pos.y, vs.y - sz.y - 8.0)
	_cursor_panel.position = pos
	_cursor_panel.size = sz
