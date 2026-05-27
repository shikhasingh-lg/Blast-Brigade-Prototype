extends Object
class_name UICommon
## Shared visual helpers for the meta-loop screens. Mirrors the look used in
## MatchScene's HUD (Polygon2D chips, white outlined labels, dark panels) so the
## meta screens read as the same game.

const CHIP_RADIUS_FAKE: float = 6.0   # we don't draw real rounded corners; just track for layout
const CHIP_STROKE: Color = Color(0.10, 0.13, 0.20, 0.95)

const COLOR_PANEL_BG: Color   = Color(0.10, 0.13, 0.20, 0.92)
const COLOR_PANEL_EDGE: Color = Color(1, 1, 1, 0.18)
const COLOR_TEXT: Color       = Color(1, 1, 1)
const COLOR_TEXT_DIM: Color   = Color(0.78, 0.84, 0.92)
const COLOR_GOLD: Color       = Color(1.00, 0.84, 0.30)
const COLOR_GEM: Color        = Color(0.55, 0.78, 1.00)
const COLOR_ENERGY: Color     = Color(1.00, 0.95, 0.40)
const COLOR_PRIMARY: Color    = Color(0.36, 0.74, 0.98)
const COLOR_SUCCESS: Color    = Color(0.36, 0.80, 0.50)
const COLOR_DANGER: Color     = Color(0.92, 0.42, 0.40)
const COLOR_WARN: Color       = Color(0.96, 0.66, 0.30)

static func make_label(text: String, font_size: int, color: Color = COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func add_label(parent: Node, pos: Vector2, text: String, font_size: int, color: Color = COLOR_TEXT) -> Label:
	var l := make_label(text, font_size, color)
	l.position = pos
	parent.add_child(l)
	return l

# Filled rect with a 2-px dark outer "stroke" band. Returns the holder Node2D.
static func make_chip(pos: Vector2, size: Vector2, fill: Color) -> Node2D:
	var holder := Node2D.new()
	holder.position = pos
	var stroke := Polygon2D.new()
	stroke.color = CHIP_STROKE
	stroke.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(size.x + 2, -2),
		Vector2(size.x + 2, size.y + 3), Vector2(-2, size.y + 3),
	])
	holder.add_child(stroke)
	var body := Polygon2D.new()
	body.color = fill
	body.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y),
	])
	holder.add_child(body)
	return holder

# Solid dark panel (rectangle). Returns ColorRect for sizing.
static func make_panel(pos: Vector2, size: Vector2, fill: Color = COLOR_PANEL_BG) -> ColorRect:
	var p := ColorRect.new()
	p.color = fill
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# A big tappable button (Button node with simple custom theme so it matches chips).
static func make_button(text: String, size: Vector2, fill: Color = COLOR_PRIMARY) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_color_pressed", Color(0.92, 0.92, 1))
	b.add_theme_color_override("font_color_hover", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	b.add_theme_constant_override("outline_size", 5)
	# Style boxes — flat fills, no gradients.
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = fill
	sb_normal.set_corner_radius_all(10)
	sb_normal.border_width_bottom = 4
	sb_normal.border_color = Color(0, 0, 0, 0.45)
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = fill.lightened(0.08)
	var sb_pressed := sb_normal.duplicate()
	sb_pressed.bg_color = fill.darkened(0.10)
	sb_pressed.border_width_bottom = 1
	b.add_theme_stylebox_override("normal", sb_normal)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.add_theme_stylebox_override("focus", sb_normal)
	return b

# Paint a sky-gradient background as a TextureRect filling vp. Returns the node.
static func make_sky(vp: Vector2, top: Color = Color(0.46, 0.74, 0.93),
		mid: Color = Color(0.99, 0.85, 0.60),
		horizon: Color = Color(1.00, 0.74, 0.48)) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, horizon)
	grad.add_point(0.65, mid)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 16
	gt.height = 512
	var sky := TextureRect.new()
	sky.texture = gt
	sky.position = Vector2.ZERO
	sky.size = vp
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Draw behind the parent's own _draw() so Node2D-painted overlays (paths,
	# stage nodes, etc.) show on top of the gradient.
	sky.show_behind_parent = true
	return sky

# Currency chip with icon character + value. e.g. ("⚡", "7/10", COLOR_ENERGY)
static func make_currency_chip(pos: Vector2, size: Vector2,
		icon: String, value: String, icon_color: Color) -> Node2D:
	var chip := make_chip(pos, size, COLOR_PANEL_BG)
	var ic := make_label(icon, 22, icon_color)
	ic.position = Vector2(6, size.y * 0.5 - 16)
	chip.add_child(ic)
	var v := make_label(value, 18, COLOR_TEXT)
	v.position = Vector2(32, size.y * 0.5 - 12)
	v.size = Vector2(size.x - 36, 24)
	chip.add_child(v)
	return chip
