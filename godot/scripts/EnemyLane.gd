extends Node2D
class_name EnemyLane
## Owns enemies for the current wave. Schedules spawns from SPAWN_TOTALS,
## paces them across wave_duration_sec, biases spawn columns toward closed.

signal enemy_reached_base(damage: int)
signal wave_cleared

# Lead before the first spawn of a wave — small so action starts right after
# the countdown instead of mid-wave.
const SPAWN_LEAD_SEC: float = 0.3

var gate_ref: Gate
var hero_row_ref: HeroRow
var lane_top_y: float = 0.0
var lane_bottom_y: float = 0.0
var post_breach_target_y: float = 0.0
var column_x_func: Callable

var enemies: Array[Enemy] = []
var spawn_queue: Array = []     # [{t: float, color: String}, ...]
var spawn_index: int = 0
var wave_clock: float = 0.0
var wave_active: bool = false

# Boss wave (boss-design.md §2).
var boss: Boss = null
var is_boss_wave: bool = false
var next_minion_t: float = -1.0   # absolute wave_clock for next minion spawn (-1 = disabled)

# Mini-boss wave (combat-design.md §3.6) — wave 5 of every stage.
var miniboss: Enemy = null
var is_miniboss_wave: bool = false

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func configure(g: Gate, lane_top: float, lane_bot: float, post_target: float, col_x: Callable) -> void:
	gate_ref = g
	lane_top_y = lane_top
	lane_bottom_y = lane_bot
	post_breach_target_y = post_target
	column_x_func = col_x

func begin_wave(idx: int) -> void:
	_clear_enemies()
	# Precedence: wave 5 = miniboss (even on Stage 1 where it's also the last wave),
	# otherwise last wave = Corrupter boss.
	is_miniboss_wave = (idx == GameConfig.miniboss_wave_idx)
	is_boss_wave = (not is_miniboss_wave) and (idx == GameConfig.num_waves - 1)
	if is_miniboss_wave:
		spawn_queue.clear()
		_spawn_miniboss()
		next_minion_t = -1.0
	elif is_boss_wave:
		spawn_queue.clear()
		_spawn_boss()
		next_minion_t = GameConfig.corrupter_minion_first_spawn_delay_sec
	else:
		spawn_queue = _build_spawn_queue(idx)
		next_minion_t = -1.0
	wave_clock = 0.0
	spawn_index = 0
	wave_active = true

func _build_spawn_queue(idx: int) -> Array:
	var totals: Dictionary = GameConfig.spawn_totals_for_wave(idx)
	var mix: Dictionary = GameConfig.variant_mix_for_wave(idx)
	var cluster_size: int = GameConfig.cluster_size_for_wave(idx)
	var forced_brutes: int = GameConfig.forced_brutes_for_wave(idx)
	var colors: Array = []
	for c in totals.keys():
		for i in range(totals[c]):
			colors.append(c)
	colors.shuffle()
	var duration: float = GameConfig.wave_duration_for_wave(idx)
	var n: int = colors.size()
	# Pre-pick variants per slot. Forced BRUTEs overwrite random slots so they
	# can land in any cluster — guarantees Test C's "2 BRUTEs somewhere" rule.
	var variants: Array = []
	for i in range(n):
		variants.append(_pick_variant(mix))
	if forced_brutes > 0:
		var slots: Array = []
		for i in range(n):
			slots.append(i)
		slots.shuffle()
		for i in range(min(forced_brutes, n)):
			variants[slots[i]] = "BRUTE"
	var q: Array = []
	if cluster_size > 0:
		# Group spawns into clusters at the same timestamp, spread across N
		# columns picked per-cluster. Column -1 = let _spawn pick at runtime.
		var num_clusters: int = int(ceil(float(n) / float(cluster_size)))
		var cols_per_cluster: int = GameConfig.cluster_columns_for_wave(idx)
		for ci in range(num_clusters):
			# Start the first cluster almost immediately (0.3s lead), then space
			# the rest evenly across the wave window — no dead air after countdown.
			var t: float = SPAWN_LEAD_SEC + (duration - SPAWN_LEAD_SEC) * float(ci) / float(max(1, num_clusters))
			var cluster_cols: Array = _pick_cluster_columns(cols_per_cluster)
			var start: int = ci * cluster_size
			var end: int = min(start + cluster_size, n)
			for i in range(start, end):
				var col: int = -1
				if not cluster_cols.is_empty():
					col = cluster_cols[(i - start) % cluster_cols.size()]
				q.append({"t": t, "color": colors[i], "variant": variants[i], "column": col})
	else:
		for i in range(n):
			var t: float = SPAWN_LEAD_SEC + (duration - SPAWN_LEAD_SEC) * float(i) / float(max(1, n))
			q.append({"t": t, "color": colors[i], "variant": variants[i], "column": -1})
	return q

func _pick_cluster_columns(count: int) -> Array:
	if count <= 0:
		return []
	var pool: Array = []
	for c in range(GameConfig.gate_columns):
		pool.append(c)
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))

func _pick_variant(mix: Dictionary) -> String:
	var r: float = _rng.randf()
	var acc: float = 0.0
	for v in mix.keys():
		acc += float(mix[v])
		if r <= acc:
			return v
	return "WALKER"

# ─── Per-frame ─────────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	if not wave_active:
		return
	wave_clock += dt
	if is_miniboss_wave:
		# Solo miniboss — wave ends when it dies (or reaches the cannon).
		if miniboss == null or not is_instance_valid(miniboss) or miniboss.state == Enemy.State.DEAD:
			wave_active = false
			emit_signal("wave_cleared")
		return
	if is_boss_wave:
		# Drip-feed minions every corrupter_minion_spawn_interval_sec, starting
		# at next_minion_t. Stop when boss dies (wave end handled below).
		while next_minion_t >= 0.0 and wave_clock >= next_minion_t:
			_spawn("RED", "WALKER")
			next_minion_t += GameConfig.corrupter_minion_spawn_interval_sec
		# Wave end: boss is dead.
		if boss == null or not is_instance_valid(boss) or boss.state == Enemy.State.DEAD:
			wave_active = false
			emit_signal("wave_cleared")
		return
	while spawn_index < spawn_queue.size() and spawn_queue[spawn_index].t <= wave_clock:
		var entry: Dictionary = spawn_queue[spawn_index]
		_spawn(entry.color, entry.variant, entry.get("column", -1))
		spawn_index += 1
	if spawn_index >= spawn_queue.size() and enemies.is_empty():
		wave_active = false
		emit_signal("wave_cleared")

func _spawn_boss() -> void:
	boss = Boss.new()
	add_child(boss)
	var center_col: int = GameConfig.gate_columns / 2
	boss.init_boss({
		"column": center_col,
		"gate": gate_ref,
		"hero_row": hero_row_ref,
		"lane_top_y": lane_top_y,
		"lane_bottom_y": lane_bottom_y,
		"post_breach_target_y": post_breach_target_y,
		"column_x_func": column_x_func,
	})
	boss.died_signal.connect(_on_enemy_died)
	boss.boss_died.connect(_on_boss_died)
	enemies.append(boss)
	Telemetry.log_event("boss_spawn", {"name": "Corrupter", "col": center_col, "hp": boss.max_hp})

func _on_boss_died(_b: Boss) -> void:
	Telemetry.log_event("boss_died", {"name": "Corrupter"})
	boss = null
	next_minion_t = -1.0

func _spawn_miniboss() -> void:
	var col: int = GameConfig.gate_columns / 2
	miniboss = Enemy.new()
	add_child(miniboss)
	miniboss.init_enemy({
		"color": "YELLOW",
		"variant": "MINIBOSS",
		"column": col,
		"gate": gate_ref,
		"hero_row": hero_row_ref,
		"wave_idx": RunState.wave_index,
		"lane_top_y": lane_top_y,
		"lane_bottom_y": lane_bottom_y,
		"post_breach_target_y": post_breach_target_y,
		"column_x_func": column_x_func,
	})
	miniboss.reached_cannon.connect(_on_enemy_reached_cannon)
	miniboss.died_signal.connect(_on_enemy_died)
	miniboss.breached_signal.connect(_on_enemy_breached)
	enemies.append(miniboss)
	Telemetry.log_event("miniboss_spawn", {"col": col, "hp": miniboss.max_hp})

func _spawn(color: String, variant: String = "WALKER", forced_column: int = -1) -> void:
	var col: int = forced_column if forced_column >= 0 else _pick_spawn_column()
	var e: Enemy = Enemy.new()
	add_child(e)
	e.init_enemy({
		"color": color,
		"variant": variant,
		"column": col,
		"gate": gate_ref,
		"hero_row": hero_row_ref,
		"wave_idx": RunState.wave_index,
		"lane_top_y": lane_top_y,
		"lane_bottom_y": lane_bottom_y,
		"post_breach_target_y": post_breach_target_y,
		"column_x_func": column_x_func,
	})
	e.reached_cannon.connect(_on_enemy_reached_cannon)
	e.died_signal.connect(_on_enemy_died)
	e.breached_signal.connect(_on_enemy_breached)
	enemies.append(e)

func _pick_spawn_column() -> int:
	if _rng.randf() < GameConfig.spawn_column_closed_bias:
		var closed: Array[int] = []
		for c in range(GameConfig.gate_columns):
			if gate_ref.column_state(c) == "closed":
				closed.append(c)
		if not closed.is_empty():
			return closed[_rng.randi() % closed.size()]
	return _rng.randi() % GameConfig.gate_columns

# ─── Enemy event handlers ──────────────────────────────────────────────────

func _on_enemy_reached_cannon(e: Enemy) -> void:
	emit_signal("enemy_reached_base", e.color_dmg_base)
	enemies.erase(e)

func _on_enemy_died(e: Enemy) -> void:
	VFX.play("enemy_hit", e.global_position, {"color": e.color})
	SFX.play("enemy_death")
	enemies.erase(e)
	# Blast Brigade — kill grants currency scaled to the enemy's base HP.
	RunState.grant_currency(e.currency_value)

func _on_enemy_breached(e: Enemy) -> void:
	Telemetry.enemy_breach(e.column, gate_ref.column_state(e.column), false)
	VFX.play("enemy_breach", e.global_position)
	SFX.play("enemy_breach")

# ─── Cleanup ───────────────────────────────────────────────────────────────

func _clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	spawn_queue.clear()
	spawn_index = 0
	wave_clock = 0.0
	wave_active = false
	boss = null
	is_boss_wave = false
	miniboss = null
	is_miniboss_wave = false
	next_minion_t = -1.0
