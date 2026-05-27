extends Node2D
class_name Enemy
## A single enemy in the flipped layout.
## Lifecycle: TELEGRAPH (visible at gate base) → LANE (walking DOWN through the
##   perspective ground toward heroes, growing) → reach lane_bottom → damage
##   base, despawn.

const SIZE: float = 26.0
const HP_BAR_W: float = 44.0
const MIN_LANE_SCALE: float = 0.30   # at gate base
const GATE_OVERLAY_SCALE: float = 0.40   # at telegraph — slightly larger than lane spawn
const SHADOW_W_MULT: float = 1.55
const SHADOW_H_MULT: float = 0.32
const SPRITE_DRAW_SIZE: float = 130.0  # sprite drawn larger than collision box for art presence
const ENGAGE_STANDOFF_PX: float = 56.0   # ENGAGED enemies park this far above the hero portrait

static var _texture_cache: Dictionary = {}

## Status-icon sheet — slices for slow/freeze/burn/poison/stun glyphs.
## Source: assets/status/status-icons.png (1536×2752). 5 icons in one row at
## y=1252..1500, each 247×248 px, x starts at 67 with 289 px stride.
const STATUS_SHEET_PATH: String = "res://assets/status/status-icons.png"
const STATUS_REGIONS: Dictionary = {
	"slow":   Rect2(67,   1252, 247, 248),
	"freeze": Rect2(356,  1252, 247, 248),
	"burn":   Rect2(645,  1252, 247, 248),
	"poison": Rect2(934,  1252, 247, 248),
	"stun":   Rect2(1223, 1252, 247, 248),
}
static var _status_sheet: Texture2D = null
static func _get_status_sheet() -> Texture2D:
	if _status_sheet == null:
		_status_sheet = load(STATUS_SHEET_PATH) as Texture2D
	return _status_sheet

static func _get_texture(variant_key: String, color_key: String) -> Texture2D:
	var cache_key: String = "%s_%s" % [variant_key, color_key]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var path := "res://assets/enemies/%s_%s.png" % [variant_key.to_lower(), color_key.to_lower()]
	var tex: Texture2D = load(path)
	_texture_cache[cache_key] = tex
	return tex

signal reached_cannon(enemy)
signal died_signal(enemy)
signal breached_signal(enemy)

enum State { TELEGRAPH, LANE, ENGAGED, DEAD }

# Identity / stats
var color: String = "RED"
var variant: String = "WALKER"
var variant_scale: float = 1.0
var hp: float = 50.0
var max_hp: float = 50.0
var color_speed_mult: float = 1.0
var color_dmg_base: int = 20
var color_dmg_hero: int = 10

# Path state
var column: int = 0
var lane_progress: float = 0.0    # 0 = at gate base (just emerged), 1 = at hero row top
var state: int = State.TELEGRAPH
var telegraph_timer: float = 0.0

# Status effects (combat-design.md §7). Five types: slow/freeze/burn/poison/stun.
# Each entry: { type: String, remaining: float, stacks: int }.
# Slow/freeze/stun: don't stack, refresh duration. Burn/poison: stack up to max.
var statuses: Array[Dictionary] = []
var _dot_accum: float = 0.0

# Geometry (from EnemyLane)
var lane_top_y: float = 0.0       # = gate base in screen Y (vanishing point)
var lane_bottom_y: float = 0.0    # = hero row top in screen Y (camera-near)
var post_breach_target_y: float = 0.0  # kept for API compat; equals lane_bottom_y
var column_x_func: Callable

var engage_dps_accum: float = 0.0

# Hit-feel: per-hit white flash counter (ticks down in _process).
var _hit_flash_t: float = 0.0

# Procedural "alive" animation (option A — no spritesheet). Phase clock ticks
# while LANE / ENGAGED; consumed by _draw() to bob, waddle, and tilt the sprite.
# Per-variant feel: bob freq/amplitude, waddle amplitude, tilt amplitude.
# WALKER = mid stride, RUNNER = fast + forward lean, BRUTE = slow heavy thud.
var _anim_t: float = 0.0
const _VARIANT_ANIM: Dictionary = {
	"WALKER": {"bob_hz": 1.5, "bob_px": 2.0, "waddle_px": 1.0, "tilt_deg": 1.5, "lean_deg": 0.0},
	"RUNNER": {"bob_hz": 3.0, "bob_px": 3.0, "waddle_px": 2.0, "tilt_deg": 3.0, "lean_deg": -3.0},
	"BRUTE":  {"bob_hz": 0.8, "bob_px": 4.0, "waddle_px": 0.0, "tilt_deg": 1.0, "lean_deg": 0.0},
}

# Refs
var gate: Gate
var hero_row: HeroRow

func init_enemy(cfg: Dictionary) -> void:
	color = cfg.color
	variant = cfg.get("variant", "WALKER")
	column = cfg.column
	gate = cfg.gate
	hero_row = cfg.get("hero_row", null)
	lane_top_y = cfg.lane_top_y
	lane_bottom_y = cfg.lane_bottom_y
	post_breach_target_y = cfg.post_breach_target_y
	column_x_func = cfg.column_x_func

	var stats: Dictionary = GameConfig.ENEMY_STATS[color]
	var var_stats: Dictionary = GameConfig.ENEMY_VARIANTS.get(variant, GameConfig.ENEMY_VARIANTS["WALKER"])
	var w: int = cfg.wave_idx
	var hp_mult: float = GameConfig.enemy_hp_mult_for_wave(w) * float(var_stats.hp_mult)
	var dmg_mult: float = GameConfig.enemy_dmg_mult_for_wave(w) * float(var_stats.dmg_mult)
	max_hp = float(stats.hp) * hp_mult
	hp = max_hp
	color_speed_mult = float(stats.speed) * float(var_stats.speed_mult)
	color_dmg_base = int(round(stats.dmg_base * dmg_mult))
	color_dmg_hero = int(round(stats.dmg_hero * dmg_mult))
	variant_scale = float(var_stats.scale)

	state = State.TELEGRAPH
	telegraph_timer = GameConfig.spawn_telegraph_sec
	z_index = 1   # always in front of gate so telegraph + walk read clearly
	_set_pos_at_gate()

# Push back along the depth rail + brief stun. Called by the cannon's AOE
# blast on every surviving enemy in radius. Knockback amount is a 0..1 delta
# subtracted from lane_progress; stun is wired through the existing status
# system (halts speed + draws a status icon).
# - DEAD / TELEGRAPH: ignored (not yet walking, or already gone).
# - LANE: lane_progress -= amount, clamped at 0; position refreshes next frame.
# - ENGAGED: position is locked to the hero row, so we only stun (no unpark).
func apply_knockback(amount: float, stun_sec: float) -> void:
	if state == State.DEAD or state == State.TELEGRAPH:
		return
	if state == State.LANE and amount > 0.0:
		lane_progress = max(0.0, lane_progress - amount)
		_update_lane_pos()
	if stun_sec > 0.0:
		apply_status("stun", stun_sec)

func take_damage(amount: float, opts: Dictionary = {}) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	queue_redraw()
	# Per-hit polish — skipped for silent (DoT, status ticks) damage so it
	# doesn't fire every second from burn/poison.
	var silent: bool = bool(opts.get("silent", false))
	if not silent:
		_hit_flash_t = GameConfig.hit_flash_duration_sec
		var crit: bool = bool(opts.get("crit", false))
		var num_pos: Vector2 = global_position + Vector2(0.0, -SIZE * 0.6 * scale.y)
		VFX.spawn_damage_number(num_pos, amount, crit)
		VFX.hit_freeze()
	if hp <= 0.0:
		_die()

# ─── Status effects (combat-design.md §7) ──────────────────────────────────

func apply_status(type: String, duration: float, max_stacks: int = 1) -> void:
	if state == State.DEAD:
		return
	for s in statuses:
		if s.type == type:
			if max_stacks <= 1:
				# Refresh-only types: slow, freeze, stun.
				s.remaining = max(s.remaining, duration)
			else:
				# Stackable types: burn, poison.
				s.stacks = min(s.stacks + 1, max_stacks)
				s.remaining = max(s.remaining, duration)
			queue_redraw()
			return
	statuses.append({"type": type, "remaining": duration, "stacks": 1})
	queue_redraw()

func _tick_statuses(dt: float) -> void:
	if statuses.is_empty():
		return
	var dot_dmg: float = 0.0
	var changed: bool = false
	for s in statuses:
		s.remaining -= dt
	# DoT tick (burn + poison) — accumulate per-second.
	_dot_accum += dt
	if _dot_accum >= 1.0:
		_dot_accum -= 1.0
		for s in statuses:
			if s.type == "burn":
				dot_dmg += max_hp * GameConfig.status_burn_pct_per_sec * s.stacks
			elif s.type == "poison":
				dot_dmg += max_hp * GameConfig.status_poison_pct_per_sec * s.stacks
	# Expire.
	var i: int = statuses.size() - 1
	while i >= 0:
		if statuses[i].remaining <= 0.0:
			statuses.remove_at(i)
			changed = true
		i -= 1
	if dot_dmg > 0.0:
		take_damage(dot_dmg, {"silent": true})
	if changed:
		queue_redraw()

func effective_speed_mult() -> float:
	# Freeze and stun fully halt movement; slow scales.
	for s in statuses:
		if s.type == "freeze" or s.type == "stun":
			return 0.0
	for s in statuses:
		if s.type == "slow":
			return GameConfig.status_slow_speed_mult
	return 1.0

# ─── Per-frame ─────────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	_tick_statuses(dt)
	if _hit_flash_t > 0.0:
		_hit_flash_t = max(0.0, _hit_flash_t - dt)
		queue_redraw()
	if state == State.DEAD:
		return
	var spd_mult: float = effective_speed_mult()
	match state:
		State.TELEGRAPH:
			telegraph_timer -= dt
			_set_pos_at_gate()
			queue_redraw()
			if telegraph_timer <= 0.0:
				_decide_post_telegraph()
		State.LANE:
			var step: float = (color_speed_mult * spd_mult * dt) / GameConfig.lane_traversal_sec_for_red
			lane_progress = clamp(lane_progress + step, 0.0, 1.0)
			_update_lane_pos()
			_anim_t += dt * spd_mult
			queue_redraw()
			if lane_progress >= 1.0:
				_on_reach_hero_row()
		State.ENGAGED:
			if spd_mult <= 0.0:
				return
			_anim_t += dt * spd_mult
			queue_redraw()
			_tick_engagement(dt * spd_mult)
		State.DEAD:
			pass

func _set_pos_at_gate() -> void:
	# Pinned just below the gate base, in the target column, sized small to
	# convey "this enemy is up there at the far wall" depth-wise.
	position = Vector2(column_x_func.call(column, 0.0), lane_top_y - 6.0)
	var s: float = GATE_OVERLAY_SCALE * variant_scale
	scale = Vector2(s, s)

func _update_lane_pos() -> void:
	var y: float = lerp(lane_top_y, lane_bottom_y, lane_progress)
	var x: float = column_x_func.call(column, lane_progress)
	position = Vector2(x, y)
	var s: float = lerp(MIN_LANE_SCALE, 1.0, lane_progress) * variant_scale
	scale = Vector2(s, s)

# ─── Transitions ───────────────────────────────────────────────────────────

func _decide_post_telegraph() -> void:
	_enter_lane()

func _enter_lane() -> void:
	state = State.LANE
	lane_progress = 0.0
	emit_signal("breached_signal", self)
	_update_lane_pos()

func _on_reach_hero_row() -> void:
	# Combat-design §1.2: if a hero stands in this column, lock into ENGAGED and
	# duel them. If the column is empty (or hero already dead), push past to the
	# cannon — current "damage base, despawn" behavior.
	var defender: Hero = null
	if hero_row != null:
		defender = hero_row.hero_at(column)
	if defender != null and is_instance_valid(defender) and defender.hp > 0.0:
		state = State.ENGAGED
		engage_dps_accum = 0.0
		# Park just above the hero portrait so the engager doesn't draw on top of
		# the hero and so heroes have a clear visual target to fire at.
		var park_y: float = lane_bottom_y - ENGAGE_STANDOFF_PX
		lane_progress = inverse_lerp(lane_top_y, lane_bottom_y, park_y)
		position = Vector2(column_x_func.call(column, lane_progress), park_y)
		scale = Vector2(variant_scale, variant_scale)
		z_index = 5   # in front of the lane but behind heroes
		return
	emit_signal("reached_cannon", self)
	state = State.DEAD
	queue_free()

func _tick_engagement(dt: float) -> void:
	var defender: Hero = null
	if hero_row != null:
		defender = hero_row.hero_at(column)
	if defender == null or not is_instance_valid(defender) or defender.hp <= 0.0:
		# Hero died — push through to cannon.
		emit_signal("reached_cannon", self)
		state = State.DEAD
		queue_free()
		return
	engage_dps_accum += dt
	if engage_dps_accum >= 1.0:
		defender.take_damage(float(color_dmg_hero))
		engage_dps_accum -= 1.0

func _die() -> void:
	state = State.DEAD
	emit_signal("died_signal", self)
	queue_free()

# ─── Draw ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var fill: Color = Bubble.COLORS.get(color, Color.GRAY)
	# Depth tint — dimmer when far (top of lane / at gate); full when near.
	var depth_t: float = 1.0
	match state:
		State.TELEGRAPH:
			depth_t = 0.45    # consistently "far away at the wall"
		State.LANE:
			depth_t = clamp(lane_progress, 0.0, 1.0)
		_:
			depth_t = 1.0
	var dim: float = lerp(0.55, 1.0, depth_t)
	var tinted: Color = Color(fill.r * dim, fill.g * dim, fill.b * dim, fill.a)

	var tex: Texture2D = _get_texture(variant, color)
	var draw_rect2 := Rect2(-SPRITE_DRAW_SIZE * 0.5, -SPRITE_DRAW_SIZE * 0.5, SPRITE_DRAW_SIZE, SPRITE_DRAW_SIZE)

	if state == State.TELEGRAPH:
		var pulse: float = 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		var ghost_mod: Color = Color(dim, dim, dim, pulse)
		_draw_ground_shadow(0.6)
		if tex != null:
			draw_texture_rect(tex, draw_rect2, false, ghost_mod)
		else:
			draw_rect(Rect2(-SIZE, -SIZE, SIZE * 2, SIZE * 2), Color(tinted.r, tinted.g, tinted.b, pulse))
		return

	_draw_ground_shadow(1.0)

	# Procedural "alive" tweens — shadow drawn first (stays planted), then sprite
	# / hit-flash / HP bar / status icons drawn inside a bob+waddle+tilt transform.
	var feel: Dictionary = _VARIANT_ANIM.get(variant, _VARIANT_ANIM["WALKER"])
	var phase: float = _anim_t * float(feel.bob_hz) * TAU
	var bob_y: float = -abs(sin(phase)) * float(feel.bob_px)   # always upward (head bounce)
	var waddle_x: float = sin(phase * 0.5) * float(feel.waddle_px)
	var tilt_rad: float = deg_to_rad(sin(phase * 0.5) * float(feel.tilt_deg) + float(feel.lean_deg))
	draw_set_transform(Vector2(waddle_x, bob_y), tilt_rad, Vector2.ONE)

	if tex != null:
		draw_texture_rect(tex, draw_rect2, false, Color(dim, dim, dim, 1.0))
		# Hit-flash: redraw the sprite as pure white over the top with alpha
		# falling from 1→0 across hit_flash_duration_sec.
		if _hit_flash_t > 0.0:
			var flash_a: float = clamp(_hit_flash_t / GameConfig.hit_flash_duration_sec, 0.0, 1.0)
			draw_texture_rect(tex, draw_rect2, false, Color(1.0, 1.0, 1.0, flash_a))
	else:
		draw_rect(Rect2(-SIZE, -SIZE, SIZE * 2, SIZE * 2), tinted)

	# HP bar.
	var frac: float = clamp(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-HP_BAR_W * 0.5, -SIZE - 10, HP_BAR_W, 4), Color(0.18, 0.18, 0.18))
	draw_rect(Rect2(-HP_BAR_W * 0.5, -SIZE - 10, HP_BAR_W * frac, 4),
		Color(0.35, 0.85, 0.35) if frac > 0.5 else Color(0.95, 0.7, 0.25))

	_draw_status_icons()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

const STATUS_ICON_PX: float = 18.0   # on-screen size; sheet art is 247² so this is a heavy downscale (fine).
const STATUS_ICON_PAD: float = 4.0   # horizontal gap between icons.

func _draw_status_icons() -> void:
	if statuses.is_empty():
		return
	var sheet: Texture2D = _get_status_sheet()
	var step: float = STATUS_ICON_PX + STATUS_ICON_PAD
	var x: float = -float(statuses.size() - 1) * step * 0.5
	var y: float = -SIZE - 20.0
	for s in statuses:
		var pos: Vector2 = Vector2(x, y)
		var region: Rect2 = STATUS_REGIONS.get(s.type, Rect2())
		if sheet != null and region.size != Vector2.ZERO:
			var dest := Rect2(pos - Vector2(STATUS_ICON_PX, STATUS_ICON_PX) * 0.5,
				Vector2(STATUS_ICON_PX, STATUS_ICON_PX))
			draw_texture_rect_region(sheet, dest, region)
		else:
			# Fallback if sheet missing — keep the old colored dot so debugging stays sane.
			draw_circle(pos, 4.0, Color.WHITE)
		# Stack pip for burn/poison — small badge bottom-right of the icon.
		if s.stacks > 1:
			var badge_pos := pos + Vector2(STATUS_ICON_PX * 0.35, STATUS_ICON_PX * 0.35)
			draw_circle(badge_pos, 4.5, Color(0.10, 0.08, 0.14, 0.95))
			draw_arc(badge_pos, 4.5, 0, TAU, 12, Color(1, 1, 1, 0.8), 0.8)
			var stack_label := str(s.stacks)
			var f: Font = ThemeDB.fallback_font
			var fs: int = 9
			var w: float = f.get_string_size(stack_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, badge_pos + Vector2(-w * 0.5, 3), stack_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
		x += step

func _draw_ground_shadow(intensity: float) -> void:
	var w: float = SIZE * SHADOW_W_MULT
	var h: float = SIZE * SHADOW_H_MULT
	var cy: float = SIZE + 6.0
	var pts := PackedVector2Array()
	var n: int = 18
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * w * 0.5, cy + sin(a) * h * 0.5))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.42 * intensity))
