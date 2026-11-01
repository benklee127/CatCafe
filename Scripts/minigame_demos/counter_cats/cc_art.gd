extends RefCounted

## Counter Cats demo: palette + procedural pixel sprites (no image imports).
## Sprites are ASCII maps -> Image -> ImageTexture, with an automatic 1px
## warm dark-brown outline (#4A3426) around every opaque blob.
## No class_name on purpose: preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd").

const OUTLINE := Color("#4A3426")
const CREAM := Color("#FFF6EA")
const OAK := Color("#C9A27A")
const OAK_DARK := Color("#A87B55")
const OAK_DEEP := Color("#8A6243")
const OAK_LIGHT := Color("#DDBB93")
const WALL := Color("#F6E3C8")
const WALL_STRIPE := Color("#F0D8B8")
const SAGE := Color("#8FBF9F")
const SAGE_DARK := Color("#5E8C61")
const AMBER := Color("#E8B04B")
const ORANGE := Color("#E07A3F")
const PINK := Color("#E79AA0")
const ROSE := Color("#C0563A")
const SKY := Color("#BFE0EA")
const COFFEE := Color("#7A4A2E")
const ESPRESSO := Color("#4F2E1C")
const MILK := Color("#FFF3DC")
const FOAM := Color("#FFFDF6")
const DOUGH := Color("#EBCB94")
const COOKIE := Color("#D49A5A")
const MANGO := Color("#F2A541")
const SESAME := Color("#3E3533")
const VANILLA := Color("#FBF0D2")
const GOLD := Color("#F2C14E")
const LILAC := Color("#B9A6C9")
const TEXT := Color("#4A3426")
const MUTED := Color("#8D6E57")
const SHADOW := Color(0.169, 0.129, 0.161, 0.35)   # cocoa #2B2129 @ 35%

# ------------------------------------------------------------------ art style switch
## One switch read by every Counter Cats draw helper (sprites, props, background,
## gauges, stamps, window chrome, fonts). "A" = today's art, byte-identical.
## Letters are shared with the other minigame demos so the owner picks once.
##   outline_px  sprite/prop outline thickness (art pixels)
##   chunky      simplified shapes: min feature 2px, fewer colours, bolder silhouettes
##   rim         1px light rim on the top/left inner edge
##   cel         2-tone cel shading (base + shade on the bottom/right)
##   halo        1px cream "sticker" ring outside the outline
##   shadow      1px offset cocoa contact/drop shadow (35%)
##   chrome_px   dark outline on window/chips/buttons/meters (screen px; 0 = today's)
##   font_weight UI font weight (0 = theme default)
const STYLE_ORDER: String = "ABCDEF"
const STYLES: Dictionary = {
	"A": {"name": "Current (today)", "desc": "Exactly today's art, unchanged", "outline_px": 1, "chunky": false, "rim": false, "cel": false, "halo": false, "shadow": false, "chrome_px": 0, "font_weight": 0},
	"B": {"name": "2px outline", "desc": "2px outer outline, same shapes", "outline_px": 2, "chunky": false, "rim": false, "cel": false, "halo": false, "shadow": false, "chrome_px": 3, "font_weight": 700},
	"C": {"name": "2px + chunky shapes", "desc": "2px outline + chunky simplified shapes (2px min), fewer colours", "outline_px": 2, "chunky": true, "rim": false, "cel": false, "halo": false, "shadow": false, "chrome_px": 3, "font_weight": 700},
	"D": {"name": "Chunky + rim light + cel shade", "desc": "2px outline + chunky + 1px top/left rim light + 2-tone cel shade", "outline_px": 2, "chunky": true, "rim": true, "cel": true, "halo": false, "shadow": false, "chrome_px": 3, "font_weight": 700},
	"E": {"name": "Sticker: outline + cream halo", "desc": "Sticker: 2px outline + cream halo + chunky", "outline_px": 2, "chunky": true, "rim": false, "cel": false, "halo": true, "shadow": false, "chrome_px": 3, "font_weight": 700},
	"F": {"name": "3px outline + chunky + drop shadow", "desc": "Heavy: 3px outline + chunky + 1px cocoa drop shadow", "outline_px": 3, "chunky": true, "rim": false, "cel": false, "halo": false, "shadow": true, "chrome_px": 4, "font_weight": 700},
}

## Shared text rule (same letters in every minigame): B/C bold; D bold + 1px
## outline; E bold + 1px outline + cream halo; F bold + 2px outline + drop shadow.
const TEXT_RULES: Dictionary = {
	"A": {"outline": 0, "halo": 0, "shadow": 0},
	"B": {"outline": 0, "halo": 0, "shadow": 0},
	"C": {"outline": 0, "halo": 0, "shadow": 0},
	"D": {"outline": 1, "halo": 0, "shadow": 0},
	"E": {"outline": 1, "halo": 1, "shadow": 0},
	"F": {"outline": 2, "halo": 0, "shadow": 1},
}

## Owner's pick (2026-10-26): F = 3px outline + chunky + drop shadow. A stays available for comparison.
const DEFAULT_STYLE: String = "F"

static var style: String = _boot_style()
static var style_rev: int = 0
static var _cache: Dictionary = {}

## Forced from the command line for tests: `-- --cc-art-style=D` (or env CC_ART_STYLE=D).
static func _boot_style() -> String:
	var v: String = OS.get_environment("CC_ART_STYLE")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cc-art-style="):
			v = a.substr(15)
	v = v.strip_edges().to_upper()
	return v if v.length() == 1 and STYLES.has(v) else DEFAULT_STYLE

static func set_style(letter: String) -> void:
	var l: String = letter.strip_edges().to_upper()
	if l.length() != 1 or not STYLES.has(l) or l == style:
		return
	style = l
	style_rev += 1
	_cache.clear()

static func st() -> Dictionary:
	return STYLES[style]

static func is_a() -> bool:
	return style == "A"

static func ow() -> int:
	return int(STYLES[style]["outline_px"])

static func chunky() -> bool:
	return bool(STYLES[style]["chunky"])

static func flag(k: String) -> bool:
	return bool(STYLES[style].get(k, false))

## Transparent padding around every sprite (outline + halo + shadow).
static func sprite_pad() -> int:
	if style == "A":
		return 1
	return ow() + (1 if flag("halo") else 0) + (1 if flag("shadow") else 0)

## Chunky ASCII map when the style wants simplified shapes.
static func _pick(normal: Array, chunk: Array) -> Array:
	return chunk if chunky() else normal

static func rim_col(c: Color) -> Color:
	return c.lightened(0.38)

static func cel_col(c: Color) -> Color:
	return c.darkened(0.18)

## rows: Array[String]; legend: char -> Color ("." = empty). outline: add 1px border
## (style A) or the style's outline/halo/shadow/rim/cel treatment (B-F).
static func make(key: String, rows: Array, legend: Dictionary, outline: bool = true) -> ImageTexture:
	if style != "A":
		return _make_styled(key + "@" + style, rows, legend, outline)
	if _cache.has(key):
		return _cache[key]
	var h: int = rows.size()
	var w: int = 0
	for r in rows:
		w = maxi(w, String(r).length())
	var pad: int = 1 if outline else 0
	var img := Image.create(w + pad * 2, h + pad * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var row: String = rows[y]
		for x in range(row.length()):
			var ch: String = row[x]
			if legend.has(ch):
				img.set_pixel(x + pad, y + pad, legend[ch])
	if outline:
		_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _outline(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var mark: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixel(q.x, q.y).a > 0.5:
					mark.append(Vector2i(x, y))
					break
	for p in mark:
		img.set_pixel(p.x, p.y, OUTLINE)

static func _make_styled(key: String, rows: Array, legend: Dictionary, outline: bool) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var h: int = rows.size()
	var w: int = 0
	for r in rows:
		w = maxi(w, String(r).length())
	var pad_px: int = sprite_pad() if outline else 0
	var img := Image.create(w + pad_px * 2, h + pad_px * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var row: String = rows[y]
		for x in range(row.length()):
			var ch: String = row[x]
			if legend.has(ch):
				img.set_pixel(x + pad_px, y + pad_px, legend[ch])
	shade_image(img)
	if outline:
		style_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _solid(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5

## Rim light (top/left inner edge) + cel shade (bottom/right inner edge) on opaque art.
static func shade_image(img: Image) -> void:
	if not (flag("rim") or flag("cel")):
		return
	var src: Image = img.duplicate()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = src.get_pixel(x, y)
			if c.a <= 0.5 or c.is_equal_approx(OUTLINE):
				continue
			var top_l: bool = not _solid(src, x, y - 1) or not _solid(src, x - 1, y)
			var bot_r: bool = not _solid(src, x, y + 1) or not _solid(src, x + 1, y) or not _solid(src, x, y + 2)
			if flag("rim") and top_l:
				img.set_pixel(x, y, rim_col(c))
			elif flag("cel") and bot_r:
				img.set_pixel(x, y, cel_col(c))

## The style's outline (outline_px rings, 4-neighbour so corners stay round),
## then the cream sticker halo and the offset cocoa drop shadow.
static func style_outline(img: Image) -> void:
	for i in range(ow()):
		_ring(img, OUTLINE)
	if flag("halo"):
		_ring(img, CREAM)
	if flag("shadow"):
		var src: Image = img.duplicate()
		for y in range(1, img.get_height()):
			for x in range(1, img.get_width()):
				if not _solid(src, x, y) and _solid(src, x - 1, y - 1):
					img.set_pixel(x, y, SHADOW)

static func _ring(img: Image, col: Color) -> void:
	var mark: Array[Vector2i] = []
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				continue
			if _solid(img, x + 1, y) or _solid(img, x - 1, y) or _solid(img, x, y + 1) or _solid(img, x, y - 1):
				mark.append(Vector2i(x, y))
	for p in mark:
		img.set_pixel(p.x, p.y, col)

# ------------------------------------------------------------------ sprites

static func heart() -> ImageTexture:
	return make("heart", _pick([
		".XX.XX.",
		"XWXXXXX",
		"XXXXXXX",
		".XXXXX.",
		"..XXX..",
		"...X...",
	], [
		".XX..XX.",
		"XXXXXXXX",
		"XXXXXXXX",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		"...XX...",
	]), {"X": PINK, "W": Color.WHITE})

static func paw(col: Color = FOAM, key: String = "paw") -> ImageTexture:
	return make(key, _pick([
		"..XX...XX..",
		"..XX...XX..",
		"XX.......XX",
		"XX..XXX..XX",
		"...XXXXX...",
		"..XXXXXXX..",
		"..XXXXXXX..",
		"...XXXXX...",
	], [
		"...XXX..XXX...",
		"...XXX..XXX...",
		"...XXX..XXX...",
		"XX..........XX",
		"XX..XXXXXX..XX",
		"XX..XXXXXX..XX",
		"...XXXXXXXX...",
		"...XXXXXXXX...",
		"....XXXXXX....",
	]), {"X": col})

static func fish() -> ImageTexture:
	return make("fish", _pick([
		"..XXXX..X",
		".XXXXXXXX",
		"XOXXXXXX.",
		".XXXXXXXX",
		"..XXXX..X",
	], [
		"..XXXXX.....",
		".XXXXXXX..XX",
		"XXOOXXXXXXXX",
		"XXOOXXXXXXXX",
		".XXXXXXX..XX",
		"..XXXXX.....",
	]), {"X": Color("#9FD3E0"), "O": OUTLINE})

static func wafer() -> ImageTexture:
	return make("wafer", _pick([
		"....X....",
		"...XXX...",
		"...XPX...",
		"..XXPXX..",
		"..XPPPX..",
		".XXPPPXX.",
		".XPPPPPX.",
		"XXXXXXXXX",
	], [
		"....XX....",
		"...XXXX...",
		"...XXXX...",
		"..XXPPXX..",
		"..XXPPXX..",
		".XXPPPPXX.",
		".XXPPPPXX.",
		"XXXXXXXXXX",
		"XXXXXXXXXX",
	]), {"X": Color("#E3B26E"), "P": PINK})

static func bang() -> ImageTexture:
	return make("bang", _pick([
		".WWWWWWW.",
		"WWWWRWWWW",
		"WWWWRWWWW",
		"WWWWRWWWW",
		"WWWWRWWWW",
		"WWWWWWWWW",
		"WWWWRWWWW",
		".WWWWWWW.",
		"..WW.....",
		".WW......",
	], [
		".WWWWWWWW.",
		"WWWWRRWWWW",
		"WWWWRRWWWW",
		"WWWWRRWWWW",
		"WWWWRRWWWW",
		"WWWWWWWWWW",
		"WWWWRRWWWW",
		"WWWWRRWWWW",
		".WWWWWWWW.",
		"..WWW.....",
		".WWW......",
	]), {"W": CREAM, "R": ORANGE})

static func want_pets() -> ImageTexture:
	return make("want_pets", _pick([
		".WWWWWWWWW.",
		"WWWPPWPPWWW",
		"WWPPPPPPPWW",
		"WWWPPPPPWWW",
		"WWWWPPPWWWW",
		"WWWWWPWWWWW",
		".WWWWWWWWW.",
		"..WW.......",
		".WW........",
	], [
		".WWWWWWWWWW.",
		"WWWPPWWPPWWW",
		"WWPPPPPPPPWW",
		"WWPPPPPPPPWW",
		"WWWPPPPPPWWW",
		"WWWWPPPPWWWW",
		"WWWWWPPWWWWW",
		".WWWWWWWWWW.",
		"..WWW.......",
		".WWW........",
	]), {"W": CREAM, "P": PINK})

static func hand() -> ImageTexture:
	return make("hand", _pick([
		"..XXXXXX..",
		".XXXXXXXXX",
		"XXXXXXXXXX",
		"XXXXXXXXXX",
		".XSXSXSXX.",
		".X.X.X.X..",
	], [
		"..XXXXXXXX..",
		".XXXXXXXXXX.",
		"XXXXXXXXXXXX",
		"XXXXXXXXXXXX",
		"XX.XX.XX.XX.",
		"XX.XX.XX.XX.",
	]), {"X": Color("#F4C9A8"), "S": Color("#E0A989")})

static func sparkle() -> ImageTexture:
	return make("sparkle", _pick([
		"..X..",
		"..X..",
		"XXWXX",
		"..X..",
		"..X..",
	], [
		"..XX..",
		"..XX..",
		"XXXXXX",
		"XXXXXX",
		"..XX..",
		"..XX..",
	]), {"X": GOLD, "W": Color.WHITE})

static func beans() -> ImageTexture:
	return make("beans", _pick([
		".XX..XX.",
		"XYXXXYXX",
		".XX..XX.",
		"...XX...",
		"..XYXX..",
		"...XX...",
	], [
		"..XXXX..",
		".XXXXYX.",
		"XXXXYYXX",
		"XXXYYXXX",
		"XXYYXXXX",
		".XYXXXX.",
		"..XXXX..",
	]), {"X": COFFEE, "Y": ESPRESSO})

static func jug() -> ImageTexture:
	return make("jug", _pick([
		"..XXXXXX..",
		".XSSSSSSX.",
		"XXSSSSSSXX",
		"..SSSSSS.X",
		"..SSSSSS.X",
		"..SSSSSSXX",
		"..SSSSSS..",
		"..SSSSSS..",
		"..SSSSSS..",
		"..XXXXXX..",
	], [
		"..SSSSSSSS....",
		"SSSSSSSSSSSS..",
		"SS.SSSSSSS.SS.",
		"...SSSSSSS..SS",
		"...SSSSSSS..SS",
		"...SSSSSSS.SS.",
		"...SSSSSSSSS..",
		"...SSSSSSS....",
		"...SSSSSSS....",
		"...SSSSSSS....",
	]), {"X": Color("#B7C2C9"), "S": Color("#DCE4E8")})

static func cherry() -> ImageTexture:
	return make("cherry", [
		"....G",
		"...G.",
		".RRG.",
		"RWRRR",
		"RRRRR",
		".RRR.",
	], {"R": ROSE, "W": Color("#F3A08A"), "G": SAGE_DARK})

static func sticker() -> ImageTexture:
	return paw(Color("#B88A63"), "paw_sticker")

## 5x7 bitmap glyphs for grade stamps.
const GLYPHS: Dictionary = {
	"S": [".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."],
	"A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
	"B": ["XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
	"C": [".XXX.", "X...X", "X....", "X....", "X....", "X...X", ".XXX."],
}

const GRADE_COLORS: Dictionary = {
	"S": Color("#E0A53A"),
	"A": Color("#5E8C61"),
	"B": Color("#5F87A8"),
	"C": Color("#C27B8A"),
}

const GRADE_TEXT: Dictionary = {
	"S": "Purr-fect!",
	"A": "Great!",
	"B": "Good!",
	"C": "Still tasty!",
}

# ------------------------------------------------------------------ chrome helpers (B-F)

## Pixel-stepped panel style for window/cards/chips/buttons (styles B-F). `band`
## keeps the old oak/coloured border as an inner band inside the dark outline.
static func chrome_box(bg: Color, band: Color, band_w: int, radius: int, margins: Vector4 = Vector4(10, 4, 10, 4)) -> StyleBox:
	var sb: StyleBox = load("res://Scripts/minigame_demos/counter_cats/cc_pixel_box.gd").new()
	sb.set("bg", bg)
	sb.set("band", band)
	sb.set("band_w", band_w)
	sb.set("outline_w", int(st()["chrome_px"]))
	sb.set("radius", radius)
	sb.set("step", 3 if radius >= 9 else 2)
	sb.set("rim", flag("rim"))
	sb.set("cel", flag("cel"))
	sb.set("halo", 3 if flag("halo") else 0)
	sb.set("shadow", 4 if flag("shadow") else 0)
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	return sb

## Text rule constants for the current style; `unit` = screen px per rule px.
## Returns [outline_size, shadow_outline_size, shadow_offset, shadow_color] or [] for none.
static func text_rule(unit: int = 1) -> Array:
	var r: Dictionary = TEXT_RULES[style]
	var o: int = int(r["outline"]) * unit
	if o <= 0 and int(r["halo"]) <= 0 and int(r["shadow"]) <= 0:
		return []
	if int(r["halo"]) > 0:
		return [o * 2, (o + int(r["halo"]) * unit) * 2, 0, CREAM]
	if int(r["shadow"]) > 0:
		return [o * 2, o * 2, int(r["shadow"]) * unit, SHADOW]
	return [o * 2, 0, 0, Color(0, 0, 0, 0)]

## Applies the shared text rule to one Control (Label/Button) as overrides.
static func apply_text_rule(c: Control, unit: int = 1) -> void:
	var tr: Array = text_rule(unit)
	if tr.is_empty():
		return
	c.add_theme_color_override("font_outline_color", OUTLINE)
	c.add_theme_constant_override("outline_size", int(tr[0]))
	c.add_theme_color_override("font_shadow_color", tr[3])
	c.add_theme_constant_override("shadow_outline_size", int(tr[1]))
	c.add_theme_constant_override("shadow_offset_x", int(tr[2]))
	c.add_theme_constant_override("shadow_offset_y", int(tr[2]))

static var _theme_cache: Dictionary = {}

## The cozy theme for style A; a bolder copy (heavier font, pixel buttons) for B-F.
static func ui_theme(path: String) -> Theme:
	if not ResourceLoader.exists(path):
		return null
	var base: Theme = load(path)
	if style == "A":
		return base
	if _theme_cache.has(style):
		return _theme_cache[style]
	var t: Theme = base.duplicate()
	var f: Font = base.default_font
	if f is SystemFont and int(st()["font_weight"]) > 0:
		var sf: SystemFont = (f as SystemFont).duplicate()
		sf.font_weight = int(st()["font_weight"])
		t.default_font = sf
	var m := Vector4(14, 7, 14, 8)
	for ty in ["Button", "OptionButton"]:
		t.set_stylebox("normal", ty, chrome_box(Color("#F3DFC6"), OAK, 2, 9, m))
		t.set_stylebox("hover", ty, chrome_box(Color("#F8E9D6"), Color("#B88A5E"), 2, 9, m))
		t.set_stylebox("pressed", ty, chrome_box(Color("#E8CFAE"), Color("#B88A5E"), 2, 9, m + Vector4(0, 1, 0, -1)))
		t.set_stylebox("hover_pressed", ty, chrome_box(Color("#E8CFAE"), Color("#B88A5E"), 2, 9, m + Vector4(0, 1, 0, -1)))
		t.set_stylebox("disabled", ty, chrome_box(Color("#ECE3D5"), Color("#D5C4AD"), 2, 9, m))
		t.set_stylebox("focus", ty, StyleBoxEmpty.new())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, TEXT)
		t.set_color("font_pressed_color", ty, TEXT)
		t.set_color("font_focus_color", ty, TEXT)
	var tr: Array = text_rule(1)
	if not tr.is_empty():
		for ty2 in ["Label", "Button", "OptionButton", "CheckBox", "CheckButton", "LinkButton"]:
			t.set_color("font_outline_color", ty2, OUTLINE)
			t.set_constant("outline_size", ty2, int(tr[0]))
			t.set_color("font_shadow_color", ty2, tr[3])
			t.set_constant("shadow_outline_size", ty2, int(tr[1]))
			t.set_constant("shadow_offset_x", ty2, int(tr[2]))
			t.set_constant("shadow_offset_y", ty2, int(tr[2]))
	_theme_cache[style] = t
	return t
