extends Node
## Telemetry — stub event logger.
## Spec §10 event names. Currently prints to stdout; swap with a real sink later.

const ENABLED: bool = true

func log_event(name: String, props: Dictionary = {}) -> void:
	if not ENABLED:
		return
	print("[telemetry] %s %s" % [name, JSON.stringify(props)])

# Convenience shims — keep call sites readable.
func wave_start(wave: int, seed_snapshot: Dictionary, move_budget: int) -> void:
	log_event("wave_start", {"wave": wave, "seed": seed_snapshot, "moves": move_budget})

func wave_end(result: String, moves_used: int, elapsed_sec: float, heroes_alive: int) -> void:
	log_event("wave_end", {"result": result, "moves_used": moves_used,
		"elapsed": elapsed_sec, "heroes_alive": heroes_alive})

func gate_state_snapshot(per_column: Array) -> void:
	log_event("gate_state_snapshot", {"cols": per_column})

func hero_bullet_blocked(col: int, hero_class: String) -> void:
	log_event("hero_bullet_blocked", {"col": col, "class": hero_class})

func enemy_breach(col: int, state: String, hero_present: bool) -> void:
	log_event("enemy_breach", {"col": col, "state": state, "hero": hero_present})

func cannon_miss(col: int) -> void:
	log_event("cannon_miss", {"col": col})

func bubble_pop(match_size: int, contains_hero: bool, color: String, wave: int) -> void:
	log_event("bubble_pop", {"size": match_size, "hero": contains_hero,
		"color": color, "wave": wave})
