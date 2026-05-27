extends Node
## GameConfig — Blast Brigade tunables (forked from Pop Brigade v2).
## Autoloaded. Read from anywhere as `GameConfig.<key>`.

# ─── Currency (Blast Brigade) ──────────────────────────────────────
# Player starts each run with starting_currency. Killing an enemy grants
# currency_per_kill. Spawning a hero costs hero_spawn_cost.
@export var starting_currency: int = 60
@export var hero_spawn_cost: int = 30
# Currency on kill scales with the enemy's max HP, anchored so base RED
# (70 HP) yields 6. Tankier/variant/boss enemies pay proportionally more;
# wave HP multipliers carry through, so the same enemy pays more in later waves.
@export var currency_per_hp: float = 6.0 / 70.0

func currency_for_hp(hp: float) -> int:
	return max(1, int(round(hp * currency_per_hp)))

# ─── Gate (kept for column geometry only — Blast Brigade doesn't seed bubbles) ─
@export var gate_columns: int = 11   # spans 11*60 = 660px of 720 vp → ~30px margin each side
@export var gate_rows: int = 12
@export var bubble_cell_px: int = 60

# Bomb projectile (Blast Brigade) — damage dealt on enemy hit.
@export var bomb_damage: float = 60.0
# Cannon reload between shots (seconds).
@export var cannon_reload_cooldown_sec_override: float = 0.40

# ─── Wave structure ─────────────────────────────────────────────────
# num_waves is set per-match at run start from MetaState.waves_for_stage(stage).
# Default mirrors stage 1 so a direct MatchScene launch still works.
@export var num_waves: int = 5
@export var moves_per_wave: Array[int] = [10, 6, 6, 6, 6]
@export var intermission_duration_sec: float = 5.0
@export var pre_run_countdown_sec: float = 3.0   # Wave 1 "Get Ready" — quick start

@export var gate_seed_rows_per_wave: Array[int] = [4, 5, 6, 7, 8]
# Explicit per-wave hero count — capped at 3, decreasing curve so later waves
# force harder merging decisions with fewer fresh recruits.
@export var hero_bubbles_per_wave: Array[int] = [3, 3, 2, 2, 2]

func hero_bubble_count_for_wave(wave_idx: int) -> int:
	var i: int = clamp(wave_idx, 0, hero_bubbles_per_wave.size() - 1)
	return clamp(hero_bubbles_per_wave[i], 0, 3)

# Safe per-wave accessors. Stages 3-5 run 10-16 waves but the tuning arrays
# below are length 5 — past the end we hold at the last entry until per-wave
# content is authored.
func moves_for_wave(idx: int) -> int:
	return moves_per_wave[clamp(idx, 0, moves_per_wave.size() - 1)]

func seed_rows_for_wave(idx: int) -> int:
	return gate_seed_rows_per_wave[clamp(idx, 0, gate_seed_rows_per_wave.size() - 1)]

func wave_duration_for_wave(idx: int) -> float:
	return wave_duration_sec[clamp(idx, 0, wave_duration_sec.size() - 1)]

func spawn_totals_for_wave(idx: int) -> Dictionary:
	return SPAWN_TOTALS[clamp(idx, 0, SPAWN_TOTALS.size() - 1)]

func enemy_hp_mult_for_wave(idx: int) -> float:
	return enemy_hp_mult_per_wave[clamp(idx, 0, enemy_hp_mult_per_wave.size() - 1)]

func enemy_dmg_mult_for_wave(idx: int) -> float:
	return enemy_dmg_mult_per_wave[clamp(idx, 0, enemy_dmg_mult_per_wave.size() - 1)]

# ─── Enemy lane ─────────────────────────────────────────────────────
@export var enemy_lane_cells: int = 16
@export var enemy_base_damage: int = 20
@export var enemy_hero_damage: int = 10
@export var spawn_telegraph_sec: float = 1.5
@export var spawn_column_closed_bias: float = 0.7

@export var lane_traversal_sec_for_red: float = 9.23   # 35% slower than the original 6.0

@export var wave_duration_sec: Array[float] = [30.0, 34.0, 40.0, 44.0, 44.0]

# Scaled ~2.4× from the original counts (kept in trailing comments) to match
# the Test C wave-1 density bump. Color ratios preserved; totals still escalate
# wave-over-wave. Wave 5 (idx 4) is the miniboss wave on Stage 1 so its totals
# only apply on stages 2+.
const SPAWN_TOTALS: Array = [
	{"RED": 12},                                                # 12
	{"RED": 9, "BLUE": 5},                                      # 14
	{"RED": 8, "BLUE": 5, "YELLOW": 4, "GREEN": 4},             # 21  (GREEN introduced)
	{"RED": 8, "BLUE": 6, "YELLOW": 5, "GREEN": 4, "PURPLE": 3},# 26  (PURPLE introduced)
	{"RED": 9, "BLUE": 7, "YELLOW": 6, "GREEN": 5, "PURPLE": 4},# 31  (full 5-color)
]

# ─── Wave-1 cluster test (Test C) ───────────────────────────────────
# wave_cluster_size[idx] > 0 → spawn in clusters of N at the same timestamp,
# spread across `wave_cluster_columns[idx]` different columns. 0 = legacy
# evenly-paced single-file spawning.
# wave_forced_brutes[idx] → after picking variants from VARIANT_MIX_PER_WAVE,
# overwrite N random slots with BRUTE (overrides gate that normally blocks
# BRUTE before wave 4).
@export var wave_cluster_size: Array[int]    = [4, 4, 4, 4, 4]
@export var wave_cluster_columns: Array[int] = [3, 3, 4, 4, 4]
# Forced BRUTEs only on waves 1-2 (their natural mix is all WALKER). Waves 3-5
# get RUNNER/BRUTE organically from VARIANT_MIX_PER_WAVE, so leave at 0.
@export var wave_forced_brutes: Array[int]   = [2, 2, 0, 0, 0]

func cluster_size_for_wave(idx: int) -> int:
	return wave_cluster_size[clamp(idx, 0, wave_cluster_size.size() - 1)]

func cluster_columns_for_wave(idx: int) -> int:
	return wave_cluster_columns[clamp(idx, 0, wave_cluster_columns.size() - 1)]

func forced_brutes_for_wave(idx: int) -> int:
	return wave_forced_brutes[clamp(idx, 0, wave_forced_brutes.size() - 1)]

@export var enemy_hp_mult_per_wave:  Array[float] = [1.0, 1.1, 1.2, 1.35, 1.5]
@export var enemy_dmg_mult_per_wave: Array[float] = [1.0, 1.0, 1.05, 1.1, 1.2]

# HP = original (50/80/120) +40%. RED no longer one-shots a 60-dmg bomb.
# GREEN = fast medium swarmer, PURPLE = slow tanky caster. Both counter their
# same-color hero (Druid / Wizard) via color_counter_mult.
const ENEMY_STATS: Dictionary = {
	"RED":    {"hp": 70,  "speed": 1.0,  "dmg_hero": 10, "dmg_base": 20},
	"GREEN":  {"hp": 90,  "speed": 0.90, "dmg_hero": 10, "dmg_base": 20},
	"BLUE":   {"hp": 112, "speed": 0.67, "dmg_hero": 10, "dmg_base": 20},
	"PURPLE": {"hp": 140, "speed": 0.60, "dmg_hero": 20, "dmg_base": 30},
	"YELLOW": {"hp": 168, "speed": 0.83, "dmg_hero": 15, "dmg_base": 25},
}

# Variant tags (combat-design.md §3.6). Multiplicative on color stats.
# NOTE: spec lists Runner speed_mult 0.6 and Brute 1.3, but with the codebase
# convention (higher speed_mult = faster) those values read backwards by name.
# Using intuitive directions here: Runner faster + frailer, Brute slower + tougher.
const ENEMY_VARIANTS: Dictionary = {
	"WALKER":   {"hp_mult": 1.0, "speed_mult": 1.0, "dmg_mult": 1.0, "scale": 1.0},
	"RUNNER":   {"hp_mult": 0.7, "speed_mult": 1.6, "dmg_mult": 1.0, "scale": 0.9},
	"BRUTE":    {"hp_mult": 2.0, "speed_mult": 0.7, "dmg_mult": 1.5, "scale": 1.4},
	"MINIBOSS": {"hp_mult": 3.0, "speed_mult": 1.0, "dmg_mult": 2.0, "scale": 1.6},
}

# Mini-boss wave (combat-design.md §3.6) — wave 5 of every stage spawns a solo
# YELLOW miniboss-variant enemy. For Stage 1 (5 waves) this IS the final wave;
# for stages 2+ the Corrupter still spawns on the actual last wave.
@export var miniboss_wave_idx: int = 4   # 0-based → wave 5

# Per-wave variant probability mix (sums to 1).
# Spec gates: Runner wave 3+ (idx>=2), Brute wave 4+ (idx>=3).
const VARIANT_MIX_PER_WAVE: Array = [
	{"WALKER": 1.0},
	{"WALKER": 1.0},
	{"WALKER": 0.70, "RUNNER": 0.30},
	{"WALKER": 0.50, "RUNNER": 0.30, "BRUTE": 0.20},
	{"WALKER": 0.40, "RUNNER": 0.30, "BRUTE": 0.30},
]

func variant_mix_for_wave(idx: int) -> Dictionary:
	return VARIANT_MIX_PER_WAVE[clamp(idx, 0, VARIANT_MIX_PER_WAVE.size() - 1)]

# ─── Player base ────────────────────────────────────────────────────
@export var base_max_hp: int = 100

# ─── Cannon ─────────────────────────────────────────────────────────
@export var cannon_reload_cooldown_sec: float = 0.2

# ─── Hit feel (per-hit polish on enemies) ───────────────────────────
# Tiny "freeze frame" stutter when a hit lands. Time scale dips to
# hit_freeze_time_scale for hit_freeze_duration_sec real-time seconds.
# Re-entrant calls during an active freeze are ignored so the rate is
# bounded even at peak fire density.
@export var hit_freeze_duration_sec: float = 0.035
@export var hit_freeze_time_scale: float = 0.05
# White-flash overlay drawn on top of the enemy sprite, alpha fades from 1→0.
@export var hit_flash_duration_sec: float = 0.09
# Floating damage number — vertical rise + fade.
@export var dmg_number_rise_px: float = 46.0
@export var dmg_number_lifetime_sec: float = 0.70
@export var dmg_number_font_size: int = 26
@export var dmg_number_crit_font_size: int = 34

# ─── Hero classes ───────────────────────────────────────────────────
# Hero lineup per stage is driven by MetaState.STAGE_LINEUP, not a static enable list.

# Hero class numbers (combat-design.md §7). All Bronze-tier baselines.
@export var hero_base_hp: float = 100.0
@export var hero_base_damage: float = 20.0

# Ranges below use lane_progress (0=far at gate, 1=at heroes). v1 quoted
# reach in lane cells; with enemy_lane_cells=20, "N rows ahead" maps to
# lane_progress >= (20-N)/20.

# Range tier arrays — index [0]=unused, [1]=Bronze, [2]=Silver, [3]=Gold.
# Read via *_rows_for_tier(t) / *_cols_for_tier(t) helpers below.

# Fire Knight (RED) — melee cone + cleave chance.
@export var red_fire_rate_sec: float = 0.5
@export var red_dmg_mult: float = 1.0
@export var red_cone_rows_by_tier: Array[int] = [0, 4, 5, 6]
@export var red_cone_cols_by_tier: Array[int] = [0, 1, 1, 2]
@export var red_cleave_chance: float = 0.25
@export var red_cleave_targets: int = 2

# Ice Mage (BLUE) — lob + AoE splash + slow.
@export var blue_fire_rate_sec: float = 1.0
@export var blue_dmg_mult: float = 0.5
@export var blue_reach_rows_by_tier: Array[int] = [0, 8, 10, 12]
@export var blue_col_radius_by_tier: Array[int] = [0, 5, 5, 5]   # full-board horizontal
@export var blue_aoe_radius_px: float = 90.0           # ~1.5 gate cells (CELL=60)
@export var blue_slow_pct: float = 0.30                # 30% movement slow
@export var blue_slow_duration_sec: float = 2.0

# Archer (YELLOW) — straight cone snipe + execute bonus.
@export var yellow_fire_rate_sec: float = 0.8
@export var yellow_dmg_mult: float = 0.85
@export var yellow_reach_rows_by_tier: Array[int] = [0, 12, 14, 16]
@export var yellow_col_radius_by_tier: Array[int] = [0, 5, 5, 5]   # full-board horizontal
@export var yellow_execute_threshold: float = 0.30
@export var yellow_execute_bonus: float = 0.50

# Druid (GREEN) — single-target + chain heal.
@export var green_fire_rate_sec: float = 0.7
@export var green_dmg_mult: float = 0.6
@export var green_reach_rows_by_tier: Array[int] = [0, 6, 8, 10]
@export var green_col_radius_by_tier: Array[int] = [0, 5, 5, 5]   # full-board horizontal
@export var green_chain_heal_amount: int = 5
@export var green_chain_heal_targets: int = 2
@export var green_heal_per_hero_cap_per_sec: int = 15

# Wizard (PURPLE) — cone snipe + arcane burst every Nth hit.
@export var purple_fire_rate_sec: float = 1.4
@export var purple_dmg_mult: float = 1.5
@export var purple_reach_rows_by_tier: Array[int] = [0, 10, 12, 14]
@export var purple_col_radius_by_tier: Array[int] = [0, 5, 5, 5]   # full-board horizontal
@export var purple_burst_every_n_hits: int = 5
@export var purple_aoe_radius_px: float = 90.0         # ~1.5 gate cells

func _tier_idx(t: int) -> int:
	return clamp(t, 1, 3)

func red_cone_rows_for_tier(t: int) -> int:    return red_cone_rows_by_tier[_tier_idx(t)]
func red_cone_cols_for_tier(t: int) -> int:    return red_cone_cols_by_tier[_tier_idx(t)]
func blue_reach_rows_for_tier(t: int) -> int:  return blue_reach_rows_by_tier[_tier_idx(t)]
func blue_col_radius_for_tier(t: int) -> int:  return blue_col_radius_by_tier[_tier_idx(t)]
func yellow_reach_rows_for_tier(t: int) -> int: return yellow_reach_rows_by_tier[_tier_idx(t)]
func yellow_col_radius_for_tier(t: int) -> int: return yellow_col_radius_by_tier[_tier_idx(t)]
func green_reach_rows_for_tier(t: int) -> int: return green_reach_rows_by_tier[_tier_idx(t)]
func green_col_radius_for_tier(t: int) -> int: return green_col_radius_by_tier[_tier_idx(t)]
func purple_reach_rows_for_tier(t: int) -> int: return purple_reach_rows_by_tier[_tier_idx(t)]
func purple_col_radius_for_tier(t: int) -> int: return purple_col_radius_by_tier[_tier_idx(t)]

# Status effects (combat-design.md §7)
@export var status_slow_speed_mult: float = 0.7
@export var status_slow_duration_sec: float = 2.0
@export var status_freeze_duration_sec: float = 4.0
@export var status_burn_pct_per_sec: float = 0.03      # 3% max HP / sec / stack
@export var status_burn_duration_sec: float = 3.0
@export var status_burn_max_stacks: int = 3
@export var status_poison_pct_per_sec: float = 0.05    # 5% max HP / sec / stack
@export var status_poison_duration_sec: float = 3.0
@export var status_poison_max_stacks: int = 3
@export var status_stun_duration_sec: float = 1.0

# Boss + The Corrupter (boss-design.md §2, §4)
@export var boss_hp: int = 1000
@export var boss_lane_cell: int = 5                          # fixed lane cell (of 20) — spawn position
@export var boss_walk_speed_mult: float = 0.20               # vs lane_traversal_sec_for_red; ~30s full-lane → ~20s from spawn
@export var boss_base_damage: int = 60                       # base HP damage if Corrupter reaches the tower (>50% of 100)
@export var boss_telegraph_sec: float = 2.0
@export var boss_ability_interval_sec: float = 8.0
@export var boss_low_hp_threshold: float = 0.25
@export var boss_low_hp_interval_mult: float = 0.75          # 8s → 6s at low HP
@export var corruption_splash_radius_cells: int = 1
@export var corruption_target_bias_away_from_corrupted: float = 0.7
@export var corrupter_minion_first_spawn_delay_sec: float = 10.0
@export var corrupter_minion_spawn_interval_sec: float = 15.0
@export var corrupter_minion_closed_column_bias: float = 0.7

# Color counter / merge
@export var color_counter_mult: float = 2.0
@export var hero_tier_hp_mult:  Array[float] = [0.0, 1.0, 1.6, 2.4]   # Bronze=1.0
@export var hero_tier_dmg_mult: Array[float] = [0.0, 1.0, 1.5, 2.2]
