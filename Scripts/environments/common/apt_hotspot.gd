extends Area3D

## Reusable interactable hotspot for environment dioramas.
##
## - A box-shaped Area3D on HOTSPOT_LAYER (picked by the environment with a ray query, so
##   picking works the same with a mouse, in tests, and headless).
## - set_hovered(true) puts a warm pulsing rim overlay on every MeshInstance3D under
##   `highlight_root`, shows a soft floor ring and a floating name label.
## - activate() emits `activated`; the environment then shows the prompt card.
##   choose_action(id) emits `action_chosen` (card buttons call it).
##
## Configure in code: setup(id, title, body, actions, highlight_root, box_size, box_center).
## `actions` = [{"id": "feed", "label": "Fill the bowls"}, ...]; the first is the primary one.

signal hovered(hotspot)
signal unhovered(hotspot)
signal activated(hotspot)
signal action_chosen(hotspot, action_id: String)

## Physics layer 20, away from actors (cats use layer 2).
const HOTSPOT_LAYER: int = 1 << 19

const RIM_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 glow : source_color = vec4(1.0, 0.80, 0.52, 1.0);
uniform float strength = 0.42;
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float pulse = 0.78 + 0.22 * sin(TIME * 3.6);
	ALBEDO = glow.rgb * (strength * 0.55 + fres * strength * 1.4) * pulse;
}
"""

const RING_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 ring_color : source_color = vec4(1.0, 0.86, 0.6, 0.85);
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float ring = smoothstep(0.70, 0.80, d) * (1.0 - smoothstep(0.86, 0.98, d));
	float fill = (1.0 - smoothstep(0.0, 0.8, d)) * 0.16;
	float pulse = 0.8 + 0.2 * sin(TIME * 3.6);
	ALBEDO = ring_color.rgb;
	ALPHA = (ring + fill) * ring_color.a * pulse;
}
"""

static var _rim_material: ShaderMaterial = null
static var _ring_shader: Shader = null

@export var hotspot_id: String = ""
@export var title: String = ""
@export_multiline var body: String = ""
## Short verb shown in the hover label ("Click to ..."), optional.
@export var verb: String = ""
## Icon key for the prompt card (the HUD draws it procedurally).
@export var icon: String = ""
var actions: Array = []
var highlight_root: Node3D = null
## Height of the floating label above the hotspot origin.
var label_height: float = 1.2
var ring_radius: float = 0.6
## Floating name label on hover (off when the environment shows its own cursor tooltip).
var show_label: bool = true

var is_hovered: bool = false
var _label: Label3D
var _ring: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []
var _box_center := Vector3.ZERO
var _box_size := Vector3.ONE

func setup(p_id: String, p_title: String, p_body: String, p_actions: Array, p_highlight: Node3D,
		box_size: Vector3, box_center: Vector3 = Vector3.ZERO) -> void:
	hotspot_id = p_id
	title = p_title
	body = p_body
	actions = p_actions
	highlight_root = p_highlight
	_box_size = box_size
	_box_center = box_center
	name = "Hotspot_%s" % p_id

func _ready() -> void:
	add_to_group("env_hotspots")
	collision_layer = HOTSPOT_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	input_ray_pickable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _box_size
	cs.shape = shape
	cs.position = _box_center
	add_child(cs)
	_build_ring()
	_build_label()
	_collect_meshes()

func _collect_meshes() -> void:
	_meshes.clear()
	if highlight_root == null:
		return
	var stack: Array[Node] = [highlight_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			_meshes.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)

static func _rim() -> ShaderMaterial:
	if _rim_material == null:
		var sh := Shader.new()
		sh.code = RIM_SHADER_CODE
		_rim_material = ShaderMaterial.new()
		_rim_material.shader = sh
	return _rim_material

func _build_ring() -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER_CODE
	_ring = MeshInstance3D.new()
	_ring.name = "HoverRing"
	var pm := PlaneMesh.new()
	pm.size = Vector2(ring_radius * 2.0, ring_radius * 2.0)
	_ring.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.render_priority = -1
	_ring.material_override = m
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(_box_center.x, 0.03, _box_center.z)
	_ring.visible = false
	add_child(_ring)

func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "HoverLabel"
	_label.text = title
	_label.font_size = 40
	_label.pixel_size = 0.0045
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 3
	_label.outline_render_priority = 2
	_label.modulate = Color("FFF6EA")
	_label.outline_modulate = Color("4A3426")
	_label.outline_size = 12
	_label.position = Vector3(_box_center.x, label_height, _box_center.z)
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var th = load("res://UI/cozy_theme.tres")
	if th is Theme and (th as Theme).default_font != null:
		_label.font = (th as Theme).default_font
	_label.visible = false
	add_child(_label)

func set_hovered(on: bool) -> void:
	if on == is_hovered:
		return
	is_hovered = on
	var mat: Material = _rim() if on else null
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_overlay = mat
	if _ring != null:
		_ring.visible = on
		# Keep the ring on the floor even when the hotspot origin is raised.
		_ring.global_position = Vector3(global_position.x + _box_center.x, 0.025, global_position.z + _box_center.z)
	if _label != null:
		_label.visible = on and show_label
	if on:
		hovered.emit(self)
	else:
		unhovered.emit(self)

## Hide the floating name while a prompt card for this hotspot is open.
func set_label_suppressed(on: bool) -> void:
	if _label != null:
		_label.visible = is_hovered and show_label and not on

func activate() -> void:
	activated.emit(self)

func choose_action(action_id: String) -> void:
	action_chosen.emit(self, action_id)

## World point at the middle of the pick box (cards anchor here; probes click here).
func get_focus_point() -> Vector3:
	return global_transform * _box_center

func get_primary_action() -> String:
	if actions.is_empty():
		return ""
	return str((actions[0] as Dictionary).get("id", ""))
