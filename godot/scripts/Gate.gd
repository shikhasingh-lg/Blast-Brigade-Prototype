extends Node2D
class_name Gate
## The bubble wall. Owns the grid model + match logic.
## Odd-r offset hex layout: rows with odd Y are shifted right by half a cell.

const CELL: int = 60                # bubble cell px (spec §9)
const ROW_HEIGHT: int = 52          # ≈ CELL * sqrt(3)/2 for hex stacking
const MATCH_SIZE: int = 3

# Neighbor offsets for odd-r offset hex grid.
const NEIGHBORS_EVEN_ROW: Array[Vector2i] = [
	Vector2i(-1,  0), Vector2i(1,  0),
	Vector2i(-1, -1), Vector2i(0, -1),
	Vector2i(-1,  1), Vector2i(0,  1),
]
const NEIGHBORS_ODD_ROW: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(0,  1), Vector2i(1,  1),
]

signal bubble_popped(count: int, color: String, contains_hero: bool)
signal heroes_freed(spawns: Array)  # Array of { col: int, hero_class: String, tier: int }

var cells: Dictionary = {}   # Vector2i -> Bubble
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

# ─── Coordinates ───────────────────────────────────────────────────────────

func cell_local_pos(cell: Vector2i) -> Vector2:
	var x_off: float = (CELL * 0.5) if (cell.y % 2 == 1) else 0.0
	return Vector2(cell.x * CELL + CELL * 0.5 + x_off,
				   cell.y * ROW_HEIGHT + ROW_HEIGHT * 0.5)

func cell_world_pos(cell: Vector2i) -> Vector2:
	return global_position + cell_local_pos(cell)

func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = NEIGHBORS_ODD_ROW if (cell.y % 2 == 1) else NEIGHBORS_EVEN_ROW
	var out: Array[Vector2i] = []
	for o in offsets:
		var n: Vector2i = cell + o
		if n.x >= 0 and n.x < GameConfig.gate_columns and n.y >= 0 and n.y < GameConfig.gate_rows:
			out.append(n)
	return out

# ─── Seeding ───────────────────────────────────────────────────────────────

func clear_all() -> void:
	for b in cells.values():
		(b as Node).queue_free()
	cells.clear()

# True iff at least one hero bubble is still on the gate.
func has_any_hero_bubble() -> bool:
	for b in cells.values():
		if (b as Bubble).is_hero:
			return true
	return false

# Sweep every remaining bubble off the gate with the same pop animation used for
# match-pops. Called by MatchScene when moves run out or every hero is freed.
# No `heroes_freed` signal — any hero bubbles still on the gate are forfeit.
func fade_clear_all() -> void:
	if cells.is_empty():
		return
	for b in cells.values():
		(b as Bubble).pop_disappear()
	cells.clear()

func seed_wave(wave_idx: int) -> void:
	clear_all()
	var rows: int = GameConfig.seed_rows_for_wave(wave_idx)
	var palette: Array[String] = _palette_for_wave(wave_idx)
	var all_cells: Array[Vector2i] = []
	for r in range(rows):
		for c in range(GameConfig.gate_columns):
			all_cells.append(Vector2i(c, r))
	# Pick N hero cells from the seeded area. Guarantee at least ONE hero bubble
	# lands in the bottom seed row (row = rows-1) — that's the row closest to the
	# cannon, so the first hero is always reachable within a couple of shots and
	# the player isn't starved of defense at wave start.
	all_cells.shuffle()
	var hero_count: int = min(GameConfig.hero_bubble_count_for_wave(wave_idx), all_cells.size())
	var hero_set: Dictionary = {}
	if hero_count > 0:
		var bottom_cells: Array[Vector2i] = []
		for c in range(GameConfig.gate_columns):
			bottom_cells.append(Vector2i(c, rows - 1))
		bottom_cells.shuffle()
		hero_set[bottom_cells[0]] = true
	for cell in all_cells:
		if hero_set.size() >= hero_count:
			break
		if not hero_set.has(cell):
			hero_set[cell] = true
	for cell in all_cells:
		var col: String = palette[_rng.randi() % palette.size()]
		var is_h: bool = hero_set.has(cell)
		var hclass: String = _hero_class_for_color(col) if is_h else ""
		_spawn_bubble(cell, col, is_h, hclass)

# Hero class is locked to bubble color: RED→FireKnight, BLUE→IceMage,
# YELLOW→Archer, GREEN→Druid, PURPLE→Wizard. So a yellow hero bubble always
# frees an Archer.
func _hero_class_for_color(c: String) -> String:
	match c:
		"RED":    return "FireKnight"
		"BLUE":   return "IceMage"
		"YELLOW": return "Archer"
		"GREEN":  return "Druid"
		"PURPLE": return "Wizard"
		_:        return "FireKnight"

func _palette_for_wave(w: int) -> Array[String]:
	# Stage-gated unlock: stage 1 = RBY (3 colors), stage 2 adds GREEN, stage 3+ adds PURPLE.
	# Wave 0 doubles RED/BLUE so the opening seed stays fragmented (avoids one
	# giant connected group that a single 3-match wipes — spec §5.3).
	var p: Array[String] = ["RED", "BLUE", "YELLOW"]
	if MetaState.current_stage >= 2:
		p.append("GREEN")
	if MetaState.current_stage >= 3:
		p.append("PURPLE")
	if w == 0:
		p.append("RED")
		p.append("BLUE")
	return p

func _spawn_bubble(cell: Vector2i, color: String, hero: bool, hero_class: String = "") -> Bubble:
	var b: Bubble = Bubble.new()
	b.position = cell_local_pos(cell)
	add_child(b)
	b.set_bubble(color, cell, hero, hero_class)
	cells[cell] = b
	return b

# ─── Attach + match ────────────────────────────────────────────────────────

func get_active_colors() -> Array[String]:
	# Distinct (non-corrupted, non-hero-only-blocker) bubble colors currently in the
	# gate. Used by the cannon to bias its palette toward colors that can match.
	var seen: Dictionary = {}
	for b in cells.values():
		if (b as Bubble).is_corrupted:
			continue
		seen[(b as Bubble).color] = true
	var out: Array[String] = []
	for k in seen.keys():
		out.append(String(k))
	return out

func cell_for_world_pos(world_pos: Vector2) -> Vector2i:
	# Inverse of cell_world_pos — used by the trajectory preview to know which
	# bubble the projectile would attach next to.
	var local: Vector2 = world_pos - global_position
	var row: int = int(round((local.y - ROW_HEIGHT * 0.5) / float(ROW_HEIGHT)))
	var x_off: float = (CELL * 0.5) if (row % 2 == 1) else 0.0
	var col: int = int(round((local.x - CELL * 0.5 - x_off) / float(CELL)))
	return Vector2i(col, row)

func _find_neighbor_empty_cell(hit: Bubble, world_pos: Vector2) -> Vector2i:
	# Snap target restricted to empty hex neighbors of the bubble that was hit.
	# This is the v1 fix: a glancing hit on the underside of the cluster should
	# snap adjacent to the bubble it touched, not to the globally nearest empty
	# cell (which can be a phantom row below the cluster).
	if hit == null:
		return Vector2i(-1, -1)
	var hit_cell: Vector2i = hit.grid_pos
	var local: Vector2 = world_pos - global_position
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for n in neighbors(hit_cell):
		if cells.has(n):
			continue
		var d: float = cell_local_pos(n).distance_squared_to(local)
		if d < best_d:
			best_d = d
			best = n
	return best

func predict_attach_world_position(world_pos: Vector2, hit_bubble: Bubble = null) -> Vector2:
	# Mirror v1: try snap-to-hit-neighbor first, fall back to nearest empty cell.
	# Returns the world-space center the projectile would attach at — used both
	# by the aim preview (ghost bubble) and by the actual attach call.
	var cell: Vector2i = Vector2i(-1, -1)
	if hit_bubble != null:
		cell = _find_neighbor_empty_cell(hit_bubble, world_pos)
	if cell.x < 0:
		cell = snap_world_pos_to_empty_cell(world_pos)
	return cell_world_pos(cell)

func snap_world_pos_to_empty_cell(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos - global_position
	var best: Vector2i = Vector2i.ZERO
	var best_d: float = INF
	var found: bool = false
	for r in range(GameConfig.gate_rows):
		for c in range(GameConfig.gate_columns):
			var cell: Vector2i = Vector2i(c, r)
			if cells.has(cell):
				continue
			# row 0 always valid; deeper rows only if attached to something
			if r > 0 and not _has_occupied_neighbor(cell):
				continue
			var d: float = cell_local_pos(cell).distance_squared_to(local)
			if d < best_d:
				best_d = d
				best = cell
				found = true
	if not found:
		# fallback — should not happen unless gate is full
		return Vector2i(int(local.x / CELL), 0)
	return best

func _has_occupied_neighbor(cell: Vector2i) -> bool:
	for n in neighbors(cell):
		if cells.has(n):
			return true
	return false

func attach_bubble(world_pos: Vector2, color: String, hit_bubble: Bubble = null) -> Dictionary:
	# Snap to an empty hex neighbor of the bubble that was hit (v1 pattern).
	# Falls back to globally nearest empty cell for top-bound attaches and the
	# edge case where every neighbor of the hit is already filled.
	var cell: Vector2i = Vector2i(-1, -1)
	if hit_bubble != null:
		cell = _find_neighbor_empty_cell(hit_bubble, world_pos)
	if cell.x < 0:
		cell = snap_world_pos_to_empty_cell(world_pos)
	_spawn_bubble(cell, color, false)
	var group: Array[Vector2i] = _connected_same_color(cell)
	var matched: bool = group.size() >= MATCH_SIZE
	var popped_total: int = 0
	var contained_hero: bool = false
	var hero_spawns: Array = []
	if matched:
		# v2: cluster-size no longer dictates hero tier — all freed heroes spawn at
		# T1, and the player tiers them up via merge (click or drag).
		var tier: int = 1
		# Collect corrupted neighbors before destroying — splash radius from spec §2.3.
		var splash_corrupted: Dictionary = {}
		var radius: int = GameConfig.corruption_splash_radius_cells
		for g in group:
			_collect_corrupted_within(g, radius, splash_corrupted)
		# Destroy match group.
		for g in group:
			var b: Bubble = cells[g]
			if b.is_hero:
				contained_hero = true
				hero_spawns.append({"col": g.x, "hero_class": b.hero_class, "tier": tier})
			cells.erase(g)
			b.pop_disappear()
		popped_total = group.size()
		# Splash-destroy corrupted bubbles.
		for c in splash_corrupted.keys():
			if cells.has(c):
				var sb: Bubble = cells[c]
				cells.erase(c)
				sb.pop_disappear()
				popped_total += 1
		popped_total += _drop_floaters()
		emit_signal("bubble_popped", popped_total, color, contained_hero)
		if not hero_spawns.is_empty():
			emit_signal("heroes_freed", hero_spawns)
	return {"cell": cell, "matched": matched, "popped": popped_total,
			"contained_hero": contained_hero, "color": color, "hero_spawns": hero_spawns}

func _connected_same_color(start: Vector2i) -> Array[Vector2i]:
	if not cells.has(start):
		return []
	if cells[start].is_corrupted:
		return []   # corrupted bubbles never match
	var col: String = cells[start].color
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for n in neighbors(cur):
			if cells.has(n) and not visited.has(n) \
					and not cells[n].is_corrupted \
					and cells[n].color == col:
				visited[n] = true
				queue.append(n)
	var out: Array[Vector2i] = []
	for k in visited.keys():
		out.append(k)
	return out

func _collect_corrupted_within(center: Vector2i, radius: int, out: Dictionary) -> void:
	# BFS up to `radius` hex steps; collect cells flagged is_corrupted.
	var visited: Dictionary = {center: 0}
	var queue: Array = [center]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var d: int = visited[cur]
		if d >= radius:
			continue
		for n in neighbors(cur):
			if visited.has(n):
				continue
			visited[n] = d + 1
			queue.append(n)
			if cells.has(n) and cells[n].is_corrupted:
				out[n] = true

# ─── Corruption (boss-design.md §2.3) ──────────────────────────────────────

func corrupt_column(col: int) -> int:
	# Convert every uncorrupted bubble in the column to corrupted.
	# If column has no uncorrupted bubbles, add a new corrupted bubble at the
	# top of the stack (growing decay). Returns count of newly-corrupted cells.
	var any_uncorrupted: bool = false
	var converted: int = 0
	for r in range(GameConfig.gate_rows):
		var cell: Vector2i = Vector2i(col, r)
		if cells.has(cell) and not cells[cell].is_corrupted:
			cells[cell].set_corrupted(true)
			converted += 1
			any_uncorrupted = true
	if not any_uncorrupted:
		# Grow decay: add a new corrupted bubble at the highest empty row attached
		# to existing column or to row 0 if column is fully empty.
		var add_at: Vector2i = _next_growth_cell(col)
		if add_at.x >= 0:
			var b: Bubble = _spawn_bubble(add_at, "PURPLE", false)
			b.set_corrupted(true)
			converted = 1
	return converted

func _next_growth_cell(col: int) -> Vector2i:
	# Find first empty row in column with an occupied neighbor below (or row 0).
	for r in range(GameConfig.gate_rows):
		var cell: Vector2i = Vector2i(col, r)
		if cells.has(cell):
			continue
		if r == 0 or _has_occupied_neighbor(cell):
			return cell
	return Vector2i(-1, -1)

func column_uncorrupted_count(col: int) -> int:
	var n: int = 0
	for r in range(GameConfig.gate_rows):
		var cell: Vector2i = Vector2i(col, r)
		if cells.has(cell) and not cells[cell].is_corrupted:
			n += 1
	return n

func _drop_floaters() -> int:
	# Anything not connected (any-color BFS) to row 0 is a floater.
	var anchored: Dictionary = {}
	var queue: Array[Vector2i] = []
	for c in range(GameConfig.gate_columns):
		var cell: Vector2i = Vector2i(c, 0)
		if cells.has(cell):
			anchored[cell] = true
			queue.append(cell)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for n in neighbors(cur):
			if cells.has(n) and not anchored.has(n):
				anchored[n] = true
				queue.append(n)
	var dropped: int = 0
	var to_drop: Array[Vector2i] = []
	for cell in cells.keys():
		if not anchored.has(cell):
			to_drop.append(cell)
	for cell in to_drop:
		var b: Bubble = cells[cell]
		cells.erase(cell)
		b.pop_disappear()
		dropped += 1
	return dropped

# ─── Occlusion query (used by hero firing + enemy spawn bias) ──────────────

func column_state(col: int) -> String:
	# Three-state per art-direction.md §7.2 + combat-design.md §1.2:
	#   "open"    — no bubble in column, both hero shots and enemies pass.
	#   "cracked" — cluster's bottom bubble in this column is cracked: hero shots
	#               pass through, enemies still blocked. Tactical sweet spot.
	#   "closed"  — bubble in column with no crack: both hero and enemy blocked.
	# State is derived from the bottom-most bubble (cluster's enemy-facing edge);
	# bubbles deeper in the cluster don't influence column state because hero
	# fire and enemy bash both interact with the cluster's bottom edge.
	var bottom_row: int = cluster_bottom_row(col)
	if bottom_row < 0:
		return "open"
	var bottom: Bubble = cells[Vector2i(col, bottom_row)]
	if bottom.is_cracked and not bottom.is_corrupted:
		return "cracked"
	return "closed"

func is_passable_for_hero_shot(col: int) -> bool:
	# Convenience for hero firing decision tree (combat-design §1.2 step 2):
	# heroes can shoot through cracked or open columns.
	return column_state(col) != "closed"

func crack_column_bottom(col: int) -> bool:
	# Crack the cluster's bottom bubble in this column. Returns true if a fresh
	# crack was applied (false if already cracked, corrupted, or column empty).
	# Designed as the public entry-point for any future "enemy bashes the gate"
	# trigger — keeps the cracking policy out of Bubble/Enemy and in Gate.
	var bottom_row: int = cluster_bottom_row(col)
	if bottom_row < 0:
		return false
	var b: Bubble = cells[Vector2i(col, bottom_row)]
	if b.is_corrupted or b.is_cracked:
		return false
	b.set_cracked(true)
	return true

func cluster_bottom_row(col: int) -> int:
	# Highest row index (= cluster's enemy-facing edge in new layout) that has
	# a bubble in this column. -1 if column is empty.
	for r in range(GameConfig.gate_rows - 1, -1, -1):
		if cells.has(Vector2i(col, r)):
			return r
	return -1
