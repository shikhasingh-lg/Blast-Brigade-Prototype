extends Node2D
class_name AimOverlay
## Dotted parabola preview + blast-radius landing reticle for the Blast Brigade
## cannon. Cannon owns this and updates the polyline whenever the player drags.
## Lives as a child of MatchScene root so local space == world space.

const DOT_SPACING_PX: float = 28.0
const DOT_BASE_RADIUS: float = 5.0
const DOT_TIP_RADIUS: float = 3.0
const FADE_NEAR_ALPHA: float = 0.85
const FADE_FAR_ALPHA: float = 0.20
const DOT_COLOR: Color = Color(1.00, 0.78, 0.30, 1.0)  # ember orange — fuse-like
const DOT_OUTLINE: Color = Color(0, 0, 0, 0.55)
# Landing reticle = the bomb's AOE footprint. Reads as "your blast covers this."
const RETICLE_COLOR_RING: Color = Color(1.00, 0.55, 0.15, 0.85)
const RETICLE_COLOR_FILL: Color = Color(1.00, 0.55, 0.15, 0.10)
const RETICLE_RING_WIDTH: float = 3.0
# Explicit preload to dodge class_name parse-order races on cold boot.
const BombProjScript: GDScript = preload("res://scripts/BombProjectile.gd")

var polyline: PackedVector2Array = PackedVector2Array()
var landing: Vector2 = Vector2.ZERO
var has_landing: bool = false

func set_polyline(pts: PackedVector2Array, _color_unused: String, land_pos: Variant = null) -> void:
	polyline = pts
	has_landing = land_pos is Vector2
	if has_landing:
		landing = land_pos
	queue_redraw()

func clear() -> void:
	polyline = PackedVector2Array()
	has_landing = false
	queue_redraw()

func _draw() -> void:
	if polyline.size() < 2:
		return
	# Total length drives the per-dot fade (older = farther = fainter).
	var total_len: float = 0.0
	for i in range(polyline.size() - 1):
		total_len += polyline[i].distance_to(polyline[i + 1])
	if total_len <= 0.0:
		return
	# Walk the polyline at fixed spacing; emit a fading dot at each step. The
	# polyline approximates the parabola as many short segments, so dots laid
	# along it trace the curve smoothly.
	var dist_along: float = DOT_SPACING_PX * 0.5
	for seg in range(polyline.size() - 1):
		var a: Vector2 = polyline[seg]
		var b: Vector2 = polyline[seg + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.001:
			continue
		var seg_start_dist: float = _dist_to_seg_start(seg)
		while dist_along < seg_start_dist + seg_len:
			var t: float = (dist_along - seg_start_dist) / seg_len
			var p: Vector2 = a.lerp(b, t)
			var u: float = dist_along / total_len
			var alpha: float = lerp(FADE_NEAR_ALPHA, FADE_FAR_ALPHA, u)
			var r: float = lerp(DOT_BASE_RADIUS, DOT_TIP_RADIUS, u)
			draw_circle(p, r + 1.0, Color(DOT_OUTLINE.r, DOT_OUTLINE.g, DOT_OUTLINE.b, alpha * 0.7))
			draw_circle(p, r, Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, alpha))
			dist_along += DOT_SPACING_PX
	# Landing reticle — only when the bomb is predicted to actually land in
	# the playfield. Overshoots leave the preview without a landing marker so
	# the player gets visual feedback that the shot is wasted.
	if has_landing:
		_draw_reticle(landing)

func _dist_to_seg_start(seg_idx: int) -> float:
	var d: float = 0.0
	for i in range(seg_idx):
		d += polyline[i].distance_to(polyline[i + 1])
	return d

func _draw_reticle(world_pos: Vector2) -> void:
	var r: float = BombProjScript.BLAST_RADIUS
	# Soft fill so the AOE footprint reads, then a crisp ring on top.
	draw_circle(world_pos, r, RETICLE_COLOR_FILL)
	draw_arc(world_pos, r, 0.0, TAU, 48, RETICLE_COLOR_RING, RETICLE_RING_WIDTH, true)
	# Small crosshair at the impact point so the eye locks on the center.
	var x_arm: float = 7.0
	draw_line(world_pos + Vector2(-x_arm, 0), world_pos + Vector2(x_arm, 0),
		RETICLE_COLOR_RING, 2.0, true)
	draw_line(world_pos + Vector2(0, -x_arm), world_pos + Vector2(0, x_arm),
		RETICLE_COLOR_RING, 2.0, true)
