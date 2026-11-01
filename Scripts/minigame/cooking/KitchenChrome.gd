extends RefCounted

## Host / launcher chrome for the A..F art styles (MinigameHost window, cards, chips, buttons,
## Test Kitchen panel). Style A never calls into this beyond legacy() checks: callers keep their
## original StyleBoxFlat / theme code path, so A is byte-identical.
##
## B..F: KitchenPixelBox panels (the old oak / honey border becomes an inner band inside an ink
## outline of PixelDraw.chrome_px(); D rim + cel, E cream halo, F cocoa drop shadow), the cozy
## theme with a bold (700) font, and the shared text rule on system-font labels / buttons:
## D 1px outline, E + cream halo, F 2px outline + drop shadow (dark text gets a cream ring).
##
## Usage (no class_name; preload by path):
##   const KitchenChrome = preload("res://Scripts/minigame/cooking/KitchenChrome.gd")
##   panel.add_theme_stylebox_override("panel", KitchenChrome.box(bg, C_OAK, 3, 12, Vector4(...)))

const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")
const BOX_SCRIPT := "res://Scripts/minigame/cooking/KitchenPixelBox.gd"

const INK := Color("#4A3426")
const CREAM := Color("#FFF6EA")

static var _theme_cache: Dictionary = {}


## B..F pixel panel. band / band_w: the original border colour + width (kept as an inner band).
static func box(bg: Color, band: Color, band_w: int, radius: int, pad: Vector4 = Vector4(10, 6, 10, 6)) -> StyleBox:
	var sb: StyleBox = load(BOX_SCRIPT).new()
	var chunk: bool = PixelDraw.chunky()
	# A translucent fill (done chips: sage @ 45%) would sit on the panel's own ink outline shape
	# and turn muddy; pre-blend it over cream so the fill is as light as in A.
	var fill: Color = bg
	if fill.a < 1.0:
		fill = CREAM.blend(bg)
	sb.set("bg", fill)
	sb.set("band", band)
	sb.set("band_w", band_w)
	sb.set("outline_w", PixelDraw.chrome_px())
	sb.set("radius", mini(radius, 8) if chunk else radius)
	sb.set("step", 3 if radius >= 9 else 2)
	sb.set("rim", bool(PixelDraw.S["rim_highlight"]))
	sb.set("cel", bool(PixelDraw.S["cel_shade"]))
	sb.set("halo", 3 if bool(PixelDraw.S["halo"]) else 0)
	sb.set("shadow", 4 if bool(PixelDraw.S["drop_shadow"]) else 0)
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb


## The cozy theme for A; for B..F a copy whose SystemFont is weight 700 (shared text rule: bold).
static func ui_theme(path: String) -> Theme:
	if not ResourceLoader.exists(path):
		return null
	var base: Theme = load(path) as Theme
	if PixelDraw.legacy():
		return base
	var key: String = path + PixelDraw.style
	if _theme_cache.has(key):
		return _theme_cache[key]
	var t: Theme = base.duplicate()
	var f: Font = base.default_font
	if f is SystemFont:
		var sf: SystemFont = (f as SystemFont).duplicate()
		sf.font_weight = int(PixelDraw.S["font_weight"])
		t.default_font = sf
	_theme_cache[key] = t
	return t


## Shared text rule on a system-font Label / Button (A: removes any rule overrides it set).
## small (< 20 px) text keeps a 1px ring and no halo, like the pixel font below 2x.
static func style_text(c: Control, col: Color) -> void:
	for k in ["outline_size", "shadow_outline_size", "shadow_offset_x", "shadow_offset_y"]:
		c.remove_theme_constant_override(k)
	for k in ["font_outline_color", "font_shadow_color"]:
		c.remove_theme_color_override(k)
	if PixelDraw.legacy():
		c.add_theme_color_override("font_color", col)
		return
	var ring: int = int(PixelDraw.S["text_ring"])
	var small: bool = c.get_theme_font_size("font_size") < 20
	if small:
		ring = mini(ring, 1)
	var lum: float = col.get_luminance()
	var dark: bool = lum < 0.6
	var fc: Color = col
	if small and ring > 0 and bool(PixelDraw.S["text_shadow"]) and lum > 0.25 and lum < 0.6:
		# F: small mid-tone print (oak subtitles like "Gold paw!") with a cream ring + cocoa
		# shadow is mush; flip it to cream text so the cocoa ring reads (D / E keep the colour).
		fc = CREAM
		dark = false
	c.add_theme_color_override("font_color", fc)
	if ring > 0:
		c.add_theme_constant_override("outline_size", ring * 2)
		c.add_theme_color_override("font_outline_color", CREAM if dark else INK)
	if bool(PixelDraw.S["text_halo"]) and ring > 0 and not dark and not small:
		c.add_theme_color_override("font_shadow_color", CREAM)
		c.add_theme_constant_override("shadow_offset_x", 0)
		c.add_theme_constant_override("shadow_offset_y", 0)
		c.add_theme_constant_override("shadow_outline_size", ring * 2 + 2)
	if bool(PixelDraw.S["text_shadow"]):
		c.add_theme_color_override("font_shadow_color", PixelDraw.DROP_COL)
		c.add_theme_constant_override("shadow_offset_x", 1)
		c.add_theme_constant_override("shadow_offset_y", 1)
		c.add_theme_constant_override("shadow_outline_size", ring * 2)


## Wraps host-level pixel art (drawn into a Control at an integer scale) so E / F get the sticker
## halo / drop shadow too: while an FX style is on, the Control's own draw is skipped and an FX
## CanvasGroup child redraws the same art. draw_fn: func(ci: CanvasItem) -> void. Returns the
## updater to call after a style change (also called once now).
static func art_canvas(ctrl: Control, draw_fn: Callable, px_scale: float) -> Callable:
	ctrl.draw.connect(func() -> void:
		if not PixelDraw.fx_active():
			draw_fn.call(ctrl)
		else:
			var art: CanvasItem = ctrl.get_node_or_null("ArtFX/Art") as CanvasItem
			if art != null:
				art.queue_redraw.call_deferred())
	var update := func() -> void:
		var g: CanvasGroup = ctrl.get_node_or_null("ArtFX") as CanvasGroup
		if PixelDraw.fx_active():
			if g == null:
				g = PixelDraw.make_fx_group("ArtFX", px_scale)
				var n := Node2D.new()
				n.name = "Art"
				n.draw.connect(func() -> void: draw_fn.call(n))
				g.add_child(n)
				ctrl.add_child(g)
			g.material = PixelDraw.fx_material(px_scale)
			(g.get_node("Art") as CanvasItem).queue_redraw()
		elif g != null:
			ctrl.remove_child(g)
			g.queue_free()
		ctrl.queue_redraw()
	if not PixelDraw.legacy():
		update.call()
	return update
