extends Node2D
class_name BasePlatform
## Foreground stone parapet / tomb wall that the cannon is mounted on.
## Purely procedural — no asset needed. The HP bar in the HUD represents the
## health of THIS structure; before this existed the cannon looked like it was
## floating with no visible "base" for enemies to damage.
##
## Drawn behind the cannon (so the cannon reads as mounted on top) and in front
## of heroes / lane / gate. configure() takes viewport size + cannon Y; the
## platform shapes itself around them.

const STONE_BASE: Color    = Color(0.55, 0.50, 0.46)
const STONE_HI: Color      = Color(0.70, 0.64, 0.57)
const STONE_LO: Color      = Color(0.34, 0.30, 0.27)
const MORTAR: Color        = Color(0.18, 0.15, 0.13, 0.85)
const CAPSTONE: Color      = Color(0.46, 0.42, 0.38)
const CAPSTONE_HI: Color   = Color(0.62, 0.57, 0.51)
const MOSS: Color          = Color(0.36, 0.48, 0.30, 0.55)
const SHADOW: Color        = Color(0.05, 0.06, 0.10, 0.30)

var _vp: Vector2 = Vector2.ZERO
var _top_y: float = 0.0        # top of crenellations
var _cap_y: float = 0.0        # top of platform capstone (cannon sits here)
var _left_x: float = 0.0
var _right_x: float = 0.0
var _bottom_y: float = 0.0
var _cannon_x: float = 0.0
var _cannon_half_w: float = 70.0  # gap for the cannon to nest into

func configure(vp: Vector2, cannon_pos: Vector2, cannon_half_w: float) -> void:
	_vp = vp
	_cannon_x = cannon_pos.x
	_cannon_half_w = cannon_half_w
	# Platform geometry. Wider at the bottom for perspective; the cannon's wheel
	# line lands roughly on the capstone (cap_y) so the recoil ground-shadow
	# doesn't visually float.
	_cap_y = cannon_pos.y + 30.0          # capstone top — wheels rest here
	_top_y = _cap_y - 22.0                # crenellations rise 22px above capstone
	_bottom_y = _vp.y + 20.0              # past screen bottom so no gap
	_left_x = -20.0
	_right_x = _vp.x + 20.0
	queue_redraw()

func _draw() -> void:
	if _vp == Vector2.ZERO:
		return
	_draw_drop_shadow()
	_draw_main_body()
	_draw_block_courses()
	_draw_capstone()
	_draw_crenellations()
	_draw_cannon_pedestal()
	_draw_moss_specks()

func _draw_drop_shadow() -> void:
	# Soft band beneath the capstone — sells "wall casting shadow on lane ground"
	# back behind it. Drawn first so block courses paint over it.
	var sh := PackedVector2Array([
		Vector2(_left_x, _cap_y - 6.0),
		Vector2(_right_x, _cap_y - 6.0),
		Vector2(_right_x, _cap_y + 4.0),
		Vector2(_left_x, _cap_y + 4.0),
	])
	draw_colored_polygon(sh, SHADOW)

func _draw_main_body() -> void:
	# Trapezoid filling cap → bottom. Slight inward taper at top (perspective).
	var taper: float = 28.0
	var body := PackedVector2Array([
		Vector2(_left_x + taper, _cap_y),
		Vector2(_right_x - taper, _cap_y),
		Vector2(_right_x, _bottom_y),
		Vector2(_left_x, _bottom_y),
	])
	draw_colored_polygon(body, STONE_BASE)
	# Vertical edge shadows (left + right) for volume.
	var edge_w: float = 26.0
	var left_shade := PackedVector2Array([
		Vector2(_left_x + taper, _cap_y),
		Vector2(_left_x + taper + edge_w, _cap_y),
		Vector2(_left_x + edge_w, _bottom_y),
		Vector2(_left_x, _bottom_y),
	])
	draw_colored_polygon(left_shade, STONE_LO)
	var right_shade := PackedVector2Array([
		Vector2(_right_x - taper - edge_w, _cap_y),
		Vector2(_right_x - taper, _cap_y),
		Vector2(_right_x, _bottom_y),
		Vector2(_right_x - edge_w, _bottom_y),
	])
	draw_colored_polygon(right_shade, STONE_LO)

func _draw_block_courses() -> void:
	# 3 horizontal courses of blocks with offset mortar joints (running bond).
	# Each course is ~ a third of the body height.
	var body_h: float = _bottom_y - _cap_y
	var course_h: float = body_h / 3.0
	var block_w: float = 110.0
	for course in range(3):
		var y0: float = _cap_y + course_h * course
		var y1: float = _cap_y + course_h * (course + 1)
		# Horizontal mortar line at top of this course (skip top — capstone covers it).
		if course > 0:
			draw_line(Vector2(_left_x, y0), Vector2(_right_x, y0), MORTAR, 2.0, true)
		# Vertical joints — offset every other course (running bond).
		var offset: float = (block_w * 0.5) if course % 2 == 1 else 0.0
		var x: float = _left_x + offset
		while x < _right_x:
			# Only draw inside the trapezoid horizontally; quick clamp is fine.
			if x > _left_x and x < _right_x:
				draw_line(Vector2(x, y0), Vector2(x, y1), MORTAR, 2.0, true)
			# Subtle top-of-block highlight (1px) to fake bevel.
			var hi_start: float = max(x, _left_x)
			var hi_end: float = min(x + block_w, _right_x)
			if course > 0 and hi_end > hi_start:
				draw_line(Vector2(hi_start + 2.0, y0 + 1.5),
					Vector2(hi_end - 2.0, y0 + 1.5),
					Color(STONE_HI.r, STONE_HI.g, STONE_HI.b, 0.30), 1.0, true)
			x += block_w

func _draw_capstone() -> void:
	# Solid horizontal slab across the top of the body — flat shelf the cannon
	# wheels rest on. Top edge sits at _top_y (same as crenellation base).
	var cap_top_y: float = _top_y + 2.0
	var cap := PackedVector2Array([
		Vector2(_left_x, cap_top_y),
		Vector2(_right_x, cap_top_y),
		Vector2(_right_x, _cap_y),
		Vector2(_left_x, _cap_y),
	])
	draw_colored_polygon(cap, CAPSTONE)
	# Bright top edge.
	draw_line(Vector2(_left_x, cap_top_y), Vector2(_right_x, cap_top_y),
		CAPSTONE_HI, 2.0, true)
	# Bottom shadow line under capstone (creates the overhang).
	draw_line(Vector2(_left_x, _cap_y - 1.0), Vector2(_right_x, _cap_y - 1.0),
		STONE_LO, 2.0, true)

func _draw_crenellations() -> void:
	# Tooth blocks along the top — skip the center span where the cannon nests.
	var tooth_w: float = 56.0
	var gap_w: float = 38.0
	var period: float = tooth_w + gap_w
	var gap_left: float = _cannon_x - _cannon_half_w - 6.0
	var gap_right: float = _cannon_x + _cannon_half_w + 6.0
	var x: float = _left_x + 12.0
	while x < _right_x - tooth_w:
		var x1: float = x + tooth_w
		# Skip teeth that would intersect the cannon pedestal gap.
		if x1 > gap_left and x < gap_right:
			x += period
			continue
		var poly := PackedVector2Array([
			Vector2(x, _top_y),
			Vector2(x1, _top_y),
			Vector2(x1, _top_y + 22.0),
			Vector2(x, _top_y + 22.0),
		])
		draw_colored_polygon(poly, CAPSTONE)
		# Tiny bright top + dark right side for bevel.
		draw_line(Vector2(x, _top_y + 1.0), Vector2(x1, _top_y + 1.0),
			CAPSTONE_HI, 2.0, true)
		draw_line(Vector2(x1 - 1.0, _top_y), Vector2(x1 - 1.0, _top_y + 22.0),
			STONE_LO, 2.0, true)
		x += period

func _draw_cannon_pedestal() -> void:
	# Slightly raised plinth directly under the cannon — sells "the cannon is
	# bolted to a stone mount" instead of just resting on the wall.
	var w: float = _cannon_half_w * 2.0 + 24.0
	var h: float = 14.0
	var x0: float = _cannon_x - w * 0.5
	var top_y: float = _cap_y - h
	var plinth := PackedVector2Array([
		Vector2(x0, top_y),
		Vector2(x0 + w, top_y),
		Vector2(x0 + w + 6.0, _cap_y),
		Vector2(x0 - 6.0, _cap_y),
	])
	draw_colored_polygon(plinth, CAPSTONE_HI)
	draw_line(Vector2(x0, top_y + 1.0), Vector2(x0 + w, top_y + 1.0),
		Color(1, 1, 1, 0.35), 1.5, true)

func _draw_moss_specks() -> void:
	# A few moss patches at the base of crenellations + on capstone for age.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337   # deterministic — moss in the same spots every run
	for _i in range(14):
		var px: float = rng.randf_range(_left_x + 20.0, _right_x - 20.0)
		var py: float = _cap_y + rng.randf_range(-6.0, 4.0)
		var r: float = rng.randf_range(3.0, 7.0)
		draw_circle(Vector2(px, py), r, MOSS)
