extends Node2D
class_name BombProjectile
## Blast Brigade cannon shot, mortar / indirect-fire model in a 2.5D scene.
## The player picks a TARGET POINT (tap-to-target reticle in Cannon.gd); the
## bomb is lobbed in a straight line on the ground while the visible sprite
## arcs over via a sine-wave Y lift, then detonates AOE at the target. Bombs
## do NOT collide with enemies mid-flight — they fly over close enemies and
## land where the player aimed.

const RADIUS: float = 18.0
const DRAW_RADIUS: float = 22.0
# Ground travel — linear, constant speed. MAX_RANGE is how far forward the
# cannon can reach into the lane on an empty-air shot.
const LAUNCH_SPEED: float = 1100.0
const MAX_RANGE: float = 950.0
# Visual-only — height of the sine bump above the ground path. Bigger = more
# cartoony arc, smaller = flatter trajectory. ~12% of viewport height reads
# well without making the bomb leave the top of the screen on vertical aims.
const ARC_PEAK: float = 120.0
const OFFSCREEN_MARGIN: float = 50.0
const BLAST_RADIUS: float = 110.0
# Damage at the edge of the blast = center damage × this ratio (linear falloff).
const BLAST_DMG_EDGE_RATIO: float = 0.45
# Screen shake on detonation — bigger than the cannon-fire kick so impact reads
# as the heavier event (boom > thump).
const BLAST_SHAKE_AMP: float = 11.0
const BLAST_SHAKE_SEC: float = 0.22
# Hitstop — short Engine.time_scale freeze paired with the shake. Longer than
# the default per-hit freeze (0.035s) so the cannon's "boom" lands harder than
# a hero arrow.
const BLAST_FREEZE_SEC: float = 0.08
# Knockback applied to AOE survivors. Amount is a delta on Enemy.lane_progress
# (0..1 along the depth rail); 0.06 ≈ 40 px push-back at the rail's current
# vertical span. Stun halts the enemy for the duration via the status system.
const KNOCKBACK_AMOUNT: float = 0.06
const KNOCKBACK_STUN_SEC: float = 0.25
const SHELL_COLOR: Color = Color(0.18, 0.20, 0.26, 1.0)
const FUSE_COLOR: Color = Color(1.00, 0.78, 0.30, 1.0)
const HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
# Smoke trail — warm grey puffs that fade as they age.
const SMOKE_COLOR: Color = Color(0.78, 0.74, 0.68, 1.0)
# Drop a new puff every Nth physics frame so the trail reads as discrete
# wisps, not a continuous ribbon. 2 = ~30 ms at 60 Hz physics.
const TRAIL_SPAWN_INTERVAL: int = 2
# Soft ground shadow drawn at _travel_pos. Bigger when bomb is low (visual
# anchor), smaller at apex (suggests altitude).
const SHADOW_COLOR: Color = Color(0.05, 0.06, 0.10, 0.40)

var velocity: Vector2 = Vector2.ZERO
var damage: float = 60.0
var dead: bool = false
var enemy_lane: EnemyLane = null

var _viewport_size: Vector2 = Vector2.ZERO
var _trail: PackedVector2Array = PackedVector2Array()
var _trail_frame_counter: int = 0
const TRAIL_LEN: int = 14

# 2.5D split: collision-plane position uses _travel_pos (ground), drawing
# uses position (= _travel_pos + visual lift). _distance_traveled / _flight_distance
# drives both the arc progress and the landing trigger.
var _travel_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _distance_traveled: float = 0.0
var _flight_distance: float = 0.0
var _arc_offset_y: float = 0.0
# Per-shot arc height — scales with flight distance so short lobs aren't
# absurdly arched and long lobs read as committed.
var _arc_height: float = ARC_PEAK

func setup(target_pos: Vector2, dmg: float, lane: EnemyLane, speed: float = LAUNCH_SPEED) -> void:
	_target_pos = target_pos
	damage = dmg
	enemy_lane = lane
	_viewport_size = get_viewport_rect().size
	_travel_pos = position
	var delta: Vector2 = target_pos - position
	_flight_distance = max(delta.length(), 1.0)
	velocity = (delta / _flight_distance) * speed
	# Arc scales sub-linearly with distance: short shots get ~40% peak; max-range
	# shots get the full ARC_PEAK. sqrt feels right (consistent with how mortars
	# scale in Brawl Stars / Clash Royale clones).
	var range_t: float = clamp(_flight_distance / MAX_RANGE, 0.0, 1.0)
	_arc_height = ARC_PEAK * lerp(0.40, 1.00, sqrt(range_t))
	_arc_offset_y = 0.0
	queue_redraw()

func _physics_process(dt: float) -> void:
	if dead:
		return

	# Mortar model — bomb travels straight from launch to target, no mid-flight
	# enemy collision (it lobs OVER close enemies). Detonates at the target.
	var step_vec: Vector2 = velocity * dt
	var step_dist: float = step_vec.length()
	_travel_pos += step_vec
	_distance_traveled += step_dist

	# Landed: explode at the exact target so micro-overshoot from the last
	# frame's full step doesn't shift the blast center.
	if _distance_traveled >= _flight_distance:
		_explode(_target_pos)
		return

	# Update visible position with sine-wave lift. Progress 0 → 1 over flight.
	var progress: float = clamp(_distance_traveled / _flight_distance, 0.0, 1.0)
	_arc_offset_y = -sin(progress * PI) * _arc_height
	position = _travel_pos + Vector2(0.0, _arc_offset_y)

	# Smoke trail tracks the LIFTED position so wisps curve with the visible
	# bomb path (not the ground line). Old puffs roll off the front.
	_trail_frame_counter += 1
	if _trail_frame_counter >= TRAIL_SPAWN_INTERVAL:
		_trail_frame_counter = 0
		_trail.append(position)
		if _trail.size() > TRAIL_LEN:
			_trail.remove_at(0)

	# Off-screen safety using ground position (so steep side-shots that exit
	# the lane don't linger).
	if _travel_pos.x < -OFFSCREEN_MARGIN \
			or _travel_pos.x > _viewport_size.x + OFFSCREEN_MARGIN \
			or _travel_pos.y < -OFFSCREEN_MARGIN \
			or _travel_pos.y > _viewport_size.y + OFFSCREEN_MARGIN:
		_die()
		return

	queue_redraw()

func _sweep_first_enemy_hit(pos: Vector2, dir: Vector2, max_t: float) -> Dictionary:
	if enemy_lane == null:
		return {"t": INF, "enemy": null}
	var sum_r_sq: float = (RADIUS + 22.0) * (RADIUS + 22.0)  # ~Enemy collision radius
	var best_t: float = INF
	var best_e: Enemy = null
	for e in enemy_lane.enemies:
		if e == null or not is_instance_valid(e):
			continue
		var d: Vector2 = pos - e.global_position
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
			best_e = e
	return {"t": best_t, "enemy": best_e}

func _explode(at: Vector2) -> void:
	if dead:
		return
	dead = true
	# Visual + audio first so they fire even if the lane is empty.
	VFX.play("bomb_blast", at, {"radius": BLAST_RADIUS})
	VFX.shake(BLAST_SHAKE_AMP, BLAST_SHAKE_SEC)
	# Claim the time-scale freeze before per-enemy take_damage fires (it
	# also calls VFX.hit_freeze() but re-entrant calls are no-ops, so our
	# longer duration wins).
	VFX.hit_freeze(BLAST_FREEZE_SEC)
	SFX.play("bomb_impact")
	# Sweep enemies in radius and damage with linear falloff. Center hits do
	# full damage; edge hits do BLAST_DMG_EDGE_RATIO × damage. Enemies dying
	# emit died_signal which EnemyLane catches to grant currency, so the
	# "kills drop coins" payoff happens automatically per kill. Survivors
	# get knocked back along the depth rail + briefly stunned.
	if enemy_lane != null:
		var r_sq: float = BLAST_RADIUS * BLAST_RADIUS
		for e in enemy_lane.enemies:
			if e == null or not is_instance_valid(e):
				continue
			var dist_sq: float = at.distance_squared_to(e.global_position)
			if dist_sq > r_sq:
				continue
			var t_dist: float = sqrt(dist_sq) / BLAST_RADIUS  # 0 at center → 1 at edge
			var scale_dmg: float = lerp(1.0, BLAST_DMG_EDGE_RATIO, t_dist)
			e.take_damage(damage * scale_dmg)
			# Survivor check — take_damage may have killed + queue_free'd them.
			if is_instance_valid(e) and e.state != Enemy.State.DEAD:
				e.apply_knockback(KNOCKBACK_AMOUNT, KNOCKBACK_STUN_SEC)
	queue_free()

func _die() -> void:
	if dead:
		return
	dead = true
	queue_free()

func _draw() -> void:
	# Ground shadow at _travel_pos. In local space, that's at y = -_arc_offset_y
	# (positive screen Y, i.e. below the lifted sprite). Shadow shrinks slightly
	# as the bomb climbs, which sells altitude without needing real depth.
	var altitude: float = abs(_arc_offset_y)
	var altitude_t: float = clamp(altitude / max(_arc_height, 1.0), 0.0, 1.0)
	var shadow_w: float = lerp(DRAW_RADIUS * 1.10, DRAW_RADIUS * 0.65, altitude_t)
	var shadow_h: float = lerp(DRAW_RADIUS * 0.42, DRAW_RADIUS * 0.25, altitude_t)
	var shadow_alpha: float = lerp(SHADOW_COLOR.a, SHADOW_COLOR.a * 0.45, altitude_t)
	var shadow_center := Vector2(0.0, -_arc_offset_y)
	var shadow_pts := PackedVector2Array()
	var n_pts: int = 22
	for j in range(n_pts):
		var ang: float = TAU * float(j) / float(n_pts)
		shadow_pts.append(shadow_center + Vector2(cos(ang) * shadow_w, sin(ang) * shadow_h))
	draw_colored_polygon(shadow_pts, Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b, shadow_alpha))

	# Smoke trail. Each puff = a slightly grown circle with falling alpha as it
	# ages. Newest puff (last in array) is small + opaque; oldest is large + faint.
	# Drawn in local space, so subtract this frame's lifted position.
	var n: int = _trail.size()
	for i in range(n):
		var u: float = float(i + 1) / float(n)
		var puff_r: float = lerp(13.0, 5.0, u)
		var alpha: float = lerp(0.05, 0.42, u)
		var c: Color = SMOKE_COLOR
		c.a = alpha
		var local_pos: Vector2 = _trail[i] - position
		draw_circle(local_pos, puff_r, c)
	# Shell.
	draw_circle(Vector2.ZERO, DRAW_RADIUS, SHELL_COLOR)
	# Highlight (top-left).
	draw_circle(Vector2(-DRAW_RADIUS * 0.35, -DRAW_RADIUS * 0.40), DRAW_RADIUS * 0.30, HIGHLIGHT_COLOR)
	# Fuse spark on top.
	draw_circle(Vector2(0, -DRAW_RADIUS - 4), 4.0, FUSE_COLOR)
	draw_circle(Vector2(0, -DRAW_RADIUS - 4), 7.0, Color(FUSE_COLOR.r, FUSE_COLOR.g, FUSE_COLOR.b, 0.45))
