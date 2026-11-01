extends Node2D
class_name Cat2D

## Procedural, side-view (3/4 facing +X) chibi cat. No textures, no Skeleton2D,
## no physics: every part is a decorative polygon (collision lives on Cat3D).
##
## Coordinates (scale 1, facing +X): origin = center between the feet, on the
## ground. Feet touch y = 0, everything else is at negative y.
## Default genome, idle pose: about x -26..+28 (whisker tips), y -47..+1
## (tail tip -47, ear tips about -42). Worst case (maine coon, big head, long
## tail, sit): about x -36..+33, y -58..+2. The in-game SubViewport (Cat3D)
## is a 76.8 x 76.8 unit window (72.8 up, 4 down): 192 px at scale 2.5 in
## smooth mode, 56 px at scale 56/76.8 in pixel_art mode (the default).
## Tools/render_cat_seeds.gd uses the same framing.
##
## Public API:
##   apply_genome(g)          CatGenome dict, a whole cat_def, or a visual dict
##   set_facing_left(bool)    mirrors the whole rig (Visual.scale.x = -1 / +1)
##   facing_left              current facing
##   set_move_speed(v)        0 = standing; ~1 = normal walk (also drives cadence)
##   set_pose(&"idle" | &"walk" | &"sit" | &"sleep")
##   refresh_visuals()        re-layout + redraw from the current genome
##   get_genome()
##   draw_shadow              export, toggles the soft ground shadow
##   pixel_art / set_pixel_art(on)  pixel-art mode for low-res viewports (see export)
##   set_expression(&"open" | &"happy" | &"stressed" | &"sleepy" | &"angry" |
##                  &"worried" | &"sad" | &"surprised" | &"smug")
##   get_landmarks()          shared anatomy of the current frame (see below)
##   fit_scale()              fit-guard shrink factor (1 = no shrink)
##
## Two renderers, one anatomy. Both read the same genome, proportions, poses,
## animation timing and LANDMARKS (layout + per-frame: head pose, eye anchors,
## nose, cheek edge, ear roots, paws, tail root/path, body union polygon,
## pattern regions; see get_landmarks()).
##   smooth  vector polygons with offset-polygon outlines, soft alpha shading,
##           AA lines (the look-dev / 192px path).
##   pixel   (pixel_art = true) fills only, opaque 2-3 tone ramps, no alpha
##           inside the cat; the 1px outline is NOT drawn here but derived from
##           the rasterized alpha mask by CatPixelPipeline.gd (one mask per
##           draw layer, so head-over-body and body-over-far-legs get a single
##           1px separation line). Face = hand-authored stamps from
##           CatPixelFace.gd placed on the whole-pixel grid; head ~12% bigger.
##   Parts carry visibility_layer bits LAYER_BACK / LAYER_BODY / LAYER_HEAD for
##   that pipeline; ordinary viewports render all of them as before.
##
## Silhouette model (see Docs/ART_STYLE_GUIDE.md, "Cat rig"):
##   torso loaf + rear haunch + chest bridge + the two NEAR legs are merged into
##   one polygon (Geometry2D.merge_polygons) that gets ONE outline, so there is
##   no outline ring where legs/chest meet the body. Internal separation is
##   only darker fill. Far legs are drawn behind the body, darker. The head has
##   its own outline, but a chest-colored "neck patch" hides that outline where
##   the chin overlaps the chest, and the ear fills hide it at the ear roots.
##
## Draw order: shadow, far legs, tail, body union (+near legs, patterns,
## internal shading), [head pivot] ear outlines, head outline, neck patch,
## ear fills, head fill (+face), eyes.
##
## Animation is procedural in _process: pose weights blend with move_toward.
## The body/legs geometry depends on (quantized pose weights, walk phase index
## out of WALK_PHASES, genome) and is cached per key, so steady-state animation
## does no polygon booleans. Breathing is a node scale, head bob/sway and ear
## twitch are node transforms, blink is an eyes-node squash. The tail rebuilds
## at most TAIL_HZ times per second.

const CatGenomeScript := preload("res://Scripts/prototype3d/CatGenome.gd")
const CatPartScript := preload("res://Scripts/prototype3d/CatPart2D.gd")
const CatPixelFaceScript := preload("res://Scripts/prototype3d/CatPixelFace.gd")

# Draw layers for the pixel pipeline (CanvasItem.visibility_layer bits).
const LAYER_BACK: int = 2      # shadow, far legs, tail (behind)
const LAYER_BODY: int = 4      # body union + near legs + markings
const LAYER_HEAD: int = 8      # head, ears, face, tail when it wraps in front
const LAYER_ALL: int = 0xF

const EXPRESSIONS: Array[StringName] = [&"open", &"happy", &"stressed", &"sleepy", &"angry", &"worried", &"sad", &"surprised", &"smug"]

const POSE_IDLE: StringName = &"idle"
const POSE_WALK: StringName = &"walk"
const POSE_SIT: StringName = &"sit"
const POSE_SLEEP: StringName = &"sleep"
const POSES: Array[StringName] = [POSE_IDLE, POSE_WALK, POSE_SIT, POSE_SLEEP]

# ---- proportion knobs (units at scale 1, default genome) ----
const BODY_RX: float = 18.0        # torso half length
const BODY_RY: float = 10.8         # torso half depth
const BODY_EXP: float = 2.5        # torso superellipse exponent (2 = ellipse, higher = boxier loaf)
const RUMP_LIFT: float = 1.8       # rump raised above the shoulder line
const SHOULDER_DIP: float = 0.6
const LEG_BASE_LEN: float = 7.6    # visible leg length (belly line to ground)
const LEG_ROOT_W: Array[float] = [7.8, 7.2]   # [rear, front] width at hip/shoulder root
const LEG_ANKLE_W: Array[float] = [5.8, 5.4]  # [rear, front] width just above the paw
const PAW_H: float = 3.0
const PAW_EXTRA_W: float = 1.4     # paw is this much wider than the ankle
const FAR_LEG_OFFSET: Vector2 = Vector2(2.6, -0.8)
const HEAD_RX: float = 13.8
const HEAD_RY: float = 11.6
const HEAD_EXP: float = 2.35        # rounded-square head
const HEAD_FORWARD: float = 0.70   # head center x, in torso half-lengths from torso center
const HEAD_UP: float = 0.76        # head center height above torso center, in torso half-depths
const EAR_W: float = 10.0
const EAR_H: float = 8.6
const TAIL_SEGMENTS: int = 6
const TAIL_BASE_LEN: float = 26.0
const TAIL_FALLOFF: Array[float] = [0.35, 0.6, 0.8, 1.0, 1.15, 1.3]
const SIT_ROT: float = -0.28
const WALK_STRIDE: float = 3.0
const WALK_LIFT: float = 1.7

# ---- fur edge knobs (genome: fur_style / fur_length / fur_density / fur_jitter) ----
const BODY_FLOW: Vector2 = Vector2(-1.0, 0.55)   # fur grows backward/down
const HEAD_FLOW: Vector2 = Vector2(-0.75, 0.66)
const FUR_LEAN: Dictionary = {"medium": 0.42, "fuzzy": 0.55}    # tip shift along flow, x amplitude
const FUR_SHARP: Dictionary = {"medium": 0.6, "fuzzy": 0.85}   # tuft profile exponent (higher = pointier)
const FUR_BACK: Dictionary = {"medium": 0.18, "fuzzy": 0.32}   # strength on the back top
const EAR_FUR: float = 0.35
const TAIL_FUR: float = 0.8

# ---- viewport fit guard (units at scale 1; in-game window is +-38.4 x, 72.8 up) ----
const FIT_X: float = 36.0
const FIT_TOP: float = 69.0

# ---- render / perf knobs ----
const WALK_PHASES: int = 8         # walk cycle quantization (cache key)
const WEIGHT_STEPS: float = 8.0    # pose-weight quantization (cache key)
const CACHE_MAX: int = 128
const TAIL_HZ: float = 20.0
const PIXEL_TAIL_HZ: float = 12.0

# ---- pixel renderer knobs ----
const PIXEL_HEAD_SCALE: float = 1.12   # pixel exaggeration of the head (+ears, face)
const PIXEL_FUR_SPACING: float = 4.2   # min art px between pixel fur spikes
const PIXEL_STRIPE_MIN: float = 1.5    # min tabby stripe width, art px
const DECAL_ALPHA: float = 0.8         # "no outline" marker alpha (whisker tips past the head)
# feature_ids colours (tools only).
const FID_NEAR := Color(1, 0, 0)
const FID_FAR := Color(0, 1, 0)
const FID_MOUTH := Color(0, 0, 1)
const FID_WHISKER := Color(1, 1, 0)
const FID_MARK := Color(1, 0, 1)
const FID_OUTLINE := Color(0, 1, 1)
# Pixel muzzle / siamese mask patch (tools: snoot centring measurement; the
# contact check reads it as fur).
const FID_MUZZLE := Color(1, 0.5, 0)
# feature_eye_parts ids, [near, far] (the eye line / lid keeps FID_NEAR / FID_FAR).
const FID_PUPIL: Array[Color] = [Color(1, 0, 0.5), Color(0, 1, 0.5)]
const FID_IRIS: Array[Color] = [Color(1, 0, 0.25), Color(0, 1, 0.25)]
const FID_GLINT: Array[Color] = [Color(1, 0, 0.75), Color(0, 1, 0.75)]
# Eye centres from the face axis, x head size (near / far keep the 3/4 ratio).
# v4 spacing: ~11% wider than the legacy 6.1 / 5.6 (blush moved out with them).
const EYE_NEAR_X: float = 6.8
const EYE_FAR_X: float = 6.25
const BLUSH_X: float = 7.9
const LEGACY_EYE_SPACING: Array[float] = [6.1, 5.6, 7.2]

# Smooth-renderer look of each eye_shape (pixel stamps: CatPixelFace.gd).
#   w, h      eye radii multipliers (round = 2.6 x 2.9 * head size)
#   pupil     pupil radii as fractions of the eye radii; pupil_dy = offset (x ry)
#   glints    1 = one big glint, 2 = + small lower one, 3 = + a mid one
#   lemon     pointed (almond) outline instead of an ellipse
#   lid       upper lid cut: tilt in radians (+ = outer corner lower / droopy,
#             - = upturned) through lid_y (x ry) at the eye centre
#   slit      lens-shaped vertical slit pupil
#   lower     lighter lower-iris strength; lash = outer flick
const SMOOTH_EYES: Dictionary = {
	"round": {"w": 1.0, "h": 1.0, "pupil": [0.68, 0.72], "glints": 2},
	"big": {"w": 1.15, "h": 1.13, "pupil": [0.76, 0.78], "glints": 2},
	"almond": {"w": 1.18, "h": 0.8, "lemon": true, "pupil": [0.6, 0.8], "glints": 2},
	"slit": {"w": 1.05, "h": 1.05, "slit": true, "pupil": [0.2, 0.86], "glints": 1},
	"big_slit": {"w": 1.16, "h": 1.15, "slit": true, "pupil": [0.28, 0.88], "glints": 1},
	"gentle": {"w": 1.08, "h": 1.0, "lid": 0.24, "lid_y": -0.42, "pupil": [0.68, 0.7], "glints": 2},
	"mischievous": {"w": 1.12, "h": 0.92, "lemon": true, "lid": -0.32, "lid_y": -0.1, "pupil": [0.5, 0.8], "glints": 1, "lash": true},
	"wide": {"w": 1.34, "h": 0.74, "pupil": [0.56, 0.78], "glints": 2},
}
# Smooth expression looks: lid = [tilt (+ = outer corner lower), lid_y (x ry)]
# replaces the shape's lid; pupil = pupil scale.
const SMOOTH_EXPR: Dictionary = {
	"stressed": {"pupil": 0.62},
	"surprised": {"pupil": 0.45},
	"worried": {"pupil": 0.8, "lid": [0.32, -0.62]},
	"sad": {"pupil": 0.95, "lid": [0.5, -0.4], "glossy": true},
	"angry": {"pupil": 0.8, "lid": [-0.55, -0.02]},
	"smug": {"lid": [0.0, -0.2]},
	"sleepy": {"lid": [0.0, 0.14], "no_glint": true},
}

@export var draw_shadow: bool = true:
	set(v):
		draw_shadow = v
		if _shadow != null:
			_shadow.visible = v
@export var animate: bool = true
## Tools only: the pre-v4 (narrower) eye spacing, for before/after sheets.
@export var legacy_eye_spacing: bool = false
## Tools only (Tools/check_eye_contacts.gd): draw every face feature in a flat
## id colour (FID_*) with no antialiasing, so contacts can be found by
## scanning rendered pixels. Set before apply_genome.
@export var feature_ids: bool = false
## Tools only (with feature_ids, Tools/check_eye_contacts.gd pupil metric):
## the eye is split into part ids: line / lid (FID_NEAR / FID_FAR), pupil or
## bead (FID_PUPIL), iris + eye white (FID_IRIS), glint (FID_GLINT).
@export var feature_eye_parts: bool = false
## Tools only: start the pixel stamp fallback chain at this set ("L", "M",
## "S", "XS", "XXS"; "" = automatic) to exercise the compact stamps.
## Placement rules (min gap, edge clearance) are unchanged.
@export var debug_stamp_bucket: String = ""
## Tools only (eye option sheets): alternate pixel eye stamps, same structure
## as CatPixelFace.EYES ({bucket: {shape: {expression: rows}}}). Consulted
## before CatPixelFace when non-empty; missing entries fall through to it.
## Empty in game, so game rendering is unchanged.
var eye_stamp_override: Dictionary = {}
## Tools only (mouth option sheets): alternate nose + mouth stamps
## ({bucket: {kind: rows}}, consulted before CatPixelFace.MOUTHS) and an extra
## downward offset (art px) of the drawn nose + mouth stamp; the face layout
## (eyes, whiskers) is unchanged. Empty / 0 in game.
var mouth_stamp_override: Dictionary = {}
var mouth_dy_offset: int = 0
## Tools only (mouth option sheets): raise both eyes this many art px, only
## when the raised stamps still keep MIN_EYE_EDGE_PX (else unchanged). 0 in game.
var eye_up_px: int = 0
@export var outline_width: float = 1.0
## Pixel-art mode: the separate pixel renderer, meant for a low-res viewport
## run through CatPixelPipeline.gd (mask outline) and upscaled with nearest
## filtering. Fills only (opaque tone ramps), face stamps from CatPixelFace.gd
## on the whole-pixel grid, pixel fur spikes, bigger head, no head rotation,
## tail at PIXEL_TAIL_HZ (1 art px = 1 / global scale units).
## Set the node scale first, then call set_pixel_art() (or toggle this).
@export var pixel_art: bool = false:
	set(v):
		if v == pixel_art:
			return
		pixel_art = v
		if _built:
			refresh_visuals()
@export_range(0.5, 3.0) var pixel_outline: float = 1.0
@export_range(0.0, 0.5) var far_leg_darken: float = 0.18
@export_range(0.0, 1.0) var limb_shade_alpha: float = 0.22

var facing_left: bool = false
var expression: StringName = &"open"
var pose: StringName = POSE_IDLE
var move_speed: float = 0.0
var genome: Dictionary = {}

var _pal: Dictionary = {}
var _built: bool = false
var _t: float = 0.0
var _phase: float = 0.0
var _w_walk: float = 0.0
var _w_sit: float = 0.0
var _w_sleep: float = 0.0
var _blink_timer: float = 2.5
var _blink_left: float = 0.0
var _twitch_timer: float = 4.0
var _twitch_left: float = 0.0
var _twitch_ear: int = 0
var _eyes_closed: bool = false
var _facing_x: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tail_accum: float = 1.0
var _tail_front: bool = false
var _ow: float = 1.0      # effective outline width (units)
var _px: float = 0.0      # one art pixel in rig units (pixel_art only, else 0)
var _pixel_shut: bool = false

# Layout (recomputed from the genome), in rest (idle) body coordinates.
var _rx: float = BODY_RX
var _ry: float = BODY_RY
var _hs: float = 1.0
var _leg_len: float = LEG_BASE_LEN
var _body_c: Vector2 = Vector2.ZERO
var _torso_rest: PackedVector2Array
var _haunch_rest: PackedVector2Array
var _chest_rest: PackedVector2Array
var _core_rest: PackedVector2Array
var _haunch_c: Vector2 = Vector2.ZERO
var _haunch_r: Vector2 = Vector2.ONE
var _chest_c: Vector2 = Vector2.ZERO
var _chest_r: Vector2 = Vector2.ONE
var _head_base: Vector2 = Vector2.ZERO
var _tail_root: Vector2 = Vector2.ZERO
var _leg_roots: Array[Vector2] = []
var _sit_pivot: Vector2 = Vector2.ZERO
var _head_rx: float = HEAD_RX
var _head_ry: float = HEAD_RY
var _face_x: float = 1.8
var _leg_w: float = 1.0
var _cheek: float = 0.07
var _head_wide: float = 1.0
var _fur_amp: float = 0.0
var _fur_den: float = 0.36
var _fur_jit: float = 0.3
var _fur_style: String = "flat"
var _fur_seed: int = 0
var _fit: float = 1.0
var _head_shape: PackedVector2Array
var _head_lm: Dictionary = {}     # head-space landmarks (per genome)
var _chin_y: float = NAN          # lowest head-shape y (pixel floor guard)

# Caches.
var _genome_hash: int = 0
var _frame_cache: Dictionary = {}
var _frame_key: String = ""
var _frame: Dictionary = {}
var _head_lists: Dictionary = {}
# Pixel mode: head-space x offset that moves the muzzle / siamese mask / tuxedo
# blaze onto the snoot axis of _pixel_face_layout (NAN = not computed yet;
# reset with the head lists).
var _snoot_dx: float = NAN
var _snoot_step: float = NAN

# Art-pixel grid step in head space (same as _pixel_face_layout).
func _pixel_step() -> float:
	return _px / maxf(0.05, _fit)

# Nodes (built in code under Visual).
var _visual: Node2D
var _shadow: Node2D
var _far_legs: Node2D
var _tail: Node2D
var _body: Node2D
var _head_pivot: Node2D
var _head_line: Node2D
var _neck: Node2D
var _head: Node2D
var _eyes: Node2D
var _ear_lines: Array[Node2D] = []
var _ear_fills: Array[Node2D] = []

func _ready() -> void:
	_rng.randomize()
	_build_rig()
	if genome.is_empty():
		genome = CatGenomeScript.normalize({})
	refresh_visuals()
	_blink_timer = _rng.randf_range(1.0, 4.0)
	_process(0.0)

# ---------------------------------------------------------------- public API

func apply_genome(g: Variant) -> void:
	var src: Dictionary = g if g is Dictionary else {}
	genome = CatGenomeScript.normalize(src)
	if _built:
		refresh_visuals()

func get_genome() -> Dictionary:
	return genome.duplicate(true)

func set_facing_left(is_left: bool) -> void:
	facing_left = is_left

func set_move_speed(v: float) -> void:
	move_speed = maxf(0.0, v)

func set_pose(p: Variant) -> void:
	var sn: StringName = StringName(str(p))
	if sn in POSES:
		pose = sn
	else:
		pose = POSE_IDLE

## Face expression. Pixel mode swaps eye/mouth stamps and adds expression
## marks (CatPixelFace.gd); smooth mode draws the matching lids (SMOOTH_EXPR),
## mouth and marks. happy = "^" arcs; open = the default look.
func set_expression(e: Variant) -> void:
	var sn: StringName = StringName(str(e))
	if not (sn in EXPRESSIONS):
		sn = &"open"
	if sn == expression:
		return
	expression = sn
	if _built:
		_eyes.queue_redraw()
		if not pixel_art:
			# Smooth mouths live in the cached head fill list.
			_head_lists.clear()
			_head.queue_redraw()

## Colour of the pixel pipeline's mask outline (palette outline).
func pixel_outline_color() -> Color:
	if feature_ids:
		return FID_OUTLINE
	return _pal.get("outline", Color("#3A2620"))

## Shared anatomy of the current frame, in rig (Visual) space unless noted.
## Both renderers draw from these; tools/effects may read them.
##   head_pos, head_rot      head pivot pose
##   head: {eye_near, eye_far, eye_center, eye_r, nose, muzzle, cheek_x,
##          ear_roots, face_x}  (head space)
##   paws (4, far rear/front, near rear/front), leg_roots, core (torso
##   polygon), union (silhouette body polygon), tail_root, tail_path, xf
##   (pose transform for rest-space pattern regions), fit
func get_landmarks() -> Dictionary:
	var f: Dictionary = _frame
	var out: Dictionary = {
		"head_pos": f.get("head_pos", _head_base),
		"head_rot": f.get("head_rot", 0.0),
		"head": _head_lm.duplicate(),
		"paws": f.get("paws", []),
		"leg_roots": f.get("roots", []),
		"core": f.get("core", PackedVector2Array()),
		"union": f.get("union", PackedVector2Array()),
		"tail_root": f.get("tail_pos", _tail_root),
		"xf": f.get("xf", Transform2D.IDENTITY),
		"fit": _fit,
	}
	var angles: Array = _tail.params.get("angles", []) if _tail != null else []
	if not angles.is_empty():
		out["tail_path"] = _tail_path(angles)[0]
	return out

## Switches pixel-art mode and re-reads the art-pixel size from the current
## global scale. Call after positioning/scaling the rig in its viewport.
func set_pixel_art(on: bool) -> void:
	var want_px: float = _art_px() if on else 0.0
	if on == pixel_art and is_equal_approx(want_px, _px) and _built:
		return
	pixel_art = on
	if _built:
		refresh_visuals()

func _art_px() -> float:
	var sx: float = absf(get_global_transform().get_scale().x) if is_inside_tree() else absf(scale.x)
	return 1.0 / maxf(0.05, sx)

func refresh_visuals() -> void:
	if not _built:
		return
	_px = _art_px() if pixel_art else 0.0
	_ow = _px * pixel_outline if pixel_art else outline_width
	var g: Dictionary = genome if not genome.is_empty() else CatGenomeScript.normalize({})
	_pal = CatGenomeScript.resolve(g)
	_genome_hash = hash(g)
	_frame_cache.clear()
	_frame_key = ""
	_head_lists.clear()
	_snoot_dx = NAN
	_head_shape = PackedVector2Array()
	_chin_y = NAN
	_layout()
	_compute_fit()
	_tail_accum = 1.0
	for part in _all_parts():
		part.queue_redraw()
	_process(0.0)

# ---------------------------------------------------------------- build

func _build_rig() -> void:
	_visual = get_node_or_null("Visual") as Node2D
	if _visual == null:
		_visual = Node2D.new()
		_visual.name = "Visual"
		add_child(_visual)
	for c in _visual.get_children():
		c.queue_free()
	_shadow = _make_part(_visual, "Shadow", &"shadow")
	_shadow.visible = draw_shadow
	_far_legs = _make_part(_visual, "FarLegs", &"far")
	_tail = _make_part(_visual, "Tail", &"tail", {"angles": [], "skip": 0.0})
	_tail_front = false
	_body = _make_part(_visual, "Body", &"body")
	_head_pivot = Node2D.new()
	_head_pivot.name = "HeadPivot"
	_visual.add_child(_head_pivot)
	_ear_lines.clear()
	_ear_fills.clear()
	_ear_lines.append(_make_part(_head_pivot, "EarLineFar", &"ear_line", {"side": -1}))
	_ear_lines.append(_make_part(_head_pivot, "EarLineNear", &"ear_line", {"side": 1}))
	_head_line = _make_part(_head_pivot, "HeadLine", &"head_line")
	_neck = _make_part(_head_pivot, "NeckPatch", &"neck")
	_ear_fills.append(_make_part(_head_pivot, "EarFillFar", &"ear_fill", {"side": -1}))
	_ear_fills.append(_make_part(_head_pivot, "EarFillNear", &"ear_fill", {"side": 1}))
	_head = _make_part(_head_pivot, "Head", &"head")
	_eyes = _make_part(_head_pivot, "Eyes", &"eyes")
	# Pixel pipeline layers (ordinary viewports render every layer).
	visibility_layer = visibility_layer | LAYER_ALL
	_visual.visibility_layer = LAYER_ALL
	_head_pivot.visibility_layer = LAYER_ALL
	for part in [_shadow, _far_legs, _tail]:
		part.visibility_layer = LAYER_BACK
	for part in [_body, _neck]:
		part.visibility_layer = LAYER_BODY
	for part in [_head_line, _head, _eyes] + _ear_lines + _ear_fills:
		part.visibility_layer = LAYER_HEAD
	_built = true

func _make_part(parent: Node, part_name: String, kind: StringName, params: Dictionary = {}) -> Node2D:
	var p: Node2D = CatPartScript.new()
	p.name = part_name
	p.setup(self, kind, params)
	parent.add_child(p)
	return p

func _all_parts() -> Array[Node2D]:
	var out: Array[Node2D] = [_shadow, _far_legs, _tail, _body, _head_line, _neck, _head, _eyes]
	out.append_array(_ear_lines)
	out.append_array(_ear_fills)
	return out

func _layout() -> void:
	var bs: Vector2 = _pal.get("body_scale", Vector2.ONE)
	_hs = float(_pal.get("head_size", 1.0)) * (PIXEL_HEAD_SCALE if pixel_art else 1.0)
	_leg_w = sqrt(bs.x) * float(_pal.get("leg_thickness", 1.0))
	var cw: float = float(_pal.get("cheek_width", 1.0))
	_cheek = 0.07 + (cw - 1.0) * 0.5
	_head_wide = 1.0 + (cw - 1.0) * 0.15
	_fur_style = str(_pal.get("fur_style", "flat"))
	_fur_amp = float(_pal.get("fur_length", 0.0)) if _fur_style != "flat" else 0.0
	_fur_den = maxf(0.1, float(_pal.get("fur_density", 0.36)))
	_fur_jit = clampf(float(_pal.get("fur_jitter", 0.3)), 0.0, 1.0)
	_fur_seed = int(_pal.get("seed", 0))
	var hsz: float = float(_pal.get("haunch_size", 1.0))
	var nf: float = float(_pal.get("neck_fluff", 1.0))
	_rx = BODY_RX * bs.x
	_ry = BODY_RY * bs.y
	_leg_len = LEG_BASE_LEN * float(_pal.get("leg_length", 1.0))
	_head_rx = HEAD_RX * _hs
	_head_ry = HEAD_RY * _hs
	_face_x = 1.8 * _hs
	# Superellipse bottom at the leg x (~0.6 rx) sits ~0.89 ry below center.
	var cy: float = -(_leg_len + _ry * 0.89)
	_body_c = Vector2(0.0, cy)
	_haunch_r = Vector2(7.4 * sqrt(bs.x), 7.6 * bs.y) * hsz
	_haunch_c = Vector2(-_rx * 0.56, cy + _ry * 0.3)
	_chest_r = Vector2(6.6 * sqrt(bs.x), 8.0 * bs.y) * (0.8 + 0.25 * nf)
	_chest_c = Vector2(_rx * 0.7, cy + _ry * 0.12)
	var rear_root := Vector2(_haunch_c.x + 1.4, _haunch_c.y + 1.2)
	var front_root := Vector2(_rx * 0.56, cy + _ry * 0.15)
	# Center the near feet on x = 0.
	var shift: float = -(rear_root.x + front_root.x) * 0.5 - 0.4
	_body_c.x += shift
	_haunch_c.x += shift
	_chest_c.x += shift
	rear_root.x += shift
	front_root.x += shift
	_leg_roots = [rear_root + FAR_LEG_OFFSET, front_root + FAR_LEG_OFFSET, rear_root, front_root]
	_torso_rest = _torso_poly()
	_haunch_rest = _ellipse(_haunch_c, _haunch_r.x, _haunch_r.y, 32)
	_chest_rest = _ellipse(_chest_c, _chest_r.x, _chest_r.y, 32)
	# Torso core (torso + haunch + chest) in rest space, fur edge applied once
	# per genome; frames only transform it (the tuft phase is rest-space anyway).
	_core_rest = _union([_torso_rest, _haunch_rest, _chest_rest])
	if _fur_amp > 0.01:
		_core_rest = _fur_edge(_core_rest, Transform2D.IDENTITY, _body_c, (_rx + _ry) * 0.5, _mask_body, BODY_FLOW.normalized(), 1.0, 101)
	var head_lift: float = (_hs - 1.0) * 4.0
	_head_base = Vector2(_body_c.x + _rx * HEAD_FORWARD, cy - _ry * HEAD_UP - head_lift)
	_tail_root = Vector2(_body_c.x - _rx * 0.8, cy - _ry * 0.5)
	# Sit pivot = bottom of the haunch (it ends on the floor).
	_sit_pivot = Vector2(_haunch_c.x, _haunch_c.y + _haunch_r.y)
	# Head-space part placement.
	_head.position = Vector2.ZERO
	_head_line.position = Vector2.ZERO
	_neck.position = Vector2.ZERO
	var es: float = float(_pal.get("ear_size", 1.0))
	var ear_roots: Array[Vector2] = []
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var pos := Vector2(_face_x * 0.35 + side * _head_rx * 0.6, -_head_ry * 0.74)
		if side < 0.0:
			pos.x -= 0.6 * _hs
		ear_roots.append(pos)
		for ear in [_ear_lines[i], _ear_fills[i]]:
			ear.position = pos
			ear.set_meta("base_rot", side * (0.22 + 0.05 * es))
	# Head-space landmarks shared by both face renderers.
	var hs: float = _hs
	var eye_y: float = -1.3 * hs
	_head_lm = {
		"eye_y": eye_y,
		"eye_near": Vector2(_face_x + (LEGACY_EYE_SPACING[0] if legacy_eye_spacing else EYE_NEAR_X) * hs, eye_y),
		"eye_far": Vector2(_face_x - (LEGACY_EYE_SPACING[1] if legacy_eye_spacing else EYE_FAR_X) * hs, eye_y),
		"eye_center": Vector2(_face_x + 0.25 * hs, eye_y),
		"eye_r": Vector2(2.6, 2.9) * hs,
		"nose": Vector2(_face_x + 0.4 * hs, 1.9 * hs),
		"muzzle": Vector2(_face_x + 0.4 * hs, 4.6 * hs),
		"cheek_x": _head_rx * _head_wide * (1.0 + _cheek),
		"ear_roots": ear_roots,
		"face_x": _face_x,
	}
	# Smooth face lives in an eyes node at the eye row; the pixel face is
	# drawn in head space on the head pivot's whole-pixel grid.
	_eyes.position = Vector2.ZERO if pixel_art else Vector2(0.0, eye_y)

func _torso_poly() -> PackedVector2Array:
	var n: int = 64
	var pts := PackedVector2Array()
	var e: float = 2.0 / BODY_EXP
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var c: float = cos(a)
		var s: float = sin(a)
		var x: float = signf(c) * pow(absf(c), e) * _rx
		var y: float = signf(s) * pow(absf(s), e) * _ry
		if s < 0.0:
			var t: float = clampf(0.5 - 0.5 * x / _rx, 0.0, 1.0)
			y -= -s * (RUMP_LIFT * t * t - SHOULDER_DIP * (1.0 - t))
		pts.append(_body_c + Vector2(x, y))
	return pts

# ---------------------------------------------------------------- animation

func _q(w: float) -> float:
	return roundf(w * WEIGHT_STEPS) / WEIGHT_STEPS

func _process(delta: float) -> void:
	if not _built or _leg_roots.is_empty():
		return
	if animate:
		_t += delta
	var fidget: float = float(genome.get("idle_fidget_rate", 1.0))
	# Pose weights.
	var want_walk: bool = (pose == POSE_WALK or move_speed > 0.05) and pose != POSE_SIT and pose != POSE_SLEEP
	var rate: float = delta * 5.0
	_w_walk = move_toward(_w_walk, 1.0 if want_walk else 0.0, rate)
	_w_sit = move_toward(_w_sit, 1.0 if pose == POSE_SIT else 0.0, rate * 0.8)
	_w_sleep = move_toward(_w_sleep, 1.0 if pose == POSE_SLEEP else 0.0, rate * 0.6)
	var cadence: float = clampf(move_speed if move_speed > 0.05 else 1.0, 0.5, 2.2)
	_phase = fmod(_phase + delta * 10.0 * cadence * float(genome.get("walk_speed_mult", 1.0)) * _w_walk, TAU * 64.0)
	var ws: float = _w_walk * (1.0 - _w_sleep) * (1.0 - _w_sit)

	# Facing: quick squash-turn that never reaches scale 0.
	var target_x: float = -1.0 if facing_left else 1.0
	if delta <= 0.0:
		_facing_x = target_x
	else:
		_facing_x = move_toward(_facing_x, target_x, delta * 14.0)
	var fx: float = _facing_x
	if absf(fx) < 0.2:
		fx = 0.2 * signf(target_x)
	_visual.scale = Vector2(fx, 1.0 + (1.0 - absf(_facing_x)) * 0.08) * _fit

	# Quantized body frame (cached geometry).
	var qw: float = _q(_w_walk)
	var qs: float = _q(_w_sit)
	var ql: float = _q(_w_sleep)
	var pi: int = 0
	if qw * (1.0 - qs) * (1.0 - ql) > 0.0:
		pi = posmod(int(floor(_phase / TAU * float(WALK_PHASES))), WALK_PHASES)
	var key: String = _key(qw, qs, ql, pi)
	if key != _frame_key:
		_frame_key = key
		_frame = _frame_for(key, qw, qs, ql, pi)
		_body.queue_redraw()
		_far_legs.queue_redraw()
		_neck.queue_redraw()
		_shadow.queue_redraw()

	# Breathing: scale about the ground line so paws stay planted.
	var breathe_amp: float = lerpf(0.022, 0.04, _w_sleep) * (1.0 - ws * 0.6)
	var breathe: float = sin(_t * lerpf(2.2, 1.3, _w_sleep))
	if pixel_art and _px > 0.0:
		# Whole-pixel breathing: the back rises by 0 or 1 art pixel (a continuous
		# sub-pixel scale would make the body edge shimmer).
		var body_h: float = maxf(1.0, -(_body_c.y - _ry))
		var up: float = 1.0 if breathe > 0.35 else 0.0
		_body.scale = Vector2(1.0, 1.0 + up * (_px / maxf(0.05, _fit)) / body_h)
	else:
		_body.scale = Vector2(1.0 - breathe * breathe_amp * 0.3, 1.0 + breathe * breathe_amp)

	# Head.
	var head_pos: Vector2 = _frame["head_pos"]
	head_pos.y += -sin(_t * 2.2 + 0.6) * 0.35 * (1.0 - ws) * (1.0 - _w_sleep)
	head_pos.y += breathe * breathe_amp * head_pos.y * 0.5
	if pixel_art and _px > 0.0:
		# Whole-art-pixel bob, no continuous sway (rotation boils pixel edges).
		var step: float = _px / maxf(0.05, _fit)
		# Keep the chin (and its fur spikes) above the floor row.
		if is_nan(_chin_y):
			_chin_y = 0.0
			for q in _head_furred():
				_chin_y = maxf(_chin_y, q.y)
		head_pos.y = minf(head_pos.y, -(_chin_y + step))
		head_pos = (head_pos / step).round() * step
		_head_pivot.position = head_pos
		# No head rotation either: the face stamps stay on the pixel grid.
		_head_pivot.rotation = 0.0
	else:
		_head_pivot.position = head_pos
		_head_pivot.rotation = float(_frame["head_rot"]) + sin(_t * 0.7) * 0.03 * (1.0 - _w_sleep)

	# Tail ripple (throttled).
	_tail_accum += delta
	if _tail_accum >= 1.0 / (PIXEL_TAIL_HZ if pixel_art else TAIL_HZ) or delta <= 0.0:
		_tail_accum = 0.0
		_update_tail(ws, float(_frame["rot"]))
	_tail.position = _frame["tail_pos"]

	# Blink and ear twitch.
	if animate and delta > 0.0:
		_blink_timer -= delta * fidget
		if _blink_timer <= 0.0:
			_blink_left = 0.14
			_blink_timer = _rng.randf_range(2.0, 5.0)
		_blink_left = maxf(0.0, _blink_left - delta)
		_twitch_timer -= delta * fidget
		if _twitch_timer <= 0.0:
			_twitch_left = 0.3
			_twitch_ear = _rng.randi_range(0, 1)
			_twitch_timer = _rng.randf_range(3.0, 8.0)
		_twitch_left = maxf(0.0, _twitch_left - delta)
	var closed: bool = _w_sleep > 0.6
	if closed != _eyes_closed:
		_eyes_closed = closed
		_eyes.queue_redraw()
	if pixel_art:
		var shut: bool = closed or _blink_left > 0.0
		if shut != _pixel_shut:
			_pixel_shut = shut
			_eyes.queue_redraw()
		_eyes.scale = Vector2.ONE
	else:
		_eyes.scale = Vector2(1.0, 0.12 if (_blink_left > 0.0 and not closed) else 1.0)
	for i in range(2):
		var base: float = float(_ear_lines[i].get_meta("base_rot", 0.0))
		var tw: float = 0.0
		if i == _twitch_ear and _twitch_left > 0.0:
			tw = sin((0.3 - _twitch_left) / 0.3 * PI) * 0.34 * (-1.0 if i == 0 else 1.0)
		var r: float = base + tw + (0.14 * _w_sleep * (-1.0 if i == 0 else 1.0))
		_ear_lines[i].rotation = r
		_ear_fills[i].rotation = r

func _key(qw: float, qs: float, ql: float, pi: int) -> String:
	return "%d|%d|%d|%d|%d" % [_genome_hash, int(qw * WEIGHT_STEPS), int(qs * WEIGHT_STEPS), int(ql * WEIGHT_STEPS), pi]

func _update_tail(ws: float, body_rot: float) -> void:
	var front: bool = _w_sleep > 0.5
	if front != _tail_front:
		_tail_front = front
		_visual.move_child(_tail, _body.get_index())
		# Pixel pipeline: a front tail gets its own outline over the body.
		_tail.visibility_layer = LAYER_HEAD if front else LAYER_BACK
	_tail.params["skip"] = 0.34 if front else 0.0
	_tail.params["angles"] = _tail_angles(ws, body_rot, _w_sleep, NAN)
	_tail.queue_redraw()

# wave_sign NAN = live sway; +-1 = every segment at its sway extreme (bounds).
func _tail_angles(ws: float, body_rot: float, w_sleep: float, wave_sign: float) -> Array[float]:
	var sway_deg: float = float(genome.get("tail_sway_deg", 10.0))
	var sway_spd: float = float(genome.get("tail_sway_speed", 2.2))
	# Long tails hook over more (question mark) so the tip stays in frame.
	var tl_extra: float = maxf(0.0, float(_pal.get("tail_length", 1.0)) - 1.0)
	var a0: float = lerpf(-2.2, -1.95, ws) - tl_extra * 0.25
	var curve: float = lerpf(0.36, 0.26, ws) + tl_extra * 0.22
	# Sit keeps the upright hook (follows the tilted body). Sleep: the tail wraps
	# forward along the floor in FRONT of the loaf (drawn after the body, with its
	# root portion skipped so it seems to come around from behind the rump).
	a0 = lerpf(a0, 2.55, w_sleep)
	curve = lerpf(curve, -0.56, w_sleep)
	var w_low: float = w_sleep
	var amp: float = deg_to_rad(sway_deg) * lerpf(1.0, 0.55, ws) * lerpf(1.0, 0.3, w_low)
	var spd: float = sway_spd * lerpf(1.0, 1.8, ws)
	var angles: Array[float] = []
	var acc: float = a0 + body_rot
	for i in range(TAIL_SEGMENTS):
		var s: float = sin(_t * spd - float(i) * 0.7) if is_nan(wave_sign) else wave_sign
		angles.append(acc + s * amp * TAIL_FALLOFF[i] * 0.5)
		acc += curve
	return angles

# ---------------------------------------------------------------- frame geometry

func _frame_for(key: String, qw: float, qs: float, ql: float, pi: int) -> Dictionary:
	if _frame_cache.has(key):
		return _frame_cache[key]
	if _frame_cache.size() >= CACHE_MAX:
		_frame_cache.clear()
	var f: Dictionary = _build_frame(qw, qs, ql, pi)
	_frame_cache[key] = f
	return f

func cache_size() -> int:
	return _frame_cache.size()

# bounds_only: skip booleans/fur/draw lists, return the posed raw shapes in
# "pts" (fit guard).
func _build_frame(wk: float, wsit: float, wsl: float, pi: int, bounds_only: bool = false) -> Dictionary:
	var ws: float = wk * (1.0 - wsl) * (1.0 - wsit)
	var ph: float = (float(pi) + 0.5) / float(WALK_PHASES) * TAU
	var bob: float = -absf(sin(ph)) * 0.9 * ws
	var rot: float = SIT_ROT * wsit * (1.0 - wsl)
	var sit_drop: float = -0.3 - _sit_pivot.y
	var sleep_drop: float = -0.5 - (_body_c.y + _ry)
	var drop: float = sit_drop * wsit * (1.0 - wsl) + sleep_drop * wsl + bob
	var off := Vector2(1.5 * wsit * (1.0 - wsl), drop)
	var xf := Transform2D(rot, _sit_pivot - _sit_pivot.rotated(rot) + off)

	var torso: PackedVector2Array = xf * _torso_rest
	var haunch: PackedVector2Array = xf * _haunch_rest
	var chest: PackedVector2Array = xf * _chest_rest
	# Sleep: the loaf squashes a little wider/lower.
	var legs: Array[PackedVector2Array] = []
	var paws: Array[Vector2] = []
	var roots: Array[Vector2] = []
	var wsc: float = _leg_w
	for i in range(4):
		var far: bool = i < 2
		var front: bool = i % 2 == 1
		var root_rest: Vector2 = _leg_roots[i]
		var root: Vector2 = xf * root_rest
		var gy: float = FAR_LEG_OFFSET.y if far else 0.0
		var phi: float = ph if (i == 3 or i == 0) else ph + PI
		var stand := Vector2(root_rest.x + 0.4, gy)
		var walkp := Vector2(root_rest.x + 0.4 - sin(phi) * WALK_STRIDE, gy - maxf(0.0, -cos(phi)) * WALK_LIFT)
		var p: Vector2 = stand.lerp(walkp, ws)
		var sit_t := Vector2(root.x + (0.9 if front else 5.2), gy)
		var sleep_t := Vector2(root.x + (6.2 if front else 4.4), gy)
		p = p.lerp(sit_t, wsit * (1.0 - wsl))
		p = p.lerp(sleep_t, wsl)
		p.y = minf(p.y, gy)
		var idx: int = 1 if front else 0
		var wr: float = LEG_ROOT_W[idx] * wsc
		var wa: float = LEG_ANKLE_W[idx] * wsc
		legs.append(_leg_poly(root, p, wr, wa, wa + PAW_EXTRA_W, bounds_only))
		paws.append(p)
		roots.append(root)

	var f: Dictionary = {}
	if bounds_only:
		var all_pts := PackedVector2Array()
		for poly in [torso, haunch, chest, legs[0], legs[1], legs[2], legs[3]]:
			all_pts.append_array(poly)
		f["pts"] = all_pts
	# The furred core is both the pattern clip and the silhouette's body part,
	# so markings run into the tufts and belly fur hangs over the leg tops.
	var core: PackedVector2Array = torso if bounds_only else xf * _core_rest
	var union: PackedVector2Array = core if bounds_only else _union([core, legs[2], legs[3]])

	f["rot"] = rot
	f["xf"] = xf
	f["tail_pos"] = xf * _tail_root
	var head_pos: Vector2 = xf * _head_base
	head_pos += Vector2(-0.6, -1.2) * wsit * (1.0 - wsl) + Vector2(2.4, 4.2) * wsl
	head_pos.y += sin(ph * 2.0 + 0.9) * 0.3 * ws
	f["head_pos"] = head_pos
	var head_rot: float = rot * 0.25 + 0.1 * wsl
	f["head_rot"] = head_rot
	if bounds_only:
		return f
	f["paws"] = paws
	f["roots"] = roots
	f["core"] = core
	f["union"] = union
	f["far"] = _far_list(legs, paws, roots, core)
	f["body"] = _body_list(xf, union, core, legs, paws, roots, wsl)
	f["neck"] = _neck_list(chest, head_pos, head_rot)
	f["shadow_rx"] = _rx * lerpf(1.25, 1.4, wsl)
	return f

func _leg_poly(root: Vector2, paw: Vector2, wr: float, wa: float, pw: float, raw: bool = false) -> PackedVector2Array:
	var ankle := paw + Vector2(0.0, -PAW_H * 0.6)
	var d: Vector2 = ankle - root
	if d.length() < 0.6:
		d = Vector2(0.0, 0.6)
	var dir: Vector2 = d.normalized()
	var n := Vector2(-dir.y, dir.x)
	var cap := PackedVector2Array()
	var base: float = n.angle()
	for k in range(9):
		var a: float = base + PI * float(k) / 8.0
		cap.append(root + Vector2(cos(a), sin(a)) * wr * 0.5)
	cap.append(ankle - n * wa * 0.5)
	cap.append(ankle + n * wa * 0.5)
	if raw:
		cap.append_array(_paw_poly(paw, pw))
		return cap
	return _union([cap, _paw_poly(paw, pw)])

func _paw_poly(paw: Vector2, pw: float) -> PackedVector2Array:
	# Oval with a flat bottom resting on paw.y.
	var c := Vector2(paw.x + 0.5, paw.y - PAW_H * 0.5)
	var rx: float = pw * 0.5
	var ryt: float = PAW_H * 0.6
	var ryb: float = paw.y - c.y
	var pts := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		var s: float = sin(a)
		var y: float = c.y + (pow(s, 0.3) * ryb if s > 0.0 else s * ryt)
		pts.append(Vector2(c.x + cos(a) * rx, y))
	return pts

func _union(polys: Array) -> PackedVector2Array:
	var acc: Array[PackedVector2Array] = []
	for item in polys:
		var cur: PackedVector2Array = item
		if cur.size() < 3:
			continue
		var keep: Array[PackedVector2Array] = []
		for a in acc:
			var outers: Array[PackedVector2Array] = _outers(Geometry2D.merge_polygons(a, cur))
			if outers.size() == 1:
				cur = outers[0]
			else:
				keep.append(a)
		keep.append(cur)
		acc = keep
	var best := PackedVector2Array()
	var best_area: float = -1.0
	for a in acc:
		var ar: float = absf(_area(a))
		if ar > best_area:
			best_area = ar
			best = a
	return best

func _outers(res: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if res.is_empty():
		return out
	var big: PackedVector2Array = res[0]
	for r in res:
		if absf(_area(r)) > absf(_area(big)):
			big = r
	var cw: bool = Geometry2D.is_polygon_clockwise(big)
	for r in res:
		if Geometry2D.is_polygon_clockwise(r) == cw:
			out.append(r)
	return out

func _area(p: PackedVector2Array) -> float:
	var s: float = 0.0
	var n: int = p.size()
	for i in range(n):
		var a: Vector2 = p[i]
		var b: Vector2 = p[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

# Draw lists: [0, polygon, color] or [1, polyline, color, width].

func _add(list: Array, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() < 3 or col.a <= 0.0:
		return
	if _fur_amp > 0.01:
		# Furred booleans can leave slivers the canvas triangulator rejects:
		# clean them here (draw lists are cached, so this runs once per frame key).
		for q in _drawable(poly):
			list.append([0, q, col])
		return
	list.append([0, poly, col])

# Returns poly (cleaned) if the canvas can triangulate it, else convex pieces.
func _drawable(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not Geometry2D.triangulate_polygon(poly).is_empty():
		out.append(poly)
		return out
	var clean: PackedVector2Array = _clean_poly(poly, 0.04)
	if clean.size() >= 3 and not Geometry2D.triangulate_polygon(clean).is_empty():
		out.append(clean)
		return out
	clean = _clean_poly(poly, 0.18)
	if clean.size() >= 3 and not Geometry2D.triangulate_polygon(clean).is_empty():
		out.append(clean)
		return out
	for piece in Geometry2D.decompose_polygon_in_convex(clean):
		if piece.size() >= 3:
			out.append(piece)
	return out

# Drops near-duplicate and collinear points.
func _clean_poly(poly: PackedVector2Array, min_d: float) -> PackedVector2Array:
	var tmp := PackedVector2Array()
	for q in poly:
		if tmp.is_empty() or tmp[tmp.size() - 1].distance_to(q) > min_d:
			tmp.append(q)
	if tmp.size() > 3 and tmp[0].distance_to(tmp[tmp.size() - 1]) <= min_d:
		tmp.remove_at(tmp.size() - 1)
	var out := PackedVector2Array()
	var n: int = tmp.size()
	for i in range(n):
		var a: Vector2 = tmp[(i - 1 + n) % n]
		var b: Vector2 = tmp[i]
		var c: Vector2 = tmp[(i + 1) % n]
		if absf((b - a).cross(c - b)) > 0.0005:
			out.append(b)
	return out

func _add_clip(list: Array, shape: PackedVector2Array, clip_to: PackedVector2Array, col: Color) -> void:
	if shape.size() < 3 or clip_to.size() < 3:
		return
	for p in _outers(Geometry2D.intersect_polygons(shape, clip_to)):
		_add(list, p, col)

func _add_minus(list: Array, shape: PackedVector2Array, minus: PackedVector2Array, col: Color) -> void:
	if shape.size() < 3:
		return
	for p in _outers(Geometry2D.clip_polygons(shape, minus)):
		_add(list, p, col)

func _line(list: Array, pts: PackedVector2Array, col: Color, w: float) -> void:
	list.append([1, pts, col, w])

func _visible_leg(leg: PackedVector2Array, core: PackedVector2Array) -> Array[PackedVector2Array]:
	return _outers(Geometry2D.clip_polygons(leg, core))

func _chest_col() -> Color:
	match str(_pal["pattern"]):
		"solid":
			return _pal["primary"]
		_:
			return _pal["belly"]

func _shade_col(a: float) -> Color:
	# Lighter coats need less shade or the outline tint reads as grey smudges.
	var lum: float = (_pal["primary"] as Color).get_luminance()
	return Color(_pal["outline"], a * lerpf(1.0, 0.55, clampf((lum - 0.4) / 0.5, 0.0, 1.0)))

func _leg_colors(idx: int) -> Array:
	# [upper color, sock color or null, sock height]
	var primary: Color = _pal["primary"]
	match str(_pal["pattern"]):
		"stripes":
			return [primary, _pal["belly"], 3.6]
		"tuxedo":
			return [primary, _pal["belly"], 4.4]
		"points":
			return [primary.lerp(_pal["accent"], 0.35), primary.lerp(_pal["accent"], 0.8), 5.5]
		"patches":
			var r := _part_rng(31 + idx)
			if r.randf() < 0.3:
				return [_pal["stripe"] if r.randf() < 0.6 else _pal["accent"], primary, 4.0]
			return [primary, null, 0.0]
	return [primary, null, 0.0]

# Pixel tone ramp: 0 = base, -1 = shade, -2 = deep shade, +1 = highlight.
# Opaque colours only (the pixel renderer never alpha-blends inside the cat).
# Shades lean toward the palette outline hue so they stay warm.
func _tone(c: Color, step: int) -> Color:
	if step == 0:
		return Color(c, 1.0)
	var outline: Color = _pal.get("outline", Color("#3A2620"))
	if step < 0:
		var lum: float = c.get_luminance()
		var k: float = lerpf(0.2, 0.13, clampf((lum - 0.3) / 0.6, 0.0, 1.0)) * float(-step)
		if lum < 0.22:
			# Dark coats: shade by darkening less, or it sinks into the outline.
			return Color(c.darkened(0.16 * float(-step)), 1.0)
		return Color(c.lerp(outline, k), 1.0)
	var hl: Color = Color(1.0, 0.98, 0.93)
	var amt: float = 0.1 * float(step) if c.get_luminance() > 0.25 else 0.14 * float(step)
	return Color(c.lerp(hl, amt), 1.0)

func _far_list(legs: Array[PackedVector2Array], paws: Array[Vector2], _roots: Array[Vector2], _core: PackedVector2Array) -> Array:
	var list: Array = []
	if pixel_art:
		# Fills only; the mask outline also draws the far-leg / body edge.
		for i in range(2):
			var lc: Array = _leg_colors(i)
			_add(list, legs[i], _tone(lc[0], -1))
			if lc[1] != null:
				var band := _rect_poly(paws[i].y - float(lc[2]), paws[i].y + 3.0, paws[i].x - 12.0, paws[i].x + 12.0)
				_add_clip(list, band, legs[i], _tone(lc[1], -1))
		return list
	var outline: Color = _pal["outline"]
	for i in range(2):
		var leg: PackedVector2Array = legs[i]
		var lc: Array = _leg_colors(i)
		var upper: Color = (lc[0] as Color).darkened(far_leg_darken)
		_add(list, _outline_of(leg, _ow), outline)
		_add(list, leg, upper)
		if lc[1] != null:
			var band := _rect_poly(paws[i].y - float(lc[2]), paws[i].y + 3.0, paws[i].x - 12.0, paws[i].x + 12.0)
			_add_clip(list, band, leg, (lc[1] as Color).darkened(far_leg_darken))
		_add_toes(list, paws[i], LEG_ANKLE_W[i % 2] * _leg_w + PAW_EXTRA_W, Color(outline, 0.4))
	return list

func _rect_poly(y0: float, y1: float, x0: float, x1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

func _add_toes(list: Array, paw: Vector2, pw: float, col: Color) -> void:
	for k in range(2):
		var tx: float = paw.x + 0.5 + (float(k) - 0.5) * pw * 0.3
		_line(list, PackedVector2Array([Vector2(tx, paw.y - 1.4), Vector2(tx, paw.y - 0.2)]), col, 0.4)

func _body_list(xf: Transform2D, union: PackedVector2Array, core: PackedVector2Array, legs: Array[PackedVector2Array], paws: Array[Vector2], roots: Array[Vector2], _wsl: float) -> Array:
	if pixel_art:
		return _body_list_pixel(xf, union, core, legs, paws, roots)
	var list: Array = []
	var primary: Color = _pal["primary"]
	var outline: Color = _pal["outline"]
	var belly: Color = _pal["belly"]
	var stripe: Color = _pal["stripe"]
	var accent: Color = _pal["accent"]
	var pattern: String = _pal["pattern"]
	var cx: float = _body_c.x
	var cy: float = _body_c.y
	_add(list, _outline_of(union, _ow), outline)
	_add(list, union, primary)
	var r := _part_rng(11)

	# Near leg base colors (patches/points) and socks.
	for i in [2, 3]:
		var lc: Array = _leg_colors(i)
		var vis: Array[PackedVector2Array] = _visible_leg(legs[i], core)
		if lc[0] != primary:
			for v in vis:
				_add(list, v, lc[0])
		if lc[1] != null:
			var band := _rect_poly(paws[i].y - float(lc[2]), paws[i].y + 3.0, paws[i].x - 12.0, paws[i].x + 12.0)
			for v in vis:
				_add_clip(list, band, v, lc[1])

	# Coat markings (rest-space shapes, posed with xf), clipped to the torso core.
	match pattern:
		"stripes":
			var count: int = 9
			for k in range(count):
				var t: float = float(k) / float(count - 1)
				var x: float = cx - _rx * 0.95 + t * _rx * 1.6 + r.randf_range(-0.5, 0.5)
				var w: float = lerpf(1.7, 1.3, t)
				var depth: float = cy + _ry * r.randf_range(0.0, 0.45)
				var lean: float = -1.4
				var band := PackedVector2Array([
					Vector2(x - w * 0.5, cy - _ry - 4.0), Vector2(x + w * 0.5, cy - _ry - 4.0),
					Vector2(x + w * 0.4 + lean * 0.5, cy - _ry * 0.2), Vector2(x + lean, depth),
					Vector2(x - w * 0.4 + lean * 0.5, cy - _ry * 0.2)])
				_add_clip(list, xf * band, core, stripe)
			# Near leg rings.
			for i in [2, 3]:
				for v in _visible_leg(legs[i], core):
					for k in range(2):
						var y: float = roots[i].y + (_leg_len * 0.35) + float(k) * 2.4
						var ring := PackedVector2Array([Vector2(paws[i].x - 8, y), Vector2(paws[i].x + 8, y - 0.8), Vector2(paws[i].x + 8, y + 0.3), Vector2(paws[i].x - 8, y + 1.1)])
						if y < paws[i].y - 4.0:
							_add_clip(list, ring, v, stripe)
			_add_clip(list, xf * _ellipse(Vector2(cx + _rx * 0.2, cy + _ry * 1.3), _rx * 0.8, _ry * 0.62, 28), core, belly)
		"tuxedo":
			_add_clip(list, xf * _ellipse(_chest_c + Vector2(0.4, 1.8), _chest_r.x * 1.05, _chest_r.y * 1.05, 28), core, belly)
		"patches":
			var cols: Array[Color] = [stripe, accent, stripe, accent]
			for k in range(4):
				var c := Vector2(cx + r.randf_range(-0.95, 0.45) * _rx, cy + r.randf_range(-1.0, -0.15) * _ry)
				var rad: float = r.randf_range(3.8, 6.0) * sqrt(_rx / BODY_RX)
				var blob: PackedVector2Array = _union([_ellipse(c, rad * 1.3, rad, 20), _ellipse(c + Vector2(rad * 0.9, rad * 0.45), rad * 0.75, rad * 0.65, 16)])
				_add_clip(list, xf * blob, core, cols[k])
			_add_clip(list, xf * _ellipse(Vector2(cx + _rx * 0.1, cy + _ry * 1.0), _rx * 0.85, _ry * 0.5, 28), core, belly)
		"points":
			pass
		"wrinkles":
			for k in range(3):
				var c := Vector2(_chest_c.x - 3.0, cy - _ry * 0.15 + float(k) * 2.0)
				_line(list, xf * _arc_pts(c, 4.2 - float(k) * 0.6, -2.4, -1.2, 8), stripe, 0.55)
			for k in range(2):
				var c := Vector2(_haunch_c.x + 1.0, _haunch_c.y - 2.0 + float(k) * 2.0)
				_line(list, xf * _arc_pts(c, 3.6 - float(k) * 0.6, -2.0, -0.9, 8), stripe, 0.5)
	# Chest bib (matches the neck patch color).
	if pattern != "solid":
		_add_clip(list, xf * _ellipse(_chest_c + Vector2(0.4, 0.4), _chest_r.x + 0.5, _chest_r.y + 0.6, 28), core, _chest_col())

	# Volume: soft light on the back, warm shade on the underside.
	for k in range(2):
		_add_clip(list, xf * _ellipse(Vector2(cx - _rx * 0.15, cy - _ry * 1.0), _rx * (0.8 - 0.15 * float(k)), _ry * (0.42 - 0.08 * float(k)), 28), core, Color(1.0, 0.97, 0.9, 0.04))
	_add_clip(list, xf * _ellipse(Vector2(cx - _rx * 0.25, cy + _ry * 1.15), _rx * 0.85, _ry * 0.32, 28), core, _shade_col(0.07))

	# Internal limb shading (fill only, no lines).
	# Haunch rim: the front/bottom edge of the thigh reads as a soft crease.
	var haunch: PackedVector2Array = xf * _haunch_rest
	var haunch_in: PackedVector2Array = xf * _ellipse(_haunch_c + Vector2(-0.8, -0.7), _haunch_r.x, _haunch_r.y, 32)
	for p in _outers(Geometry2D.clip_polygons(haunch, haunch_in)):
		for q in _outers(Geometry2D.intersect_polygons(p, xf * _rect_poly(_haunch_c.y - _haunch_r.y * 0.5, _haunch_c.y + _haunch_r.y * 0.8, _haunch_c.x + _haunch_r.x * 0.2, _haunch_c.x + 20.0))):
			_add(list, q, _shade_col(limb_shade_alpha * 0.6))
	for i in [2, 3]:
		var vis: Array[PackedVector2Array] = _visible_leg(legs[i], core)
		# Belly overhang shadow on the top of the visible leg.
		var core_down: PackedVector2Array = Transform2D(0.0, Vector2(0.0, 1.3)) * core
		for v in vis:
			_add_clip(list, core_down, v, _shade_col(limb_shade_alpha))
		# Back edge of the leg slightly darker.
		var shifted: PackedVector2Array = Transform2D(0.0, Vector2(-1.1, 0.0)) * legs[i]
		for v in vis:
			for p in _outers(Geometry2D.clip_polygons(v, shifted)):
				_add(list, p, _shade_col(limb_shade_alpha * 0.8))
		_add_toes(list, paws[i], LEG_ANKLE_W[i % 2] * _leg_w + PAW_EXTRA_W, _shade_col(0.55))
	return list

# Pixel body: opaque fills and cel-shade shapes, drawn base -> shade -> marks.
# Same anatomy and pattern regions as the smooth list; no outline polygons,
# no alpha (the pipeline outlines the rasterized mask).
func _body_list_pixel(xf: Transform2D, union: PackedVector2Array, core: PackedVector2Array, legs: Array[PackedVector2Array], paws: Array[Vector2], roots: Array[Vector2]) -> Array:
	var list: Array = []
	var primary: Color = _pal["primary"]
	var belly: Color = _pal["belly"]
	var stripe: Color = _pal["stripe"]
	var accent: Color = _pal["accent"]
	var pattern: String = _pal["pattern"]
	var cx: float = _body_c.x
	var cy: float = _body_c.y
	var step: float = _px / maxf(0.05, _fit)
	# Fur spikes never poke through the floor (cached per frame key).
	var above: PackedVector2Array = _rect_poly(-200.0, 0.0, -200.0, 200.0)
	var floor_cut: PackedVector2Array = _clip_first(union, above)
	if floor_cut.size() >= 3:
		union = floor_cut
	floor_cut = _clip_first(core, above)
	if floor_cut.size() >= 3:
		core = floor_cut
	_add(list, union, primary)
	var r := _part_rng(11)

	# Back highlight strip: the top rim of the torso between shoulder and rump.
	var rim_w: float = maxf(step, 1.4)
	var lowered: PackedVector2Array = Transform2D(0.0, Vector2(0.0, rim_w)) * core
	var back_zone: PackedVector2Array = xf * _ellipse(Vector2(cx - _rx * 0.12, cy - _ry * 0.95), _rx * 0.72, _ry * 0.5, 28)
	for rim in _outers(Geometry2D.clip_polygons(core, lowered)):
		_add_clip(list, rim, back_zone, _tone(primary, 1))
	# Haunch crease (shade tone), under the markings.
	var haunch: PackedVector2Array = xf * _haunch_rest
	var haunch_in: PackedVector2Array = xf * _ellipse(_haunch_c + Vector2(-step, -step * 0.6), _haunch_r.x, _haunch_r.y, 32)
	for p in _outers(Geometry2D.clip_polygons(haunch, haunch_in)):
		for q in _outers(Geometry2D.intersect_polygons(p, xf * _rect_poly(_haunch_c.y - _haunch_r.y * 0.45, _haunch_c.y + _haunch_r.y * 0.8, _haunch_c.x + _haunch_r.x * 0.25, _haunch_c.x + 20.0))):
			_add(list, q, _tone(primary, -1))

	# Near legs: base colours, socks, belly-overhang shade band, back edge.
	for i in [2, 3]:
		var lc: Array = _leg_colors(i)
		var vis: Array[PackedVector2Array] = _visible_leg(legs[i], core)
		if lc[0] != primary:
			for v in vis:
				_add(list, v, lc[0])
		var shifted: PackedVector2Array = Transform2D(0.0, Vector2(-step, 0.0)) * legs[i]
		for v in vis:
			for p in _outers(Geometry2D.clip_polygons(v, shifted)):
				_add(list, p, _tone(lc[0], -1))
		if lc[1] != null:
			var band := _rect_poly(paws[i].y - float(lc[2]), paws[i].y + 3.0, paws[i].x - 12.0, paws[i].x + 12.0)
			for v in vis:
				_add_clip(list, band, v, lc[1])
		var core_down: PackedVector2Array = Transform2D(0.0, Vector2(0.0, step * 1.05)) * core
		for v in vis:
			_add_clip(list, core_down, v, _tone(lc[0], -1))

	# Coat markings (rest-space regions shared with the smooth renderer).
	match pattern:
		"stripes":
			var count: int = 9
			var wmin: float = PIXEL_STRIPE_MIN * step
			for k in range(count):
				var t: float = float(k) / float(count - 1)
				var x: float = cx - _rx * 0.95 + t * _rx * 1.6 + r.randf_range(-0.5, 0.5)
				var w: float = maxf(lerpf(1.7, 1.3, t), wmin)
				var depth: float = cy + _ry * r.randf_range(0.0, 0.45)
				var lean: float = -1.4
				var band := PackedVector2Array([
					Vector2(x - w * 0.5, cy - _ry - 4.0), Vector2(x + w * 0.5, cy - _ry - 4.0),
					Vector2(x + w * 0.45 + lean * 0.5, cy - _ry * 0.2), Vector2(x + lean, depth),
					Vector2(x - w * 0.45 + lean * 0.5, cy - _ry * 0.2)])
				_add_clip(list, xf * band, core, stripe)
			for i in [2, 3]:
				for v in _visible_leg(legs[i], core):
					var y: float = roots[i].y + (_leg_len * 0.35)
					var ring := _rect_poly(y, y + step, paws[i].x - 8.0, paws[i].x + 8.0)
					if y < paws[i].y - 4.0:
						_add_clip(list, ring, v, stripe)
			_add_clip(list, xf * _ellipse(Vector2(cx + _rx * 0.2, cy + _ry * 1.3), _rx * 0.8, _ry * 0.62, 28), core, belly)
		"tuxedo":
			_add_clip(list, xf * _ellipse(_chest_c + Vector2(0.4, 1.8), _chest_r.x * 1.05, _chest_r.y * 1.05, 28), core, belly)
		"patches":
			var cols: Array[Color] = [stripe, accent, stripe, accent]
			for k in range(4):
				var c := Vector2(cx + r.randf_range(-0.95, 0.45) * _rx, cy + r.randf_range(-1.0, -0.15) * _ry)
				var rad: float = r.randf_range(3.8, 6.0) * sqrt(_rx / BODY_RX)
				var blob: PackedVector2Array = _union([_ellipse(c, rad * 1.3, rad, 20), _ellipse(c + Vector2(rad * 0.9, rad * 0.45), rad * 0.75, rad * 0.65, 16)])
				_add_clip(list, xf * blob, core, cols[k])
			_add_clip(list, xf * _ellipse(Vector2(cx + _rx * 0.1, cy + _ry * 1.0), _rx * 0.85, _ry * 0.5, 28), core, belly)
		"wrinkles":
			var wc: Color = _tone(primary, -1)
			for k in range(2):
				var c := Vector2(_chest_c.x - 3.0, cy - _ry * 0.15 + float(k) * 2.6)
				_line(list, xf * _arc_pts(c, 4.2 - float(k) * 0.6, -2.4, -1.2, 6), wc, 1.0)
			var c2 := Vector2(_haunch_c.x + 1.0, _haunch_c.y - 2.0)
			_line(list, xf * _arc_pts(c2, 3.6, -2.0, -0.9, 6), wc, 1.0)
	if pattern != "solid":
		_add_clip(list, xf * _ellipse(_chest_c + Vector2(0.4, 0.4), _chest_r.x + 0.5, _chest_r.y + 0.6, 28), core, _chest_col())
	# Paws: one toe split per near paw at higher densities (noise at 56px).
	if _pixel_density() > 70.0:
		for i in [2, 3]:
			var lc: Array = _leg_colors(i)
			var col: Color = _tone(lc[1] if lc[1] != null else lc[0], -1)
			var tx: float = paws[i].x + 0.5
			_line(list, PackedVector2Array([Vector2(tx, paws[i].y - step * 1.5), Vector2(tx, paws[i].y - step * 0.5)]), col, 1.0)
	return list

# Effective art pixels across the 76.8-unit window (after the fit shrink).
func _pixel_density() -> float:
	if _px <= 0.0:
		return 999.0
	return 76.8 * _fit / _px

func _clip_first(shape: PackedVector2Array, clip_to: PackedVector2Array) -> PackedVector2Array:
	var res: Array[PackedVector2Array] = _outers(Geometry2D.intersect_polygons(shape, clip_to))
	return res[0] if not res.is_empty() else PackedVector2Array()

func _arc_pts(c: Vector2, rad: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a: float = lerpf(a0, a1, float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts

func _neck_list(chest: PackedVector2Array, head_pos: Vector2, head_rot: float) -> Array:
	# Chest-colored patch over the head outline where the chin sits on the chest.
	var list: Array = []
	if pixel_art:
		return list   # pixel: the mask outline gives a single 1px chin line
	var shrunk: Array = Geometry2D.offset_polygon(chest, -1.0)
	if shrunk.is_empty():
		return list
	var to_head: Transform2D = Transform2D(head_rot, head_pos).affine_inverse()
	var chest_h: PackedVector2Array = to_head * (shrunk[0] as PackedVector2Array)
	var head_out: PackedVector2Array = _outline_of(_head_furred(), _ow + 0.3)
	_add_clip(list, chest_h, head_out, _chest_col())
	return list

# ---------------------------------------------------------------- drawing

func _draw_part(ci: Node2D, kind: StringName, params: Dictionary) -> void:
	if _pal.is_empty():
		return
	match kind:
		&"shadow":
			_draw_shadow(ci)
		&"far":
			_draw_list(ci, _frame.get("far", []))
		&"body":
			_draw_list(ci, _frame.get("body", []))
		&"neck":
			_draw_list(ci, _frame.get("neck", []))
		&"head_line":
			_draw_list(ci, _head_list("line"))
		&"head":
			_draw_list(ci, _head_list("fill"))
		&"eyes":
			_draw_eyes(ci)
		&"ear_line":
			_draw_list(ci, _head_list("ear_line_%d" % int(params.get("side", 1))))
		&"ear_fill":
			_draw_list(ci, _head_list("ear_fill_%d" % int(params.get("side", 1))))
		&"tail":
			_draw_tail(ci, params.get("angles", []), float(params.get("skip", 0.0)))

func _draw_list(ci: Node2D, list: Array) -> void:
	for e in list:
		if int(e[0]) == 0:
			ci.draw_colored_polygon(e[1], e[2])
		else:
			if pixel_art:
				ci.draw_polyline(e[1], e[2], -1.0, false)
			else:
				ci.draw_polyline(e[1], e[2], float(e[3]), not feature_ids)

func _ellipse(c: Vector2, rx: float, ry: float, n: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _outline_of(poly: PackedVector2Array, w: float = 1.0) -> PackedVector2Array:
	var res: Array = Geometry2D.offset_polygon(poly, w, Geometry2D.JOIN_ROUND)
	if res.is_empty():
		return poly
	var best: PackedVector2Array = res[0]
	for r in res:
		if absf(_area(r)) > absf(_area(best)):
			best = r
	return best

func _part_rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(_pal.get("seed", 0)) * 7919 + salt
	return r

func _draw_shadow(ci: Node2D) -> void:
	var rx: float = float(_frame.get("shadow_rx", _rx * 1.25))
	if pixel_art:
		# One flat, faint ellipse (below the pipeline's mask threshold, so it is
		# composited as-is and never outlined).
		ci.draw_colored_polygon(_ellipse(Vector2(-0.5, 0.3), rx, 2.2, 28), Color(0.25, 0.14, 0.1, 0.22))
		return
	ci.draw_colored_polygon(_ellipse(Vector2(-0.5, 0.3), rx, 2.6, 28), Color(0.25, 0.14, 0.1, 0.16))
	ci.draw_colored_polygon(_ellipse(Vector2(-0.5, 0.3), rx * 0.78, 1.8, 24), Color(0.25, 0.14, 0.1, 0.12))

# ---------------------------------------------------------------- head

func _head_poly() -> PackedVector2Array:
	var rx: float = _head_rx * _head_wide
	var ry: float = _head_ry
	var pts := PackedVector2Array()
	var n: int = 56
	var e: float = 2.0 / HEAD_EXP
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var c: float = cos(a)
		var s: float = sin(a)
		var x: float = signf(c) * pow(absf(c), e) * rx
		var y: float = signf(s) * pow(absf(s), e) * ry
		# Full cheeks: wider in the lower half, slightly narrower forehead.
		x *= 1.0 + _cheek * maxf(0.0, s) - 0.05 * maxf(0.0, -s)
		pts.append(Vector2(x, y))
	return pts

# Head outline shape with the fur edge applied (cached per genome).
func _head_furred() -> PackedVector2Array:
	if _head_shape.is_empty():
		_head_shape = _head_poly()
		if _fur_amp > 0.01:
			_head_shape = _fur_edge(_head_shape, Transform2D.IDENTITY, Vector2.ZERO, (_head_rx + _head_ry) * 0.5, _mask_head, HEAD_FLOW.normalized(), 1.0, 202)
	return _head_shape

func _head_list(which: String) -> Array:
	# Pixel fills sit on the snoot axis, which lives on the art grid: rebuild
	# when the grid step changed since they were built (e.g. after the fit).
	if pixel_art and not _head_lists.is_empty() and not is_equal_approx(float(_head_lists.get("snoot_step", -1.0)), _pixel_step()):
		_head_lists.clear()
	if _head_lists.is_empty():
		_build_head_lists()
	return _head_lists.get(which, [])

func _build_head_lists() -> void:
	_snoot_dx = NAN
	_head_lists["snoot_step"] = _pixel_step()
	var head: PackedVector2Array = _head_furred()
	var outline: Color = _pal["outline"]
	var line: Array = []
	if not pixel_art:
		_add(line, _outline_of(head, _ow), FID_OUTLINE if feature_ids else outline)
	_head_lists["line"] = line
	_head_lists["fill"] = _head_fill_list_pixel(head) if pixel_art else _head_fill_list(head)
	for side in [-1, 1]:
		var l: Array = []
		var f: Array = []
		_ear_lists(side, l, f)
		_head_lists["ear_line_%d" % side] = l
		_head_lists["ear_fill_%d" % side] = f

func _head_fill_list(head: PackedVector2Array) -> Array:
	var list: Array = []
	var primary: Color = _pal["primary"]
	var outline: Color = _pal["outline"]
	var belly: Color = _pal["belly"]
	var stripe: Color = _pal["stripe"]
	var accent: Color = _pal["accent"]
	var pattern: String = _pal["pattern"]
	var hs: float = _hs
	var fx: float = _face_x
	var ry: float = _head_ry
	var rx: float = _head_rx
	_add(list, head, primary)
	var r := _part_rng(23)
	match pattern:
		"stripes":
			# Forehead "M" stripes.
			for k in range(3):
				var x: float = fx + (float(k) - 1.0) * 2.6 * hs
				var long: float = 0.4 if k == 1 else 0.55
				_add_clip(list, PackedVector2Array([Vector2(x - 1.0 * hs, -ry - 2.0), Vector2(x + 1.0 * hs, -ry - 2.0), Vector2(x, -ry * long)]), head, stripe)
			# Cheek stripes from both edges.
			for side in [-1.0, 1.0]:
				for k in range(2):
					var y: float = (0.4 + float(k) * 2.4) * hs
					var edge: float = side * rx * 1.3
					var tip: float = fx + side * rx * (0.72 if side < 0.0 else 0.8)
					_add_clip(list, PackedVector2Array([Vector2(edge, y - 0.8 * hs), Vector2(edge, y + 0.8 * hs), Vector2(tip, y + 0.2 * hs)]), head, stripe)
			_add_clip(list, _muzzle_poly(1.0), head, belly)
		"tuxedo":
			_add_clip(list, _muzzle_poly(1.12), head, belly)
			_add_clip(list, PackedVector2Array([Vector2(fx - 1.9 * hs, ry * 0.25), Vector2(fx - 0.2 * hs, -ry * 0.5), Vector2(fx + 0.4 * hs, -ry * 0.5), Vector2(fx + 2.1 * hs, ry * 0.25)]), head, belly)
		"patches":
			var swap: bool = r.randf() < 0.5
			var col_a: Color = accent if swap else stripe
			var col_b: Color = stripe if swap else accent
			_add_clip(list, _ellipse(Vector2(fx - 8.5 * hs, -ry * 0.55), 8.0 * hs, 7.2 * hs, 24), head, col_a)
			_add_clip(list, _ellipse(Vector2(fx + 8.5 * hs, -ry * 0.8), 6.8 * hs, 5.6 * hs, 24), head, col_b)
		"points":
			var mask_col: Color = primary.lerp(accent, 0.8)
			_add_clip(list, _ellipse(Vector2(fx + 0.5 * hs, ry * 0.32), 8.2 * hs, 6.6 * hs, 28), head, Color(mask_col, 0.35))
			_add_clip(list, _ellipse(Vector2(fx + 0.5 * hs, ry * 0.36), 6.4 * hs, 5.0 * hs, 28), head, mask_col)
		"wrinkles":
			for k in range(3):
				_line(list, _arc_pts(Vector2(fx, -ry * 0.3 + float(k) * 1.5 * hs), (2.4 - 0.4 * float(k)) * hs, -2.6, -0.55, 10), stripe, 0.5)
	# Volume: top light, lower-rear cheek shade.
	_add_clip(list, _ellipse(Vector2(-rx * 0.95, ry * 0.75), rx * 0.45, ry * 0.45, 24), head, _shade_col(0.1))
	if pixel_art:
		return list   # nose, mouth, whiskers are hand-placed pixels (_draw_pixel_face)
	# Blush.
	var blush: Color = _pal["blush"]
	for side in [-1.0, 1.0]:
		var bx: float = LEGACY_EYE_SPACING[2] if legacy_eye_spacing else BLUSH_X
		_add(list, _ellipse(Vector2(fx + side * bx * hs, 2.4 * hs), 1.9 * hs, 1.0 * hs, 16), blush)
	# Nose and "w" mouth.
	var nose_c: Vector2 = _head_lm["nose"]
	var nose := PackedVector2Array([
		nose_c + Vector2(-1.25, -0.7) * hs, nose_c + Vector2(1.25, -0.7) * hs,
		nose_c + Vector2(0.3, 0.6) * hs, nose_c + Vector2(-0.3, 0.6) * hs])
	var nose_col: Color = _pal["nose"]
	_add(list, _outline_of(nose, 0.3), _fm(nose_col.darkened(0.35), FID_MOUTH))
	_add(list, nose, _fm(nose_col, FID_MOUTH))
	var mouth_col: Color = Color(outline, 0.9) if not bool(_pal["dark_coat"]) else Color(0.1, 0.07, 0.07, 1.0)
	if pattern == "points":
		mouth_col = Color(0.18, 0.11, 0.1, 1.0)
	mouth_col = _fm(mouth_col, FID_MOUTH)
	var my: float = nose_c.y + 0.8 * hs
	_line(list, PackedVector2Array([nose_c + Vector2(0, 0.55 * hs), Vector2(nose_c.x, my)]), mouth_col, 0.45)
	match String(expression):
		"angry":
			_line(list, _arc_pts(Vector2(nose_c.x, my + 1.7 * hs), 1.5 * hs, PI + 0.6, TAU - 0.6, 8), mouth_col, 0.45)
		"surprised":
			var o := _ellipse(Vector2(nose_c.x, my + 0.9 * hs), 0.7 * hs, 0.85 * hs, 14)
			_add(list, o, _fm(Color("#B5505C"), FID_MOUTH))
			_line(list, o + PackedVector2Array([o[0]]), mouth_col, 0.4)
		"sad":
			var wv := PackedVector2Array()
			for i in range(9):
				var x: float = -1.6 + 3.2 * float(i) / 8.0
				wv.append(Vector2(nose_c.x + x * hs, my + (0.75 + 0.3 * sin(float(i) * PI * 0.5)) * hs))
			_line(list, wv, mouth_col, 0.4)
		"worried", "stressed":
			_line(list, PackedVector2Array([Vector2(nose_c.x - 0.9 * hs, my + 0.6 * hs), Vector2(nose_c.x + 0.9 * hs, my + 0.6 * hs)]), mouth_col, 0.45)
		_:
			_line(list, _arc_pts(Vector2(nose_c.x - 0.95 * hs, my), 0.95 * hs, 0.1, PI - 0.25, 8), mouth_col, 0.45)
			_line(list, _arc_pts(Vector2(nose_c.x + 0.95 * hs, my), 0.95 * hs, 0.25, PI - 0.1, 8), mouth_col, 0.45)
	# Whiskers: near side reaches past the head outline, far side stays on the cheek.
	var wcol: Color = _fm(_pal["whisker"], FID_WHISKER)
	var wscale: float = float(_pal["whiskers"])
	if wscale > 0.0:
		for side in [-1.0, 1.0]:
			for k in range(3):
				var start := Vector2(nose_c.x + side * 3.4 * hs, (2.4 + 0.75 * float(k)) * hs)
				var reach: float = (rx * _head_wide * (1.0 + _cheek) - start.x + 2.2 + _fur_amp * 0.6) if side > 0.0 else (start.x + rx * 0.45)
				var end := start + Vector2(side * reach * wscale * (1.0 - 0.1 * float(k)), (-1.1 + 1.1 * float(k)) * hs)
				_line(list, PackedVector2Array([start, end]), wcol, 0.35)
	return list

# Pixel head: opaque fill + markings (same regions as smooth). The face
# (eyes, nose, mouth, whiskers) is stamped by _draw_pixel_face.
func _head_fill_list_pixel(head: PackedVector2Array) -> Array:
	var list: Array = []
	var primary: Color = _pal["primary"]
	var belly: Color = _pal["belly"]
	var stripe: Color = _pal["stripe"]
	var accent: Color = _pal["accent"]
	var pattern: String = _pal["pattern"]
	var hs: float = _hs
	var fx: float = _face_x
	var ry: float = _head_ry
	var rx: float = _head_rx
	# Cream muzzle, tuxedo blaze and siamese mask follow the snoot axis
	# (nose + mouth stamp column), not the raw landmark.
	var sdx: float = _pixel_snoot_dx()
	_add(list, head, primary)
	var r := _part_rng(23)
	match pattern:
		"stripes":
			for k in range(3):
				var x: float = fx + (float(k) - 1.0) * 2.6 * hs
				var long: float = 0.45 if k == 1 else 0.6
				_add_clip(list, PackedVector2Array([Vector2(x - 1.1 * hs, -ry - 2.0), Vector2(x + 1.1 * hs, -ry - 2.0), Vector2(x, -ry * long)]), head, stripe)
			for side in [-1.0, 1.0]:
				for k in range(2):
					var y: float = (0.4 + float(k) * 2.6) * hs
					var edge: float = side * rx * 1.3
					var tip: float = fx + side * rx * (0.72 if side < 0.0 else 0.8)
					_add_clip(list, PackedVector2Array([Vector2(edge, y - 0.9 * hs), Vector2(edge, y + 0.9 * hs), Vector2(tip, y + 0.2 * hs)]), head, stripe)
			_add_clip(list, _muzzle_poly(1.0, sdx), head, _fm(belly, FID_MUZZLE))
		"tuxedo":
			_add_clip(list, _muzzle_poly(1.12, sdx), head, _fm(belly, FID_MUZZLE))
			_add_clip(list, PackedVector2Array([Vector2(fx + sdx - 1.9 * hs, ry * 0.25), Vector2(fx + sdx - 0.2 * hs, -ry * 0.5), Vector2(fx + sdx + 0.4 * hs, -ry * 0.5), Vector2(fx + sdx + 2.1 * hs, ry * 0.25)]), head, _fm(belly, FID_MUZZLE))
		"patches":
			var swap: bool = r.randf() < 0.5
			var col_a: Color = accent if swap else stripe
			var col_b: Color = stripe if swap else accent
			_add_clip(list, _ellipse(Vector2(fx - 8.5 * hs, -ry * 0.55), 8.0 * hs, 7.2 * hs, 24), head, col_a)
			_add_clip(list, _ellipse(Vector2(fx + 8.5 * hs, -ry * 0.8), 6.8 * hs, 5.6 * hs, 24), head, col_b)
		"points":
			var mask_col: Color = _points_mask_col()
			if _pixel_density() > 70.0:
				_add_clip(list, _ellipse(Vector2(fx + 0.4 * hs + sdx, ry * 0.32), 8.2 * hs, 6.6 * hs, 28), head, primary.lerp(mask_col, 0.45))
			_add_clip(list, _ellipse(Vector2(fx + 0.4 * hs + sdx, ry * 0.36), 6.6 * hs, 5.2 * hs, 28), head, _fm(mask_col, FID_MUZZLE))
		"wrinkles":
			for k in range(2):
				_line(list, _arc_pts(Vector2(fx, -ry * 0.35 + float(k) * 2.0 * hs), (2.6 - 0.5 * float(k)) * hs, -2.6, -0.55, 8), _tone(primary, -1), 1.0)
	return list

func _points_mask_col() -> Color:
	return (_pal["primary"] as Color).lerp(_pal["accent"], 0.8)

func _muzzle_poly(k: float, dx: float = 0.0) -> PackedVector2Array:
	# White muzzle/chin that runs down to the bottom of the head (meets the bib).
	# dx: pixel mode shifts it onto the snoot axis (_pixel_snoot_dx).
	var hs: float = _hs
	var c := Vector2(_face_x + 0.4 * hs + dx, 4.6 * hs)
	return _union([
		_ellipse(c, 5.4 * hs * k, 4.4 * hs * k, 28),
		_ellipse(c + Vector2(0.0, 3.6 * hs), 6.6 * hs * k, 4.6 * hs, 28)])

func _ear_lists(side: int, line: Array, fill: Array) -> void:
	var es: float = float(_pal["ear_size"]) * _hs * (0.94 if side < 0 else 1.0)
	var w: float = EAR_W * es
	var h: float = EAR_H * es
	var tip_dx: float = float(side) * 0.9 * es
	var ear := PackedVector2Array([
		Vector2(-w * 0.5, 3.5), Vector2(-w * 0.36, -h * 0.4), Vector2(tip_dx - 1.3 * es, -h + 1.0 * es),
		Vector2(tip_dx - 0.4 * es, -h), Vector2(tip_dx + 0.4 * es, -h), Vector2(tip_dx + 1.3 * es, -h + 1.0 * es),
		Vector2(w * 0.36, -h * 0.4), Vector2(w * 0.5, 3.5)])
	var pattern: String = _pal["pattern"]
	var col: Color = _pal["primary"]
	if pattern == "points":
		col = (_pal["primary"] as Color).lerp(_pal["accent"], 0.85)
	elif pattern == "patches":
		var r := _part_rng(23)
		var swap: bool = r.randf() < 0.5
		col = (_pal["accent"] if swap else _pal["stripe"]) if side < 0 else (_pal["stripe"] if swap else _pal["accent"])
	if _fur_amp > 0.01:
		var ear_mask: Callable = func(p: Vector2) -> float: return EAR_FUR * _ss(-h * 0.25, -h * 0.55, p.y)
		ear = _fur_edge(ear, Transform2D.IDENTITY, Vector2(tip_dx * 0.5, -h * 0.45), h * 0.5, ear_mask, Vector2(float(side) * 0.3, -1.0).normalized(), 0.6, 303 + side)
	if not pixel_art:
		_add(line, _outline_of(ear, _ow), FID_OUTLINE if feature_ids else _pal["outline"])
		_add(line, ear, col)
	_add(fill, ear, col)
	var inner := PackedVector2Array()
	var anchor := Vector2(tip_dx * 0.6, -h * 0.2)
	for p in ear:
		inner.append(anchor + (p - anchor) * 0.6 + Vector2(0, 0.6))
	_add(fill, inner, _pal["inner_ear"])

func _draw_eyes(ci: Node2D) -> void:
	if pixel_art and _px > 0.0:
		_draw_pixel_face(ci)
		return
	var hs: float = _hs
	var line_col: Color = Color("#2A1A16") if not bool(_pal["dark_coat"]) else Color("#120C0B")
	var eye: Color = _pal["eye"]
	var ex: String = String(expression)
	var closed: bool = _eyes_closed
	var happy: bool = ex == "happy" and not closed
	var ext: Dictionary = SMOOTH_EXPR.get(ex, {})
	var spec: Dictionary = SMOOTH_EYES.get(str(_pal.get("eye_shape", "round")), SMOOTH_EYES["round"])
	var aw: float = clampf(float(spec.get("w", 1.0)), 0.75, 1.2)
	var near_c := Vector2.ZERO
	for side in [-1.0, 1.0]:
		var s: float = 1.0 if side > 0.0 else 0.92
		# Eye anchors from the shared landmarks (eyes node sits on the eye row).
		var anchor: Vector2 = _head_lm["eye_near"] if side > 0.0 else _head_lm["eye_far"]
		var c := Vector2(anchor.x, anchor.y - float(_head_lm["eye_y"]))
		if side > 0.0:
			near_c = c
		_fid = (FID_NEAR if side > 0.0 else FID_FAR) if feature_ids else Color(0, 0, 0, 0)
		if closed:
			_dline(ci, _arc_pts(c + Vector2(0, -0.4 * hs), 2.2 * hs * s * aw, 0.35, PI - 0.35, 10), line_col, 0.7, true)
			continue
		if happy:
			_dline(ci, _arc_pts(c + Vector2(0, 1.2 * hs), 2.2 * hs * s * aw, PI + 0.35, TAU - 0.35, 10), line_col, 0.7, true)
			continue
		_draw_smooth_eye(ci, c, side, hs * s, spec, ext, eye, line_col)
	if not closed:
		_draw_smooth_mark(ci, ex, near_c, hs, spec)
	_fid = Color(0, 0, 0, 0)

# One open smooth eye: SMOOTH_EYES shape + SMOOTH_EXPR lids / pupil. k = head
# size * side scale. Layers (all clipped to the eye when it is not a plain
# ellipse): outline, dark iris, mid iris, light lower crescent, big pupil,
# glints, heavy upper lid.
func _draw_smooth_eye(ci: Node2D, c: Vector2, side: float, k: float, spec: Dictionary, ext: Dictionary, eye: Color, line_col: Color) -> void:
	var rx: float = 2.6 * k * float(spec.get("w", 1.0))
	var ry: float = 2.9 * k * float(spec.get("h", 1.0))
	var pupil_k: float = float(ext.get("pupil", 1.0))
	var pupil_col := Color("#24150F")
	var glint := Color(1, 1, 1, 0.98)
	var lemon: bool = bool(spec.get("lemon", false))
	var lid: float = float(spec.get("lid", 0.0))
	var lid_y: float = float(spec.get("lid_y", 0.0))
	var has_lid: bool = lid != 0.0
	if ext.has("lid"):
		var el: Array = ext["lid"]
		lid = float(el[0])
		lid_y = float(el[1])
		has_lid = true
	var shaped: bool = lemon or has_lid
	var shape: PackedVector2Array = _lemon(c, rx, ry, 28) if lemon else _ellipse(c, rx, ry, 24)
	if has_lid:
		# Keep the part of the eye below the (slanted) lid line.
		var y0: float = c.y + lid_y * ry
		var t: float = tan(lid)
		var span: float = rx * 3.0
		var below := PackedVector2Array([
			Vector2(c.x - span, y0 - t * span * side), Vector2(c.x + span, y0 + t * span * side),
			Vector2(c.x + span, c.y + ry * 3.0), Vector2(c.x - span, c.y + ry * 3.0)])
		var cut: Array = Geometry2D.intersect_polygons(shape, below)
		if not cut.is_empty():
			shape = cut[0]
	_eye_part(side, 0)
	if shaped:
		var grown: Array = Geometry2D.offset_polygon(shape, 0.55, Geometry2D.JOIN_ROUND)
		if not grown.is_empty():
			_dpoly(ci, grown[0], line_col)
	else:
		_dpoly(ci, _ellipse(c, rx + 0.55, ry + 0.55, 24), line_col)
	# Layered iris: dark outer / top, mid, light lower crescent.
	_eye_part(side, 2)
	_dpoly(ci, shape, eye.darkened(0.3))
	_clip_fill(ci, _ellipse(c + Vector2(0, ry * 0.2), rx * 0.84, ry * 0.78, 22), shape, true, eye)
	var lower_k: float = maxf(0.38, float(spec.get("lower", 0.38)))
	_clip_fill(ci, _ellipse(c + Vector2(0, ry * 0.62), rx * 0.7, ry * 0.4, 18), shape, true, eye.lightened(lower_k))
	var pr: Array = spec.get("pupil", [0.68, 0.72])
	var pc: Vector2 = c + Vector2(0.1, -0.1 * ry + float(spec.get("pupil_dy", 0.0)) * ry)
	var pupil: PackedVector2Array
	if bool(spec.get("slit", false)):
		var calm: bool = expression in [&"open", &"smug", &"sleepy", &"sad", &"happy"]
		var sw: float = float(pr[0]) * (1.7 if calm else 1.0) * (0.75 if pupil_k < 0.9 else 1.0)
		pupil = _lemon(pc, rx * sw, ry * float(pr[1]) * minf(1.0, pupil_k + 0.1), 16, true)
	else:
		pupil = _ellipse(pc, rx * float(pr[0]) * pupil_k, ry * float(pr[1]) * pupil_k, 20)
	_eye_part(side, 1)
	_clip_fill(ci, pupil, shape, shaped, pupil_col)
	_eye_part(side, 3)
	if not bool(ext.get("no_glint", false)):
		var gk: float = k * clampf(minf(float(spec.get("w", 1.0)), float(spec.get("h", 1.0))), 0.7, 1.15)
		var n_glint: int = int(spec.get("glints", 2))
		if bool(ext.get("glossy", false)):
			n_glint = 3
		var big_r: float = (1.15 if pupil_k >= 0.9 else 0.8) * gk
		_clip_fill(ci, _ellipse(c + Vector2(rx * 0.26, -ry * 0.3), big_r, big_r, 16), shape, shaped, glint)
		if n_glint >= 3:
			_clip_fill(ci, _ellipse(c + Vector2(-rx * 0.32, -ry * 0.02), 0.55 * gk, 0.55 * gk, 10), shape, shaped, Color(1, 1, 1, 0.92))
		if n_glint >= 2 and pupil_k >= 0.75:
			_clip_fill(ci, _ellipse(c + Vector2(-rx * 0.3, ry * 0.36), 0.48 * gk, 0.48 * gk, 10), shape, shaped, Color(1, 1, 1, 0.88))
	_eye_part(side, 0)
	_draw_upper_lid(ci, shape, c, line_col, 0.85 * k / maxf(0.5, _hs))
	if bool(spec.get("lash", false)):
		# Outer-corner flick (mirrors with the side).
		var top: Vector2 = shape[0]
		var best: float = -INF
		for p in shape:
			var score: float = (p.x - c.x) * side - (p.y - c.y) * 0.8
			if score > best:
				best = score
				top = p
		var tip: Vector2 = top + Vector2(1.25 * side, -1.0) * k
		_dpoly(ci, PackedVector2Array([top + Vector2(-0.55 * side, -0.2) * k, tip, top + Vector2(0.25 * side, 0.5) * k]), line_col)

# feature_eye_parts: route the next smooth eye layer to its part id
# (0 line / lid, 1 pupil / bead, 2 iris, 3 glint).
func _eye_part(side: float, part: int) -> void:
	if not (feature_ids and feature_eye_parts):
		return
	var i: int = 0 if side > 0.0 else 1
	match part:
		1:
			_fid = FID_PUPIL[i]
		2:
			_fid = FID_IRIS[i]
		3:
			_fid = FID_GLINT[i]
		_:
			_fid = FID_NEAR if i == 0 else FID_FAR

# Heavy "eyeliner" along the upper chain of a convex eye polygon.
func _draw_upper_lid(ci: Node2D, shape: PackedVector2Array, c: Vector2, col: Color, w: float) -> void:
	var n: int = shape.size()
	if n < 3:
		return
	var i0: int = 0
	var i1: int = 0
	for i in range(n):
		if shape[i].x < shape[i0].x:
			i0 = i
		if shape[i].x > shape[i1].x:
			i1 = i
	var chains: Array = [PackedVector2Array(), PackedVector2Array()]
	var i: int = i0
	while true:
		chains[0].append(shape[i])
		if i == i1:
			break
		i = (i + 1) % n
	i = i0
	while true:
		chains[1].append(shape[i])
		if i == i1:
			break
		i = (i - 1 + n) % n
	var avg: Array = [0.0, 0.0]
	for k in range(2):
		for p in chains[k]:
			avg[k] += p.y
		avg[k] /= maxf(1.0, float(chains[k].size()))
	var upper: PackedVector2Array = chains[0] if avg[0] < avg[1] else chains[1]
	if upper.size() >= 2:
		_dline(ci, upper, col, maxf(0.5, w), true)

# Expression marks in smooth mode (eyes node space; near = near eye centre).
func _draw_smooth_mark(ci: Node2D, ex: String, near: Vector2, hs: float, spec: Dictionary) -> void:
	# The tear belongs to the near eye's footprint; vein / sweat are marks.
	if feature_ids:
		_fid = FID_NEAR if ex == "sad" else FID_MARK
	match ex:
		"angry":
			# Anger vein: four bracket arcs on the forehead above the near eye.
			var vc: Vector2 = near + Vector2(1.6, -7.0) * hs
			var col := Color("#D9434F")
			for q in range(4):
				var a0: float = PI * 0.5 * float(q) + PI * 0.25
				var off := Vector2(cos(a0), sin(a0)) * 2.7 * hs
				_dline(ci, _arc_pts(vc + off, 1.4 * hs, a0 + PI * 0.75, a0 + PI * 1.25, 8), col, 0.34 * hs, true)
		"worried":
			# Beside the eye's top-outer corner, clear of its outline.
			_drop(ci, near + Vector2(2.6 * float(spec.get("w", 1.0)) + 2.3, -2.9 * float(spec.get("h", 1.0)) * 0.85) * hs, 1.0 * hs, Color("#7EC3F2"))
		"sad":
			var ry: float = 2.9 * hs * float(spec.get("h", 1.0))
			_drop(ci, near + Vector2(-1.0 * hs, ry + 1.1 * hs), 0.7 * hs, Color("#A8DBF7"))

# Small teardrop (point up) with a highlight.
func _drop(ci: Node2D, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * float(i) / 16.0
		var p := Vector2(cos(a), sin(a)) * r
		if p.y < 0.0:
			p.x *= 1.0 + p.y / r * 0.85
			p.y *= 1.8
		pts.append(c + p)
	_dpoly(ci, pts, col)
	_dline(ci, pts + PackedVector2Array([pts[0]]), col.darkened(0.35), 0.3, true)
	_dpoly(ci, _ellipse(c + Vector2(-0.3, 0.1) * r, 0.28 * r, 0.28 * r, 8), Color(1, 1, 1, 0.9))

# Fills poly, clipped to the eye shape when the eye is not a plain ellipse.
func _clip_fill(ci: Node2D, poly: PackedVector2Array, shape: PackedVector2Array, clip: bool, col: Color) -> void:
	if not clip:
		_dpoly(ci, poly, col)
		return
	for part in Geometry2D.intersect_polygons(poly, shape):
		if (part as PackedVector2Array).size() >= 3:
			_dpoly(ci, part, col)

# feature_ids colour routing for the smooth face (tools only).
var _fid: Color = Color(0, 0, 0, 0)

func _fm(c: Color, id: Color) -> Color:
	return Color(id, c.a if c.a < 1.0 and c.a >= 0.5 else 1.0) if feature_ids else c

func _dpoly(ci: Node2D, poly: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(poly, _fid if _fid.a > 0.0 else col)

func _dline(ci: Node2D, pts: PackedVector2Array, col: Color, w: float, aa: bool = true) -> void:
	ci.draw_polyline(pts, _fid if _fid.a > 0.0 else col, w, aa and not feature_ids)

# Almond / lens outline: an ellipse whose ends taper to points. vertical =
# lens standing up (slit pupils).
func _lemon(c: Vector2, rx: float, ry: float, n: int = 24, vertical: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var along: float = cos(a)
		var across: float = sin(a) * (0.55 + 0.45 * absf(sin(a)))
		out.append(c + (Vector2(across * rx, along * ry) if vertical else Vector2(along * rx, across * ry)))
	return out

# ---------------------------------------------------------------- pixel face

# One run of whole art pixels at grid (gx, gy) in head space.
func _pxr(ci: Node2D, step: float, gx: int, gy: int, w: int, h: int, col: Color) -> void:
	if w <= 0 or h <= 0 or col.a <= 0.0:
		return
	ci.draw_rect(Rect2(Vector2(gx, gy) * step, Vector2(w, h) * step), col, true)

# Draws a text stamp with its top-left pixel at grid (gx, gy); legend maps
# characters to colours ("." and unmapped characters are skipped).
func _stamp(ci: Node2D, step: float, rows: Array, gx: int, gy: int, legend: Dictionary) -> void:
	for ry in range(rows.size()):
		var row: String = str(rows[ry])
		var x: int = 0
		while x < row.length():
			var ch: String = row[x]
			if not legend.has(ch):
				x += 1
				continue
			var run: int = 1
			while x + run < row.length() and row[x + run] == ch:
				run += 1
			_pxr(ci, step, gx + x, gy + ry, run, 1, legend[ch])
			x += run

# Eye stamp rows: eye_stamp_override (tools) first, else CatPixelFace.
func _eye_rows(sb: String, shape: String, ex: String, far: bool = false) -> Array:
	if not eye_stamp_override.is_empty():
		var b: Dictionary = eye_stamp_override.get(sb, {})
		var s: Dictionary = b.get(shape, {})
		var rows: Array = s.get(ex, [])
		if not rows.is_empty():
			if far and (CatPixelFaceScript.MIRROR_FAR.has(shape) or CatPixelFaceScript.MIRROR_EXPR.has(ex)):
				var out: Array = []
				for r in rows:
					out.append(str(r).reverse())
				return out
			return rows
	return CatPixelFaceScript.eye(sb, shape, ex, far)

# Face geometry on the head pivot's whole-pixel grid. The head pivot is
# snapped to the art grid, so the face origin (eye-centre row, nose column) is
# snapped once here and every stamp sits at an integer offset from it: faces
# are identical for every cat sharing a stamp and never jitter with head bob.
func _pixel_face_layout() -> Dictionary:
	var step: float = _px / maxf(0.05, _fit)
	var bucket: String = CatPixelFaceScript.bucket_for(_pixel_density())
	var lay: Dictionary = CatPixelFaceScript.layout(bucket)
	var shape: String = str(_pal.get("eye_shape", "round"))
	var nose: Vector2 = _head_lm["nose"]
	var ax: int = int(floor(nose.x / step))
	var oy: int = int(roundf(float(_head_lm["eye_y"]) / step))
	var ny: int = oy + int(lay["nose_dy"])
	var near: Vector2 = _head_lm["eye_near"]
	var d_px: float = (near.x - (float(ax) + 0.5) * step) / step
	var fs: int = CatPixelFaceScript.FAR_SHIFT
	if legacy_eye_spacing:
		# Pre-v4 placement (tools' before/after sheets only).
		var lrows: Array = _eye_rows(bucket, shape, "open")
		var lw: int = str(lrows[0]).length()
		var lh: int = lrows.size()
		var lim: Array = lay.get("legacy_gap", [lay["gap_min"], lay["gap_max"]])
		var lg: int = clampi(int(roundf(d_px - float(lw) * 0.5)), int(lim[0]), int(lim[1]))
		return {"step": step, "bucket": bucket, "lay": lay, "shape": shape, "stamp_bucket": bucket,
			"ew": lw, "eh": lh, "ax": ax, "oy": oy, "gap": lg, "edge": 9999, "far_edge": -9999,
			"eye_top": oy - lh / 2, "near_x": ax + lg, "far_x": ax - lg - lw + 1 + fs, "nose_y": ny, "snoot_x": ax}
	# Eyes sit on fixed CENTRE anchors (landmarks eye_near / eye_far; the 3/4
	# view lives in their asymmetry), so a smaller stamp on the same centres
	# always gets a LARGER gap. Hard minimum (CatPixelFace.MIN_EYE_GAP_PX):
	# that many fur columns between the two eyes' footprints; stamps too wide
	# for the centres push the eyes apart. Nothing below (fallback stamps,
	# face slide, expressions) can lower it.
	var min_fur: int = CatPixelFaceScript.min_eye_gap(bucket)
	var cn: float = near.x / step
	var cf: float = (_head_lm["eye_far"] as Vector2).x / step
	# Fit priority when an eye would not keep MIN_EYE_EDGE_PX fur from its
	# cheek outline: (a) keep the gap, (b) fall back to the next smaller stamp
	# set (L > M > S > XS) on the same centres, (c) slide the whole face (nose
	# included) up to MAX_FACE_SLIDE_PX toward the far cheek. If nothing fits,
	# the smallest set is used on the minimum gap (edge clearance is lost,
	# the gap never is).
	var pick: Dictionary = {}
	# Each set is followed by its size alternates (big / big_slit: +1 tall,
	# +1 wide, silhouette size), so the largest eye that fits is used.
	var sets: Array = CatPixelFaceScript.stamp_chain(bucket, shape)
	if debug_stamp_bucket != "":
		# Forced start of the chain (tools); smaller sets still back it up.
		var chain: Array = ["L", "M", "S", "XS", "XXS"]
		sets = CatPixelFaceScript.expand_chain(chain.slice(maxi(0, chain.find(debug_stamp_bucket))), shape)
	for sb in sets:
		var rows: Array = _eye_rows(sb, shape, "open")
		var ew: int = str(rows[0]).length()
		var eh: int = rows.size()
		# Eyes end >= 1 fur row above the nose row.
		var top: int = mini(oy - eh / 2, ny - 1 - eh)
		var nl: int = roundi(cn - float(ew) * 0.5)
		var fl: int = roundi(cf - float(ew) * 0.5)
		var short: int = min_fur - (nl - fl - ew)
		if short > 0:
			nl += (short + 1) / 2
			fl -= short / 2
		var edge: int = 9999
		var far_edge: int = -9999
		for r in range(eh):
			edge = mini(edge, _head_edge_col(top + r, step, 1, ax))
			far_edge = maxi(far_edge, _head_edge_col(top + r, step, -1, ax))
		pick = {"stamp_bucket": sb, "ew": ew, "eh": eh, "top": top, "nl": nl, "fl": fl, "edge": edge, "far_edge": far_edge}
		if _slide_fit(pick) > -99:
			break
	var eye_up: int = 0
	if eye_up_px > 0 and _slide_fit(pick) > -99:
		var p2: Dictionary = pick.duplicate()
		p2["top"] = int(pick["top"]) - eye_up_px
		var e2: int = 9999
		var f2: int = -9999
		for r in range(int(p2["eh"])):
			e2 = mini(e2, _head_edge_col(int(p2["top"]) + r, step, 1, ax))
			f2 = maxi(f2, _head_edge_col(int(p2["top"]) + r, step, -1, ax))
		p2["edge"] = e2
		p2["far_edge"] = f2
		if _slide_fit(p2) == _slide_fit(pick):
			pick = p2
			eye_up = eye_up_px
	var sh: int = _slide_fit(pick)
	if sh == -99:
		sh = 0
	var w: int = pick["ew"]
	var near_x: int = int(pick["nl"]) + sh
	var far_x: int = int(pick["fl"]) + sh
	if near_x - (far_x + w - 1) - 1 < min_fur:
		push_warning("Cat2D: eye gap %d px < MIN_EYE_GAP_PX %d (%s/%s)" % [near_x - (far_x + w - 1) - 1, min_fur, bucket, shape])
	# Snoot axis (nose + mouth stamp centre column, muzzle patch centre): the
	# midpoint of both PLACED eyes' footprints (far_x .. near_x + w - 1) plus
	# CatPixelFace.SNOOT_FORWARD_PX toward the facing side. A midpoint between
	# two columns rounds toward the facing side too. Head space is +x = facing
	# side; facing left mirrors the whole rig, so this mirrors with it.
	var foot_sum: int = far_x + near_x + w - 1
	var snoot_x: int = floori(float(foot_sum + 1) * 0.5) + CatPixelFaceScript.SNOOT_FORWARD_PX
	return {
		"step": step, "bucket": bucket, "lay": lay, "shape": shape, "stamp_bucket": pick["stamp_bucket"],
		"ew": w, "eh": pick["eh"], "ax": ax + sh, "oy": oy, "gap": near_x - ax - sh, "edge": pick["edge"], "far_edge": pick["far_edge"],
		"eye_top": pick["top"],
		"eye_up": eye_up,
		"near_x": near_x,
		"far_x": far_x,
		"nose_y": ny,
		"snoot_x": snoot_x,
	}

# Smallest face slide (0, -1, ... -MAX_FACE_SLIDE_PX toward the far cheek) at
# which both eyes fit, or -99 when none does.
func _slide_fit(p: Dictionary) -> int:
	for k in range(CatPixelFaceScript.MAX_FACE_SLIDE_PX + 1):
		if _eyes_fit(-k, p):
			return -k
	return -99

# Both eyes keep >= MIN_EYE_EDGE_PX fur columns from their cheek outline
# when the face slides by sh columns.
func _eyes_fit(sh: int, p: Dictionary) -> bool:
	var w: int = p["ew"]
	var m: int = CatPixelFaceScript.MIN_EYE_EDGE_PX
	if int(p["nl"]) + sh + w - 1 > int(p["edge"]) - m or int(p["fl"]) + sh < int(p["far_edge"]) + m:
		return false
	# Full ring of MIN_EYE_EDGE_PX around each stamp's box (top / ear edge and
	# the diagonal corners included) must be fur.
	var step: float = _px / maxf(0.05, _fit)
	var top: int = int(p["top"])
	var h: int = p["eh"]
	for x0 in [int(p["nl"]) + sh, int(p["fl"]) + sh]:
		for y in range(top - m, top + h + m):
			var inner: bool = y >= top and y < top + h
			for x in range(x0 - m, x0 + w + m):
				if inner and x >= x0 and x < x0 + w:
					continue
				if not _in_head(x, y, step):
					return false
	return true

# Head-space x shift that centres the pixel muzzle / mask / blaze on the
# snoot axis column of _pixel_face_layout (0 in smooth mode).
func _pixel_snoot_dx() -> float:
	if not pixel_art or _px <= 0.0:
		return 0.0
	if is_nan(_snoot_dx) or not is_equal_approx(_snoot_step, _pixel_step()):
		_snoot_step = _pixel_step()
		var fl: Dictionary = _pixel_face_layout()
		var step: float = fl["step"]
		_snoot_dx = (float(int(fl.get("snoot_x", fl["ax"]))) + 0.5) * step - (_head_lm["nose"] as Vector2).x
	return _snoot_dx

func _muzzle_col() -> Color:
	match str(_pal["pattern"]):
		"stripes", "tuxedo":
			return _pal["belly"]
		"points":
			return _points_mask_col()
	return _pal["primary"]

func _pixel_expression() -> String:
	if _eyes_closed:
		return "closed"
	if _pixel_shut and expression != &"happy":
		return "closed"
	var ex: String = String(expression)
	return ex if CatPixelFaceScript.EXPRESSIONS.has(ex) else "open"

# Rightmost (dir = 1) / leftmost (dir = -1) grid column of row gy whose pixel
# centre lies inside the head silhouette, scanning out from column from_x.
func _head_edge_col(gy: int, step: float, dir: int, from_x: int) -> int:
	var x: int = from_x
	for _i in range(200):
		if not _in_head(x + dir, gy, step):
			return x
		x += dir
	return x

func _in_head(gx: int, gy: int, step: float) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2((float(gx) + 0.5) * step, (float(gy) + 0.5) * step), _head_furred())

func _draw_pixel_face(ci: Node2D) -> void:
	var fl: Dictionary = _pixel_face_layout()
	var step: float = fl["step"]
	var bucket: String = fl["bucket"]
	var lay: Dictionary = fl["lay"]
	var dark: bool = bool(_pal["dark_coat"])
	var eye: Color = _pal["eye"]
	var line_col: Color = Color("#2A1A16") if not dark else Color("#120C0B")
	var ex: String = _pixel_expression()
	var bead: Color = Color("#1C1210") if not dark else eye.darkened(0.3)
	var eye_legend: Dictionary = {
		"#": line_col, "L": line_col, "d": eye.darkened(0.3), "o": eye, "l": eye.lightened(0.38),
		"p": Color("#24150F"), "w": Color(1, 1, 1, 1), "e": Color("#FFF8F0"), "b": bead}
	var shape: String = str(fl["shape"])
	var sb: String = fl["stamp_bucket"]
	var far_legend: Dictionary = eye_legend
	if feature_ids:
		far_legend = _parts_legend(eye_legend, 1) if feature_eye_parts else _id_legend(eye_legend, FID_FAR)
		eye_legend = _parts_legend(eye_legend, 0) if feature_eye_parts else _id_legend(eye_legend, FID_NEAR)
	# Same stamp for both eyes (mirrored for the far eye on slanted shapes).
	_stamp(ci, step, _eye_rows(sb, shape, ex), int(fl["near_x"]), int(fl["eye_top"]), eye_legend)
	_stamp(ci, step, _eye_rows(sb, shape, ex, true), int(fl["far_x"]), int(fl["eye_top"]), far_legend)
	_draw_pixel_mark(ci, fl, ex)

	# Nose + mouth stamp centred on the snoot axis (fl["snoot_x"]).
	var mz: Color = _muzzle_col()
	var outline: Color = _pal["outline"]
	var mouth_col: Color = Color(outline, 1.0)
	if absf(outline.get_luminance() - mz.get_luminance()) < 0.3:
		mouth_col = Color(mz.lerp(Color(1.0, 0.95, 0.9), 0.5), 1.0)
	var nose_col: Color = _pal["nose"]
	var nose_dark: Color = nose_col.darkened(0.35) if mz.get_luminance() > 0.45 else nose_col
	var mrows: Array = _pixel_mouth_rows(bucket, ex)
	var mw: int = str(mrows[0]).length()
	# Snoot axis column (eye midpoint + SNOOT_FORWARD_PX); whiskers follow it.
	var ax: int = fl.get("snoot_x", fl["ax"])
	var ny: int = fl["nose_y"]
	var ml: Dictionary = {"n": nose_col, "N": nose_dark, "m": mouth_col, "r": Color("#B5505C")}
	if feature_ids:
		ml = _id_legend(ml, FID_MOUTH)
	_stamp(ci, step, mrows, ax - mw / 2, ny + mouth_dy_offset, ml)

	# Whiskers: whole-pixel lines. Near side starts inside the cheek and pokes
	# past the outline (those pixels use the DECAL alpha so the pipeline does
	# not outline them); far side sits on the cheek beside the muzzle.
	var wscale: float = float(_pal["whiskers"])
	if wscale <= 0.0:
		return
	var primary: Color = _pal["primary"]
	var w_out: Color = Color(outline, DECAL_ALPHA) if primary.get_luminance() > 0.42 else Color(Color("#9A8B80"), DECAL_ALPHA)
	var wrows: Array = lay["whisker_rows"]
	var lines: int = 2 if (_pixel_density() >= 44.0 and wscale >= 1.0) else 1
	for k in range(lines):
		var row_off: int = int(wrows[k]) if lines == 2 else (int(wrows[0]) + int(wrows[1])) / 2
		var gy: int = ny + row_off
		var tilt: int = (-1 if k == 0 else 1) if lines == 2 else 0
		# Near side.
		var edge: int = _head_edge_col(gy, step, 1, ax)
		var x0: int = maxi(edge - int(lay["whisker_in"]) + 1, ax + mw / 2 + 2)
		var x1: int = edge + int(lay["whisker_out"])
		for x in range(x0, x1 + 1):
			var y: int = gy + (tilt if x > edge + 1 else 0)
			_pxr(ci, step, x, y, 1, 1, _fm(_whisker_col(x, y, step) if _in_head(x, y, step) else w_out, FID_WHISKER))
		# Far side (3/4 view: stays on the cheek).
		var fx1: int = ax - mw / 2 - 2
		var flen: int = int(lay["far_len"])
		for i in range(flen):
			var x: int = fx1 - i
			var y: int = gy + (tilt if i == flen - 1 else 0)
			_pxr(ci, step, x, y, 1, 1, _fm(_whisker_col(x, y, step) if _in_head(x, y, step) else w_out, FID_WHISKER))

# Nose + mouth stamp rows for this expression (mouth_stamp_override first).
func _pixel_mouth_rows(bucket: String, ex: String) -> Array:
	var kind: String = str(CatPixelFaceScript.EXPRESSION_MOUTH.get(ex, _pal.get("mouth", "w")))
	var mrows: Array = CatPixelFaceScript.mouth(bucket, kind)
	if not mouth_stamp_override.is_empty():
		var mo: Dictionary = mouth_stamp_override.get(bucket, {})
		if mo.has(kind):
			mrows = mo[kind]
	return mrows

# True when grid cell (gx, gy) touches (8-neighbour) or overlaps a pixel of
# the nose + mouth stamp as _draw_pixel_face places it.
func _touches_mouth(fl: Dictionary, ex: String, gx: int, gy: int) -> bool:
	var mrows: Array = _pixel_mouth_rows(str(fl["bucket"]), ex)
	var x0: int = int(fl.get("snoot_x", fl["ax"])) - str(mrows[0]).length() / 2
	var y0: int = int(fl["nose_y"]) + mouth_dy_offset
	for ry in range(mrows.size()):
		var row: String = str(mrows[ry])
		for x in range(row.length()):
			if row[x] != "." and absi(x0 + x - gx) <= 1 and absi(y0 + ry - gy) <= 1:
				return true
	return false

# feature_eye_parts legend; side 0 = near eye, 1 = far eye.
func _parts_legend(legend: Dictionary, side: int) -> Dictionary:
	var out: Dictionary = {}
	for k in legend.keys():
		match str(k):
			"p", "b":
				out[k] = FID_PUPIL[side]
			"w":
				out[k] = FID_GLINT[side]
			"d", "o", "l", "e":
				out[k] = FID_IRIS[side]
			_:
				out[k] = FID_NEAR if side == 0 else FID_FAR
	return out

func _id_legend(legend: Dictionary, id: Color) -> Dictionary:
	var out: Dictionary = {}
	for k in legend.keys():
		out[k] = id
	return out

# Expression mark (anger vein / sweat drop / tear) at its LAYOUT anchor next
# to the near eye. Pixels inside the head are opaque, outside ones use the
# decal alpha so the pipeline does not outline them.
func _draw_pixel_mark(ci: Node2D, fl: Dictionary, ex: String) -> void:
	var kind: String = str(CatPixelFaceScript.EXPRESSION_MARK.get(ex, ""))
	if kind == "":
		return
	var bucket: String = fl["bucket"]
	var rows: Array = CatPixelFaceScript.accessory(bucket, kind)
	if rows.is_empty():
		return
	var lay: Dictionary = fl["lay"]
	var off: Array = lay.get(kind, [0, 0])
	var step: float = fl["step"]
	var gx: int
	var gy: int
	if kind == "tear":
		gx = int(fl["near_x"]) + int(fl["ew"]) / 2 + int(off[0])
		gy = int(fl["eye_top"]) + int(fl["eh"]) + int(off[1])
	else:
		gx = int(fl["near_x"]) + int(fl["ew"]) + int(off[0])
		gy = int(fl["eye_top"]) + int(off[1])
		if kind == "vein":
			gx -= str(rows[0]).length()
	var cols: Dictionary = {"v": Color("#D9434F"), "s": Color("#7EC3F2"), "t": Color("#A8DBF7"), "w": Color(1, 1, 1)}
	# The tear is part of the eye's footprint: stop >= 1 fur row above the whiskers.
	var max_row: int = 1 << 20
	if kind == "tear":
		max_row = int(fl["nose_y"]) + int((lay["whisker_rows"] as Array)[0]) - 2
	for ry in range(rows.size()):
		if gy + ry > max_row:
			break
		# ... and never touches the nose / mouth (the snoot sits forward,
		# toward the near eye).
		if kind == "tear":
			var hit: bool = false
			for x in range(str(rows[ry]).length()):
				if str(rows[ry])[x] != "." and _touches_mouth(fl, ex, gx + x, gy + ry):
					hit = true
			if hit:
				break
		var row: String = str(rows[ry])
		for x in range(row.length()):
			var ch: String = row[x]
			if not cols.has(ch):
				continue
			var px: int = gx + x
			var py: int = gy + ry
			var col: Color = cols[ch]
			if feature_ids:
				col = FID_NEAR if kind == "tear" else FID_MARK
			if not _in_head(px, py, step):
				col = Color(col, DECAL_ALPHA)
			_pxr(ci, step, px, py, 1, 1, col)

# Whisker pixel colour that contrasts with the fur region under it (muzzle /
# siamese mask / plain fur): dark on light fur, light on dark fur.
func _whisker_col(gx: int, gy: int, step: float) -> Color:
	var p := Vector2((float(gx) + 0.5) * step, (float(gy) + 0.5) * step)
	var base: Color = _pal["primary"]
	match str(_pal["pattern"]):
		"stripes":
			if Geometry2D.is_point_in_polygon(p, _muzzle_poly(1.0, _pixel_snoot_dx())):
				base = _pal["belly"]
		"tuxedo":
			if Geometry2D.is_point_in_polygon(p, _muzzle_poly(1.12, _pixel_snoot_dx())):
				base = _pal["belly"]
		"points":
			var hs: float = _hs
			var q: Vector2 = (p - Vector2(_face_x + 0.4 * hs + _pixel_snoot_dx(), _head_ry * 0.32)) / (Vector2(8.2, 6.6) * hs)
			if q.length() <= 1.0:
				base = _points_mask_col()
	if base.get_luminance() > 0.42:
		return Color((_pal["outline"] as Color).lerp(base, 0.12), 1.0)
	return Color("#E6DACB")

# ---------------------------------------------------------------- tail

# Tail centerline samples, normalized arc params and radii for an angle list
# (tail-root space). Shared by drawing and the fit guard.
func _tail_path(angles: Array) -> Array:
	var tl: float = float(_pal["tail_length"])
	var th: float = float(_pal["tail_thickness"])
	var fluffy: bool = bool(_pal["tail_fluffy"])
	var seg_len: float = TAIL_BASE_LEN * tl / float(TAIL_SEGMENTS)
	var pts: Array[Vector2] = [Vector2.ZERO]
	var p := Vector2.ZERO
	for a in angles:
		p += Vector2(cos(float(a)), sin(float(a))) * seg_len
		pts.append(p)
	var samples: Array[Vector2] = []
	var ts: Array[float] = []
	var total: float = seg_len * float(TAIL_SEGMENTS)
	var count: int = maxi(4, int(total / 0.6))
	for i in range(count + 1):
		var t: float = float(i) / float(count)
		var fi: float = t * float(TAIL_SEGMENTS)
		var si: int = mini(int(fi), TAIL_SEGMENTS - 1)
		var lt: float = fi - float(si)
		samples.append(_catmull(pts[maxi(si - 1, 0)], pts[si], pts[si + 1], pts[mini(si + 2, TAIL_SEGMENTS)], lt))
		ts.append(t)
	var r0: float = (3.1 if not fluffy else 3.5) * th
	var r1: float = (2.7 if not fluffy else 3.1) * th
	var radii: Array[float] = []
	for i in range(samples.size()):
		var t: float = ts[i]
		var rr: float = lerpf(r0, r1, t)
		if t > 0.88:
			rr *= sqrt(maxf(0.0, 1.0 - (t - 0.88) / 0.12)) * 0.55 + 0.45
		if fluffy and _fur_amp <= 0.01:
			rr *= 1.0 + 0.08 * sin(t * 38.0)
		radii.append(rr)
	return [samples, ts, radii]

func _tail_color(t: float, patch_a: float) -> Color:
	var primary: Color = _pal["primary"]
	var stripe: Color = _pal["stripe"]
	var accent: Color = _pal["accent"]
	var tl: float = float(_pal["tail_length"])
	var fluffy: bool = bool(_pal["tail_fluffy"])
	match str(_pal["pattern"]):
		"stripes":
			var rings: float = 5.0 * maxf(0.6, tl) * (0.6 if fluffy else 1.0)
			var band: float = fmod(t * rings, 1.0)
			var ring_col: Color = stripe if not fluffy else primary.lerp(stripe, 0.7)
			if (t > 0.12 and band > 0.55 and band < 0.85) or t > 0.92:
				return ring_col
		"tuxedo":
			if t > 0.84:
				return _pal["belly"]
		"points":
			return primary.lerp(accent, clampf(0.25 + t * 2.0, 0.0, 0.85))
		"patches":
			if t > patch_a - 0.12 and t < patch_a:
				return accent
			elif t >= patch_a:
				return stripe
		"wrinkles":
			return primary.lerp(stripe, 0.15 * t)
	return primary

func _tail_color_px(t: float, patch_a: float) -> Color:
	match str(_pal["pattern"]):
		"points", "wrinkles":
			return _tail_color(floorf(t * 3.0 + 0.5) / 3.0, patch_a)
	return Color(_tail_color(t, patch_a), 1.0)

# Fur tufts along both sides of the tail and fanned around its tip:
# [outline triangle, fill triangle, sample index]. Tufts lean toward the tip.
func _tail_tufts(samples: Array[Vector2], ts: Array[float], radii: Array[float], first: int) -> Array:
	var out: Array = []
	if _fur_amp <= 0.01 or samples.size() < 4:
		return out
	var n: int = samples.size()
	var spacing: float = 0.8 / (_fur_den * 1.15)
	if pixel_art:
		spacing = maxf(spacing, PIXEL_FUR_SPACING * _px)
	var step: int = maxi(2, int(round(spacing / 0.6)))
	var lean: float = float(FUR_LEAN.get(_fur_style, 0.5)) * 0.6
	var amp: float = _fur_amp * TAIL_FUR * (1.1 if bool(_pal["tail_fluffy"]) else 0.9)
	if pixel_art:
		amp = clampf(amp, _px * 1.1, _px * 2.2)
	for side in [-1.0, 1.0]:
		var i: int = maxi(first, 1) + (0 if side < 0.0 else step / 2)
		while i < n - 2:
			var d: Vector2 = (samples[i + 1] - samples[i - 1]).normalized()
			var nrm: Vector2 = Vector2(-d.y, d.x) * side
			var t: float = ts[i]
			var k: int = i * 2 + (0 if side < 0.0 else 1)
			var h: float = _hash01(k, 404)
			var L: float = amp * (0.35 + 0.65 * _ss(0.0, 0.25, t)) * lerpf(1.0, 0.5 + 0.8 * h, _fur_jit)
			var w: float = spacing * 0.7 if not pixel_art else _px * 0.7
			var bc: Vector2 = samples[i] + nrm * radii[i] * 0.6
			var tip: Vector2 = samples[i] + nrm * (radii[i] + L) + d * L * lean
			_tuft_pair(out, bc - d * w, bc + d * w, tip, i)
			i += step
	# Tip: three tufts fanned around the end direction.
	var e: int = n - 1
	var de: Vector2 = (samples[e] - samples[e - 2]).normalized()
	for k in range(3):
		var dir: Vector2 = de.rotated((float(k) - 1.0) * 0.75)
		var nrm := Vector2(-dir.y, dir.x)
		var L: float = amp * (1.0 if k == 1 else 0.8)
		var bc: Vector2 = samples[e] + dir * radii[e] * 0.3
		_tuft_pair(out, bc - nrm * radii[e] * 0.7, bc + nrm * radii[e] * 0.7, samples[e] + dir * (radii[e] + L), e)
	return out

func _tuft_pair(out: Array, b0: Vector2, b1: Vector2, tip: Vector2, idx: int) -> void:
	if pixel_art:
		# Pixel spike: plain triangle (fill only, the mask outline wraps it).
		var tri := PackedVector2Array([b0, tip, b1])
		out.append([tri, tri, idx])
		return
	var mid: Vector2 = (b0 + b1) * 0.5
	var along: Vector2 = (b1 - b0).normalized()
	var up: Vector2 = (tip - mid).normalized()
	var ow: float = _ow
	out.append([
		_tuft_shape(b0 - along * ow, b1 + along * ow, tip + up * ow * 1.2, ow),
		_tuft_shape(b0, b1, tip, 0.0), idx])

# Soft leaf-shaped tuft: quadratic curves from each base corner to the tip,
# bulging outward so tufts read as fluffy clumps, not spikes.
func _tuft_shape(b0: Vector2, b1: Vector2, tip: Vector2, grow: float) -> PackedVector2Array:
	var mid: Vector2 = (b0 + b1) * 0.5
	var up: Vector2 = tip - mid
	var c0: Vector2 = b0 + up * 0.75 - (b1 - b0) * 0.05
	var c1: Vector2 = b1 + up * 0.55 + (b1 - b0) * 0.05
	var pts := PackedVector2Array()
	for k in range(5):
		var t: float = float(k) / 5.0
		pts.append(b0.lerp(c0, t).lerp(c0.lerp(tip, t), t))
	for k in range(5):
		var t: float = float(k) / 5.0
		pts.append(tip.lerp(c1, t).lerp(c1.lerp(b1, t), t))
	pts.append(b1)
	return pts

func _draw_tail(ci: Node2D, angles: Array, skip: float = 0.0) -> void:
	if angles.is_empty():
		return
	var path: Array = _tail_path(angles)
	var samples: Array[Vector2] = path[0]
	var ts: Array[float] = path[1]
	var radii: Array[float] = path[2]
	# Never dip below the floor: flatten the tail along the ground instead.
	var floor_y: float = -ci.position.y - _ow - 0.3
	if pixel_art and _fur_amp > 0.01:
		floor_y -= _px * 2.2   # room for the pixel fur spikes under the tail
	for i in range(samples.size()):
		samples[i].y = minf(samples[i].y, floor_y - radii[i])
	var outline: Color = _pal["outline"]
	var first: int = int(skip * float(samples.size()))
	var tufts: Array = _tail_tufts(samples, ts, radii, first)
	if pixel_art:
		# Fills only; colours quantized to whole bands (no gradients).
		var rp := _part_rng(41)
		var pa: float = rp.randf_range(0.3, 0.55)
		for i in range(first, samples.size()):
			ci.draw_circle(samples[i], radii[i], _tail_color_px(ts[i], pa))
		for tf in tufts:
			ci.draw_colored_polygon(tf[1], _tail_color_px(ts[int(tf[2])], pa))
		return
	for i in range(first, samples.size()):
		ci.draw_circle(samples[i], radii[i] + _ow, outline)
	for tf in tufts:
		ci.draw_colored_polygon(tf[0], outline)
	var r := _part_rng(41)
	var patch_a: float = r.randf_range(0.3, 0.55)
	for i in range(first, samples.size()):
		ci.draw_circle(samples[i], radii[i], _tail_color(ts[i], patch_a))
	for tf in tufts:
		ci.draw_colored_polygon(tf[1], _tail_color(ts[int(tf[2])], patch_a))

# ---------------------------------------------------------------- fur edge

func _ss(e0: float, e1: float, x: float) -> float:
	if is_equal_approx(e0, e1):
		return 1.0 if x >= e1 else 0.0
	var t: float = clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _hash01(k: int, salt: int) -> float:
	var x: int = (k * 374761393 + salt * 668265263 + _fur_seed * 1274126177) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1103515245 + 12345) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x % 10007) / 10006.0

# Even arc-length resample of a closed polygon.
func _resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var n: int = poly.size()
	var per: float = 0.0
	for i in range(n):
		per += poly[i].distance_to(poly[(i + 1) % n])
	var count: int = maxi(8, int(round(per / step)))
	var ds: float = per / float(count)
	var out := PackedVector2Array()
	var seg: int = 0
	var seg_start: float = 0.0
	var seg_len: float = poly[0].distance_to(poly[1 % n])
	for k in range(count):
		var target: float = float(k) * ds
		while target > seg_start + seg_len and seg < n - 1:
			seg_start += seg_len
			seg += 1
			seg_len = poly[seg].distance_to(poly[(seg + 1) % n])
		var t: float = 0.0 if seg_len <= 0.00001 else (target - seg_start) / seg_len
		out.append(poly[seg].lerp(poly[(seg + 1) % n], clampf(t, 0.0, 1.0)))
	return out

# Fur edge pass. Resample at even arc length, then push each point out along
# its outward normal by a tuft profile and shift it along the fur flow, so
# every tuft leans backward/downward (asymmetric sawtooth). mask(rest_pt) sets
# the per-region strength. The tuft coordinate is the angle around `center`
# in rest space (seam at the bottom), so tufts stay put while legs move between
# walk frames. Fill and outline both use the returned polygon. The result is
# cleaned with a boolean union so concave corners never self-intersect.
func _fur_edge(poly: PackedVector2Array, to_rest: Transform2D, center: Vector2, radius: float, mask: Callable, flow_w: Vector2, amp_mul: float, salt: int) -> PackedVector2Array:
	if _fur_amp <= 0.01 or poly.size() < 3:
		return poly
	var spacing: float = 1.0 / _fur_den
	if pixel_art:
		spacing = maxf(spacing, PIXEL_FUR_SPACING * _px)
	var pts: PackedVector2Array = _resample(poly, clampf(spacing / 6.0, 0.3, 0.55))
	var n: int = pts.size()
	var orient: float = 1.0 if _area(pts) > 0.0 else -1.0
	var count: float = maxf(3.0, roundf(TAU * radius / spacing))
	var sharp: float = float(FUR_SHARP.get(_fur_style, 0.8))
	var lean: float = float(FUR_LEAN.get(_fur_style, 0.5))
	var out := PackedVector2Array()
	out.resize(n)
	var moved: bool = false
	for i in range(n):
		var p: Vector2 = pts[i]
		var rp: Vector2 = to_rest * p
		var m: float = float(mask.call(rp)) * amp_mul
		if m <= 0.01:
			out[i] = p
			continue
		var tng: Vector2 = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		var nrm := Vector2(tng.y, -tng.x) * orient
		var rel: Vector2 = rp - center
		var u: float = (Vector2(-rel.y, rel.x).angle() + PI) / TAU * count
		u += _fur_jit * 0.3 * sin(u * 0.9 + float(salt))
		var k: float = floorf(u)
		var f: float = u - k
		var h: float = _hash01(int(k), salt)
		var a: float = m * _fur_amp * lerpf(1.0, 0.45 + 0.9 * h, _fur_jit)
		var d: float = a * pow(1.0 - absf(2.0 * f - 1.0), sharp)
		if pixel_art:
			# Pixel spike: 1-2 art px tall, ~1.5 px wide, a sawtooth leaning
			# with the flow; weak regions (m small) drop out instead of turning
			# into sub-pixel noise.
			var amp_px: float = clampf(roundf(_fur_amp / _px * 0.9 * lerpf(1.0, 0.6 + 0.8 * h, _fur_jit)), 1.0, 2.0)
			a = amp_px * _px if m >= 0.45 else 0.0
			var wf: float = clampf(2.4 * _px / spacing, 0.15, 0.7)
			var g: float = clampf(1.0 - absf(f - 0.5) / (wf * 0.5), 0.0, 1.0)
			d = a * g
		var tan_flow: Vector2 = flow_w - nrm * flow_w.dot(nrm)
		out[i] = p + nrm * d + tan_flow * d * lean
		moved = true
	if not moved:
		return poly
	# Boolean union resolves the loops a tuft can form at concave corners;
	# keep the biggest outer ring (stray islands are sub-pixel).
	var merged: Array[PackedVector2Array] = _outers(Geometry2D.merge_polygons(poly, out))
	var best := PackedVector2Array()
	for m in merged:
		if absf(_area(m)) > absf(_area(best)):
			best = m
	return best if best.size() >= 3 else poly

# Body region mask (rest space): strong at belly underside, chest ruff and
# haunch, weak on the back top, fading to nothing down the legs and paws.
func _mask_body(p: Vector2) -> float:
	var nx: float = (p.x - _body_c.x) / _rx
	var ny: float = (p.y - _body_c.y) / _ry
	var top: float = _ss(-0.2, -0.8, ny)
	var bottom: float = _ss(0.3, 0.85, ny)
	var rear: float = _ss(-0.3, -0.85, nx)
	var front: float = _ss(0.35, 0.8, nx)
	var nf: float = float(_pal.get("neck_fluff", 1.0))
	var m: float = lerpf(0.55, float(FUR_BACK.get(_fur_style, 0.25)), top)
	m = maxf(m, 0.95 * bottom)
	m = maxf(m, 0.85 * rear * (1.0 - top))
	m = maxf(m, (0.35 + 0.55 * nf) * front * (1.0 - top * 0.7))
	var belly_y: float = _body_c.y + _ry * 0.9
	m = lerpf(m, 0.12, _ss(belly_y, belly_y + 3.0, p.y))
	m *= 1.0 - _ss(-PAW_H * 2.4, -PAW_H * 1.2, p.y)
	return m

# Head mask (head space): full cheeks, medium chin, weak top of the head.
func _mask_head(p: Vector2) -> float:
	var nx: float = p.x / _head_rx
	var ny: float = p.y / _head_ry
	var cheeks: float = _ss(0.5, 0.95, absf(nx)) * _ss(-0.35, 0.25, ny)
	var top: float = _ss(-0.35, -0.85, ny)
	var chin: float = _ss(0.55, 0.95, ny)
	var m: float = lerpf(0.4, float(FUR_BACK.get(_fur_style, 0.25)), top)
	m = maxf(m, cheeks * 1.0)
	m = maxf(m, chin * (0.25 + 0.45 * float(_pal.get("neck_fluff", 1.0))))
	return m

# ---------------------------------------------------------------- fit guard

# Shrinks the whole rig (Visual scale) when some pose of this genome would leave
# the in-game viewport window. Uses raw posed shapes (no booleans), padded by
# the outline and fur length, so it stays cheap.
func _compute_fit() -> void:
	_fit = 1.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var head_pts: PackedVector2Array = _head_extent_pts()
	var specs: Array = [[0.0, 0.0, 0.0, 0], [1.0, 0.0, 0.0, 1], [1.0, 0.0, 0.0, 5], [0.0, 1.0, 0.0, 0], [0.0, 0.0, 1.0, 0]]
	# Pixel mode: + one more art pixel for rasterization rounding / fur spikes
	# (the mask outline itself is _ow = 1 art px).
	var pad: float = _ow + 0.4 + (_px if pixel_art else 0.0)
	for sp in specs:
		var qw: float = sp[0]
		var qs: float = sp[1]
		var ql: float = sp[2]
		var pi: int = sp[3]
		var f: Dictionary = _build_frame(qw, qs, ql, pi, true)
		var fur_pad: float = _fur_amp * 1.2
		for q in f["pts"]:
			lo = lo.min(q - Vector2(fur_pad, fur_pad))
			hi = hi.max(q + Vector2(fur_pad, fur_pad))
		var hx := Transform2D(float(f["head_rot"]), f["head_pos"])
		for q in head_pts:
			var w: Vector2 = hx * q
			lo = lo.min(w)
			hi = hi.max(w)
		var ws: float = qw * (1.0 - ql) * (1.0 - qs)
		for wave in [-1.0, 1.0]:
			var path: Array = _tail_path(_tail_angles(ws, float(f["rot"]), ql, wave))
			var tp: Vector2 = f["tail_pos"]
			var smp: Array[Vector2] = path[0]
			var rad: Array[float] = path[2]
			for i in range(smp.size()):
				var e: float = rad[i] + pad + _fur_amp * TAIL_FUR * 1.3
				lo = lo.min(tp + smp[i] - Vector2(e, e))
				hi = hi.max(tp + smp[i] + Vector2(e, e))
	var half_w: float = maxf(-lo.x, hi.x) + pad + 0.4
	var top: float = -lo.y + pad + 0.8
	_fit = minf(1.0, minf(FIT_X / maxf(half_w, 1.0), FIT_TOP / maxf(top, 1.0)))

func fit_scale() -> float:
	return _fit

# Head-space points bounding the head, ears (incl. twitch range) and whiskers.
func _head_extent_pts() -> PackedVector2Array:
	var out := PackedVector2Array()
	for which in ["line", "fill"]:
		for item in _head_list(which):
			out.append_array(item[1])
	if pixel_art:
		# Whisker tips (drawn by the face, not in the head lists).
		var reach: float = float(_head_lm.get("cheek_x", _head_rx)) + _fur_amp + 4.0 * _px
		var ny: float = (_head_lm.get("nose", Vector2.ZERO) as Vector2).y
		out.append(Vector2(reach, ny + 5.0 * _px))
		out.append(Vector2(-reach * 0.5, ny + 5.0 * _px))
	var ear_key: String = "ear_fill_%d" if pixel_art else "ear_line_%d"
	for i in range(2):
		var side: int = -1 if i == 0 else 1
		var ear: Node2D = _ear_lines[i]
		var base: float = float(ear.get_meta("base_rot", 0.0))
		for extra in [0.0, 0.34 * float(side), 0.14 * float(side)]:
			var xf := Transform2D(base + extra, ear.position)
			for item in _head_list(ear_key % side):
				for q in item[1]:
					out.append(xf * q)
	return out

func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
