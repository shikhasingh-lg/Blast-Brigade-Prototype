extends Node2D
class_name Bubble

const RADIUS: float = 26.0
# Collision radius is smaller than the visible bubble so shots can thread a
# perceived gap between two cluster bubbles without grazing them (v1 pattern).
const ATTACH_RADIUS: float = 26.0
# Single source of truth for how big a bubble looks on screen. Per-texture
# calibration (see get_draw_rect) scales each source PNG so the round bubble
# matches this diameter, regardless of canvas size, transparent padding, or
# soft shadows below the bubble. Cell stride is 60 → target 58 leaves a 1px
# hex breathing gap. Hero bubbles use the SAME diameter and add a gold glow.
const TARGET_VISIBLE_DIAMETER: float = 58.0
const HERO_VISIBLE_DIAMETER: float = 58.0
# Box used for the procedural fallback only.
const SPRITE_DRAW_SIZE: float = 60.0

const COLORS: Dictionary = {
	"RED":    Color(0.88, 0.30, 0.30),
	"BLUE":   Color(0.28, 0.50, 0.90),
	"YELLOW": Color(0.95, 0.80, 0.22),
	"GREEN":  Color(0.40, 0.78, 0.42),
	"PURPLE": Color(0.62, 0.36, 0.86),
}

const COLOR_SLUG: Dictionary = {
	"RED":    "red",
	"BLUE":   "blue",
	"YELLOW": "yellow",
	"GREEN":  "green",
	"PURPLE": "purple",
}

# Hero class tint used for the portrait dot on hero bubbles.
const CLASS_TINTS: Dictionary = {
	"FireKnight": Color(0.95, 0.45, 0.20),
	"IceMage":    Color(0.55, 0.80, 1.00),
	"Archer":     Color(0.95, 0.90, 0.45),
	"Druid":      Color(0.50, 0.86, 0.50),
	"Wizard":     Color(0.72, 0.46, 0.96),
}

static var _bubble_tex_cache: Dictionary = {}
static var _hero_tex_cache: Dictionary = {}
# Per-texture calibration: resource_path|target → {pos: Vector2, size: Vector2}
static var _calibration_cache: Dictionary = {}

static func _get_bubble_tex(c: String) -> Texture2D:
	if _bubble_tex_cache.has(c):
		return _bubble_tex_cache[c]
	var slug: String = COLOR_SLUG.get(c, "red")
	var tex: Texture2D = load("res://assets/bubbles/bubble_%s.png" % slug)
	_bubble_tex_cache[c] = tex
	return tex

static func _get_hero_tex(c: String) -> Texture2D:
	if _hero_tex_cache.has(c):
		return _hero_tex_cache[c]
	var slug: String = COLOR_SLUG.get(c, "red")
	var tex: Texture2D = load("res://assets/bubbles/hero_%s.png" % slug)
	_hero_tex_cache[c] = tex
	return tex

# Returns {pos, size} for draw_texture_rect such that the texture's visible
# (non-transparent) content is centered at (0,0) with max visible dimension
# = target. Compensates for differing canvas sizes AND off-center artwork.
static func get_draw_rect(tex: Texture2D, target: float) -> Dictionary:
	if tex == null:
		return {"pos": Vector2(-target * 0.5, -target * 0.5), "size": Vector2(target, target)}
	var key: String = "%s|%f" % [tex.resource_path, target]
	if _calibration_cache.has(key):
		return _calibration_cache[key]
	var img: Image = tex.get_image()
	var cal: Dictionary
	if img == null:
		cal = {"pos": Vector2(-target * 0.5, -target * 0.5), "size": Vector2(target, target)}
	else:
		var bbox: Rect2i = img.get_used_rect()
		if bbox.size.x <= 0 or bbox.size.y <= 0:
			cal = {"pos": Vector2(-target * 0.5, -target * 0.5), "size": Vector2(target, target)}
		else:
			# Diameter = bbox WIDTH. Some textures have a soft shadow below the
			# bubble that extends the bbox vertically — using width keeps the
			# round bubble at the same size across all colors.
			# Bubble center = a square of side `width` sitting at the TOP of the
			# bbox (handles the shadow case; for shadow-less textures bbox is
			# already square so this matches bbox-center).
			var canvas := Vector2(float(img.get_width()), float(img.get_height()))
			var diameter: float = float(bbox.size.x)
			var bubble_center := Vector2(
				float(bbox.position.x) + diameter * 0.5,
				float(bbox.position.y) + diameter * 0.5,
			)
			var s: float = target / diameter
			var size: Vector2 = canvas * s
			var pos: Vector2 = -bubble_center * s
			cal = {"pos": pos, "size": size}
	_calibration_cache[key] = cal
	return cal

var color: String = "RED"
var grid_pos: Vector2i = Vector2i.ZERO
var is_hero: bool = false
var hero_class: String = ""
var is_corrupted: bool = false   # boss-design.md §2.3 — no match, splash-clearable
var is_cracked: bool = false     # art-direction.md §7.2 — gate state "cracked":
                                 # hero shots pass through, enemies still blocked.

func set_bubble(c: String, gp: Vector2i, hero: bool = false, h_class: String = "") -> void:
	color = c
	grid_pos = gp
	is_hero = hero
	hero_class = h_class
	queue_redraw()

func set_corrupted(corrupted: bool) -> void:
	is_corrupted = corrupted
	if corrupted:
		is_hero = false   # corruption consumes the hero portrait
		is_cracked = false   # corruption supersedes the crack overlay
	queue_redraw()

func set_cracked(cracked: bool) -> void:
	if is_corrupted:
		return   # corrupted bubbles render their own face; cracks don't apply
	is_cracked = cracked
	queue_redraw()

# Animated removal — shrink + fade, then queue_free. Use instead of plain
# queue_free() so the player sees *what* killed the bubble (floater drop,
# splash) rather than wondering why the wall thinned out on its own. Caller
# MUST erase the bubble from the Gate.cells dictionary before calling this,
# since the bubble is still in the scene tree during the tween. Safe to call
# from physics callbacks.
func pop_disappear(duration_sec: float = 0.18) -> void:
	# Detach from any group/lookup behavior here first if needed.
	set_process(false)
	# Fire micro VFX + audio. Corrupted bubbles don't sparkle (different
	# clear pattern — boss death effect handles that).
	if not is_corrupted:
		VFX.play("bubble_pop", global_position, {"color": color})
		SFX.play_bubble_pop(color)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.15, 0.15), duration_sec) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, duration_sec) \
		.set_trans(Tween.TRANS_LINEAR)
	tw.chain().tween_callback(queue_free)

func _draw() -> void:
	if is_corrupted:
		_draw_corrupted()
		return
	# Hero bubbles render the SAME bubble texture as regulars; the gold glow
	# below is the only difference. (The hero_*.png assets have face stickers
	# baked in — we could swap to those if/when the art settles, but for now
	# uniform size + glow reads better.)
	var tex: Texture2D = _get_hero_tex(color) if is_hero else _get_bubble_tex(color)
	if tex != null:
		if is_hero:
			# Soft golden glow drawn UNDER the bubble; two concentric arcs so it
			# feathers from saturated near the bubble to faint farther out.
			var r0: float = TARGET_VISIBLE_DIAMETER * 0.5 + 3.0
			var r1: float = TARGET_VISIBLE_DIAMETER * 0.5 + 8.0
			draw_circle(Vector2.ZERO, r1, Color(1.0, 0.85, 0.30, 0.25))
			draw_circle(Vector2.ZERO, r0, Color(1.0, 0.92, 0.45, 0.45))
		var cal: Dictionary = get_draw_rect(tex, TARGET_VISIBLE_DIAMETER)
		draw_texture_rect(tex, Rect2(cal["pos"], cal["size"]), false, Color.WHITE)
		if is_hero:
			# Crisp gold ring at the bubble's edge so heroes pop against the cluster.
			draw_arc(Vector2.ZERO, TARGET_VISIBLE_DIAMETER * 0.5 + 1.0, 0, TAU, 36,
				Color(1.0, 0.88, 0.35, 0.95), 2.5, true)
		if is_cracked:
			_draw_crack_overlay()
		return
	# Procedural fallback if textures missing.
	var fill: Color = COLORS.get(color, Color.GRAY)
	draw_circle(Vector2.ZERO, RADIUS, fill)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, Color(0, 0, 0, 0.7), 1.5, true)
	draw_circle(Vector2(-RADIUS * 0.35, -RADIUS * 0.35), RADIUS * 0.22, Color(1, 1, 1, 0.4))
	if is_hero:
		draw_arc(Vector2.ZERO, RADIUS + 4, 0, TAU, 32, Color(1, 0.95, 0.5, 0.9), 3.0, true)
		var tint: Color = CLASS_TINTS.get(hero_class, Color(1, 1, 1, 0.85))
		draw_circle(Vector2.ZERO, RADIUS * 0.45, tint)
		draw_arc(Vector2.ZERO, RADIUS * 0.45, 0, TAU, 24, Color(0, 0, 0, 0.7), 1.0, true)
	if is_cracked:
		_draw_crack_overlay()

# Cracked gate state (art-direction.md §7.2). Three short fracture lines across
# the bubble face + 80% opacity feel on the bubble's brightness. Lines are the
# same dark outline color regardless of bubble color so the crack reads as
# damage, not as a colored decoration.
func _draw_crack_overlay() -> void:
	var crack_color: Color = Color(0.10, 0.09, 0.15, 0.85)   # near-black purple, matches outline spec
	var r: float = RADIUS
	# Three crack lines through the bubble face — pre-baked angles so every
	# cracked bubble looks the same (one shared sprite per spec §7.2, but drawn).
	draw_line(Vector2(-r * 0.70, -r * 0.10),
			  Vector2( r * 0.55,  r * 0.35), crack_color, 2.2)
	draw_line(Vector2(-r * 0.10, -r * 0.65),
			  Vector2( r * 0.20,  r * 0.55), crack_color, 2.0)
	draw_line(Vector2( r * 0.35, -r * 0.50),
			  Vector2(-r * 0.45,  r * 0.55), crack_color, 1.8)
	# Two short branch lines off the main fracture to suggest spider-web damage.
	draw_line(Vector2(-r * 0.20, -r * 0.05),
			  Vector2(-r * 0.10, -r * 0.40), crack_color, 1.4)
	draw_line(Vector2( r * 0.15,  r * 0.20),
			  Vector2( r * 0.40,  r * 0.10), crack_color, 1.4)

func _draw_corrupted() -> void:
	# Grey/black body with faint purple aura + crack lines.
	draw_circle(Vector2.ZERO, RADIUS + 2.0, Color(0.42, 0.20, 0.55, 0.35))   # aura
	draw_circle(Vector2.ZERO, RADIUS, Color(0.18, 0.16, 0.22))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, Color(0, 0, 0, 0.85), 1.5, true)
	# Cracks — three short lines through the center.
	var crack: Color = Color(0.78, 0.55, 0.95, 0.85)
	draw_line(Vector2(-RADIUS * 0.7, -RADIUS * 0.2), Vector2(RADIUS * 0.5, RADIUS * 0.3), crack, 1.5)
	draw_line(Vector2(-RADIUS * 0.2, -RADIUS * 0.7), Vector2(RADIUS * 0.1, RADIUS * 0.5), crack, 1.5)
	draw_line(Vector2(RADIUS * 0.3, -RADIUS * 0.5), Vector2(-RADIUS * 0.4, RADIUS * 0.6), crack, 1.5)
