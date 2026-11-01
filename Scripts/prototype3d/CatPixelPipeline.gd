extends Node

# Pixel-art compositing for a pixel_art Cat2D that lives in a SubViewport.
# No class_name on purpose: preload("res://Scripts/prototype3d/CatPixelPipeline.gd").
# Used by all three pixel consumers (MainLevelCat3D's Sprite3D, CatPreview's
# pixel view, Tools/render_cat_seeds.gd pixel sheets), so the look is the same.
#
#   source SubViewport (holds the Cat2D)  renders only LAYER_BACK
#   body   SubViewport (shares its World2D) renders only LAYER_BODY
#   head   SubViewport (shares its World2D) renders only LAYER_HEAD
#   out    SubViewport: one ColorRect whose shader outlines each layer's
#          rasterized alpha mask (transparent pixel with an opaque 4-neighbour
#          -> outline colour) and composites back -> body -> head.
#
# So the silhouette gets exactly one 1px outline, and internal lines appear only
# where one layer's mask sits over another (chin over chest, body over far legs,
# a front tail over the loaf). Pixels drawn with alpha in [0.5, 0.98) are
# "decals" (shown opaque, never outlined, e.g. whisker tips); alpha < 0.5 is
# composited as-is (soft ground shadow). Cat2D never draws outlines in pixel
# mode, so nothing doubles.
#
# Usage:
#   var pipe = CatPixelPipelineScript.new()
#   pipe.setup(host_node, cat_subviewport, cat2d)
#   pipe.set_pixel(true)          # false = passthrough (smooth rig)
#   sprite.texture = pipe.get_texture()
#   pipe.set_active(on)           # update modes on/off (F6 fallback)

const Cat2DScript := preload("res://Scripts/prototype3d/Cat2D.gd")

const SHADER_CODE: String = """shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D tex_back : filter_nearest;
uniform sampler2D tex_body : filter_nearest;
uniform sampler2D tex_head : filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.23, 0.15, 0.13, 1.0);

const float SOLID = 0.98;
const float DECAL = 0.5;

float solid_at(sampler2D t, ivec2 p, ivec2 sz) {
	if (p.x < 0 || p.y < 0 || p.x >= sz.x || p.y >= sz.y) {
		return 0.0;
	}
	return step(SOLID, texelFetch(t, p, 0).a);
}

// One layer: fill (opaque), decal (unpremultiplied, opaque), outline (empty
// pixel 4-adjacent to the mask) or faint (shadow, unpremultiplied).
vec4 layer(sampler2D t, ivec2 p, ivec2 sz) {
	vec4 c = texelFetch(t, p, 0);
	if (c.a >= SOLID) {
		return vec4(c.rgb / c.a, 1.0);
	}
	if (c.a >= DECAL) {
		return vec4(c.rgb / c.a, 1.0);
	}
	float m = solid_at(t, p + ivec2(1, 0), sz) + solid_at(t, p + ivec2(-1, 0), sz)
		+ solid_at(t, p + ivec2(0, 1), sz) + solid_at(t, p + ivec2(0, -1), sz);
	if (m > 0.5) {
		return vec4(outline_color.rgb, 1.0);
	}
	if (c.a > 0.004) {
		return vec4(c.rgb / c.a, c.a);
	}
	return vec4(0.0);
}

vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	vec3 rgb = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / a;
	return vec4(rgb, a);
}

void fragment() {
	ivec2 sz = textureSize(tex_back, 0);
	ivec2 p = clamp(ivec2(floor(UV * vec2(sz))), ivec2(0), sz - ivec2(1));
	vec4 c = layer(tex_back, p, sz);
	c = over(layer(tex_body, p, sz), c);
	c = over(layer(tex_head, p, sz), c);
	COLOR = c;
}
"""

static var _shader: Shader = null

var source: SubViewport
var cat: Node2D
var pixel: bool = false
var active: bool = true
## Update mode of the output viewport while active (in game: WHEN_VISIBLE, so
## off-screen cats skip the composite; tools: ALWAYS).
var out_update_mode: int = SubViewport.UPDATE_ALWAYS
## Update mode of the source viewport when NOT in pixel mode (passthrough).
var source_update_mode: int = SubViewport.UPDATE_ALWAYS

var _body_vp: SubViewport
var _head_vp: SubViewport
var _out_vp: SubViewport
var _rect: ColorRect
var _mat: ShaderMaterial
var _outline: Color = Color(0, 0, 0, 0)

func setup(host: Node, src: SubViewport, cat_node: Node2D) -> void:
	source = src
	cat = cat_node
	name = "CatPixelPipeline"
	if get_parent() == null:
		host.add_child(self)
	_body_vp = _make_layer("BodyLayer", Cat2DScript.LAYER_BODY)
	_head_vp = _make_layer("HeadLayer", Cat2DScript.LAYER_HEAD)
	_out_vp = SubViewport.new()
	_out_vp.name = "Composite"
	_out_vp.disable_3d = true
	_out_vp.transparent_bg = true
	_out_vp.gui_disable_input = true
	_out_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_out_vp)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("tex_back", source.get_texture())
	_mat.set_shader_parameter("tex_body", _body_vp.get_texture())
	_mat.set_shader_parameter("tex_head", _head_vp.get_texture())
	_rect = ColorRect.new()
	_rect.name = "Outline"
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_out_vp.add_child(_rect)
	_sync_size()
	_sync_outline()
	_apply_modes()

func _make_layer(layer_name: String, mask: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = layer_name
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.gui_disable_input = true
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.snap_2d_transforms_to_pixel = true
	vp.world_2d = source.world_2d
	vp.canvas_cull_mask = mask
	add_child(vp)
	return vp

## On: layered outline pipeline. Off: the source viewport is shown directly
## (smooth rig, every layer).
func set_pixel(on: bool) -> void:
	pixel = on
	if source != null:
		source.canvas_cull_mask = Cat2DScript.LAYER_BACK if on else 0xFFFFFFFF
	_sync_size()
	_sync_outline()
	_apply_modes()

func set_active(on: bool) -> void:
	active = on
	_apply_modes()

func get_texture() -> Texture2D:
	if pixel and _out_vp != null:
		return _out_vp.get_texture()
	return source.get_texture() if source != null else null

func _apply_modes() -> void:
	if source == null or _out_vp == null:
		return
	var on_px: bool = active and pixel
	var layer_mode: int = SubViewport.UPDATE_ALWAYS if on_px else SubViewport.UPDATE_DISABLED
	source.render_target_update_mode = layer_mode if pixel else (source_update_mode if active else SubViewport.UPDATE_DISABLED)
	_body_vp.render_target_update_mode = layer_mode
	_head_vp.render_target_update_mode = layer_mode
	_out_vp.render_target_update_mode = out_update_mode if on_px else SubViewport.UPDATE_DISABLED
	set_process(on_px)

func _sync_size() -> void:
	if source == null or _out_vp == null:
		return
	var sz: Vector2i = source.size
	for vp in [_body_vp, _head_vp, _out_vp]:
		if vp.size != sz:
			vp.size = sz
	_body_vp.snap_2d_transforms_to_pixel = source.snap_2d_transforms_to_pixel
	_head_vp.snap_2d_transforms_to_pixel = source.snap_2d_transforms_to_pixel
	_rect.position = Vector2.ZERO
	_rect.size = Vector2(sz)

func _sync_outline() -> void:
	if cat == null or _mat == null or not cat.has_method("pixel_outline_color"):
		return
	var c: Color = cat.call("pixel_outline_color")
	if c != _outline:
		_outline = c
		_mat.set_shader_parameter("outline_color", c)

func _process(_delta: float) -> void:
	if source == null:
		return
	if _out_vp.size != source.size:
		_sync_size()
	_sync_outline()
