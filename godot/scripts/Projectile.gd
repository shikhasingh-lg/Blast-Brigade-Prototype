extends Node2D
class_name Projectile
## Cannon shot. Swept circle-circle collision against the gate so the attach
## point always matches the aim preview (v1 pattern). Renders with the same
## bubble texture as gate cells so in-flight and seated bubbles look identical.

const RADIUS: float = Bubble.ATTACH_RADIUS
const VISUAL_BOX: float = Bubble.SPRITE_DRAW_SIZE

var velocity: Vector2 = Vector2.ZERO
var color: String = "RED"
var attached: bool = false
var hit_bubble: Bubble = null   # the gate bubble that triggered the attach (null = top-bound)

var _viewport_size: Vector2 = Vector2.ZERO
var _gate: Gate = null
var _attach_world_pos: Vector2 = Vector2.ZERO

func setup(dir: Vector2, col: String, gate: Gate, speed: float = Cannon.SHOT_SPEED) -> void:
	velocity = dir * speed
	color = col
	_gate = gate
	_viewport_size = get_viewport_rect().size
	queue_redraw()

func _physics_process(dt: float) -> void:
	if attached:
		return
	# Swept advance: step in micro-segments that resolve against walls and the
	# nearest gate bubble each tick. Mirrors v1's Bubble._physics_process so the
	# preview path and the actual flight always agree.
	var remaining: float = velocity.length() * dt
	var safety: int = 4
	while remaining > 0.001 and safety > 0:
		safety -= 1
		var dir: Vector2 = velocity.normalized()
		var t_left: float = INF
		var t_right: float = INF
		var t_top: float = INF
		if dir.x < 0.0:
			t_left = (RADIUS - position.x) / dir.x
		if dir.x > 0.0:
			t_right = (_viewport_size.x - RADIUS - position.x) / dir.x
		# Top-bound = row 0 of the gate (bubbles hang from sky).
		var top_y: float = _gate.global_position.y + Gate.ROW_HEIGHT * 0.5
		if dir.y < 0.0:
			t_top = (top_y - position.y) / dir.y
		var t_wall: float = min(t_left, t_right)
		var hit: Dictionary = _sweep_first_gate_hit(position, dir, remaining)
		var t_cluster: float = hit["t"]
		var t: float = min(t_wall, min(t_top, t_cluster))
		if t == INF or t > remaining:
			position += dir * remaining
			remaining = 0.0
			break
		if t <= 0.001:
			t = min(remaining, 0.001)
		position += dir * t
		remaining -= t
		if t == t_cluster:
			hit_bubble = hit["bubble"]
			_attach_world_pos = _gate.predict_attach_world_position(position, hit_bubble)
			position = _attach_world_pos
			attached = true
			return
		if t == t_top:
			_attach_world_pos = _gate.predict_attach_world_position(position, null)
			position = _attach_world_pos
			attached = true
			return
		if t == t_wall:
			# Side-wall ricochet
			if position.x < _viewport_size.x * 0.5:
				position.x = RADIUS
			else:
				position.x = _viewport_size.x - RADIUS
			velocity.x = -velocity.x

func _sweep_first_gate_hit(pos: Vector2, dir: Vector2, max_t: float) -> Dictionary:
	# Distance along (pos, dir) at which this projectile first overlaps a gate
	# bubble. Solves |(pos + dir*t) - C|² = R² where R = 2 * ATTACH_RADIUS.
	if _gate == null:
		return {"t": INF, "bubble": null}
	var sum_r: float = RADIUS + Bubble.ATTACH_RADIUS
	var sum_r_sq: float = sum_r * sum_r
	var best_t: float = INF
	var best_b: Bubble = null
	for cell in _gate.cells.keys():
		var b: Bubble = _gate.cells[cell]
		if b == null:
			continue
		var d: Vector2 = pos - b.global_position
		var b_coef: float = 2.0 * d.dot(dir)
		var c_coef: float = d.dot(d) - sum_r_sq
		var disc: float = b_coef * b_coef - 4.0 * c_coef
		if disc < 0.0:
			continue
		var sqrt_disc: float = sqrt(disc)
		var t0: float = (-b_coef - sqrt_disc) * 0.5
		var t1: float = (-b_coef + sqrt_disc) * 0.5
		var t_hit: float = t0 if t0 > 0.001 else t1
		if t_hit > 0.001 and t_hit <= max_t and t_hit < best_t:
			best_t = t_hit
			best_b = b
	return {"t": best_t, "bubble": best_b}

func _draw() -> void:
	var tex: Texture2D = Bubble._get_bubble_tex(color)
	if tex != null:
		var cal: Dictionary = Bubble.get_draw_rect(tex, Bubble.TARGET_VISIBLE_DIAMETER)
		draw_texture_rect(tex, Rect2(cal["pos"], cal["size"]), false, Color.WHITE)
		return
	# Procedural fallback if textures missing.
	var fill: Color = Bubble.COLORS.get(color, Color.GRAY)
	draw_circle(Vector2.ZERO, RADIUS, fill)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, Color(0, 0, 0, 0.7), 1.5, true)
	draw_circle(Vector2(-RADIUS * 0.35, -RADIUS * 0.35), RADIUS * 0.22, Color(1, 1, 1, 0.4))
