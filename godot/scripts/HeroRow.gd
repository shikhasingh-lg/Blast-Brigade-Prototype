extends Node2D
class_name HeroRow
## Hero row manager. Owns the 8 row-0 cells, handles placement resolution on
## hero-bubble pop, drag/merge/swap, queue FIFO, and respawn on hero death.
## Combat-design §2.3 / §2.4.

const QUEUE_MAX: int = 3
const DRAG_Y_TOLERANCE: float = 90.0   # covers the full ~150px portrait height
const CLICK_DEAD_ZONE: float = 18.0          # px before a press becomes a drag (trackpad-tolerant)

# Click-to-merge prompt (floating "MERGE" pill above the tapped hero).
const MERGE_BUTTON_W: float = 92.0
const MERGE_BUTTON_H: float = 32.0
const MERGE_BUTTON_OFFSET_Y: float = -110.0  # above portrait top (portrait half = 75)
const PARTNER_PULSE_SCALE: float = 1.10

signal hero_died(col: int)

var gate: Gate
var enemy_lane: EnemyLane
var column_x_func: Callable
var row_y: float = 0.0

var heroes: Array = []    # length 8; null or Hero
var queue: Array = []     # FIFO of { hero_class: String, tier: int }

var _dragged: Hero = null
var _drag_from_col: int = -1

# Press-state (distinguish click from drag).
var _press_pos: Vector2 = Vector2.ZERO
var _press_col: int = -1
var _press_hero: Hero = null
var _drag_started: bool = false
var _suppress_click_open: bool = false   # tapping the same hero again closes, doesn't reopen

# Active merge prompt.
var _merge_prompt_hero: Hero = null
var _merge_partners: Array = []          # Hero[]
var _merge_partner_tweens: Array = []    # Tween[]

func configure(g: Gate, el: EnemyLane, col_x: Callable, ry: float) -> void:
	gate = g
	enemy_lane = el
	column_x_func = col_x
	row_y = ry
	heroes.resize(GameConfig.gate_columns)
	for i in range(GameConfig.gate_columns):
		heroes[i] = null

func is_dragging() -> bool:
	return _dragged != null

func has_any_heroes() -> bool:
	if not queue.is_empty():
		return true
	for h in heroes:
		if h != null and is_instance_valid(h):
			return true
	return false

func hero_at(col: int) -> Hero:
	if col < 0 or col >= heroes.size():
		return null
	return heroes[col]

func clear_all() -> void:
	for i in range(heroes.size()):
		var h: Hero = heroes[i]
		if h != null and is_instance_valid(h):
			h.queue_free()
		heroes[i] = null
	queue.clear()

# ─── Hero spawn / placement (combat-design §2.3) ───────────────────

# Blast Brigade — public spawn entrypoint. Picks the first empty cell from the
# center outward and places a tier-1 hero of the given class there. Returns
# true if placed (or queued); false if no slot at all (queue full + every
# column has a tier-3 hero of a different class).
func spawn_hero_td(hero_class: String) -> bool:
	var center: int = GameConfig.gate_columns / 2
	# Search outward from center for an empty slot.
	for delta in range(0, GameConfig.gate_columns):
		for sgn in [+1, -1]:
			if delta == 0 and sgn == -1:
				continue
			var c: int = center + delta * sgn
			if c < 0 or c >= GameConfig.gate_columns:
				continue
			if heroes[c] == null:
				_spawn(hero_class, 1, c)
				return true
	# All slots filled — fall back to place_hero's merge/queue logic.
	return place_hero(hero_class, 1, center)

func place_hero(hero_class: String, tier: int, preferred_col: int) -> bool:
	# 1. Direct column merge.
	var existing: Hero = hero_at(preferred_col)
	if existing != null and existing.hero_class == hero_class and existing.tier == tier and existing.tier < 3:
		_promote(existing, preferred_col)
		return true
	# 2. Nearest empty (search outward).
	for delta in range(0, GameConfig.gate_columns):
		for sgn in [+1, -1]:
			if delta == 0 and sgn == -1:
				continue
			var c: int = preferred_col + delta * sgn
			if c < 0 or c >= GameConfig.gate_columns:
				continue
			if heroes[c] == null:
				_spawn(hero_class, tier, c)
				return true
	# 3. Adjacent merge (within ±2).
	for delta in [1, -1, 2, -2]:
		var c: int = preferred_col + delta
		if c < 0 or c >= GameConfig.gate_columns:
			continue
		var h: Hero = heroes[c]
		if h != null and h.hero_class == hero_class and h.tier == tier and h.tier < 3:
			_promote(h, c)
			return true
	# 4. Tier-upgrade replace (replace lowest existing tier, only if incoming > lowest).
	var lowest_col: int = -1
	var lowest_tier: int = 99
	for c in range(GameConfig.gate_columns):
		var h: Hero = heroes[c]
		if h == null:
			continue
		if h.tier < lowest_tier:
			lowest_tier = h.tier
			lowest_col = c
	if lowest_col != -1 and tier > lowest_tier:
		heroes[lowest_col].queue_free()
		heroes[lowest_col] = null
		_spawn(hero_class, tier, lowest_col)
		return true
	# 5. Queue.
	if queue.size() < QUEUE_MAX:
		queue.append({"hero_class": hero_class, "tier": tier})
		return true
	return false

func _spawn(hero_class: String, tier: int, col: int) -> void:
	var h: Hero = Hero.new()
	add_child(h)
	h.init_hero(hero_class, tier, col, gate, enemy_lane)
	h.position = Vector2(column_x_func.call(col), row_y)
	h.died_signal.connect(_on_hero_died)
	heroes[col] = h
	Telemetry.log_event("hero_freed", {"class": hero_class, "tier": tier, "col": col})

func _promote(h: Hero, col: int) -> void:
	h.promote_tier()
	Telemetry.log_event("hero_merge", {"class": h.hero_class, "tier": h.tier, "col": col})

func _on_hero_died(h: Hero) -> void:
	# If a participant in the open merge prompt dies (enemy kill), tear it down.
	if _merge_prompt_hero == h or _merge_partners.has(h):
		_close_merge_prompt()
	var col: int = h.column
	if col >= 0 and col < heroes.size() and heroes[col] == h:
		heroes[col] = null
	Telemetry.log_event("hero_death", {"col": col, "class": h.hero_class})
	emit_signal("hero_died", col)
	if not queue.is_empty():
		var next: Dictionary = queue.pop_front()
		_spawn(next.hero_class, next.tier, col)

# ─── Input (drag + click-to-merge — combat-design §2.4) ────────────
# Press records position; movement past CLICK_DEAD_ZONE promotes to drag,
# otherwise the release is treated as a click and may open the merge prompt.

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release(event.position)
	elif event is InputEventMouseMotion:
		_on_motion(event.position)

func _on_press(mp: Vector2) -> void:
	# Merge prompt takes precedence: tap the button to confirm, anywhere else dismisses.
	var was_open_hero: Hero = _merge_prompt_hero
	if _merge_prompt_hero != null:
		if _hit_merge_button(mp):
			_execute_merge()
			get_viewport().set_input_as_handled()
			return
		_close_merge_prompt()
	var c: int = _column_at(mp)
	if c < 0 or heroes[c] == null:
		return
	if abs(mp.y - row_y) > DRAG_Y_TOLERANCE:
		return
	_press_hero = heroes[c]
	_press_col = c
	_press_pos = mp
	_drag_started = false
	# Same-hero re-tap = close-only (don't reopen on release).
	_suppress_click_open = (was_open_hero != null and was_open_hero == _press_hero)
	get_viewport().set_input_as_handled()

func _on_motion(mp: Vector2) -> void:
	if _press_hero == null:
		return
	if not _drag_started and _press_pos.distance_to(mp) > CLICK_DEAD_ZONE:
		_drag_started = true
		_dragged = _press_hero
		_drag_from_col = _press_col
		_suppress_click_open = false   # this is a drag now, not a click
	if _drag_started and _dragged != null:
		_dragged.position = Vector2(mp.x, row_y)

func _on_release(mp: Vector2) -> void:
	if _drag_started and _dragged != null:
		_resolve_release(mp)
		_dragged = null
		_drag_from_col = -1
		_drag_started = false
		_press_hero = null
		_press_col = -1
		_suppress_click_open = false
		get_viewport().set_input_as_handled()
		return
	if _press_hero != null:
		if not _suppress_click_open and abs(mp.y - row_y) <= DRAG_Y_TOLERANCE:
			_try_open_merge_prompt(_press_hero)
		_press_hero = null
		_press_col = -1
		_suppress_click_open = false
		get_viewport().set_input_as_handled()

# ─── Click-to-merge prompt ─────────────────────────────────────────

func _try_open_merge_prompt(h: Hero) -> void:
	if h == null or not is_instance_valid(h) or h.tier >= 3:
		return
	var partners: Array = []
	for other in heroes:
		if other == null or other == h or not is_instance_valid(other):
			continue
		if other.hero_class == h.hero_class and other.tier == h.tier:
			partners.append(other)
	if partners.is_empty():
		return
	_merge_prompt_hero = h
	_merge_partners = partners
	_start_partner_pulse()
	queue_redraw()

func _close_merge_prompt() -> void:
	_stop_partner_pulse()
	_merge_prompt_hero = null
	_merge_partners.clear()
	queue_redraw()

func _hit_merge_button(mp: Vector2) -> bool:
	if _merge_prompt_hero == null or not is_instance_valid(_merge_prompt_hero):
		return false
	var center: Vector2 = _merge_button_center()
	var rect := Rect2(center - Vector2(MERGE_BUTTON_W, MERGE_BUTTON_H) * 0.5,
		Vector2(MERGE_BUTTON_W, MERGE_BUTTON_H))
	return rect.has_point(mp)

func _merge_button_center() -> Vector2:
	return _merge_prompt_hero.position + Vector2(0, MERGE_BUTTON_OFFSET_Y)

func _execute_merge() -> void:
	if _merge_prompt_hero == null or _merge_partners.is_empty():
		_close_merge_prompt()
		return
	var target: Hero = _merge_prompt_hero
	var partner: Hero = _nearest_partner(target, _merge_partners)
	_close_merge_prompt()
	if not is_instance_valid(target):
		return
	# Free the partner first so its slot opens for queue drain.
	if partner != null and is_instance_valid(partner):
		var col: int = partner.column
		if col >= 0 and col < heroes.size() and heroes[col] == partner:
			heroes[col] = null
		partner.queue_free()
		if not queue.is_empty():
			var next: Dictionary = queue.pop_front()
			_spawn(next.hero_class, next.tier, col)
	_promote(target, target.column)

func _nearest_partner(h: Hero, options: Array) -> Hero:
	var best: Hero = null
	var best_d: int = 99
	for p in options:
		if not is_instance_valid(p):
			continue
		var d: int = abs(p.column - h.column)
		if d < best_d:
			best_d = d
			best = p
	return best

func _start_partner_pulse() -> void:
	_stop_partner_pulse()
	for p in _merge_partners:
		if not is_instance_valid(p):
			continue
		# Bind tween to the partner so it auto-kills if the hero is freed.
		var tw: Tween = p.create_tween()
		tw.set_loops()
		tw.tween_property(p, "scale", Vector2(PARTNER_PULSE_SCALE, PARTNER_PULSE_SCALE), 0.45) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "scale", Vector2(1.0, 1.0), 0.45) \
			.set_trans(Tween.TRANS_SINE)
		_merge_partner_tweens.append(tw)

func _stop_partner_pulse() -> void:
	for tw in _merge_partner_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_merge_partner_tweens.clear()
	for p in _merge_partners:
		if is_instance_valid(p):
			p.scale = Vector2(1.0, 1.0)

# ─── Draw the floating MERGE pill ──────────────────────────────────

func _draw() -> void:
	if _merge_prompt_hero == null or not is_instance_valid(_merge_prompt_hero):
		return
	var hero_pos: Vector2 = _merge_prompt_hero.position
	var center: Vector2 = _merge_button_center()
	var size := Vector2(MERGE_BUTTON_W, MERGE_BUTTON_H)
	var rect := Rect2(center - size * 0.5, size)
	# Connector line from portrait-top to button-bottom.
	draw_line(hero_pos + Vector2(0, -75.0), center + Vector2(0, MERGE_BUTTON_H * 0.5),
		Color(1, 0.85, 0.30, 0.75), 2.0)
	# Pill background + border.
	_draw_rounded_pill(rect,
		Color(0.12, 0.10, 0.18, 0.94),
		Color(1, 0.85, 0.30, 0.95),
		14.0)
	# Label.
	var font: Font = ThemeDB.fallback_font
	var fs: int = 16
	var text := "MERGE"
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, center + Vector2(-ts.x * 0.5, ts.y * 0.32), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 0.96, 0.78, 1))

func _draw_rounded_pill(rect: Rect2, fill: Color, border: Color, radius: float) -> void:
	var r: float = min(radius, rect.size.y * 0.5)
	var inner := Rect2(rect.position + Vector2(r, 0), Vector2(rect.size.x - 2.0 * r, rect.size.y))
	draw_rect(inner, fill)
	var left_c: Vector2 = rect.position + Vector2(r, rect.size.y * 0.5)
	var right_c: Vector2 = rect.position + Vector2(rect.size.x - r, rect.size.y * 0.5)
	draw_circle(left_c, r, fill)
	draw_circle(right_c, r, fill)
	# Outline.
	var steps: int = 14
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t: float = PI * 0.5 + PI * float(i) / float(steps)
		pts.append(left_c + Vector2(cos(t), sin(t)) * r)
	for i in steps + 1:
		var t: float = -PI * 0.5 + PI * float(i) / float(steps)
		pts.append(right_c + Vector2(cos(t), sin(t)) * r)
	pts.append(pts[0])
	draw_polyline(pts, border, 2.0)

func _column_at(mp: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	for c in range(GameConfig.gate_columns):
		var x: float = column_x_func.call(c)
		var dx: float = abs(mp.x - x)
		if dx < best_d:
			best_d = dx
			best = c
	return best

func _resolve_release(mp: Vector2) -> void:
	var to_col: int = _column_at(mp)
	if to_col < 0 or to_col == _drag_from_col:
		_snap_to_col(_dragged, _drag_from_col)
		return
	var other: Hero = heroes[to_col]
	if other == null:
		heroes[_drag_from_col] = null
		heroes[to_col] = _dragged
		_dragged.column = to_col
		_snap_to_col(_dragged, to_col)
	elif other.hero_class == _dragged.hero_class and other.tier == _dragged.tier and _dragged.tier < 3:
		_promote(other, to_col)
		_dragged.queue_free()
		heroes[_drag_from_col] = null
	else:
		heroes[_drag_from_col] = other
		other.column = _drag_from_col
		_snap_to_col(other, _drag_from_col)
		heroes[to_col] = _dragged
		_dragged.column = to_col
		_snap_to_col(_dragged, to_col)

func _snap_to_col(h: Hero, col: int) -> void:
	h.position = Vector2(column_x_func.call(col), row_y)
