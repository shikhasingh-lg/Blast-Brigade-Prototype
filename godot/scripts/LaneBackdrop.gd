extends Node2D
class_name LaneBackdrop
## 2D depth cues for the lane.
##
## Layout: vanishing point at the TOP of the lane (narrow_y), trapezoid widens
## DOWN toward the camera-near end (wide_y). The path is a distinct warm sand
## road carved into a green meadow, with darker grass-edge bands on each side,
## perspective shading (desaturated at horizon), a tight treeline silhouette
## clustered behind the gate, and flowers along the path borders.

const N_SHADOW_BANDS: int = 18
const SHADOW_HEIGHT_PX: float = 36.0

# Path / meadow palette.
const GRASS_BASE: Color = Color(0.48, 0.74, 0.32, 1.0)       # meadow green
const GRASS_EDGE: Color = Color(0.30, 0.54, 0.22, 1.0)       # darker rim along path
const PATH_NEAR: Color  = Color(0.86, 0.74, 0.50, 1.0)       # warm sand, camera-near
const PATH_FAR: Color   = Color(0.72, 0.66, 0.58, 1.0)       # desaturated near horizon
const TREELINE: Color   = Color(0.24, 0.46, 0.24, 1.0)       # tight forest behind gate

const EDGE_BAND_PX: float = 9.0   # darker grass-edge rim on each side of path
const N_PATH_BANDS: int = 28      # horizontal slices for perspective shading

# Treeline (tightened to a band roughly the width of the gate, not full screen).
const N_TREES: int = 6
const TREELINE_SPAN_MULT: float = 1.15   # treeline width = narrow_w × this

# Flower border counts — clustered along path edges, not scattered everywhere.
const N_FLOWERS_PER_SIDE: int = 22
const N_GRASS_TUFTS_APRON: int = 40

const DECO_RNG_SEED: int = 919191

var narrow_y: float = 0.0
var wide_y: float = 0.0
var narrow_left: float = 0.0
var narrow_right: float = 0.0
var wide_left: float = 0.0
var wide_right: float = 0.0
var screen_w: float = 720.0

func configure(n_y: float, w_y: float, nl: float, nr: float, wl: float, wr: float, sw: float) -> void:
	narrow_y = n_y
	wide_y = w_y
	narrow_left = nl
	narrow_right = nr
	wide_left = wl
	wide_right = wr
	screen_w = sw
	queue_redraw()

func _draw() -> void:
	if wide_y <= narrow_y:
		return

	var lane_h: float = wide_y - narrow_y
	var rng := RandomNumberGenerator.new()
	rng.seed = DECO_RNG_SEED

	# 1) Full meadow base — solid green across the band. The path is then painted
	#    on top as a distinct sand-colored trapezoid.
	draw_rect(Rect2(0.0, narrow_y, screen_w, lane_h), GRASS_BASE)

	# 2) Tight treeline silhouette clustered roughly behind the gate width,
	#    sitting at narrow_y so the path appears to emerge from the forest line.
	_draw_treeline(rng)

	# 3) The path itself — sand-colored trapezoid built from N_PATH_BANDS thin
	#    horizontal quads, each shaded by depth (PATH_FAR at top → PATH_NEAR at
	#    bottom). This gives perspective shading along the path length.
	_draw_path_bands()

	# 4) Darker grass-edge rim flanking the path on both sides — the "carved out"
	#    line that makes the path feel inset rather than overlaid.
	_draw_path_edge_bands()

	# 5) Flowers clustered along the path edges only — left rim + right rim, with
	#    perspective scaling. Apron gets a few sparse grass tufts for texture.
	_draw_flower_borders(rng)
	_draw_apron_tufts(rng)

	# 6) Wall shadow falling from the gate base onto the near end of the path.
	for i in range(N_SHADOW_BANDS):
		var ft: float = float(i) / float(N_SHADOW_BANDS - 1)
		var y: float = narrow_y + SHADOW_HEIGHT_PX * ft + 1.0
		var alpha: float = 0.35 * (1.0 - ft)
		var t_local: float = (y - narrow_y) / lane_h
		var lx: float = lerp(narrow_left, wide_left, t_local)
		var rx: float = lerp(narrow_right, wide_right, t_local)
		draw_rect(Rect2(lx, y, rx - lx, 2.0), Color(0.0, 0.0, 0.0, alpha))

# ─── Path painters ────────────────────────────────────────────────────────

func _draw_path_bands() -> void:
	# Slice the trapezoid into N_PATH_BANDS thin horizontal strips. Each strip's
	# left/right x and fill color are interpolated based on its depth t (0=far,
	# 1=near).
	var lane_h: float = wide_y - narrow_y
	for i in range(N_PATH_BANDS):
		var t0: float = float(i) / float(N_PATH_BANDS)
		var t1: float = float(i + 1) / float(N_PATH_BANDS)
		var y0: float = narrow_y + t0 * lane_h
		var y1: float = narrow_y + t1 * lane_h
		var l0: float = lerp(narrow_left, wide_left, t0)
		var r0: float = lerp(narrow_right, wide_right, t0)
		var l1: float = lerp(narrow_left, wide_left, t1)
		var r1: float = lerp(narrow_right, wide_right, t1)
		var col: Color = lerp(PATH_FAR, PATH_NEAR, (t0 + t1) * 0.5)
		var poly := PackedVector2Array([
			Vector2(l0, y0), Vector2(r0, y0),
			Vector2(r1, y1), Vector2(l1, y1),
		])
		draw_colored_polygon(poly, col)

func _draw_path_edge_bands() -> void:
	# Darker grass-edge bands hugging the trapezoid on both sides — same
	# perspective slope, EDGE_BAND_PX wide, sitting just OUTSIDE the path.
	# Left rim.
	var l_poly := PackedVector2Array([
		Vector2(narrow_left - EDGE_BAND_PX, narrow_y),
		Vector2(narrow_left, narrow_y),
		Vector2(wide_left, wide_y),
		Vector2(wide_left - EDGE_BAND_PX, wide_y),
	])
	draw_colored_polygon(l_poly, GRASS_EDGE)
	# Right rim.
	var r_poly := PackedVector2Array([
		Vector2(narrow_right, narrow_y),
		Vector2(narrow_right + EDGE_BAND_PX, narrow_y),
		Vector2(wide_right + EDGE_BAND_PX, wide_y),
		Vector2(wide_right, wide_y),
	])
	draw_colored_polygon(r_poly, GRASS_EDGE)

# ─── Treeline ─────────────────────────────────────────────────────────────

func _draw_treeline(rng: RandomNumberGenerator) -> void:
	# Tight cluster of overlapping foliage circles, span = narrow_w × mult,
	# centered horizontally. Sits at narrow_y so the path appears to emerge from
	# inside the forest.
	var narrow_w: float = narrow_right - narrow_left
	var span: float = narrow_w * TREELINE_SPAN_MULT
	var cx_center: float = (narrow_left + narrow_right) * 0.5
	var span_left: float = cx_center - span * 0.5
	var line_y: float = narrow_y + 2.0
	for i in range(N_TREES):
		var x_t: float = (float(i) + 0.5) / float(N_TREES)
		var jitter: float = rng.randf_range(-0.04, 0.04)
		var cx: float = span_left + (x_t + jitter) * span
		var r: float = rng.randf_range(16.0, 24.0)
		var cy: float = line_y - r * 0.55
		draw_circle(Vector2(cx, cy), r, TREELINE)
		draw_circle(Vector2(cx - r * 0.5, cy + r * 0.25), r * 0.7, TREELINE)
		draw_circle(Vector2(cx + r * 0.5, cy + r * 0.25), r * 0.7, TREELINE)

# ─── Flowers + tufts ──────────────────────────────────────────────────────

func _draw_flower_borders(rng: RandomNumberGenerator) -> void:
	# Two rows of flowers — one hugging the left rim of the path, one the right.
	# Each flower sits a few px OUTSIDE the trapezoid (on grass), scaled by
	# perspective so distant ones are tiny.
	var palette := [
		Color(0.95, 0.32, 0.32),   # red
		Color(0.98, 0.83, 0.28),   # yellow
		Color(0.98, 0.55, 0.78),   # pink
		Color(1.00, 1.00, 1.00),   # white
	]
	for side in [-1, 1]:
		for _i in range(N_FLOWERS_PER_SIDE):
			var t: float = pow(rng.randf(), 0.55)              # bias toward camera
			var y: float = narrow_y + t * (wide_y - narrow_y)
			var lx: float = lerp(narrow_left, wide_left, t)
			var rx: float = lerp(narrow_right, wide_right, t)
			# Offset 4-22px outside the rim (perspective-scaled).
			var offset: float = lerp(4.0, 22.0, t) + rng.randf_range(0.0, lerp(6.0, 28.0, t))
			var x: float = (lx - EDGE_BAND_PX - offset) if side < 0 else (rx + EDGE_BAND_PX + offset)
			x = clamp(x, 4.0, screen_w - 4.0)
			var r: float = lerp(1.6, 3.8, t)
			var col: Color = palette[rng.randi() % palette.size()]
			draw_circle(Vector2(x, y), r * 0.7, Color(0.98, 0.85, 0.25))
			var d: float = r * 1.05
			draw_circle(Vector2(x - d, y), r, col)
			draw_circle(Vector2(x + d, y), r, col)
			draw_circle(Vector2(x, y - d), r, col)
			draw_circle(Vector2(x, y + d), r, col)

func _draw_apron_tufts(rng: RandomNumberGenerator) -> void:
	# Sparse grass tufts on the meadow ONLY (outside the path + edge bands), so
	# the path stays clean.
	var lane_h: float = wide_y - narrow_y
	var attempts_cap: int = 6
	var placed: int = 0
	var iter: int = 0
	while placed < N_GRASS_TUFTS_APRON and iter < N_GRASS_TUFTS_APRON * attempts_cap:
		iter += 1
		var t: float = pow(rng.randf(), 0.7)
		var y: float = narrow_y + t * lane_h
		var x: float = rng.randf() * screen_w
		var lx: float = lerp(narrow_left, wide_left, t) - EDGE_BAND_PX
		var rx: float = lerp(narrow_right, wide_right, t) + EDGE_BAND_PX
		if x > lx and x < rx:
			continue   # on the path — skip
		placed += 1
		var s: float = lerp(0.5, 1.0, t)
		var w: float = 6.0 * s
		var h: float = 3.0 * s
		var col: Color = GRASS_EDGE if rng.randf() < 0.5 else Color(0.62, 0.84, 0.40, 1.0)
		draw_rect(Rect2(x - w * 0.5, y, w, h), col)
