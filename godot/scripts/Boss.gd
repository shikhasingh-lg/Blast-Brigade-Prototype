extends Enemy
class_name Boss
## The Corrupter (World 1 boss). boss-design.md §2.
##
## Floats at lane cell 5 (lane_progress 0.25). Doesn't walk or engage.
## Every boss_ability_interval_sec: telegraphs a target column, then corrupts it.
## Spawns minions on a separate cadence (handled by EnemyLane).
## Wizard's PURPLE color counter applies (roster.md §1.2).

const BOSS_SIZE: float = 64.0
const BOSS_HP_BAR_W: float = 140.0
const BOSS_SPRITE_PATH: String = "res://assets/enemies/boss_corrupter.png"
const BOSS_SPRITE_DRAW_SIZE: float = 220.0   # rendered px before node scale (~1.3); art has presence
static var _boss_texture: Texture2D = null
static func _get_boss_texture() -> Texture2D:
	if _boss_texture == null:
		_boss_texture = load(BOSS_SPRITE_PATH) as Texture2D
	return _boss_texture

signal corruption_telegraph(col: int, remaining_sec: float)
signal corruption_fired(col: int)
signal boss_died(boss)

var ability_timer: float = 0.0
var telegraphing: bool = false
var telegraph_target_col: int = -1
var telegraph_remaining: float = 0.0
var _rng_boss := RandomNumberGenerator.new()

func init_boss(cfg: Dictionary) -> void:
	# Reuse Enemy's init for geometry refs but override stats.
	color = "PURPLE"
	column = cfg.column
	gate = cfg.gate
	hero_row = cfg.get("hero_row", null)
	lane_top_y = cfg.lane_top_y
	lane_bottom_y = cfg.lane_bottom_y
	post_breach_target_y = cfg.post_breach_target_y
	column_x_func = cfg.column_x_func

	max_hp = float(GameConfig.boss_hp)
	hp = max_hp
	currency_value = GameConfig.currency_for_hp(max_hp)
	color_speed_mult = GameConfig.boss_walk_speed_mult
	color_dmg_base = GameConfig.boss_base_damage
	color_dmg_hero = 0   # Corrupter doesn't melee heroes — it walks past them straight to the tower

	# Park the boss on the lane at cell 5 (of 20) → lane_progress = 5/20 = 0.25.
	state = State.LANE
	lane_progress = float(GameConfig.boss_lane_cell) / float(GameConfig.enemy_lane_cells)
	z_index = 2
	_rng_boss.randomize()
	# First ability fires at +boss_ability_interval_sec; telegraph starts boss_telegraph_sec before.
	ability_timer = GameConfig.boss_ability_interval_sec
	telegraphing = false
	telegraph_target_col = -1
	_update_lane_pos()

# ─── Per-frame ─────────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	_tick_statuses(dt)
	if _hit_flash_t > 0.0:
		_hit_flash_t = max(0.0, _hit_flash_t - dt)
	if state == State.DEAD:
		return
	# Boss is stunned/frozen → ability + walk both halt (consistent with enemies).
	var spd_mult: float = effective_speed_mult()
	if spd_mult > 0.0:
		var step: float = (color_speed_mult * spd_mult * dt) / GameConfig.lane_traversal_sec_for_red
		lane_progress = clamp(lane_progress + step, 0.0, 1.0)
		if lane_progress >= 1.0:
			_on_reach_tower()
			return
	_update_boss_pos()
	queue_redraw()
	if spd_mult <= 0.0:
		return
	# Ability + telegraph progression.
	var interval: float = GameConfig.boss_ability_interval_sec
	if max_hp > 0.0 and (hp / max_hp) < GameConfig.boss_low_hp_threshold:
		interval *= GameConfig.boss_low_hp_interval_mult
	if telegraphing:
		telegraph_remaining -= dt * spd_mult
		emit_signal("corruption_telegraph", telegraph_target_col, max(telegraph_remaining, 0.0))
		if telegraph_remaining <= 0.0:
			_fire_corruption()
	else:
		ability_timer -= dt * spd_mult
		if ability_timer <= 0.0:
			_begin_telegraph(interval)

func _begin_telegraph(interval: float) -> void:
	telegraph_target_col = _pick_corruption_target()
	telegraphing = true
	telegraph_remaining = GameConfig.boss_telegraph_sec
	# Next ability cycle resumes after this corruption fires.
	ability_timer = interval

func _fire_corruption() -> void:
	if gate != null and telegraph_target_col >= 0:
		var n: int = gate.corrupt_column(telegraph_target_col)
		Telemetry.log_event("boss_corruption", {"col": telegraph_target_col, "cells": n})
	emit_signal("corruption_fired", telegraph_target_col)
	telegraphing = false
	telegraph_target_col = -1
	telegraph_remaining = 0.0

func _pick_corruption_target() -> int:
	# Bias toward columns with uncorrupted bubbles (target_bias_away_from_corrupted).
	# If the dice roll says "any column," pick uniformly; else prefer non-fully-corrupted.
	var n_cols: int = GameConfig.gate_columns
	var live: Array[int] = []
	for c in range(n_cols):
		if gate != null and gate.column_uncorrupted_count(c) > 0:
			live.append(c)
	if not live.is_empty() and _rng_boss.randf() < GameConfig.corruption_target_bias_away_from_corrupted:
		return live[_rng_boss.randi() % live.size()]
	return _rng_boss.randi() % n_cols

func _update_boss_pos() -> void:
	var bob: float = sin(Time.get_ticks_msec() * 0.002) * 4.0
	var y: float = lerp(lane_top_y, lane_bottom_y, lane_progress) + bob
	var x: float = column_x_func.call(column, lane_progress)
	position = Vector2(x, y)
	# Boss scale: a bit bigger than full-size lane enemy, fixed (no perspective shrink).
	scale = Vector2(1.3, 1.3)

func _die() -> void:
	state = State.DEAD
	emit_signal("boss_died", self)
	emit_signal("died_signal", self)
	queue_free()

func _on_reach_tower() -> void:
	# Corrupter slams the tower for color_dmg_base. EnemyLane forwards this to
	# the base HP via enemy_reached_base. Then mark dead so the wave ends.
	Telemetry.log_event("boss_reached_tower", {"dmg": color_dmg_base})
	emit_signal("reached_cannon", self)
	state = State.DEAD
	emit_signal("boss_died", self)
	emit_signal("died_signal", self)
	queue_free()

# ─── Draw ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Purple aura behind the sprite — keeps the menacing glow even with art.
	var fill: Color = Bubble.COLORS.get("PURPLE", Color(0.62, 0.36, 0.86))
	var aura: Color = Color(fill.r, fill.g, fill.b, 0.35)
	draw_circle(Vector2.ZERO, BOSS_SIZE + 8.0, aura)
	# Body: actual Corrupter art (fallback to procedural blob if missing).
	var tex: Texture2D = _get_boss_texture()
	if tex != null:
		var r := Rect2(-BOSS_SPRITE_DRAW_SIZE * 0.5, -BOSS_SPRITE_DRAW_SIZE * 0.5,
			BOSS_SPRITE_DRAW_SIZE, BOSS_SPRITE_DRAW_SIZE)
		draw_texture_rect(tex, r, false)
		# Hit flash — reuse the inherited counter from Enemy.gd.
		if _hit_flash_t > 0.0:
			var flash_a: float = clamp(_hit_flash_t / GameConfig.hit_flash_duration_sec, 0.0, 1.0)
			draw_texture_rect(tex, r, false, Color(1.0, 1.0, 1.0, flash_a))
	else:
		draw_circle(Vector2.ZERO, BOSS_SIZE, fill)
		draw_arc(Vector2.ZERO, BOSS_SIZE, 0, TAU, 48, Color(0, 0, 0, 0.8), 2.0, true)
		draw_circle(Vector2(0, -8), 14.0, Color(0.96, 0.92, 0.45))
		draw_circle(Vector2(0, -8), 6.0, Color(0.10, 0.08, 0.18))

	# HP bar above.
	var frac: float = clamp(hp / max_hp, 0.0, 1.0)
	var bar_y: float = -BOSS_SIZE - 22.0
	draw_rect(Rect2(-BOSS_HP_BAR_W * 0.5, bar_y, BOSS_HP_BAR_W, 7.0), Color(0.10, 0.10, 0.12))
	draw_rect(Rect2(-BOSS_HP_BAR_W * 0.5, bar_y, BOSS_HP_BAR_W * frac, 7.0),
		Color(0.70, 0.30, 0.85) if frac > 0.25 else Color(0.95, 0.45, 0.35))
	draw_rect(Rect2(-BOSS_HP_BAR_W * 0.5, bar_y, BOSS_HP_BAR_W, 7.0), Color(0, 0, 0, 0.85), false, 1.0)

	# Telegraph beam from boss to target column when telegraphing.
	if telegraphing and telegraph_target_col >= 0 and gate != null:
		var t: float = 1.0 - clamp(telegraph_remaining / GameConfig.boss_telegraph_sec, 0.0, 1.0)
		var pulse: float = 0.4 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		var target_local: Vector2 = to_local(Vector2(column_x_func.call(telegraph_target_col, 0.0), lane_top_y - 20.0))
		draw_line(Vector2.ZERO, target_local, Color(0.85, 0.40, 1.0, pulse * (0.4 + 0.5 * t)), 3.0)
		# Column outline crackle.
		var col_x: float = column_x_func.call(telegraph_target_col, 0.0)
		var col_x_local: float = to_local(Vector2(col_x, 0)).x
		var top_local: Vector2 = to_local(Vector2(col_x, gate.global_position.y))
		var bot_local: Vector2 = to_local(Vector2(col_x, lane_top_y))
		draw_line(Vector2(col_x_local, top_local.y), Vector2(col_x_local, bot_local.y),
			Color(0.85, 0.50, 1.0, pulse), 2.5)

	# Status icons.
	_draw_status_icons()
