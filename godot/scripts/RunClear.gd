extends Node2D
## Run Clear / Stage Pass — per ui-spec §3.9.
##
## Reads MetaState.last_run_* for summary. CONTINUE applies rewards then routes
## back to MetaHub (stage select). Sparkle layer + counter tick-up gives the
## "you won" payoff.

const UI := preload("res://scripts/UICommon.gd")

var _vp: Vector2 = Vector2.ZERO
var damage_label: Label
var bubbles_label: Label
var xp_label: Label
var gold_label: Label
var _counter_t: float = 0.0
var _counter_duration: float = 0.9
var _displayed_damage: int = 0
var _displayed_bubbles: int = 0
var _displayed_xp: int = 0
var _displayed_gold: int = 0
var _sparkle_t: float = 0.0
var _sparkles: Array[Dictionary] = []

func _ready() -> void:
	_vp = get_viewport_rect().size
	add_child(UI.make_sky(_vp,
		Color(0.16, 0.30, 0.50),
		Color(0.36, 0.62, 0.86),
		Color(0.96, 0.86, 0.46)))
	_spawn_sparkles()
	_build_title()
	_build_summary()
	_build_rewards()
	_build_continue()
	set_process(true)

func _spawn_sparkles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(28):
		_sparkles.append({
			"pos": Vector2(rng.randf_range(20.0, _vp.x - 20.0),
				rng.randf_range(80.0, _vp.y * 0.35)),
			"phase": rng.randf_range(0.0, TAU),
			"size": rng.randf_range(3.0, 7.0),
			"hue": rng.randf_range(0.0, 1.0),
		})

func _build_title() -> void:
	var stage: int = MetaState.current_stage
	var title := UI.add_label(self, Vector2(0, _vp.y * 0.10),
		"STAGE %d CLEAR" % stage, 54, UI.COLOR_SUCCESS)
	title.size = Vector2(_vp.x, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Three stars (placeholder — all gold for now).
	var stars_y: float = _vp.y * 0.10 + 80.0
	var star_size: float = 32.0
	for i in range(3):
		var sx: float = _vp.x * 0.5 - star_size * 1.7 + i * (star_size + 12.0)
		var st := UI.make_label("★", 42, UI.COLOR_GOLD)
		st.position = Vector2(sx, stars_y)
		add_child(st)

func _build_summary() -> void:
	var card_w: float = _vp.x - 64.0
	var card_h: float = 200.0
	var card_x: float = 32.0
	var card_y: float = _vp.y * 0.28
	var card := UI.make_panel(Vector2(card_x, card_y), Vector2(card_w, card_h))
	add_child(card)
	var top_edge := ColorRect.new()
	top_edge.color = Color(0.55, 0.85, 0.55, 0.85)
	top_edge.position = Vector2(card_x, card_y)
	top_edge.size = Vector2(card_w, 4)
	add_child(top_edge)

	var hdr := UI.add_label(self, Vector2(card_x + 24, card_y + 14),
		"Run summary", 22, UI.COLOR_TEXT)
	hdr.size = Vector2(card_w - 48, 28)

	damage_label = UI.add_label(self, Vector2(card_x + 24, card_y + 52),
		"Damage dealt:    0", 18, UI.COLOR_TEXT_DIM)
	damage_label.size = Vector2(card_w - 48, 24)

	bubbles_label = UI.add_label(self, Vector2(card_x + 24, card_y + 84),
		"Bubbles popped:  0", 18, UI.COLOR_TEXT_DIM)
	bubbles_label.size = Vector2(card_w - 48, 24)

	var mvp_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 116),
		"MVP: %s (%d dmg)" % [MetaState.last_run_mvp_hero, MetaState.last_run_mvp_damage],
		18, UI.COLOR_GOLD)
	mvp_lbl.size = Vector2(card_w - 48, 24)

	var time_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 148),
		"Waves cleared: %d / %d" % [MetaState.last_run_wave_reached, GameConfig.num_waves],
		16, UI.COLOR_TEXT_DIM)
	time_lbl.size = Vector2(card_w - 48, 22)

func _build_rewards() -> void:
	var card_w: float = _vp.x - 64.0
	var card_h: float = 200.0
	var card_x: float = 32.0
	var card_y: float = _vp.y * 0.53
	var card := UI.make_panel(Vector2(card_x, card_y), Vector2(card_w, card_h))
	add_child(card)
	var top_edge := ColorRect.new()
	top_edge.color = Color(1, 0.86, 0.36, 0.95)
	top_edge.position = Vector2(card_x, card_y)
	top_edge.size = Vector2(card_w, 4)
	add_child(top_edge)

	var hdr := UI.add_label(self, Vector2(card_x + 24, card_y + 14),
		"Rewards", 22, UI.COLOR_TEXT)
	hdr.size = Vector2(card_w - 48, 28)

	xp_label = UI.add_label(self, Vector2(card_x + 24, card_y + 52),
		"⭐  +0 XP", 18, UI.COLOR_TEXT)
	xp_label.size = Vector2(card_w - 48, 24)

	gold_label = UI.add_label(self, Vector2(card_x + 24, card_y + 84),
		"💰  +0 gold", 18, UI.COLOR_GOLD)
	gold_label.size = Vector2(card_w - 48, 24)

	var stage: int = MetaState.current_stage
	var first_clear: bool = stage > MetaState.highest_cleared
	var gem_label_text: String = "💎  +%d gem" % MetaState.REWARD_GEM_FIRST_CLEAR
	if not first_clear:
		gem_label_text = "💎  — (first clear only)"
	var gem_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 116),
		gem_label_text, 18,
		UI.COLOR_GEM if first_clear else UI.COLOR_TEXT_DIM)
	gem_lbl.size = Vector2(card_w - 48, 24)

	var chest_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 148),
		"🃏  Stage chest  (tap to open)", 18, UI.COLOR_TEXT_DIM)
	chest_lbl.size = Vector2(card_w - 48, 24)

func _build_continue() -> void:
	var btn_w: float = _vp.x * 0.72
	var btn_h: float = 80.0
	var btn_x: float = (_vp.x - btn_w) * 0.5
	var btn_y: float = _vp.y * 0.84
	var btn: Button = UI.make_button("▶  CONTINUE", Vector2(btn_w, btn_h), UI.COLOR_SUCCESS)
	btn.position = Vector2(btn_x, btn_y)
	btn.pressed.connect(_on_continue_pressed)
	add_child(btn)

# ── Animated counters + sparkles ────────────────────────────────────────────
func _process(dt: float) -> void:
	_sparkle_t += dt
	_counter_t = min(_counter_t + dt, _counter_duration)
	var u: float = _counter_t / _counter_duration
	# Ease-out cubic.
	var eu: float = 1.0 - pow(1.0 - u, 3.0)
	_displayed_damage = int(round(MetaState.last_run_damage_dealt * eu))
	_displayed_bubbles = int(round(MetaState.last_run_bubbles_popped * eu))
	_displayed_xp = int(round(MetaState.REWARD_XP * eu))
	_displayed_gold = int(round(MetaState.REWARD_GOLD * eu))
	if damage_label != null:
		damage_label.text = "Damage dealt:    %d" % _displayed_damage
	if bubbles_label != null:
		bubbles_label.text = "Bubbles popped:  %d" % _displayed_bubbles
	if xp_label != null:
		xp_label.text = "⭐  +%d XP" % _displayed_xp
	if gold_label != null:
		gold_label.text = "💰  +%d gold" % _displayed_gold
	queue_redraw()

func _draw() -> void:
	# Sparkles drifting over the top section.
	for s in _sparkles:
		var phase: float = float(s["phase"]) + _sparkle_t * 2.0
		var a: float = 0.4 + 0.4 * sin(phase)
		var c := Color.from_hsv(float(s["hue"]), 0.30, 1.0, a)
		var pos := Vector2(s["pos"])
		var size: float = float(s["size"])
		# 4-point diamond as a small "sparkle" shape.
		var pts := PackedVector2Array([
			pos + Vector2(0, -size),
			pos + Vector2(size, 0),
			pos + Vector2(0, size),
			pos + Vector2(-size, 0),
		])
		draw_colored_polygon(pts, c)

func _on_continue_pressed() -> void:
	# Apply rewards (advances highest_cleared, increments stage, awards XP/gold/gem).
	MetaState.apply_win_rewards()
	# Record best wave for this stage so the Stage Select card shows it.
	MetaState.record_best_wave(MetaState.last_stage_cleared_this_session,
		GameConfig.num_waves)
	get_tree().change_scene_to_file("res://scenes/MetaHub.tscn")
