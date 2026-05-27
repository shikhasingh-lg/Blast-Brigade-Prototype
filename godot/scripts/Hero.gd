extends Node2D
class_name Hero
## A single hero standing on row 0. Auto-fires at lane enemies through the gate
## subject to occlusion (combat-design §1, design-spec §6).

const SIZE: float = 40.56         # 1.56× original (1.2 × 1.3) — keeps pips in proportion
const SPRITE_DRAW_SIZE: float = 149.76  # 1.56× original — chibi portrait drawn larger than collision box

# Global visibility multiplier for hero-attack projectiles (arrow, streaks,
# wedges, slash). Bumped from 1.0 → 1.9 so projectiles read on a 720-wide
# mobile viewport instead of looking like hairlines. Tune here.
const PROJECTILE_SCALE: float = 1.1

const CLASS_COLOR: Dictionary = {
	"FireKnight": "RED",
	"IceMage":    "BLUE",
	"Archer":     "YELLOW",
	"Druid":      "GREEN",
	"Wizard":     "PURPLE",
}

const CLASS_TEXTURE_SLUG: Dictionary = {
	"FireKnight": "fire-knight",
	"IceMage":    "ice-mage",
	"Archer":     "archer",
	"Druid":      "druid",
	"Wizard":     "wizard",
}

static var _texture_cache: Dictionary = {}

static func _get_texture(hclass: String) -> Texture2D:
	if _texture_cache.has(hclass):
		return _texture_cache[hclass]
	var slug: String = CLASS_TEXTURE_SLUG.get(hclass, "fire-knight")
	var tex: Texture2D = load("res://assets/heroes/%s.png" % slug)
	_texture_cache[hclass] = tex
	return tex

signal died_signal(hero)

var hero_class: String = "FireKnight"
var color: String = "RED"
var tier: int = 1
var column: int = 0
var max_hp: float = 100.0
var hp: float = 100.0
var base_damage: float = 20.0
var fire_cooldown: float = 0.0

var gate: Gate
var enemy_lane: EnemyLane

func init_hero(hclass: String, t: int, col: int, g: Gate, el: EnemyLane) -> void:
	hero_class = hclass
	color = CLASS_COLOR.get(hclass, "RED")
	tier = clamp(t, 1, 3)
	column = col
	gate = g
	enemy_lane = el
	_apply_tier_stats()
	fire_cooldown = _fire_rate() * 0.5   # quick first shot
	queue_redraw()

func _apply_tier_stats() -> void:
	max_hp = GameConfig.hero_base_hp * GameConfig.hero_tier_hp_mult[tier]
	hp = max_hp
	base_damage = GameConfig.hero_base_damage * GameConfig.hero_tier_dmg_mult[tier]

func promote_tier() -> void:
	tier = min(tier + 1, 3)
	_apply_tier_stats()
	queue_redraw()
	_vfx_promote_burst()

# Scale-pop + colored ring burst + light beam so a merge reads instantly.
func _vfx_promote_burst() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.25, 1.25), 0.10).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK)
	var ring_col: Color = _tier_color(tier)
	var ring := Polygon2D.new()
	ring.color = Color(ring_col.r, ring_col.g, ring_col.b, 0.80)
	var pts := PackedVector2Array()
	for i in 28:
		var a: float = TAU * float(i) / 28.0
		pts.append(Vector2(cos(a), sin(a)) * SIZE * 1.6)
	ring.polygon = pts
	ring.z_index = 80
	add_child(ring)
	ring.scale = Vector2(0.4, 0.4)
	var rt := ring.create_tween()
	rt.tween_property(ring, "scale", Vector2(1.4, 1.4), 0.32).set_trans(Tween.TRANS_QUART)
	rt.parallel().tween_property(ring, "modulate:a", 0.0, 0.32)
	rt.tween_callback(func():
		if is_instance_valid(ring): ring.queue_free())

func _fire_rate() -> float:
	match hero_class:
		"FireKnight": return GameConfig.red_fire_rate_sec
		"IceMage":    return GameConfig.blue_fire_rate_sec
		"Archer":     return GameConfig.yellow_fire_rate_sec
		"Druid":      return GameConfig.green_fire_rate_sec
		"Wizard":     return GameConfig.purple_fire_rate_sec
		_: return 1.0

func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	queue_redraw()
	if hp <= 0.0:
		emit_signal("died_signal", self)
		queue_free()

func heal(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = clamp(hp + amount, 0.0, max_hp)
	queue_redraw()

# Druid chain-heal entry point (v1 §8.4). Returns actual amount healed after
# the per-second cap is applied so we never out-heal cap.
var _heal_received_this_sec: int = 0
var _heal_window_t: float = 0.0

func try_heal(amount: int, cap_per_sec: int) -> int:
	if hp >= max_hp:
		return 0
	if _heal_window_t <= 0.0:
		_heal_received_this_sec = 0
		_heal_window_t = 1.0
	var remaining_cap: int = max(0, cap_per_sec - _heal_received_this_sec)
	if remaining_cap <= 0:
		return 0
	var space: int = int(max_hp) - int(hp)
	var ticked: int = min(amount, min(remaining_cap, space))
	if ticked <= 0:
		return 0
	hp += float(ticked)
	_heal_received_this_sec += ticked
	queue_redraw()
	return ticked

func _process(dt: float) -> void:
	if hp <= 0.0:
		return
	fire_cooldown -= dt
	if _heal_window_t > 0.0:
		_heal_window_t -= dt
		if _heal_window_t <= 0.0:
			_heal_received_this_sec = 0
	if fire_cooldown <= 0.0:
		_try_fire()
		fire_cooldown = _fire_rate()

func _try_fire() -> void:
	# v1 parity: heroes auto-fire any valid target in range. The v2 closed-column
	# silencing rule (combat-design §1.2 step 2) was tried and abandoned — bubbles
	# above the hero no longer block their shot.
	if enemy_lane == null:
		return
	var target: Enemy = _pick_target()
	if target == null:
		return
	_fire_at(target)

func _pick_target() -> Enemy:
	match hero_class:
		"FireKnight": return _scan_zone(GameConfig.red_cone_rows_for_tier(tier),    GameConfig.red_cone_cols_for_tier(tier),    true)
		"IceMage":    return _scan_zone(GameConfig.blue_reach_rows_for_tier(tier),  GameConfig.blue_col_radius_for_tier(tier),  false)
		"Archer":     return _scan_zone(GameConfig.yellow_reach_rows_for_tier(tier), GameConfig.yellow_col_radius_for_tier(tier), false)
		"Druid":      return _scan_zone(GameConfig.green_reach_rows_for_tier(tier), GameConfig.green_col_radius_for_tier(tier), true)
		"Wizard":     return _scan_zone(GameConfig.purple_reach_rows_for_tier(tier), GameConfig.purple_col_radius_for_tier(tier), false)
	return null

# Cone/box scan: enemies in lane within ±col_span of hero, lane_progress within
# the last `max_rows_up` of the lane. `prefer_closest=true` picks the highest
# lane_progress (about to cross); false picks the lowest (furthest back, used by
# the lobbers/snipers that want to land into a pack).
func _scan_zone(max_rows_up: int, col_span: int, prefer_closest: bool) -> Enemy:
	var min_progress: float = _min_progress_for(max_rows_up)
	var best: Enemy = null
	for e in enemy_lane.enemies:
		if not _is_targetable(e):
			continue
		if abs(e.column - column) > col_span:
			continue
		if e.lane_progress < min_progress:
			continue
		if best == null \
				or (prefer_closest and e.lane_progress > best.lane_progress) \
				or (not prefer_closest and e.lane_progress < best.lane_progress):
			best = e
	return best

# Single-column scan: own column first; if empty, pick the better of ±1 cols
# (the one with the furthest-up enemy). Used by Archer + Wizard.
func _scan_column_with_adj_fallback(max_rows_up: int) -> Enemy:
	var best: Enemy = _scan_single_column(column, max_rows_up)
	if best != null:
		return best
	var left: Enemy = _scan_single_column(column - 1, max_rows_up)
	var right: Enemy = _scan_single_column(column + 1, max_rows_up)
	if left == null:  return right
	if right == null: return left
	return left if left.lane_progress < right.lane_progress else right

func _scan_single_column(col: int, max_rows_up: int) -> Enemy:
	if col < 0 or col >= GameConfig.gate_columns:
		return null
	var min_progress: float = _min_progress_for(max_rows_up)
	var best: Enemy = null
	for e in enemy_lane.enemies:
		if not _is_targetable(e) or e.column != col:
			continue
		if e.lane_progress < min_progress:
			continue
		if best == null or e.lane_progress < best.lane_progress:
			best = e
	return best

func _is_targetable(e: Enemy) -> bool:
	# Engaged enemies are physically standing in front of a hero — they must
	# remain targetable, otherwise heroes silently stare at the thing eating them.
	if not is_instance_valid(e) or e.hp <= 0.0:
		return false
	return e.state == Enemy.State.LANE or e.state == Enemy.State.ENGAGED

func _min_progress_for(max_rows_up: int) -> float:
	var cells: int = GameConfig.enemy_lane_cells
	if cells <= 0 or max_rows_up >= cells:
		return 0.0
	return float(cells - max_rows_up) / float(cells)

var _wizard_burst_count: int = 0

func _fire_at(target: Enemy) -> void:
	# Micro VFX + audio at the muzzle. Each class draws its own bespoke combat
	# VFX inside _fire_<color> via the existing _vfx_* helpers; this is the
	# universal "hero fired" pulse on top.
	VFX.play("hero_fire_flash", global_position, {"color": color})
	SFX.play("hero_fire_" + hero_class)
	match hero_class:
		"FireKnight": _fire_red(target)
		"IceMage":    _fire_blue(target)
		"Archer":     _fire_yellow(target)
		"Druid":      _fire_green(target)
		"Wizard":     _fire_purple(target)

func _damage_for_hit(target: Enemy, class_mult: float) -> float:
	var dmg: float = base_damage * class_mult
	if target.color == color:
		dmg *= GameConfig.color_counter_mult
	return dmg

# ─── Fire Knight (RED) ─ melee: lunge + slash crescent + wedge + sparks, plus
# RNG cleave on row-neighbors with their own narrower wedges. v1 §3.5 + §3.6.
func _fire_red(target: Enemy) -> void:
	if not is_instance_valid(target):
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	_vfx_lunge(dir)
	_vfx_slash(dir, 130.0, Color(1.0, 0.55, 0.20, 0.92))
	_vfx_wedge(dir, 150.0, 45.0, Color(1.0, 0.35, 0.18, 0.30), 0.20)
	_vfx_impact_sparks(target.global_position, Color(1.0, 0.7, 0.25, 1.0), 8, 36.0)
	target.take_damage(_damage_for_hit(target, GameConfig.red_dmg_mult))
	if randf() < GameConfig.red_cleave_chance:
		_red_cleave(target)

func _red_cleave(primary: Enemy) -> void:
	var max_targets: int = GameConfig.red_cleave_targets
	var cols: int = GameConfig.red_cone_cols_for_tier(tier)
	var cleaved: int = 0
	for e in enemy_lane.enemies:
		if cleaved >= max_targets:
			break
		if e == primary or not _is_targetable(e):
			continue
		if abs(e.column - primary.column) > cols:
			continue
		if abs(e.lane_progress - primary.lane_progress) > 0.10:
			continue
		var c_dir: Vector2 = (e.global_position - global_position).normalized()
		_vfx_wedge(c_dir, 90.0, 22.0, Color(1.0, 0.55, 0.20, 0.45), 0.14)
		e.take_damage(_damage_for_hit(e, GameConfig.red_dmg_mult))
		cleaved += 1

# ─── Ice Mage (BLUE) ─ lobbed ice crystal with sparkle trail; on impact: AoE
# ring + shatter + full-dmg splash + 30%/2s slow on everyone in radius.
func _fire_blue(target: Enemy) -> void:
	if not is_instance_valid(target):
		return
	var primary_dmg: float = _damage_for_hit(target, GameConfig.blue_dmg_mult)
	var radius_sq: float = GameConfig.blue_aoe_radius_px * GameConfig.blue_aoe_radius_px
	var impact_world: Vector2 = target.global_position
	_vfx_ice_lob(impact_world, func():
		_vfx_aoe_ring(impact_world, GameConfig.blue_aoe_radius_px, Color(0.40, 0.78, 1.0, 0.35))
		_vfx_ice_shatter(impact_world)
		for e in enemy_lane.enemies:
			if not is_instance_valid(e) or e.hp <= 0.0:
				continue
			if e.global_position.distance_squared_to(impact_world) > radius_sq:
				continue
			var d: float = primary_dmg if e == target else _damage_for_hit(e, GameConfig.blue_dmg_mult)
			e.take_damage(d)
			if is_instance_valid(e):
				e.apply_status("slow", GameConfig.blue_slow_duration_sec, 1)
	)

# ─── Archer (YELLOW) ─ bowstring recoil + real arrow projectile that flies
# hero → target with fletching/head and a streak trail; execute bonus < 30% HP.
func _fire_yellow(target: Enemy) -> void:
	if not is_instance_valid(target):
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var start_pos: Vector2 = position
	var rec := create_tween()
	rec.tween_property(self, "position", start_pos - dir * 5.0, 0.05)
	rec.tween_property(self, "position", start_pos, 0.12)
	var is_execute: bool = target.max_hp > 0.0 \
		and (target.hp / target.max_hp) < GameConfig.yellow_execute_threshold
	var dmg: float = _damage_for_hit(target, GameConfig.yellow_dmg_mult)
	if is_execute:
		dmg *= (1.0 + GameConfig.yellow_execute_bonus)
	_vfx_arrow(target.global_position, is_execute)
	target.take_damage(dmg)

# ─── Druid (GREEN) ─ lobs a leaf-wrapped seed pod that arcs to the target and
# bursts into a green poison puff. Damage + chain-heal land on impact.
func _fire_green(target: Enemy) -> void:
	if not is_instance_valid(target):
		return
	var impact_world: Vector2 = target.global_position
	var target_ref: Enemy = target
	_vfx_seed_pod(impact_world, func():
		_vfx_poison_puff(impact_world)
		if is_instance_valid(target_ref) and target_ref.hp > 0.0:
			target_ref.take_damage(_damage_for_hit(target_ref, GameConfig.green_dmg_mult))
		_green_chain_heal()
	)

func _green_chain_heal() -> void:
	var p: Node = get_parent()
	if not (p is HeroRow):
		return
	var row: HeroRow = p as HeroRow
	var amount: int = GameConfig.green_chain_heal_amount
	var max_targets: int = GameConfig.green_chain_heal_targets
	var cap: int = GameConfig.green_heal_per_hero_cap_per_sec
	var candidates: Array = []
	for h in row.heroes:
		if h == null or not is_instance_valid(h) or h == self:
			continue
		if h.hp >= h.max_hp:
			continue
		candidates.append({"h": h, "d": h.global_position.distance_squared_to(global_position)})
	candidates.sort_custom(func(a, b): return a.d < b.d)
	var healed: int = 0
	for entry in candidates:
		if healed >= max_targets:
			break
		var ally: Hero = entry.h as Hero
		var ticked: int = ally.try_heal(amount, cap)
		if ticked > 0:
			_vfx_heal_motes(ally.global_position)
		healed += 1

# ─── Wizard (PURPLE) ─ fires a glowing purple arcane orb straight at the
# target. Every Nth shot is a "burst" orb (bigger, brighter) that triggers an
# AoE ring on impact. v1 §8.6.
func _fire_purple(target: Enemy) -> void:
	if not is_instance_valid(target):
		return
	_wizard_burst_count += 1
	var is_burst: bool = _wizard_burst_count >= GameConfig.purple_burst_every_n_hits
	if is_burst:
		_wizard_burst_count = 0
	var impact_world: Vector2 = target.global_position
	var target_ref: Enemy = target
	_vfx_arcane_orb(impact_world, is_burst, func():
		if is_instance_valid(target_ref) and target_ref.hp > 0.0:
			target_ref.take_damage(_damage_for_hit(target_ref, GameConfig.purple_dmg_mult))
		_vfx_impact_sparks(impact_world,
			Color(0.95, 0.70, 1.0, 1.0),
			10 if is_burst else 6,
			40.0 if is_burst else 28.0)
		if is_burst:
			_purple_arcane_burst_at(impact_world, target_ref)
	)

func _purple_arcane_burst(primary: Enemy) -> void:
	_purple_arcane_burst_at(primary.global_position, primary)

func _purple_arcane_burst_at(center: Vector2, primary: Enemy) -> void:
	_vfx_aoe_ring(center, GameConfig.purple_aoe_radius_px, Color(0.85, 0.5, 1.0, 0.55))
	var radius_sq: float = GameConfig.purple_aoe_radius_px * GameConfig.purple_aoe_radius_px
	for e in enemy_lane.enemies:
		if e == primary or not is_instance_valid(e) or e.hp <= 0.0:
			continue
		if e.global_position.distance_squared_to(center) > radius_sq:
			continue
		e.take_damage(_damage_for_hit(e, GameConfig.purple_dmg_mult))

# ─── VFX helpers (ported from v1 Hero.gd) ──────────────────────────────────

func _vfx_lunge(dir: Vector2) -> void:
	var start := position
	var tw := create_tween()
	tw.tween_property(self, "position", start + dir * 8.0, 0.06)
	tw.tween_property(self, "position", start, 0.12)

# Glowing crescent slash — outer warm + inner white-hot core; sweeps through an arc.
func _vfx_slash(dir: Vector2, reach: float, col: Color) -> void:
	var holder := Node2D.new()
	add_child(holder)
	holder.rotation = dir.angle() - deg_to_rad(35.0)
	# Outline ring under the crescent for contrast against grass/sky backdrops.
	var outline := _make_crescent(reach, 18.0 * PROJECTILE_SCALE + 4.0,
		deg_to_rad(72.0), Color(0.05, 0.04, 0.08, 0.55))
	holder.add_child(outline)
	var outer := _make_crescent(reach, 18.0 * PROJECTILE_SCALE, deg_to_rad(70.0),
		Color(col.r, col.g, col.b, col.a * 0.92))
	holder.add_child(outer)
	var inner := _make_crescent(reach * 0.92, 8.0 * PROJECTILE_SCALE,
		deg_to_rad(55.0), Color(1.0, 0.97, 0.82, 0.98))
	holder.add_child(inner)
	var tw := holder.create_tween()
	tw.tween_property(holder, "rotation", dir.angle() + deg_to_rad(35.0), 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		if is_instance_valid(holder): holder.queue_free())

func _make_crescent(radius: float, thickness: float, half_arc: float, col: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = col
	var pts := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var t: float = -half_arc + 2.0 * half_arc * float(i) / float(steps)
		pts.append(Vector2(cos(t), sin(t)) * (radius + thickness * 0.5))
	for i in steps + 1:
		var t: float = half_arc - 2.0 * half_arc * float(i) / float(steps)
		pts.append(Vector2(cos(t), sin(t)) * (radius - thickness * 0.5))
	poly.polygon = pts
	return poly

# Short-lived pie wedge in front of the hero — used for FK heat haze, Druid pulse, Wizard smash, cleave secondaries.
func _vfx_wedge(dir: Vector2, reach: float, half_deg: float, col: Color, fade_dur: float) -> void:
	var wedge := Polygon2D.new()
	wedge.color = col
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	var steps := 8
	var base_angle: float = dir.angle()
	for i in steps + 1:
		var t: float = -half_deg + (2.0 * half_deg) * float(i) / float(steps)
		var a: float = base_angle + deg_to_rad(t)
		pts.append(Vector2(cos(a), sin(a)) * reach)
	wedge.polygon = pts
	add_child(wedge)
	var tw := wedge.create_tween()
	tw.tween_property(wedge, "modulate:a", 0.0, fade_dur)
	tw.tween_callback(func():
		if is_instance_valid(wedge): wedge.queue_free())

# Radial spark burst at world position — parented on enemy_lane so it outlives target.
func _vfx_impact_sparks(world_pos: Vector2, col: Color, count: int, reach: float) -> void:
	if enemy_lane == null:
		return
	var local := enemy_lane.to_local(world_pos)
	for i in count:
		var spark := Polygon2D.new()
		spark.color = col
		var sz: float = randf_range(2.5, 4.5)
		spark.polygon = PackedVector2Array([
			Vector2(-sz * 0.4, -sz), Vector2(sz * 0.4, -sz),
			Vector2(sz * 0.4, sz), Vector2(-sz * 0.4, sz),
		])
		spark.z_index = 65
		enemy_lane.add_child(spark)
		spark.position = local
		var ang: float = TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var dist: float = randf_range(reach * 0.5, reach)
		spark.rotation = ang
		var dest: Vector2 = local + Vector2(cos(ang), sin(ang)) * dist
		var dur: float = randf_range(0.18, 0.28)
		var tw := spark.create_tween()
		tw.tween_property(spark, "position", dest, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(spark, "modulate:a", 0.0, dur)
		tw.parallel().tween_property(spark, "scale", Vector2(0.2, 0.2), dur)
		tw.tween_callback(func():
			if is_instance_valid(spark): spark.queue_free())

# Ice crystal lobbed from hero to impact world point; on landing, calls `on_land`.
func _vfx_ice_lob(impact_world: Vector2, on_land: Callable) -> void:
	if enemy_lane == null:
		on_land.call()
		return
	var shard: Node2D = _make_ice_crystal(20.0)
	shard.z_index = 70
	enemy_lane.add_child(shard)
	var p0_local: Vector2 = enemy_lane.to_local(global_position)
	var p2_local: Vector2 = enemy_lane.to_local(impact_world)
	shard.position = p0_local
	var mid: Vector2 = (p0_local + p2_local) * 0.5
	mid.y -= 50.0
	shard.scale = Vector2(0.5, 0.5)
	var pop := shard.create_tween()
	pop.tween_property(shard, "scale", Vector2(1.0, 1.0), 0.06).set_trans(Tween.TRANS_BACK)
	var last_trail := [0.0]
	var fly := create_tween()
	fly.tween_method(func(t: float):
		if not is_instance_valid(shard): return
		var u: float = 1.0 - t
		shard.position = u * u * p0_local + 2.0 * u * t * mid + t * t * p2_local
		shard.rotation = (p2_local - p0_local).angle() + t * TAU * 1.5
		if t - last_trail[0] >= 0.05:
			last_trail[0] = t
			_spawn_ice_trail_dot(enemy_lane.to_global(shard.position))
	, 0.0, 1.0, 0.45)
	fly.tween_callback(func():
		if is_instance_valid(shard): shard.queue_free()
		on_land.call())

func _make_ice_crystal(size: float) -> Node2D:
	var holder := Node2D.new()
	var halo := Polygon2D.new()
	halo.color = Color(0.55, 0.85, 1.0, 0.28)
	halo.polygon = _diamond_points(size * 1.7, size * 1.3)
	holder.add_child(halo)
	var body := Polygon2D.new()
	body.color = Color(0.40, 0.78, 1.0, 0.95)
	body.polygon = _diamond_points(size, size * 0.75)
	holder.add_child(body)
	var core := Polygon2D.new()
	core.color = Color(0.92, 0.98, 1.0, 0.95)
	core.polygon = _diamond_points(size * 0.5, size * 0.36)
	holder.add_child(core)
	return holder

func _diamond_points(rx: float, ry: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -ry), Vector2(rx, 0), Vector2(0, ry), Vector2(-rx, 0),
	])

func _spawn_ice_trail_dot(world_pos: Vector2) -> void:
	if enemy_lane == null:
		return
	var dot := Polygon2D.new()
	dot.color = Color(0.75, 0.95, 1.0, 0.85)
	var s: float = randf_range(2.0, 3.5)
	dot.polygon = _diamond_points(s, s)
	dot.z_index = 55
	enemy_lane.add_child(dot)
	dot.position = enemy_lane.to_local(world_pos)
	dot.rotation = randf() * TAU
	var tw := dot.create_tween()
	tw.tween_property(dot, "scale", Vector2(0.1, 0.1), 0.28)
	tw.parallel().tween_property(dot, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func():
		if is_instance_valid(dot): dot.queue_free())

func _vfx_ice_shatter(world_pos: Vector2) -> void:
	if enemy_lane == null:
		return
	var local := enemy_lane.to_local(world_pos)
	for i in 6:
		var shard := Polygon2D.new()
		shard.color = Color(0.70, 0.92, 1.0, 0.95)
		var sz: float = randf_range(4.0, 7.0)
		shard.polygon = _diamond_points(sz * 0.5, sz)
		shard.z_index = 62
		enemy_lane.add_child(shard)
		shard.position = local
		var ang: float = TAU * float(i) / 6.0 + randf_range(-0.2, 0.2)
		var dest: Vector2 = local + Vector2(cos(ang), sin(ang)) * randf_range(30.0, 50.0)
		shard.rotation = ang + PI * 0.5
		var dur: float = randf_range(0.22, 0.32)
		var tw := shard.create_tween()
		tw.tween_property(shard, "position", dest, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(shard, "scale", Vector2(0.2, 0.2), dur)
		tw.parallel().tween_property(shard, "modulate:a", 0.0, dur)
		tw.tween_callback(func():
			if is_instance_valid(shard): shard.queue_free())

# Expanding ring at world point — used for ice splash + arcane burst.
func _vfx_aoe_ring(world_pos: Vector2, radius_px: float, col: Color) -> void:
	if enemy_lane == null:
		return
	var ring := Polygon2D.new()
	ring.color = col
	var pts := PackedVector2Array()
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * radius_px)
	ring.polygon = pts
	ring.z_index = 50
	enemy_lane.add_child(ring)
	ring.position = enemy_lane.to_local(world_pos)
	ring.scale = Vector2(0.15, 0.15)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func():
		if is_instance_valid(ring): ring.queue_free())

# Real arrow projectile with shaft + head + fletching, flies hero → target world position.
func _vfx_arrow(impact_world: Vector2, is_execute: bool) -> void:
	if enemy_lane == null:
		return
	var arrow_color := Color(1.0, 0.95, 0.55, 1.0) if is_execute else Color(1.0, 0.85, 0.20, 1.0)
	var base_len: float = (32.0 if is_execute else 26.0) * PROJECTILE_SCALE
	var arrow := _make_arrow(base_len, arrow_color)
	arrow.z_index = 75
	enemy_lane.add_child(arrow)
	var p0: Vector2 = enemy_lane.to_local(global_position)
	var p1: Vector2 = enemy_lane.to_local(impact_world)
	var dir: Vector2 = (p1 - p0).normalized()
	arrow.position = p0
	arrow.rotation = dir.angle()
	var flight_dur: float = clamp((p1 - p0).length() / 600.0, 0.18, 0.40)
	var last_trail := [0.0]
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(arrow): return
		arrow.position = p0.lerp(p1, t)
		if t - last_trail[0] >= 0.12:
			last_trail[0] = t
			_spawn_arrow_streak(enemy_lane.to_global(arrow.position), dir, arrow_color)
	, 0.0, 1.0, flight_dur)
	tw.tween_callback(func():
		if is_instance_valid(arrow):
			var stick := arrow.create_tween()
			stick.tween_interval(0.16 if is_execute else 0.10)
			stick.tween_property(arrow, "modulate:a", 0.0, 0.10)
			stick.tween_callback(func():
				if is_instance_valid(arrow): arrow.queue_free())
		_vfx_impact_sparks(impact_world, arrow_color,
			10 if is_execute else 6, 44.0 if is_execute else 32.0))

func _make_arrow(length: float, col: Color) -> Node2D:
	# Sized for legibility on a 720-wide mobile viewport. Layers (back→front):
	#   1. Dark outline silhouette for contrast against any background.
	#   2. Soft halo glow in the arrow color, larger than the head.
	#   3. Shaft (wood).
	#   4. Head (bright steel).
	#   5. Fletching (color-tinted feathers).
	# All inner dimensions track `length` so the existing PROJECTILE_SCALE knob
	# scales the whole arrow proportionally.
	var holder := Node2D.new()
	var half_len: float = length * 0.5
	# Proportional to length so the silhouette stays arrow-shaped at any
	# PROJECTILE_SCALE. Ratios match v1 (shaft 12% tall, head 27% long × 31%
	# tall, fletching 23% back × 31% tall).
	var shaft_h: float = length * 0.060
	var head_back: float = length * 0.270
	var head_h: float = length * 0.155
	var fletch_back: float = length * 0.230
	var fletch_h: float = length * 0.155

	# Dark silhouette behind the full arrow shape — traces the actual outline
	# (rect shaft → triangle head) so the silhouette itself reads as an arrow.
	var outline := Polygon2D.new()
	outline.color = Color(0.05, 0.04, 0.08, 0.85)
	var ol: float = 1.6
	var head_join_x: float = half_len - head_back
	outline.polygon = PackedVector2Array([
		Vector2(-half_len - ol,    -shaft_h - ol),        # back-top corner of shaft
		Vector2(head_join_x - ol,  -shaft_h - ol),        # shaft-to-head top junction
		Vector2(head_join_x - ol,  -head_h - ol),         # top corner of head base
		Vector2(half_len + ol,      0),                   # head tip
		Vector2(head_join_x - ol,   head_h + ol),         # bottom corner of head base
		Vector2(head_join_x - ol,   shaft_h + ol),        # shaft-to-head bottom junction
		Vector2(-half_len - ol,     shaft_h + ol),        # back-bottom corner of shaft
	])
	holder.add_child(outline)

	# Glow halo — wider than the head, semi-transparent, in arrow color.
	var glow := Polygon2D.new()
	glow.color = Color(col.r, col.g, col.b, 0.55)
	glow.polygon = PackedVector2Array([
		Vector2(half_len + 6.0, 0),
		Vector2(half_len - head_back - 4.0, -head_h - 4.0),
		Vector2(half_len - head_back - 4.0,  head_h + 4.0),
	])
	holder.add_child(glow)

	# Shaft.
	var shaft := Polygon2D.new()
	shaft.color = Color(0.32, 0.22, 0.13, 1.0)
	shaft.polygon = PackedVector2Array([
		Vector2(-half_len, -shaft_h), Vector2(half_len - head_back, -shaft_h),
		Vector2(half_len - head_back,  shaft_h), Vector2(-half_len,  shaft_h),
	])
	holder.add_child(shaft)

	# Bright steel head.
	var head := Polygon2D.new()
	head.color = Color(1.0, 0.98, 0.86, 1.0)
	head.polygon = PackedVector2Array([
		Vector2(half_len, 0),
		Vector2(half_len - head_back, -head_h),
		Vector2(half_len - head_back,  head_h),
	])
	holder.add_child(head)

	# Fletching (one each side, tinted in arrow color).
	for sign_y in [-1.0, 1.0]:
		var fl := Polygon2D.new()
		fl.color = col
		fl.polygon = PackedVector2Array([
			Vector2(-half_len, 0),
			Vector2(-half_len + fletch_back, 0),
			Vector2(-half_len + 3.0, fletch_h * sign_y),
		])
		holder.add_child(fl)
	return holder

func _spawn_arrow_streak(world_pos: Vector2, dir: Vector2, col: Color) -> void:
	if enemy_lane == null:
		return
	# Tapered trail: thick + bright at the head, fading to a point behind it.
	# 4-vertex quad with two different heights so the eye reads a streak rather
	# than a thin rectangle.
	var len_px: float = 22.0 * PROJECTILE_SCALE
	var h_front: float = 4.2 * PROJECTILE_SCALE
	var h_back: float = 0.6 * PROJECTILE_SCALE
	var streak := Polygon2D.new()
	streak.color = Color(col.r, col.g, col.b, 0.85)
	streak.polygon = PackedVector2Array([
		Vector2(-len_px, -h_back), Vector2(0, -h_front),
		Vector2(0,  h_front), Vector2(-len_px,  h_back),
	])
	streak.rotation = dir.angle()
	streak.z_index = 60
	enemy_lane.add_child(streak)
	streak.position = enemy_lane.to_local(world_pos)
	var tw := streak.create_tween()
	tw.tween_property(streak, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(streak, "scale", Vector2(0.35, 0.35), 0.22)
	tw.tween_callback(func():
		if is_instance_valid(streak): streak.queue_free())

# ─── Druid seed-pod ─ leaf-wrapped green pod lobbed hero → impact world point.
# Mirrors the ice-lob bezier arc, but with leaf-shaped body + drifting leaf
# trail. Calls `on_land` when the pod reaches the impact point.
func _vfx_seed_pod(impact_world: Vector2, on_land: Callable) -> void:
	if enemy_lane == null:
		on_land.call()
		return
	var pod: Node2D = _make_seed_pod(11.0 * PROJECTILE_SCALE)
	pod.z_index = 70
	enemy_lane.add_child(pod)
	var p0_local: Vector2 = enemy_lane.to_local(global_position)
	var p2_local: Vector2 = enemy_lane.to_local(impact_world)
	pod.position = p0_local
	var mid: Vector2 = (p0_local + p2_local) * 0.5
	mid.y -= 55.0
	pod.scale = Vector2(0.5, 0.5)
	var pop := pod.create_tween()
	pop.tween_property(pod, "scale", Vector2(1.0, 1.0), 0.06).set_trans(Tween.TRANS_BACK)
	var last_trail := [0.0]
	var fly := create_tween()
	fly.tween_method(func(t: float):
		if not is_instance_valid(pod): return
		var u: float = 1.0 - t
		pod.position = u * u * p0_local + 2.0 * u * t * mid + t * t * p2_local
		pod.rotation = (p2_local - p0_local).angle() + t * TAU * 0.8
		if t - last_trail[0] >= 0.07:
			last_trail[0] = t
			_spawn_leaf_trail(enemy_lane.to_global(pod.position))
	, 0.0, 1.0, 0.38)
	fly.tween_callback(func():
		if is_instance_valid(pod): pod.queue_free()
		on_land.call())

func _make_seed_pod(size: float) -> Node2D:
	var holder := Node2D.new()
	# Soft outer halo so the pod reads against any backdrop.
	var halo := Polygon2D.new()
	halo.color = Color(0.55, 1.0, 0.55, 0.32)
	halo.polygon = _oval_points(size * 1.7, size * 1.2, 16)
	holder.add_child(halo)
	# Body — deep green pod.
	var body := Polygon2D.new()
	body.color = Color(0.30, 0.70, 0.32, 0.95)
	body.polygon = _oval_points(size, size * 0.7, 14)
	holder.add_child(body)
	# Two leaf wings flanking the pod.
	var leaf_l := Polygon2D.new()
	leaf_l.color = Color(0.55, 0.92, 0.45, 0.95)
	leaf_l.polygon = PackedVector2Array([
		Vector2(-size * 0.2,  0.0),
		Vector2(-size * 1.2, -size * 0.6),
		Vector2(-size * 1.4,  0.0),
		Vector2(-size * 1.2,  size * 0.4),
	])
	holder.add_child(leaf_l)
	var leaf_r := Polygon2D.new()
	leaf_r.color = Color(0.55, 0.92, 0.45, 0.95)
	leaf_r.polygon = PackedVector2Array([
		Vector2(size * 0.2,  0.0),
		Vector2(size * 1.2, -size * 0.4),
		Vector2(size * 1.4,  0.0),
		Vector2(size * 1.2,  size * 0.6),
	])
	holder.add_child(leaf_r)
	# Bright core highlight.
	var core := Polygon2D.new()
	core.color = Color(0.85, 1.0, 0.70, 0.95)
	core.polygon = _oval_points(size * 0.42, size * 0.30, 10)
	holder.add_child(core)
	return holder

func _oval_points(rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a: float = TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _spawn_leaf_trail(world_pos: Vector2) -> void:
	if enemy_lane == null:
		return
	var leaf := Polygon2D.new()
	leaf.color = Color(0.55, 0.92, 0.45, 0.85)
	var s: float = randf_range(2.4, 4.0)
	leaf.polygon = PackedVector2Array([
		Vector2(0, -s), Vector2(s * 0.6, 0), Vector2(0, s), Vector2(-s * 0.6, 0),
	])
	leaf.z_index = 55
	enemy_lane.add_child(leaf)
	leaf.position = enemy_lane.to_local(world_pos)
	leaf.rotation = randf() * TAU
	var drift: Vector2 = Vector2(randf_range(-6.0, 6.0), randf_range(2.0, 10.0))
	var tw := leaf.create_tween()
	tw.tween_property(leaf, "position", leaf.position + drift, 0.30)
	tw.parallel().tween_property(leaf, "rotation", leaf.rotation + randf_range(-1.2, 1.2), 0.30)
	tw.parallel().tween_property(leaf, "modulate:a", 0.0, 0.30)
	tw.parallel().tween_property(leaf, "scale", Vector2(0.3, 0.3), 0.30)
	tw.tween_callback(func():
		if is_instance_valid(leaf): leaf.queue_free())

# Small green poison cloud at the seed-pod impact point — drifts upward and fades.
func _vfx_poison_puff(world_pos: Vector2) -> void:
	if enemy_lane == null:
		return
	var local := enemy_lane.to_local(world_pos)
	for i in 5:
		var puff := Polygon2D.new()
		puff.color = Color(0.50, 0.95, 0.45, 0.55)
		var s: float = randf_range(6.0, 10.0)
		puff.polygon = _oval_points(s, s * 0.85, 12)
		puff.z_index = 58
		enemy_lane.add_child(puff)
		puff.position = local + Vector2(randf_range(-12.0, 12.0), randf_range(-6.0, 6.0))
		puff.scale = Vector2(0.4, 0.4)
		var dur: float = randf_range(0.40, 0.60)
		var dest: Vector2 = puff.position + Vector2(randf_range(-8.0, 8.0), -randf_range(14.0, 26.0))
		var tw := puff.create_tween()
		tw.tween_property(puff, "scale", Vector2(1.1, 1.1), dur * 0.6).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(puff, "position", dest, dur)
		tw.parallel().tween_property(puff, "modulate:a", 0.0, dur)
		tw.tween_callback(func():
			if is_instance_valid(puff): puff.queue_free())

# Green sparkle motes rising off a healed ally hero — quick "you got healed" tell.
func _vfx_heal_motes(world_pos: Vector2) -> void:
	if enemy_lane == null:
		return
	var parent: Node = enemy_lane.get_parent()
	if parent == null:
		return
	for i in 5:
		var mote := Polygon2D.new()
		mote.color = Color(0.55, 1.0, 0.60, 0.95)
		var s: float = randf_range(2.0, 3.5)
		mote.polygon = PackedVector2Array([
			Vector2(0, -s * 1.4),
			Vector2(s * 0.6, 0),
			Vector2(0, s * 1.4),
			Vector2(-s * 0.6, 0),
		])
		mote.z_index = 80
		parent.add_child(mote)
		mote.position = parent.to_local(world_pos) + Vector2(randf_range(-14.0, 14.0), randf_range(-4.0, 4.0))
		mote.rotation = randf() * TAU
		var dest: Vector2 = mote.position + Vector2(randf_range(-6.0, 6.0), -randf_range(24.0, 38.0))
		var dur: float = randf_range(0.45, 0.65)
		var tw := mote.create_tween()
		tw.tween_property(mote, "position", dest, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mote, "modulate:a", 0.0, dur)
		tw.parallel().tween_property(mote, "scale", Vector2(0.4, 0.4), dur)
		tw.parallel().tween_property(mote, "rotation", mote.rotation + randf_range(-0.6, 0.6), dur)
		tw.tween_callback(func():
			if is_instance_valid(mote): mote.queue_free())

# ─── Wizard arcane orb ─ purple orb fired straight at the target with a star
# trail. Burst variant is bigger and brighter (every Nth shot). Calls `on_land`
# at the impact point.
func _vfx_arcane_orb(impact_world: Vector2, is_burst: bool, on_land: Callable) -> void:
	if enemy_lane == null:
		on_land.call()
		return
	var size: float = (10.0 if is_burst else 7.0) * PROJECTILE_SCALE
	var orb: Node2D = _make_arcane_orb(size, is_burst)
	orb.z_index = 75
	enemy_lane.add_child(orb)
	var p0: Vector2 = enemy_lane.to_local(global_position)
	var p1: Vector2 = enemy_lane.to_local(impact_world)
	var dir: Vector2 = (p1 - p0).normalized()
	orb.position = p0
	orb.rotation = dir.angle()
	var flight_dur: float = clamp((p1 - p0).length() / 520.0, 0.22, 0.46)
	var last_trail := [0.0]
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(orb): return
		orb.position = p0.lerp(p1, t)
		if t - last_trail[0] >= 0.05:
			last_trail[0] = t
			_spawn_orb_trail(enemy_lane.to_global(orb.position), is_burst)
	, 0.0, 1.0, flight_dur)
	tw.tween_callback(func():
		if is_instance_valid(orb): orb.queue_free()
		on_land.call())

func _make_arcane_orb(size: float, is_burst: bool) -> Node2D:
	var holder := Node2D.new()
	# Outer glow halo.
	var halo := Polygon2D.new()
	halo.color = Color(0.85, 0.55, 1.0, 0.32 if is_burst else 0.26)
	halo.polygon = _oval_points(size * 2.0, size * 2.0, 18)
	holder.add_child(halo)
	# Mid-ring (saturated purple).
	var ring := Polygon2D.new()
	ring.color = Color(0.70, 0.40, 0.95, 0.85)
	ring.polygon = _oval_points(size * 1.25, size * 1.25, 16)
	holder.add_child(ring)
	# Body (bright violet).
	var body := Polygon2D.new()
	body.color = Color(0.92, 0.70, 1.0, 0.95)
	body.polygon = _oval_points(size, size, 14)
	holder.add_child(body)
	# White-hot core.
	var core := Polygon2D.new()
	core.color = Color(1.0, 0.96, 1.0, 1.0)
	core.polygon = _oval_points(size * 0.42, size * 0.42, 10)
	holder.add_child(core)
	# Burst orbs get a 4-point star overlay so the "this one is special" reads
	# at speed.
	if is_burst:
		var star := Polygon2D.new()
		star.color = Color(1.0, 0.95, 1.0, 0.9)
		var r: float = size * 1.6
		var inner: float = size * 0.55
		star.polygon = PackedVector2Array([
			Vector2(0, -r), Vector2(inner * 0.7, -inner * 0.7),
			Vector2(r, 0), Vector2(inner * 0.7, inner * 0.7),
			Vector2(0, r), Vector2(-inner * 0.7, inner * 0.7),
			Vector2(-r, 0), Vector2(-inner * 0.7, -inner * 0.7),
		])
		holder.add_child(star)
	return holder

func _spawn_orb_trail(world_pos: Vector2, is_burst: bool) -> void:
	if enemy_lane == null:
		return
	var trail := Polygon2D.new()
	trail.color = Color(0.90, 0.65, 1.0, 0.80 if is_burst else 0.65)
	var s: float = randf_range(2.5, 4.0) * (1.25 if is_burst else 1.0)
	# 4-point star sparkle.
	trail.polygon = PackedVector2Array([
		Vector2(0, -s * 1.5),
		Vector2(s * 0.45, -s * 0.45),
		Vector2(s * 1.5, 0),
		Vector2(s * 0.45, s * 0.45),
		Vector2(0, s * 1.5),
		Vector2(-s * 0.45, s * 0.45),
		Vector2(-s * 1.5, 0),
		Vector2(-s * 0.45, -s * 0.45),
	])
	trail.z_index = 60
	enemy_lane.add_child(trail)
	trail.position = enemy_lane.to_local(world_pos)
	trail.rotation = randf() * TAU
	var dur: float = 0.30
	var tw := trail.create_tween()
	tw.tween_property(trail, "modulate:a", 0.0, dur)
	tw.parallel().tween_property(trail, "scale", Vector2(0.2, 0.2), dur)
	tw.parallel().tween_property(trail, "rotation", trail.rotation + randf_range(-0.8, 0.8), dur)
	tw.tween_callback(func():
		if is_instance_valid(trail): trail.queue_free())

# ─── Draw ──────────────────────────────────────────────────────────
func _draw() -> void:
	var tex: Texture2D = _get_texture(hero_class)
	if tex != null:
		var sprite_rect := Rect2(-SPRITE_DRAW_SIZE * 0.5, -SPRITE_DRAW_SIZE * 0.5, SPRITE_DRAW_SIZE, SPRITE_DRAW_SIZE)
		draw_texture_rect(tex, sprite_rect, false, Color.WHITE)
	else:
		var fill: Color = Bubble.COLORS.get(color, Color.GRAY)
		draw_rect(Rect2(-SIZE, -SIZE, SIZE * 2, SIZE * 2), fill)
		draw_rect(Rect2(-SIZE, -SIZE, SIZE * 2, SIZE * 2), Color(0, 0, 0, 0.85), false, 2.0)

	# Tier badge (top-right of portrait) — bronze / silver / gold disc with the
	# tier number stacked inside. Far more legible than 3px pips against busy art.
	_draw_tier_badge()

## Bronze / silver / gold badge in the top-LEFT of the portrait (lock-pip lives
## in the top-right). 14px disc with a dark backing and the tier number inside.
func _draw_tier_badge() -> void:
	var anchor: Vector2 = Vector2(-SIZE + 8, -SIZE + 8)
	var col: Color = _tier_color(tier)
	# Drop shadow for legibility against any portrait color.
	draw_circle(anchor + Vector2(0, 1), 13.0, Color(0, 0, 0, 0.55))
	# Outer ring (dark) + colored fill.
	draw_circle(anchor, 13.0, Color(0.10, 0.08, 0.14, 0.95))
	draw_circle(anchor, 10.5, col)
	# Inner highlight to give the disc dimension.
	draw_arc(anchor, 10.5, deg_to_rad(200), deg_to_rad(340), 18,
		Color(1, 1, 1, 0.55), 1.6)
	# Tier number.
	var font: Font = ThemeDB.fallback_font
	var fs: int = 14
	var s := str(tier)
	var ts: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, anchor + Vector2(-ts.x * 0.5, ts.y * 0.32), s,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.10, 0.08, 0.14, 1.0))

func _tier_color(t: int) -> Color:
	match t:
		1: return Color(0.85, 0.55, 0.30)   # bronze
		2: return Color(0.88, 0.88, 0.92)   # silver
		3: return Color(1.00, 0.82, 0.25)   # gold
	return Color(0.85, 0.55, 0.30)

