extends Area3D

## Clickable town hotspot. Town.gd picks it with a camera ray (collision layer HOTSPOT_LAYER,
## areas only), calls set_hovered() for the hover highlight and opens the prompt card.
## Visuals: a pulsing ground ring, a bobbing gold diamond marker with a name tag on hover,
## and a warm additive overlay on the linked building meshes. Hidden spots (doorstep
## events) show nothing until hovered.

const HOTSPOT_LAYER: int = 1 << 9

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 ring_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float hover = 0.0;
uniform float strength = 1.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float pulse = 0.5 + 0.5 * sin(TIME * 2.6);
	float r_in = mix(0.62, 0.7, pulse);
	float ring = smoothstep(r_in - 0.08, r_in, d) * (1.0 - smoothstep(0.86, 0.98, d));
	float fill = (1.0 - smoothstep(0.0, 0.9, d)) * 0.25 * hover;
	ALBEDO = ring_color.rgb;
	ALPHA = (ring * mix(0.45, 0.95, hover) + fill) * strength;
}
"""

const OVERLAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform float amount = 0.0;
void fragment() {
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	ALBEDO = tint.rgb * amount * pulse;
	ALPHA = 1.0;
}
"""

static var _ring_shader: Shader
static var _overlay_shader: Shader

@export var hotspot_id: StringName = &""
@export var title: String = ""
@export var hidden_spot: bool = false

var info: Dictionary = {}
var hovered: bool = false
var highlight_root: Node3D = null

var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _marker: Node3D
var _tag: Label3D
var _overlay: ShaderMaterial
var _hover_t: float = 0.0
var _time: float = 0.0
var _marker_base_y: float = 2.2

## def keys: id, title, ring (Vector3), area_center, area_size, marker_y, hidden, highlight (Node3D)
func setup(def: Dictionary, font: Font = null) -> void:
	info = def
	hotspot_id = StringName(def.get("id", ""))
	title = String(def.get("title", ""))
	hidden_spot = bool(def.get("hidden", false))
	name = "Hotspot_%s" % String(hotspot_id)
	collision_layer = HOTSPOT_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	input_ray_pickable = true
	var ring_pos: Vector3 = def.get("ring", Vector3.ZERO)
	position = ring_pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = def.get("area_size", Vector3(2, 2, 2))
	cs.shape = shape
	cs.position = (def.get("area_center", ring_pos) as Vector3) - ring_pos
	add_child(cs)
	_build_ring(float(def.get("ring_size", 1.7)))
	_marker_base_y = float(def.get("marker_y", 2.4))
	_build_marker(font)
	highlight_root = def.get("highlight", null)
	_apply_visibility()

func _build_ring(size: float) -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = _ring_shader
	_ring_mat.render_priority = -1
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	_ring.mesh = pm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 0.03, 0)
	add_child(_ring)

func _build_marker(font: Font) -> void:
	_marker = Node3D.new()
	_marker.name = "Marker"
	add_child(_marker)
	var gem := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.46
	sm.radial_segments = 4
	sm.rings = 2
	gem.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("F2C14E")
	gm.emission_enabled = true
	gm.emission = Color("FFC86A")
	gm.emission_energy_multiplier = 1.4
	gm.roughness = 0.3
	gem.material_override = gm
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(gem)
	_tag = Label3D.new()
	_tag.name = "Tag"
	_tag.text = title
	_tag.font_size = 40
	_tag.pixel_size = 0.0045
	_tag.outline_size = 12
	_tag.modulate = Color("4A3426")
	_tag.outline_modulate = Color("FFF6EA")
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.render_priority = 3
	_tag.outline_render_priority = 2
	_tag.shaded = false
	_tag.position = Vector3(0, 0.5, 0)
	_tag.visible = false
	if font != null:
		_tag.font = font
	_marker.add_child(_tag)

func set_hovered(on: bool) -> void:
	if hovered == on:
		return
	hovered = on
	if _tag != null:
		_tag.visible = on
	_apply_visibility()
	_apply_overlay(on)

func _apply_visibility() -> void:
	var vis_on: bool = hovered or not hidden_spot
	if _ring != null:
		_ring.visible = vis_on
	if _marker != null:
		_marker.get_child(0).visible = vis_on

func _apply_overlay(on: bool) -> void:
	if highlight_root == null or not is_instance_valid(highlight_root):
		return
	if _overlay == null:
		if _overlay_shader == null:
			_overlay_shader = Shader.new()
			_overlay_shader.code = OVERLAY_SHADER
		_overlay = ShaderMaterial.new()
		_overlay.shader = _overlay_shader
	for mi in highlight_root.find_children("*", "GeometryInstance3D", true, false):
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).material_overlay = _overlay if on else null

func _process(delta: float) -> void:
	_time += delta
	_hover_t = move_toward(_hover_t, 1.0 if hovered else 0.0, delta * 5.0)
	if _ring_mat != null:
		_ring_mat.set_shader_parameter("hover", _hover_t)
	if _overlay != null:
		_overlay.set_shader_parameter("amount", 0.16 * _hover_t)
	if _marker != null:
		_marker.position.y = _marker_base_y + sin(_time * 2.2) * 0.08 + _hover_t * 0.15
		_marker.rotation.y = _time * 1.4
		var s: float = 1.0 + _hover_t * 0.35
		_marker.scale = Vector3(s, s, s)
		if _tag != null:
			_tag.rotation.y = -_marker.rotation.y
