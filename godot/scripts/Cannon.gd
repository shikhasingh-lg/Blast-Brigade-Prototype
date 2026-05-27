extends Node2D
class_name Cannon
## Aim + fire. Tap-to-target reticle (Brawl Stars Spike / Clash Royale rocket
## model). Player taps a point in the lane; cannon rotates muzzle toward it
## and a preview arc + reticle render via AimOverlay. Release fires a bomb
## that lobs to the target. Drag the touch to move the target before release.

const SHOT_SPEED: float = 1500.0
const AIM_MAX_DEG: float = 75.0
const COLORS: Array[String] = ["RED", "BLUE", "YELLOW"]

# Tap must land at least this far above the cannon to count — keeps stray
# finger jitter near the wheels from firing minimum-range shots.
const AIM_MIN_RANGE: float = 90.0
# If the touch is below or to the side of the cannon outside the cone, we
# don't fire on release. Cone is the same ±AIM_MAX_DEG arc as before.
const AIM_REJECT_VERTICAL_PAD: float = 8.0

# Tap-to-swap target around the next-up preview. Radial hit test (vs a rect)
# so the target follows the preview's actual draw position and gives the
# player generous slack on a phone.
const SWAP_HIT_RADIUS: float = 60.0
const SWAP_PULSE_SEC: float = 0.18
# Next-up bubble preview offset from the cannon center (replaces the old
# aim-ring-radius anchor since the ring is gone).
const NEXT_PREVIEW_OFFSET: Vector2 = Vector2(154.0, 4.0)

# Muzzle wedge — rotates to point at the tap target so the cannon sells "I'm
# aiming at where you tapped." Base sits just outside the loaded bubble's edge.
const MUZZLE_BASE_DIST: float = 40.0
const MUZZLE_TIP_DIST: float = 70.0
const MUZZLE_HALF_WIDTH: float = 14.0
const MUZZLE_FILL: Color = Color(1.0, 0.92, 0.55, 0.55)
const MUZZLE_OUTLINE: Color = Color(0.18, 0.14, 0.06, 0.55)
const MUZZLE_DIM_ALPHA: float = 0.40

# Loaded bubble preview (drawn at the cannon, behind the muzzle).
const LOADED_VISIBLE: float = Bubble.TARGET_VISIBLE_DIAMETER * 0.86
const NEXT_VISIBLE: float = Bubble.TARGET_VISIBLE_DIAMETER * 0.50

# Recoil — heavier kick than the v2 bubble shooter; a real cannon has weight.
const RECOIL_DISTANCE: float = 22.0
const RECOIL_KICK_SEC: float = 0.06

## Cannon body sprite. Drawn centered behind the procedural overlays, with a soft
## elliptical ground shadow so the sprite reads as a grounded object rather than
## a floating cutout.
const CANNON_SPRITE_PATH: String = "res://assets/cannon.png"
const CANNON_BODY_DRAW_SIZE: float = 130.0
const CANNON_GROUND_OFFSET_Y: float = 36.0   # how far below origin the wheels rest
const CANNON_SHADOW_HALF_W: float = 60.0
const CANNON_SHADOW_HALF_H: float = 12.0
const CANNON_SHADOW_COLOR: Color = Color(0.05, 0.06, 0.10, 0.42)
static var _cannon_sprite: Texture2D = null
static func _get_cannon_sprite() -> Texture2D:
	if _cannon_sprite == null:
		_cannon_sprite = load(CANNON_SPRITE_PATH) as Texture2D
	return _cannon_sprite
const RECOIL_RECOVER_SEC: float = 0.32
# Camera shake on fire — small + quick muzzle kick. Impact shake (bigger,
# longer) is fired separately from BombProjectile when the blast lands.
const FIRE_SHAKE_AMP: float = 5.0
const FIRE_SHAKE_SEC: float = 0.12

const AIM_OVERLAY_SCRIPT: GDScript = preload("res://scripts/AimOverlay.gd")
# Explicit preload to dodge class_name parse-order races — globals aren't
# guaranteed resolved by the time Cannon.gd parses on a cold project boot.
const BombProjScript: GDScript = preload("res://scripts/BombProjectile.gd")

signal fired(world_origin: Vector2, target_pos: Vector2, color: String)

var current_color: String = "RED"
var next_color: String = "RED"
var can_fire: bool = true
# aim_dir = direction from cannon → target (used by recoil + muzzle). Updated
# whenever the player taps/drags a valid target.
var aim_dir: Vector2 = Vector2(0, -1)
var gate: Gate = null

var _rng := RandomNumberGenerator.new()
var _aiming: bool = false
var _target_pos: Vector2 = Vector2.ZERO       # world-space landing point
var _target_valid: bool = false               # false when touch is outside the cone
var _muzzle_angle_deg: float = -90.0          # rendered angle of the muzzle wedge
var _last_fire_ms: int = 0
var _recoil_origin: Vector2 = Vector2.ZERO
var _recoil_origin_captured: bool = false
var _recoil_tween: Tween = null
var _swap_candidate: bool = false   # press started over the next-up preview
var _swap_pulse_t: float = -1.0     # >=0 = pulse active, drives a brief scale-up in _draw
var _aim_overlay: Node2D = null   # set_script'd with AimOverlay; typed as Node2D so the
                                  # const-preload path works before the class registry is hot.

func _ready() -> void:
	_rng.randomize()
	# Defer color init until gate exists; MatchScene assigns gate right after construction.
	current_color = _random_color()
	next_color = _random_color()
	call_deferred("_resolve_gate_and_palette")
	call_deferred("_attach_aim_overlay")
	queue_redraw()

func _resolve_gate_and_palette() -> void:
	if gate == null:
		# MatchScene constructs Cannon before linking gate, so search the parent.
		var p: Node = get_parent()
		if p != null:
			gate = p.get_node_or_null("Gate")
	_refresh_palette_from_gate()
	queue_redraw()

func _attach_aim_overlay() -> void:
	if _aim_overlay != null:
		return
	var ov := Node2D.new()
	ov.set_script(AIM_OVERLAY_SCRIPT)
	ov.name = "AimOverlay"
	ov.visible = false
	ov.z_index = 25
	var parent: Node = get_parent()
	if parent != null:
		parent.add_child(ov)
	_aim_overlay = ov

func _refresh_palette_from_gate() -> void:
	# Used at startup only — initial current/next may have been picked before
	# gate state was known, so seed them from the live palette there.
	# DO NOT call this mid-game: rerolling colours the player has already
	# seen on cannon / on-deck reads as "bubbles disappearing on their own"
	# (issue: 2026-05-21). _random_color() already restricts future draws to
	# active palette, so the once-loaded queue is safe to leave alone.
	if gate == null:
		return
	var active: Array[String] = gate.get_active_colors()
	if active.is_empty():
		return
	if not active.has(current_color):
		current_color = active[_rng.randi() % active.size()]
	if not active.has(next_color):
		next_color = active[_rng.randi() % active.size()]
	queue_redraw()

# ─── Input (tap-to-target reticle, release-to-fire) ────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# Tap on the next-up preview = swap candidate (committed on release).
			if _hits_swap_target(mb.position):
				_swap_candidate = true
				return
			_begin_aim(mb.position)
		else:
			if _swap_candidate:
				_swap_candidate = false
				if _hits_swap_target(mb.position):
					swap_queue()
				return
			_release_aim(mb.position)
	elif event is InputEventMouseMotion and _aiming:
		_update_aim(event.position)

func _next_preview_world_pos() -> Vector2:
	# Mirrors the offset used by _draw_next_preview() so the hit target tracks
	# the actual draw position even if NEXT_PREVIEW_OFFSET changes.
	return global_position + NEXT_PREVIEW_OFFSET

func _hits_swap_target(touch_pos: Vector2) -> bool:
	return touch_pos.distance_to(_next_preview_world_pos()) <= SWAP_HIT_RADIUS

func swap_queue() -> void:
	var tmp: String = current_color
	current_color = next_color
	next_color = tmp
	_swap_pulse_t = 0.0
	queue_redraw()

func _begin_aim(touch_pos: Vector2) -> void:
	_aiming = true
	_update_aim(touch_pos)

func _update_aim(touch_pos: Vector2) -> void:
	if not _aiming:
		return
	var to_touch: Vector2 = touch_pos - global_position
	# Reject taps at/below the cannon — those are misses, not aim intents.
	if to_touch.y >= -AIM_REJECT_VERTICAL_PAD:
		_target_valid = false
		_hide_overlay()
		queue_redraw()
		return
	# Clamp to the upward cone (±AIM_MAX_DEG off straight-up). Tap outside the
	# cone snaps to the cone edge — generous, no rejection.
	var target_rad: float = _clamp_aim_rad(to_touch.angle())
	var dir: Vector2 = Vector2.from_angle(target_rad)
	# Clamp distance to [AIM_MIN_RANGE, MAX_RANGE] so very-close taps still
	# produce a meaningful shot and very-far taps land at the cannon's reach.
	var dist: float = clamp(to_touch.length(), AIM_MIN_RANGE, BombProjScript.MAX_RANGE)
	_target_pos = global_position + dir * dist
	_target_valid = true
	aim_dir = dir
	_muzzle_angle_deg = rad_to_deg(target_rad)
	queue_redraw()
	_refresh_overlay()

func _release_aim(touch_pos: Vector2) -> void:
	if not _aiming:
		return
	_aiming = false
	_hide_overlay()
	# Re-evaluate validity at release so the most recent finger position wins.
	var to_touch: Vector2 = touch_pos - global_position
	if to_touch.y >= -AIM_REJECT_VERTICAL_PAD:
		_target_valid = false
	if not _target_valid:
		queue_redraw()
		return
	if not (can_fire and RunState.can_fire_now()):
		queue_redraw()
		return
	_fire()
	queue_redraw()

func _clamp_aim_rad(target_rad: float) -> float:
	# Convert to "angle off straight-up" and clamp into ±AIM_MAX_DEG.
	var up_rad: float = deg_to_rad(-90.0)
	var delta: float = wrapf(target_rad - up_rad, -PI, PI)
	var max_a: float = deg_to_rad(AIM_MAX_DEG)
	delta = clamp(delta, -max_a, max_a)
	return up_rad + delta

# ─── Fire ──────────────────────────────────────────────────────────────────

func _fire() -> void:
	_last_fire_ms = Time.get_ticks_msec()
	emit_signal("fired", global_position, _target_pos, current_color)
	_apply_recoil()
	VFX.shake(FIRE_SHAKE_AMP, FIRE_SHAKE_SEC)
	SFX.play("cannon_fire")
	# Advance queue. _random_color() already pulls only from the gate's active
	# palette, so we don't need a post-advance reroll — and rerolling here
	# would silently swap the loaded bubble out from under the player.
	current_color = next_color
	next_color = _random_color()
	can_fire = false
	queue_redraw()
	await get_tree().create_timer(GameConfig.cannon_reload_cooldown_sec).timeout
	can_fire = true
	queue_redraw()

func _apply_recoil() -> void:
	if not _recoil_origin_captured:
		_recoil_origin = position
		_recoil_origin_captured = true
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	var kick: Vector2 = _recoil_origin + (-aim_dir) * RECOIL_DISTANCE
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(self, "position", kick, RECOIL_KICK_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(self, "position", _recoil_origin, RECOIL_RECOVER_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _random_color() -> String:
	if gate != null:
		var active: Array[String] = gate.get_active_colors()
		if not active.is_empty():
			return active[_rng.randi() % active.size()]
	return COLORS[_rng.randi() % COLORS.size()]

# ─── Aim overlay (preview arc + landing reticle) ───────────────────────────

func _refresh_overlay() -> void:
	if _aim_overlay == null or not _target_valid:
		return
	var pred: Dictionary = _compute_aim_prediction(_target_pos)
	_aim_overlay.visible = true
	_aim_overlay.set_polyline(pred["polyline"], current_color, pred["landing"])

func _hide_overlay() -> void:
	if _aim_overlay != null:
		_aim_overlay.visible = false
		_aim_overlay.clear()

func _compute_aim_prediction(target_pos: Vector2) -> Dictionary:
	# Mortar preview — samples the straight ground line from cannon → target,
	# applying the same sine-wave lift the bomb will use in flight. The landing
	# reticle marks the actual ground impact (where the AOE will detonate).
	var pts := PackedVector2Array()
	var origin: Vector2 = global_position
	var delta: Vector2 = target_pos - origin
	var distance: float = delta.length()
	if distance < 1.0:
		return {"polyline": pts, "landing": null}
	var dir: Vector2 = delta / distance
	# Mirror BombProjectile.setup()'s distance-scaled arc so the preview
	# matches the bomb's visible flight exactly.
	var range_t: float = clamp(distance / BombProjScript.MAX_RANGE, 0.0, 1.0)
	var arc_height: float = BombProjScript.ARC_PEAK * lerp(0.40, 1.00, sqrt(range_t))
	var samples: int = 24
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var travel_pos: Vector2 = origin + dir * (distance * t)
		var lift_y: float = -sin(t * PI) * arc_height
		pts.append(travel_pos + Vector2(0.0, lift_y))
	return {"polyline": pts, "landing": target_pos}

# ─── Draw ──────────────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	# Repaint while the cooldown ramp is animating so the muzzle dim resolves.
	if _cooldown_progress() < 1.0:
		queue_redraw()
	# Drive the swap pulse — brief scale bump on current + next, then stops.
	if _swap_pulse_t >= 0.0:
		_swap_pulse_t += dt
		if _swap_pulse_t >= SWAP_PULSE_SEC:
			_swap_pulse_t = -1.0
		queue_redraw()

func _cooldown_progress() -> float:
	var cd: float = GameConfig.cannon_reload_cooldown_sec
	if cd <= 0.001:
		return 1.0
	var since: float = float(Time.get_ticks_msec() - _last_fire_ms) / 1000.0
	return clamp(since / cd, 0.0, 1.0)

func _draw() -> void:
	# Painted cannon body sits behind everything else so the procedural overlays
	# (loaded bubble, muzzle) read on top.
	_draw_cannon_body()
	# Loaded bubble at the cannon (cluster-matching texture so size reads consistent).
	_draw_loaded_bubble()
	# Muzzle wedge — points at the current/last aimed target. Reads as "I'm
	# aiming there." Dimmed during the reload cooldown.
	_draw_muzzle(_muzzle_angle_deg)
	# Next-up preview to the right of the cannon (swap target).
	_draw_next_preview()

func _draw_cannon_body() -> void:
	# Soft ground shadow — drawn first so the sprite reads as a grounded prop.
	# Elliptical fade modeled as 3 nested ellipses with decreasing alpha (cheap
	# blur substitute; we don't have a shader available here).
	var shadow_center := Vector2(0, CANNON_GROUND_OFFSET_Y + CANNON_SHADOW_HALF_H * 0.6)
	for i in range(3):
		var t: float = float(i) / 2.0   # 0, 0.5, 1
		var w: float = CANNON_SHADOW_HALF_W * (1.15 - t * 0.30)
		var h: float = CANNON_SHADOW_HALF_H * (1.15 - t * 0.30)
		var a: float = CANNON_SHADOW_COLOR.a * (0.35 + 0.35 * (1.0 - t))
		var pts := PackedVector2Array()
		var n: int = 22
		for j in range(n):
			var ang: float = TAU * float(j) / float(n)
			pts.append(shadow_center + Vector2(cos(ang) * w, sin(ang) * h))
		var c := CANNON_SHADOW_COLOR
		c.a = a
		draw_colored_polygon(pts, c)

	var tex: Texture2D = _get_cannon_sprite()
	if tex == null:
		return
	var s: float = CANNON_BODY_DRAW_SIZE
	# Sprite is roughly square; anchor wheels at the ground shadow line. The
	# image's wheels sit at ~85% of its height, so we offset upward so they land
	# on the shadow center.
	var sprite_size := Vector2(s, s)
	var pos := Vector2(-s * 0.5, CANNON_GROUND_OFFSET_Y - s * 0.85)
	draw_texture_rect(tex, Rect2(pos, sprite_size), false, Color.WHITE)

func _swap_pulse_scale() -> float:
	# Eases from 0.7 → 1.0 over SWAP_PULSE_SEC. Returns 1.0 when no pulse active.
	if _swap_pulse_t < 0.0:
		return 1.0
	var u: float = clamp(_swap_pulse_t / SWAP_PULSE_SEC, 0.0, 1.0)
	return lerp(0.7, 1.0, u)

func _draw_loaded_bubble() -> void:
	var s: float = _swap_pulse_scale()
	var tex: Texture2D = Bubble._get_bubble_tex(current_color)
	if tex != null:
		var cal: Dictionary = Bubble.get_draw_rect(tex, LOADED_VISIBLE * s)
		draw_texture_rect(tex, Rect2(cal["pos"], cal["size"]), false, Color.WHITE)
	else:
		var fill: Color = Bubble.COLORS.get(current_color, Color.GRAY)
		draw_circle(Vector2.ZERO, Bubble.RADIUS * s, fill)
		draw_arc(Vector2.ZERO, Bubble.RADIUS * s, 0, TAU, 32, Color(0, 0, 0, 0.7), 1.5, true)

func _draw_next_preview() -> void:
	var pos: Vector2 = NEXT_PREVIEW_OFFSET
	var s: float = _swap_pulse_scale()
	var tex: Texture2D = Bubble._get_bubble_tex(next_color)
	if tex != null:
		var cal: Dictionary = Bubble.get_draw_rect(tex, NEXT_VISIBLE * s)
		var rect := Rect2(Vector2(cal["pos"]) + pos, Vector2(cal["size"]))
		draw_texture_rect(tex, rect, false, Color.WHITE)
	else:
		var fill: Color = Bubble.COLORS.get(next_color, Color.GRAY)
		draw_circle(pos, 14.0 * s, fill)
		draw_arc(pos, 14.0 * s, 0, TAU, 24, Color(0, 0, 0, 0.6), 1.0, true)

func _draw_muzzle(angle_deg: float) -> void:
	var dir: Vector2 = Vector2.from_angle(deg_to_rad(angle_deg))
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var base: Vector2 = dir * MUZZLE_BASE_DIST
	var tip: Vector2 = dir * MUZZLE_TIP_DIST
	var poly := PackedVector2Array([
		tip,
		base + perp * MUZZLE_HALF_WIDTH,
		base - perp * MUZZLE_HALF_WIDTH,
	])
	# Cooldown dim — muzzle fades back to full opacity by the time next shot is ready.
	var cd: float = _cooldown_progress()
	var fill: Color = MUZZLE_FILL
	fill.a *= lerp(MUZZLE_DIM_ALPHA, 1.0, cd)
	var outline: Color = MUZZLE_OUTLINE
	outline.a *= lerp(MUZZLE_DIM_ALPHA, 1.0, cd)
	draw_colored_polygon(poly, fill)
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[0]]),
		outline, 2.0, true)
