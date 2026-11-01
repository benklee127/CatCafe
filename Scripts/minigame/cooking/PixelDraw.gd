extends RefCounted

## Crisp pixel-art draw helpers for the cooking minigame (and any MinigameHost game).
## Everything is drawn in the 320x180 PlayArea SubViewport space, which the host upscales by an
## integer factor with nearest filtering, so 1 unit here = 1 art pixel on screen.
##
## Usage (no class_name; preload by path):
##   const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")
##   func _draw() -> void:
##       PixelDraw.outlined_rect(self, Rect2(10, 10, 40, 20), PixelDraw.CREAM)
##
## All helpers snap their inputs to whole pixels and never antialias. Outlines default to the
## warm dark-brown OUTLINE colour. Alert orange (ALERT) is reserved for spills / overflow only.

# --- Cozy palette ------------------------------------------------------------------------
const OUTLINE := Color("#4A3426")
const CREAM := Color("#FFF6EA")
const CREAM_DARK := Color("#F1E2CC")
const OAK := Color("#C9A27A")
const OAK_DARK := Color("#A57C55")
const SAGE := Color("#8FBF9F")
const SAGE_DARK := Color("#6E9E80")
const HONEY := Color("#E8B04B")
const HONEY_LIGHT := Color("#F4D58D")
const ALERT := Color("#E07A3F")
const COCOA := Color("#2B2129")
const MILK := Color("#FBF3E4")
const COFFEE := Color("#7A4E33")
const BLUSH := Color("#F2B8A8")
const WALL := Color("#F6E7D2")
const SHADOW := Color(0.29, 0.20, 0.15, 0.25)

# ============================================================== art style switch (A..F)
## One switch for every kitchen draw helper, KitchenArt, the six verbs, CookingGame and the
## MinigameHost chrome. "A" is today's art, untouched: every helper keeps its original code path
## while legacy() is true, so A renders byte-identical. B..F are the shared minigame style options
## (same letters / wording in every minigame: art_options/shared/style_table.json).
##   outline_px     outer outline of outlined shapes (grows outward, fills keep their size)
##   chunky         2px minimum lines / details, 1px shine strokes dropped, fewer tones
##   rim_highlight  1px light rim on the top/left inside edge of filled shapes
##   cel_shade      2-tone fill: base + darker band on the bottom/right
##   halo           1px cream sticker halo around whole objects (FX CanvasGroup, see fx_material)
##   drop_shadow    1px cocoa drop shadow under whole objects (FX CanvasGroup)
##   chrome_px      ink outline (screen px) of the host window / cards / chips / buttons
##   font_weight    700 = bold pixel font + bold UI font
##   text_ring / text_halo / text_shadow: shared text rule (A today; B/C bold; D bold + 1px
##                  outline; E bold + 1px outline + cream halo; F bold + 2px outline + shadow).
## Pick: `-- --ck-art-style=D` on the command line, the Test Kitchen "Art style" option, or
## PixelDraw.set_style("D") + MinigameHost.apply_art_style() (live).
const STYLE_ORDER: Array[String] = ["A", "B", "C", "D", "E", "F"]
const STYLES: Dictionary = {
	"A": {"name": "Current (today)", "desc": "Exactly today's art, unchanged", "outline_px": 1, "chunky": false, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": false, "chrome_px": 0, "font_weight": 0, "text_ring": 0, "text_halo": false, "text_shadow": false},
	"B": {"name": "2px outline", "desc": "2px outer outline, same shapes", "outline_px": 2, "chunky": false, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": false, "chrome_px": 3, "font_weight": 700, "text_ring": 0, "text_halo": false, "text_shadow": false},
	"C": {"name": "2px + chunky shapes", "desc": "2px outline + chunky simplified shapes (2px min), fewer colours", "outline_px": 2, "chunky": true, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": false, "chrome_px": 3, "font_weight": 700, "text_ring": 0, "text_halo": false, "text_shadow": false},
	"D": {"name": "Chunky + rim light + cel shade", "desc": "2px outline + chunky + 1px top/left rim light + 2-tone cel shade", "outline_px": 2, "chunky": true, "rim_highlight": true, "cel_shade": true, "halo": false, "drop_shadow": false, "chrome_px": 3, "font_weight": 700, "text_ring": 1, "text_halo": false, "text_shadow": false},
	"E": {"name": "Sticker: outline + cream halo", "desc": "Sticker: 2px outline + cream halo + chunky", "outline_px": 2, "chunky": true, "rim_highlight": false, "cel_shade": false, "halo": true, "drop_shadow": false, "chrome_px": 3, "font_weight": 700, "text_ring": 1, "text_halo": true, "text_shadow": false},
	"F": {"name": "3px outline + chunky + drop shadow", "desc": "Heavy: 3px outline + chunky + 1px cocoa drop shadow", "outline_px": 3, "chunky": true, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": true, "chrome_px": 4, "font_weight": 700, "text_ring": 2, "text_halo": false, "text_shadow": true},
}
const HALO_COL := Color("#FFF6EA")
const DROP_COL := Color(0.169, 0.129, 0.161, 0.35)  # cocoa #2B2129 @ 35%
const ART_STYLE_ARG := "--ck-art-style="
## Owner's pick (2026-10-26): F = 3px outline + chunky + drop shadow. A stays available for comparison.
const DEFAULT_STYLE: String = "F"

static var style: String = _boot_style()
static var S: Dictionary = STYLES[style]
## Bumped on every set_style (lets callers drop cached style boxes).
static var style_rev: int = 0


static func _boot_style() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(ART_STYLE_ARG):
			var l: String = a.substr(ART_STYLE_ARG.length()).strip_edges().to_upper()
			if STYLES.has(l):
				return l
	return DEFAULT_STYLE


static func set_style(letter: String) -> void:
	var l: String = letter.strip_edges().to_upper()
	if not STYLES.has(l):
		l = "A"
	style = l
	S = STYLES[l]
	style_rev += 1


static func legacy() -> bool:
	return style == "A"


## Outline thickness in art px (1 for A).
static func ow() -> int:
	return int(S["outline_px"])


static func chunky() -> bool:
	return bool(S["chunky"])


## Ink outline (screen px) for host chrome boxes; 0 in A.
static func chrome_px() -> int:
	return int(S["chrome_px"])


## True when whole objects get the cream halo / drop shadow (E / F FX groups).
static func fx_active() -> bool:
	return bool(S["halo"]) or bool(S["drop_shadow"])


static func shade_of(c: Color) -> Color:
	return Color(c.darkened(0.16), c.a)


static func rim_of(c: Color) -> Color:
	return Color(c.lightened(0.45), c.a)


static func _is_ink(c: Color) -> bool:
	return c.a > 0.9 and absf(c.r - OUTLINE.r) < 0.02 and absf(c.g - OUTLINE.g) < 0.02 and absf(c.b - OUTLINE.b) < 0.02


static func _cel(outline: Color, fill: Color) -> bool:
	return bool(S["cel_shade"]) and fill.a > 0.99 and outline != fill


static func _rim(outline: Color, fill: Color) -> bool:
	return bool(S["rim_highlight"]) and fill.a > 0.99 and outline != fill


## E / F: canvas_item shader for a CanvasGroup that adds the 1px cream halo and / or the 1px cocoa
## drop shadow around everything drawn inside it (same shader as the other minigames, plus a
## px_scale for host art drawn at 2x..4x).
const FX_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 halo_col = vec4(1.0, 0.965, 0.918, 1.0);
uniform float halo_px = 0.0;
uniform vec4 shadow_col = vec4(0.169, 0.129, 0.161, 0.35);
uniform vec2 shadow_off = vec2(0.0, 0.0);
uniform float px_scale = 1.0;

float a_at(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).a;
}

void fragment() {
	vec4 c = textureLod(screen_tex, SCREEN_UV, 0.0);
	if (c.a > 0.0001) { c.rgb /= c.a; }
	vec2 px = SCREEN_PIXEL_SIZE * px_scale;
	vec4 under = vec4(0.0);
	if (shadow_off != vec2(0.0)) {
		float s = 0.0;
		for (int x = 0; x <= 1; x++) {
			for (int y = 0; y <= 1; y++) {
				if (x + y == 0) { continue; }
				vec2 o = vec2(float(x), float(y)) * clamp(shadow_off, vec2(-1.0), vec2(1.0));
				s = max(s, a_at(SCREEN_UV - o * px));
			}
		}
		if (s > 0.5) { under = shadow_col; }
	}
	if (halo_px > 0.0) {
		float h = 0.0;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				h = max(h, a_at(SCREEN_UV + vec2(float(x), float(y)) * px));
			}
		}
		if (h > 0.5) { under = halo_col; }
	}
	float a = c.a + under.a * (1.0 - c.a);
	vec3 rgb = a > 0.0 ? (c.rgb * c.a + under.rgb * under.a * (1.0 - c.a)) / a : vec3(0.0);
	COLOR = vec4(rgb, a);
}
"""
static var _fx_shader: Shader = null


## New ShaderMaterial for an FX CanvasGroup in the current style. px_scale = screen px per art px.
static func fx_material(px_scale: float = 1.0) -> ShaderMaterial:
	if _fx_shader == null:
		_fx_shader = Shader.new()
		_fx_shader.code = FX_SHADER
	var m := ShaderMaterial.new()
	m.shader = _fx_shader
	m.set_shader_parameter("halo_px", 1.0 if bool(S["halo"]) else 0.0)
	m.set_shader_parameter("shadow_off", Vector2(1, 1) if bool(S["drop_shadow"]) else Vector2.ZERO)
	m.set_shader_parameter("halo_col", HALO_COL)
	m.set_shader_parameter("shadow_col", DROP_COL)
	m.set_shader_parameter("px_scale", px_scale)
	return m


## A CanvasGroup marked as a kitchen FX group (pixel text inside skips its own halo / shadow).
static func make_fx_group(group_name: String, px_scale: float = 1.0) -> CanvasGroup:
	var g := CanvasGroup.new()
	g.name = group_name
	g.fit_margin = 6.0 * px_scale
	g.clear_margin = 6.0 * px_scale
	g.material = fx_material(px_scale)
	g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	g.set_meta("ck_fx", true)
	return g


static func _in_fx(ci: CanvasItem) -> bool:
	var n: Node = ci
	while n != null:
		if n is CanvasGroup and n.has_meta("ck_fx") and (n as CanvasGroup).material != null:
			return true
		n = n.get_parent()
	return false


## Thin solid rect for details (1px lines, notches, pointer rows). A: plain draw_rect. B..F: ink
## (outline-coloured) rects are at least 2px thick; chunky styles thicken every 1px detail to 2px.
static func px(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	if legacy():
		ci.draw_rect(rect, color, true)
		return
	var r: Rect2 = rect
	if _is_ink(color) or chunky():
		if r.size.x > 0.0 and r.size.x < 2.0:
			r.size.x = 2.0
		if r.size.y > 0.0 and r.size.y < 2.0:
			r.size.y = 2.0
	ci.draw_rect(r, color, true)


## Shine / highlight stroke (white glints, lighter rows). Chunky styles drop it (fewer colours).
static func hl(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	if legacy():
		ci.draw_rect(rect, color, true)
		return
	if chunky():
		return
	ci.draw_rect(rect, color, true)


## Filled polygon with an outline. A: fill + 1px closed polyline (the original look). B..F: the
## polygon grown outward by outline_px (mitred), then the fill, then the D tones.
static func outlined_poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		ci.draw_colored_polygon(pts, fill)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, outline, 1.0, false)
		return
	var grown: Array = Geometry2D.offset_polygon(pts, float(ow()), Geometry2D.JOIN_MITER)
	for gp in grown:
		ci.draw_colored_polygon(gp, outline)
	ci.draw_colored_polygon(pts, fill)
	_poly_tones(ci, pts, fill, outline)


static func _poly_tones(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline: Color) -> void:
	if _cel(outline, fill):
		var inner: Array = Geometry2D.offset_polygon(pts, -1.5, Geometry2D.JOIN_MITER)
		if not inner.is_empty():
			ci.draw_colored_polygon(pts, shade_of(fill))
			var sh := PackedVector2Array()
			for p in (inner[0] as PackedVector2Array):
				sh.append(p + Vector2(-1, -1))
			ci.draw_colored_polygon(sh, fill)
	if _rim(outline, fill):
		var inner2: Array = Geometry2D.offset_polygon(pts, -1.0, Geometry2D.JOIN_MITER)
		if not inner2.is_empty():
			var ip: PackedVector2Array = inner2[0]
			var cw: bool = Geometry2D.is_polygon_clockwise(ip)
			for i in ip.size():
				var a: Vector2 = ip[i]
				var b: Vector2 = ip[(i + 1) % ip.size()]
				var d: Vector2 = (b - a).normalized()
				var nrm := Vector2(-d.y, d.x) if cw else Vector2(d.y, -d.x)
				if nrm.dot(Vector2(-0.6, -1.0).normalized()) > 0.35:
					ci.draw_line(a, b, rim_of(fill), 1.0)


## D: cel band (bottom/right) + rim (top/left) inside a rect fill.
static func _rect_tones(ci: CanvasItem, inner: Rect2, fill: Color, outline: Color, rad: int = 0) -> void:
	if inner.size.x < 4 or inner.size.y < 4:
		return
	if _cel(outline, fill):
		var sh: float = clampf(roundf(inner.size.y * 0.28), 1.0, 3.0)
		ci.draw_rect(Rect2(inner.position.x + rad, inner.end.y - sh, inner.size.x - rad * 2, sh), shade_of(fill), true)
		ci.draw_rect(Rect2(inner.end.x - 1, inner.position.y + rad, 1, inner.size.y - rad * 2), shade_of(fill), true)
	if _rim(outline, fill):
		ci.draw_rect(Rect2(inner.position.x + 1 + rad, inner.position.y, inner.size.x - 2 - rad * 2, 1), rim_of(fill), true)
		ci.draw_rect(Rect2(inner.position.x, inner.position.y + 1 + rad, 1, roundf(inner.size.y * 0.6) - rad), rim_of(fill), true)


## D: shade crescent (bottom/right) + 1px rim arc (top/left) inside a pixel disc / ellipse fill.
static func _round_tones(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, outline: Color) -> void:
	if minf(rx, ry) < 3.0:
		return
	if _cel(outline, fill):
		_ellipse_rows(ci, c, rx, ry, shade_of(fill))
		_ellipse_rows(ci, c + Vector2(-1, -1), rx - 1.0, ry - 1.0, fill)
	if _rim(outline, fill):
		_rim_arc(ci, c, rx, ry, fill)


static func _ellipse_rows(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	var c: Vector2 = snap(center)
	var ri: int = maxi(int(ceilf(ry)), 1)
	for row in range(-ri, ri):
		var dy: float = (float(row) + 0.5) / maxf(ry, 0.5)
		var hw: float = roundf(rx * sqrt(maxf(1.0 - dy * dy, 0.0)))
		if hw > 0.0:
			ci.draw_rect(Rect2(c.x - hw, c.y + row, hw * 2.0, 1), col, true)


static func snap(v: Vector2) -> Vector2:
	return Vector2(roundf(v.x), roundf(v.y))


static func snap_rect(r: Rect2) -> Rect2:
	return Rect2(snap(r.position), snap(r.size))


## Filled rect with a 1px (or `width`) outline drawn inside the rect bounds.
static func outlined_rect(ci: CanvasItem, rect: Rect2, fill: Color, outline: Color = OUTLINE, width: int = 1) -> void:
	var r: Rect2 = snap_rect(rect)
	var w: float = float(width)
	if legacy():
		ci.draw_rect(r, outline, true)
		if r.size.x > w * 2.0 and r.size.y > w * 2.0:
			ci.draw_rect(r.grow(-w), fill, true)
		return
	ci.draw_rect(r.grow(float(ow() - 1)), outline, true)
	if r.size.x > w * 2.0 and r.size.y > w * 2.0:
		var inner: Rect2 = r.grow(-w)
		ci.draw_rect(inner, fill, true)
		_rect_tones(ci, inner, fill, outline)


## Rounded rect built from pixel steps (radius 1-6 looks best). Outline 1px.
static func rounded_rect(ci: CanvasItem, rect: Rect2, radius: int, fill: Color, outline: Color = OUTLINE) -> void:
	var r: Rect2 = snap_rect(rect)
	var rad: int = clampi(radius, 0, int(minf(r.size.x, r.size.y) * 0.5))
	if legacy():
		_rounded_fill(ci, r, rad, outline)
		if r.size.x > 2.0 and r.size.y > 2.0:
			_rounded_fill(ci, r.grow(-1.0), maxi(rad - 1, 0), fill)
		return
	var g: int = ow() - 1
	_rounded_fill(ci, r.grow(float(g)), rad + g, outline)
	if r.size.x > 2.0 and r.size.y > 2.0:
		var inner: Rect2 = r.grow(-1.0)
		var irad: int = maxi(rad - 1, 0)
		_rounded_fill(ci, inner, irad, fill)
		if _cel(outline, fill) and inner.size.y >= 4.0 and inner.size.x >= 4.0:
			# cel band clipped to the rounded shape: shade the whole fill, re-fill all but the bottom
			var sh: float = clampf(roundf(inner.size.y * 0.28), 1.0, 3.0)
			_rounded_fill(ci, inner, irad, shade_of(fill))
			_rounded_fill(ci, Rect2(inner.position, inner.size - Vector2(1, sh)), irad, fill)
		if _rim(outline, fill) and inner.size.y >= 4.0 and inner.size.x >= 4.0:
			ci.draw_rect(Rect2(inner.position.x + 1 + irad, inner.position.y, inner.size.x - 2 - irad * 2, 1), rim_of(fill), true)
			ci.draw_rect(Rect2(inner.position.x, inner.position.y + 1 + irad, 1, maxf(roundf(inner.size.y * 0.6) - irad, 1.0)), rim_of(fill), true)


static func _rounded_fill(ci: CanvasItem, r: Rect2, rad: int, color: Color) -> void:
	if rad <= 0:
		ci.draw_rect(r, color, true)
		return
	# Core cross plus per-row corner spans: keeps edges pixel-exact.
	ci.draw_rect(Rect2(r.position.x, r.position.y + rad, r.size.x, r.size.y - rad * 2), color, true)
	for row in range(rad):
		var dy: float = float(rad - row) - 0.5
		var inset: float = float(rad) - floorf(sqrt(maxf(float(rad * rad) - dy * dy, 0.0)))
		var w: float = r.size.x - inset * 2.0
		if w <= 0.0:
			continue
		ci.draw_rect(Rect2(r.position.x + inset, r.position.y + row, w, 1), color, true)
		ci.draw_rect(Rect2(r.position.x + inset, r.end.y - row - 1, w, 1), color, true)


## Filled pixel circle with outline. `r` in art pixels.
static func circle(ci: CanvasItem, center: Vector2, r: float, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		disc(ci, center, r, outline)
		if r > 1.5:
			disc(ci, center, r - 1.0, fill)
		return
	disc(ci, center, r + float(ow() - 1), outline)
	if r > 1.5:
		disc(ci, center, r - 1.0, fill)
		_disc_tones(ci, center, r - 1.0, fill, outline)


## D tones for a pixel disc (same row maths as disc()).
static func _disc_tones(ci: CanvasItem, center: Vector2, r: float, fill: Color, outline: Color) -> void:
	if r < 3.0:
		return
	if _cel(outline, fill):
		disc(ci, center, r, shade_of(fill))
		disc(ci, center + Vector2(-1, -1), r - 1.0, fill)
	if _rim(outline, fill):
		_rim_arc(ci, center, r, r, fill)


static func _rim_arc(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color) -> void:
	var done: Dictionary = {}
	for i in 13:
		var a: float = lerpf(PI * 1.02, PI * 1.6, float(i) / 12.0)
		var p: Vector2 = snap(c + Vector2(cos(a) * (rx - 1.0), sin(a) * (ry - 1.0)) - Vector2(0.5, 0.5))
		if not done.has(p):
			done[p] = true
			ci.draw_rect(Rect2(p, Vector2.ONE), rim_of(fill), true)


## Filled pixel disc (no outline), drawn as 1px rows so it stays crisp at any scale.
static func disc(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	var c: Vector2 = snap(center)
	var ri: int = int(ceilf(r))
	for row in range(-ri, ri):
		var dy: float = float(row) + 0.5
		var half: float = sqrt(maxf(r * r - dy * dy, 0.0))
		var hw: float = roundf(half)
		if hw <= 0.0:
			continue
		ci.draw_rect(Rect2(c.x - hw, c.y + row, hw * 2.0, 1), color, true)


## Ring / arc (angles in radians, 0 = right, clockwise in screen space). `thickness` in pixels.
static func ring(ci: CanvasItem, center: Vector2, radius: float, thickness: float, color: Color, from_angle: float = 0.0, to_angle: float = TAU) -> void:
	var span: float = to_angle - from_angle
	if absf(span) < 0.001:
		return
	var segs: int = maxi(8, int(absf(span) * radius * 0.6))
	if legacy():
		ci.draw_arc(snap(center), radius, from_angle, to_angle, segs, color, thickness, false)
		return
	var th: float = thickness
	var rad: float = radius
	if _is_ink(color) and th < 2.0:
		# ink outline rings: 2px, grown outward
		rad += 0.5
		th = 2.0
	elif chunky() and th < 2.0:
		th = 2.0
	ci.draw_arc(snap(center), rad, from_angle, to_angle, maxi(segs, int(absf(span) * rad)), color, th, false)


## Horizontal or vertical meter: outlined track + fill (0..1). Returns the inner rect.
static func meter(ci: CanvasItem, rect: Rect2, value: float, fill: Color, bg: Color = CREAM_DARK, outline: Color = OUTLINE, vertical: bool = false) -> Rect2:
	var r: Rect2 = snap_rect(rect)
	outlined_rect(ci, r, bg, outline)
	var inner: Rect2 = r.grow(-1.0)
	var v: float = clampf(value, 0.0, 1.0)
	if vertical:
		var h: float = roundf(inner.size.y * v)
		if h > 0.0:
			ci.draw_rect(Rect2(inner.position.x, inner.end.y - h, inner.size.x, h), fill, true)
	else:
		var w: float = roundf(inner.size.x * v)
		if w > 0.0:
			ci.draw_rect(Rect2(inner.position.x, inner.position.y, w, inner.size.y), fill, true)
	return inner


## A band marker on a meter (e.g. the sweet zone). from/to are 0..1 along the meter axis.
static func meter_band(ci: CanvasItem, inner: Rect2, from_v: float, to_v: float, color: Color, vertical: bool = false) -> void:
	var a: float = clampf(minf(from_v, to_v), 0.0, 1.0)
	var b: float = clampf(maxf(from_v, to_v), 0.0, 1.0)
	if vertical:
		var y0: float = roundf(inner.end.y - inner.size.y * b)
		var y1: float = roundf(inner.end.y - inner.size.y * a)
		ci.draw_rect(Rect2(inner.position.x, y0, inner.size.x, maxf(y1 - y0, 1.0)), color, true)
	else:
		var x0: float = roundf(inner.position.x + inner.size.x * a)
		var x1: float = roundf(inner.position.x + inner.size.x * b)
		ci.draw_rect(Rect2(x0, inner.position.y, maxf(x1 - x0, 1.0), inner.size.y), color, true)


## Crisp 1px line (axis-aligned lines are exact; diagonals use draw_line without AA).
static func line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color = OUTLINE, width: float = 1.0) -> void:
	if legacy():
		ci.draw_line(snap(a) + Vector2(0.5, 0.5), snap(b) + Vector2(0.5, 0.5), color, width, false)
		return
	var w: int = int(roundf(width))
	if _is_ink(color) or chunky():
		w = maxi(w, 2)
	if w <= 1:
		ci.draw_line(snap(a) + Vector2(0.5, 0.5), snap(b) + Vector2(0.5, 0.5), color, width, false)
		return
	# B..F: w x w pixel pen stamped along a Bresenham walk (crisp, no polygon slivers).
	var p0: Vector2i = Vector2i(snap(a))
	var p1: Vector2i = Vector2i(snap(b))
	var dx: int = absi(p1.x - p0.x)
	var dy: int = -absi(p1.y - p0.y)
	var sx: int = 1 if p0.x < p1.x else -1
	var sy: int = 1 if p0.y < p1.y else -1
	var err: int = dx + dy
	var off: float = float(w / 2)
	if dy == 0 or dx == 0:
		var r := Rect2(Vector2(mini(p0.x, p1.x), mini(p0.y, p1.y)) - Vector2(off if dx == 0 else 0.0, off if dy == 0 else 0.0), Vector2(dx + (w if dx == 0 else 1), -dy + (w if dy == 0 else 1)))
		ci.draw_rect(r, color, true)
		return
	var guard: int = 0
	while guard < 2048:
		guard += 1
		ci.draw_rect(Rect2(Vector2(p0) - Vector2(off, off), Vector2(w, w)), color, true)
		if p0 == p1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			p0.x += sx
		if e2 <= dx:
			err += dx
			p0.y += sy


## Dotted path through points (for TRACE guides). `gap` = pixels between dots.
static func dotted(ci: CanvasItem, points: PackedVector2Array, color: Color, gap: float = 4.0, dot: float = 1.0) -> void:
	if points.size() < 2:
		return
	if not legacy() and chunky():
		dot = maxf(dot, 2.0)
		gap = maxf(gap, dot + 2.0)
	var carry: float = 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg: float = a.distance_to(b)
		var t: float = carry
		while t < seg:
			var p: Vector2 = snap(a.lerp(b, t / seg))
			ci.draw_rect(Rect2(p, Vector2(dot, dot)), color, true)
			t += gap
		carry = t - seg


## Small 5-point star (size = outer radius in px). Filled + outlined.
static func star(ci: CanvasItem, center: Vector2, size: float, fill: Color = HONEY, outline: Color = OUTLINE) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var ang: float = -PI * 0.5 + float(i) * PI / 5.0
		var rr: float = size if i % 2 == 0 else size * 0.45
		pts.append(snap(center + Vector2(cos(ang), sin(ang)) * rr))
	if not legacy():
		outlined_poly(ci, pts, fill, outline)
		return
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, outline, 1.0, false)


## Paw print (pad + 4 toes). `s` ~ overall radius in px (3..10).
static func paw(ci: CanvasItem, center: Vector2, s: float, color: Color = OUTLINE) -> void:
	var c: Vector2 = snap(center)
	if not legacy() and chunky():
		s = maxf(s, 4.0)
	disc(ci, c + Vector2(0, s * 0.35), s * 0.55, color)
	var toe: float = maxf(s * 0.24, 1.0 if legacy() or not chunky() else 1.5)
	disc(ci, c + Vector2(-s * 0.62, -s * 0.15), toe, color)
	disc(ci, c + Vector2(-s * 0.22, -s * 0.55), toe, color)
	disc(ci, c + Vector2(s * 0.22, -s * 0.55), toe, color)
	disc(ci, c + Vector2(s * 0.62, -s * 0.15), toe, color)


## Tiny sparkle (plus shape), for pop reactions.
static func sparkle(ci: CanvasItem, center: Vector2, size: int, color: Color = HONEY_LIGHT) -> void:
	var c: Vector2 = snap(center)
	if not legacy() and chunky():
		# 2px arms, 2x2 core
		ci.draw_rect(Rect2(c.x - size - 1, c.y, size * 2 + 2, 2), color, true)
		ci.draw_rect(Rect2(c.x, c.y - size - 1, 2, size * 2 + 2), color, true)
		return
	ci.draw_rect(Rect2(c.x - size, c.y, size * 2 + 1, 1), color, true)
	ci.draw_rect(Rect2(c.x, c.y - size, 1, size * 2 + 1), color, true)
	ci.draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), color, true)


# --- Bitmap pixel font -------------------------------------------------------------------------
# A tiny hand-made proportional font (caps 5x7, lowercase x-height 5, descenders 2) drawn as solid
# 1px runs, so text inside the upscaled viewport is as crisp as the art (no antialias fringe).
# Glyph format: "<first row>:<row>|<row>|..." with '#' = ink; rows count down from the cap top
# (row 6 sits on the baseline, rows 7-8 are descenders). Width = longest row.
const _GLYPHS: Dictionary = {
	"A": "0:.###.|#...#|#...#|#####|#...#|#...#|#...#",
	"B": "0:####.|#...#|#...#|####.|#...#|#...#|####.",
	"C": "0:.###.|#...#|#....|#....|#....|#...#|.###.",
	"D": "0:####.|#...#|#...#|#...#|#...#|#...#|####.",
	"E": "0:#####|#....|#....|####.|#....|#....|#####",
	"F": "0:#####|#....|#....|####.|#....|#....|#....",
	"G": "0:.###.|#...#|#....|#.###|#...#|#...#|.####",
	"H": "0:#...#|#...#|#...#|#####|#...#|#...#|#...#",
	"I": "0:###|.#.|.#.|.#.|.#.|.#.|###",
	"J": "0:..###|...#.|...#.|...#.|#..#.|#..#.|.##..",
	"K": "0:#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
	"L": "0:#....|#....|#....|#....|#....|#....|#####",
	"M": "0:#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
	"N": "0:#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
	"O": "0:.###.|#...#|#...#|#...#|#...#|#...#|.###.",
	"P": "0:####.|#...#|#...#|####.|#....|#....|#....",
	"Q": "0:.###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
	"R": "0:####.|#...#|#...#|####.|#.#..|#..#.|#...#",
	"S": "0:.###.|#...#|#....|.###.|....#|#...#|.###.",
	"T": "0:#####|..#..|..#..|..#..|..#..|..#..|..#..",
	"U": "0:#...#|#...#|#...#|#...#|#...#|#...#|.###.",
	"V": "0:#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
	"W": "0:#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#",
	"X": "0:#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
	"Y": "0:#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
	"Z": "0:#####|....#|...#.|..#..|.#...|#....|#####",
	"a": "2:.##.|...#|.###|#..#|.###",
	"b": "0:#...|#...|###.|#..#|#..#|#..#|###.",
	"c": "2:.###|#...|#...|#...|.###",
	"d": "0:...#|...#|.###|#..#|#..#|#..#|.###",
	"e": "2:.##.|#..#|####|#...|.###",
	"f": "0:.##|#..|###|#..|#..|#..|#..",
	"g": "2:.###|#..#|#..#|#..#|.###|...#|###.",
	"h": "0:#...|#...|###.|#..#|#..#|#..#|#..#",
	"i": "0:#|.|#|#|#|#|#",
	"j": "0:.#|..|.#|.#|.#|.#|.#|.#|#.",
	"k": "0:#...|#...|#..#|#.#.|##..|#.#.|#..#",
	"l": "0:#.|#.|#.|#.|#.|#.|.#",
	"m": "2:##.#.|#.#.#|#.#.#|#.#.#|#.#.#",
	"n": "2:###.|#..#|#..#|#..#|#..#",
	"o": "2:.##.|#..#|#..#|#..#|.##.",
	"p": "2:###.|#..#|#..#|#..#|###.|#...|#...",
	"q": "2:.###|#..#|#..#|#..#|.###|...#|...#",
	"r": "2:#.#|##.|#..|#..|#..",
	"s": "2:.###|#...|.##.|...#|###.",
	"t": "0:#..|#..|###|#..|#..|#..|.##",
	"u": "2:#..#|#..#|#..#|#..#|.###",
	"v": "2:#...#|#...#|.#.#.|.#.#.|..#..",
	"w": "2:#...#|#...#|#.#.#|#.#.#|.#.#.",
	"x": "2:#..#|#..#|.##.|#..#|#..#",
	"y": "2:#..#|#..#|#..#|#..#|.###|...#|###.",
	"z": "2:####|...#|.##.|#...|####",
	"0": "0:.##.|#..#|#..#|#..#|#..#|#..#|.##.",
	"1": "0:.#.|##.|.#.|.#.|.#.|.#.|###",
	"2": "0:.##.|#..#|...#|..#.|.#..|#...|####",
	"3": "0:###.|...#|...#|.##.|...#|...#|###.",
	"4": "0:#..#|#..#|#..#|####|...#|...#|...#",
	"5": "0:####|#...|#...|###.|...#|...#|###.",
	"6": "0:.##.|#...|#...|###.|#..#|#..#|.##.",
	"7": "0:####|...#|...#|..#.|..#.|.#..|.#..",
	"8": "0:.##.|#..#|#..#|.##.|#..#|#..#|.##.",
	"9": "0:.##.|#..#|#..#|.###|...#|...#|.##.",
	" ": "0:...",
	".": "6:#",
	",": "6:.#|#.",
	":": "2:#|.|.|.|#",
	";": "2:.#|..|..|..|.#|#.",
	"!": "0:#|#|#|#|#|.|#",
	"?": "0:.##.|#..#|...#|..#.|.#..|....|.#..",
	"'": "0:#|#",
	"\"": "0:#.#|#.#",
	"-": "3:###",
	"+": "2:.#.|.#.|###|.#.|.#.",
	"=": "2:###|...|###",
	"_": "7:####",
	"/": "0:...#|..#.|..#.|.#..|.#..|#...|#...",
	"%": "0:##..#|##..#|...#.|..#..|.#...|#..##|#..##",
	"(": "0:.#|#.|#.|#.|#.|#.|.#",
	")": "0:#.|.#|.#|.#|.#|.#|#.",
	"<": "1:..#|.#.|#..|.#.|..#",
	">": "1:#..|.#.|..#|.#.|#..",
	"^": "0:.#.|#.#",
	"*": "1:#.#|.#.|#.#",
	"~": "2:.#..#|#.##.",
	"$": "0:.###.|#.#..|.###.|..#.#|..#.#|####.|..#..",
	"#": "1:.#.#.|#####|.#.#.|#####|.#.#.",
	"&": "0:.##..|#..#.|.##..|.#...|#.#.#|#..#.|.##.#",
	"[": "0:##|#.|#.|#.|#.|#.|##",
	"]": "0:##|.#|.#|.#|.#|.#|##",
	"|": "0:#|#|#|#|#|#|#",
	"@": "0:.###.|#...#|#.###|#.#.#|#.##.|#....|.###.",
	"★": "0:..#..|..#..|#####|.###.|.#.#.|#...#",
	"☆": "0:..#..|.#.#.|##.##|#...#|.#.#.|#.#.#",
}
const GLYPH_H := 7
## B..F bold at 1x: hand-made bold bitmaps for glyphs whose 1px inner gaps a +1px stroke would
## close or blur (W read as N / H, M, w). Used instead of the auto-grow for these glyphs only.
const _BOLD_GLYPHS: Dictionary = {
	"W": "0:##...##|##...##|##...##|##.#.##|##.#.##|###.###|##...##",
	"M": "0:##...##|###.###|##.#.##|##.#.##|##...##|##...##|##...##",
	"w": "2:##...##|##...##|##.#.##|##.#.##|.##.##.",
}
static var _glyph_cache: Dictionary = {}


## Parsed glyph: {w: int, runs: Array[Vector3i(x, row, len)]}. Unknown chars render as '?'.
static func _glyph(ch: String, bold_1x: bool = false) -> Dictionary:
	var key: String = ("b:" + ch) if bold_1x and _BOLD_GLYPHS.has(ch) else ch
	if _glyph_cache.has(key):
		return _glyph_cache[key]
	var src: String = String(_GLYPHS.get(ch, _GLYPHS.get(ch.to_upper(), _GLYPHS["?"])))
	if key != ch:
		src = String(_BOLD_GLYPHS[ch])
	var first: int = int(src.get_slice(":", 0))
	var rows: PackedStringArray = src.substr(src.find(":") + 1).split("|")
	var w: int = 0
	var runs: Array[Vector3i] = []
	var cells: Dictionary = {}
	for ri in range(rows.size()):
		var row: String = rows[ri]
		w = maxi(w, row.length())
		var x: int = 0
		while x < row.length():
			if row[x] == "#":
				var x2: int = x
				while x2 < row.length() and row[x2] == "#":
					x2 += 1
				runs.append(Vector3i(x, first + ri, x2 - x))
				for cx in range(x, x2):
					cells[Vector2i(cx, first + ri)] = true
				x = x2
			else:
				x += 1
	# B..F bold: each run grows `bold` px to the right, except into a 1-unit inner gap (the
	# gaps in m / w / M / W / N / # / %), which would close the gap ('m' -> block, 'W' -> 'H').
	var grow_ok: Array[bool] = []
	for r in runs:
		# hand-made bold glyphs are already bold: no extra grow
		grow_ok.append(key == ch and not cells.has(Vector2i(r.x + r.z + 1, r.y)))
	var g: Dictionary = {"w": w, "runs": runs, "grow": grow_ok}
	_glyph_cache[key] = g
	return g


static func _font_scale(font_size: int) -> int:
	return maxi(1, int(roundf(float(font_size) / 8.0)))


## Width in art pixels of `s` at `font_size` (8 -> 1x glyphs, 16 -> 2x).
static func text_width(s: String, font_size: int = 8) -> float:
	var sc: int = _font_scale(font_size)
	var bold: int = _bold(sc)
	var w: int = 0
	for i in range(s.length()):
		w += (int(_glyph(s[i], bold > 0 and sc == 1)["w"]) + 1) * sc + bold
	return float(maxi(w - sc, 0))


## B..F bold pixel font: px added to the right of every glyph run (0 in A), except runs that sit
## 1 glyph unit left of more ink (see _glyph "grow"); every glyph also advances `bold` px more.
static func _bold(sc: int) -> int:
	if legacy() or int(S["font_weight"]) <= 0:
		return 0
	return maxi(1, sc / 2)


## Pixel-font text. `pos` is the left end of the baseline (like draw_string); caps are 7px tall
## at size 8. Sizes 8 and 16 are the intended ones. `width` + `align` centre / right-align.
static func text(ci: CanvasItem, pos: Vector2, s: String, color: Color = OUTLINE, font_size: int = 8, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var sc: int = _font_scale(font_size)
	var p: Vector2 = snap(pos)
	if width > 0.0 and align != HORIZONTAL_ALIGNMENT_LEFT:
		var tw: float = text_width(s, font_size)
		p.x += roundf((width - tw) * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0))
	var top: float = p.y - float(GLYPH_H * sc)
	if not legacy():
		_styled_text(ci, Vector2(p.x, top), s, color, sc)
		return
	var x: float = p.x
	for i in range(s.length()):
		var g: Dictionary = _glyph(s[i])
		for r in g["runs"]:
			var run: Vector3i = r
			ci.draw_rect(Rect2(x + run.x * sc, top + run.y * sc, run.z * sc, sc), color, true)
		x += float((int(g["w"]) + 1) * sc)


## B..F shared text rule: bold runs; D/E/F an outline ring (1px below 2x glyphs, F 2px at 2x);
## E a cream halo outside the ring (2x glyphs); F a cocoa drop shadow. Dark text gets a cream ring
## (an ink ring around ink text is a blob). Inside an E/F FX group the group adds halo / shadow.
static func _styled_text(ci: CanvasItem, tl: Vector2, s: String, color: Color, sc: int) -> void:
	var bold: int = _bold(sc)
	if color.a < 0.5:
		_text_runs(ci, tl, s, color, sc, 0, bold)
		return
	var ring: int = int(S["text_ring"])
	if sc < 2:
		ring = mini(ring, 1)
	var light_ring: bool = color.get_luminance() < 0.6
	var rc: Color = Color(CREAM, color.a) if light_ring else Color(OUTLINE, color.a)
	var fx: bool = _in_fx(ci)
	var halo: bool = bool(S["text_halo"]) and not fx and ring > 0 and not light_ring and sc >= 2
	var outer: int = ring + (1 if halo else 0)
	if bool(S["text_shadow"]) and not fx:
		_text_mask(ci, tl + Vector2(1, 1), s, Color(DROP_COL, DROP_COL.a * color.a), sc, outer, bold)
	if halo:
		_text_runs(ci, tl, s, Color(HALO_COL, color.a), sc, ring + 1, bold)
	if ring > 0:
		_text_runs(ci, tl, s, rc, sc, ring, bold)
	_text_runs(ci, tl, s, color, sc, 0, bold)


static func _text_runs(ci: CanvasItem, tl: Vector2, s: String, color: Color, sc: int, grow: int, bold: int) -> void:
	var x: float = tl.x
	for i in range(s.length()):
		var g: Dictionary = _glyph(s[i], bold > 0 and sc == 1)
		var runs: Array = g["runs"]
		for ri in runs.size():
			var run: Vector3i = runs[ri]
			var b: int = bold if bool(g["grow"][ri]) else 0
			var rr := Rect2(x + run.x * sc, tl.y + run.y * sc, run.z * sc + b, sc)
			if grow > 0:
				rr = rr.grow(float(grow))
			ci.draw_rect(rr, color, true)
		x += float((int(g["w"]) + 1) * sc + bold)


## Translucent text footprint (each pixel once, so overlapping runs never double the alpha).
static func _text_mask(ci: CanvasItem, tl: Vector2, s: String, color: Color, sc: int, grow: int, bold: int) -> void:
	var pxs: Dictionary = {}
	var x: int = int(tl.x)
	for i in range(s.length()):
		var g: Dictionary = _glyph(s[i], bold > 0 and sc == 1)
		var runs: Array = g["runs"]
		for ri in runs.size():
			var run: Vector3i = runs[ri]
			var x0: int = x + run.x * sc - grow
			var x1: int = x + (run.x + run.z) * sc + (bold if bool(g["grow"][ri]) else 0) + grow
			var y0: int = int(tl.y) + run.y * sc - grow
			var y1: int = int(tl.y) + (run.y + 1) * sc + grow
			for yy in range(y0, y1):
				for xx in range(x0, x1):
					pxs[Vector2i(xx, yy)] = true
		x += (int(g["w"]) + 1) * sc + bold
	var rows: Dictionary = {}
	for k in pxs.keys():
		var v: Vector2i = k
		if not rows.has(v.y):
			rows[v.y] = []
		(rows[v.y] as Array).append(v.x)
	for yy in rows.keys():
		var xs: Array = rows[yy]
		xs.sort()
		var i2: int = 0
		while i2 < xs.size():
			var j: int = i2
			while j + 1 < xs.size() and int(xs[j + 1]) == int(xs[j]) + 1:
				j += 1
			ci.draw_rect(Rect2(int(xs[i2]), int(yy), int(xs[j]) - int(xs[i2]) + 1, 1), color, true)
			i2 = j + 1


## Drop shadow ellipse under objects.
static func shadow(ci: CanvasItem, center: Vector2, half_w: float, half_h: float = 2.0) -> void:
	var c: Vector2 = snap(center)
	var hh: int = maxi(int(half_h), 1)
	for row in range(-hh, hh):
		var dy: float = (float(row) + 0.5) / float(hh)
		var hw: float = roundf(half_w * sqrt(maxf(1.0 - dy * dy, 0.0)))
		if hw > 0.0:
			ci.draw_rect(Rect2(c.x - hw, c.y + row, hw * 2.0, 1), SHADOW, true)


## Simple mug: body rect + handle + optional liquid fill (0..1). Bottom-centre anchored.
static func mug(ci: CanvasItem, bottom_center: Vector2, w: float, h: float, body: Color, liquid: Color, fill: float = 0.0) -> Rect2:
	var r := Rect2(bottom_center.x - w * 0.5, bottom_center.y - h, w, h)
	shadow(ci, bottom_center + Vector2(0, 1), w * 0.6, 2)
	# handle
	var hr := Rect2(r.end.x - 1, r.position.y + h * 0.25, maxf(w * 0.28, 4), h * 0.45)
	rounded_rect(ci, hr, 2, body)
	ci.draw_rect(snap_rect(hr.grow(-2.0)), CREAM_DARK, true)
	rounded_rect(ci, r, 2, body)
	var inner: Rect2 = snap_rect(r.grow(-2.0))
	var f: float = clampf(fill, 0.0, 1.0)
	if f > 0.0:
		var lh: float = roundf(inner.size.y * f)
		ci.draw_rect(Rect2(inner.position.x, inner.end.y - lh, inner.size.x, lh), liquid, true)
	return inner
