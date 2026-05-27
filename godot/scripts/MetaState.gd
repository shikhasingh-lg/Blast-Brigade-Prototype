extends Node
## MetaState — persistent-feeling meta loop state.
##
## Singleton (autoload). Holds stage progress, currencies, player level/XP, last
## run summary, and the currently-selected stage. All meta screens read/write
## through this so we don't have to thread state through scene_changed calls.
##
## Not persisted to disk in v2 — this is the prototype loop. Add ResourceSaver
## hooks before soft launch.

const TOTAL_STAGES: int = 5
const BOSS_STAGE: int = 5
const MAX_ENERGY: int = 10
const STAGE_ENERGY_COST: int = 1

const REWARD_XP: int = 80
const REWARD_GOLD: int = 60
const REWARD_GEM_FIRST_CLEAR: int = 1
const PARTIAL_XP: int = 20
const PARTIAL_GOLD: int = 15

## XP table — flat 500 per level for prototype.
const XP_PER_LEVEL: int = 500

signal stage_changed(stage: int)
signal currencies_changed()
signal level_changed(level: int, xp: int)

# Progression.
var current_stage: int = 2                 # the player's "next to play" stage
var highest_cleared: int = 1               # 0 = nothing cleared
var viewing_stage: int = 2                 # which stage the Stage Select card is showing (left/right scrub)
var last_stage_cleared_this_session: int = -1   # set on win, consumed by stage-progressed anim

# Currencies.
var energy: int = 7
var gems: int = 250
var gold: int = 4200
var tickets: int = 3

# Player level.
var player_level: int = 7
var player_xp: int = 320                   # XP into current level

# Last run summary — populated when MatchScene exits, consumed by RunClear/RunFail.
var last_run_result: String = ""           # "win" | "lose" | "stall_loss"
var last_run_wave_reached: int = 0
var last_run_damage_dealt: int = 0
var last_run_bubbles_popped: int = 0
var last_run_mvp_hero: String = "Ice Mage"
var last_run_mvp_damage: int = 0
var last_run_revive_used: bool = false

# Best wave reached per stage (1-indexed). 0 = never played.
var best_wave_per_stage: Dictionary = {}

# Stage roster — heroes available in each stage. Prototype unlock curve:
# stage 1 = 3 heroes, stage 2 = 4 heroes, stages 3-5 = full 5-hero roster.
const STAGE_LINEUP: Array = [
	# Stage 1 — 3 heroes (FK, AR, IM)
	[["FK", Color(0.95, 0.42, 0.36)], ["AR", Color(0.45, 0.78, 0.40)], ["IM", Color(0.36, 0.74, 0.98)]],
	# Stage 2 — 4 heroes (+ DR)
	[["FK", Color(0.95, 0.42, 0.36)], ["AR", Color(0.45, 0.78, 0.40)], ["IM", Color(0.36, 0.74, 0.98)], ["DR", Color(0.78, 0.62, 0.36)]],
	# Stage 3 — full 5-hero roster (+ WZ)
	[["FK", Color(0.95, 0.42, 0.36)], ["AR", Color(0.45, 0.78, 0.40)], ["IM", Color(0.36, 0.74, 0.98)], ["DR", Color(0.78, 0.62, 0.36)], ["WZ", Color(0.86, 0.46, 0.96)]],
	# Stage 4 — full roster
	[["FK", Color(0.95, 0.42, 0.36)], ["AR", Color(0.45, 0.78, 0.40)], ["IM", Color(0.36, 0.74, 0.98)], ["DR", Color(0.78, 0.62, 0.36)], ["WZ", Color(0.86, 0.46, 0.96)]],
	# Stage 5 — boss, full roster
	[["FK", Color(0.95, 0.42, 0.36)], ["AR", Color(0.45, 0.78, 0.40)], ["IM", Color(0.36, 0.74, 0.98)], ["DR", Color(0.78, 0.62, 0.36)], ["WZ", Color(0.86, 0.46, 0.96)]],
]

# Wave count per stage (prototype): 5 → 7 → 10 → 13 → 16.
const WAVES_PER_STAGE: Array[int] = [5, 7, 10, 13, 16]

func lineup_for_stage(stage: int) -> Array:
	if STAGE_LINEUP.is_empty():
		return []
	var idx: int = clamp(stage - 1, 0, STAGE_LINEUP.size() - 1)
	return STAGE_LINEUP[idx]

func waves_for_stage(stage: int) -> int:
	var idx: int = clamp(stage - 1, 0, WAVES_PER_STAGE.size() - 1)
	return WAVES_PER_STAGE[idx]

func best_wave_for_stage(stage: int) -> int:
	return int(best_wave_per_stage.get(stage, 0))

func record_best_wave(stage: int, wave: int) -> void:
	if wave > best_wave_for_stage(stage):
		best_wave_per_stage[stage] = wave

# Stage names for the world 1 path. Index 0 = stage 1.
const STAGE_NAMES: Array[String] = [
	"Sunny Meadow", "Bramble Bend", "Hollow Rock", "Mossy Steps", "The Corrupter",
]

func stage_name_for(stage: int) -> String:
	if stage < 1 or stage > STAGE_NAMES.size():
		return "Stage %d" % stage
	return STAGE_NAMES[stage - 1]

func is_boss_stage(stage: int) -> bool:
	return stage == BOSS_STAGE

func is_stage_cleared(stage: int) -> bool:
	return stage <= highest_cleared

func is_stage_playable(stage: int) -> bool:
	return stage == highest_cleared + 1

func is_stage_locked(stage: int) -> bool:
	return stage > highest_cleared + 1

# Called before launching a stage. Locks in the stage, spends energy.
func select_stage(stage: int) -> void:
	current_stage = stage
	emit_signal("stage_changed", stage)

func spend_energy_for_stage() -> bool:
	if energy < STAGE_ENERGY_COST:
		return false
	energy -= STAGE_ENERGY_COST
	emit_signal("currencies_changed")
	return true

# Called when MatchScene reports run_ended("win").
func record_win(damage: int, bubbles_popped: int, mvp: String, mvp_dmg: int) -> void:
	last_run_result = "win"
	last_run_wave_reached = GameConfig.num_waves
	last_run_damage_dealt = damage
	last_run_bubbles_popped = bubbles_popped
	last_run_mvp_hero = mvp
	last_run_mvp_damage = mvp_dmg

func record_loss(result: String, wave_reached: int, damage: int, bubbles_popped: int) -> void:
	# wave_reached is 1-based: the wave the player died on (1..num_waves).
	last_run_result = result   # "lose" or "stall_loss"
	last_run_wave_reached = wave_reached
	last_run_damage_dealt = damage
	last_run_bubbles_popped = bubbles_popped

# Called from RunClear when player taps CONTINUE. Awards rewards + advances
# highest_cleared. Returns the just-cleared stage.
func apply_win_rewards() -> int:
	var cleared: int = current_stage
	var first_clear: bool = cleared > highest_cleared
	if first_clear:
		highest_cleared = cleared
		gems += REWARD_GEM_FIRST_CLEAR
	gold += REWARD_GOLD
	add_xp(REWARD_XP)
	last_stage_cleared_this_session = cleared
	if cleared < TOTAL_STAGES:
		current_stage = cleared + 1
	emit_signal("stage_changed", current_stage)
	emit_signal("currencies_changed")
	return cleared

func apply_loss_partial_rewards() -> void:
	gold += PARTIAL_GOLD
	add_xp(PARTIAL_XP)
	emit_signal("currencies_changed")

func add_xp(amount: int) -> void:
	player_xp += amount
	while player_xp >= XP_PER_LEVEL:
		player_xp -= XP_PER_LEVEL
		player_level += 1
	emit_signal("level_changed", player_level, player_xp)

func reset_last_run() -> void:
	last_run_result = ""
	last_run_wave_reached = 0
	last_run_damage_dealt = 0
	last_run_bubbles_popped = 0
	last_run_mvp_damage = 0
	last_run_revive_used = false
