extends Node2D
## Run Fail / Stage Failed — per ui-spec §3.10.
##
## Shown after MatchScene reports a non-win run_ended. REVIVE for gems (once
## per run) or END RUN → back to MetaHub. Energy was consumed at stage start
## regardless.

const UI := preload("res://scripts/UICommon.gd")
const REVIVE_COST_GEMS: int = 50

var _vp: Vector2 = Vector2.ZERO

func _ready() -> void:
	_vp = get_viewport_rect().size
	# Cool dim sky for defeat — desaturated, cooler hue.
	add_child(UI.make_sky(_vp,
		Color(0.10, 0.14, 0.22),
		Color(0.22, 0.26, 0.36),
		Color(0.50, 0.36, 0.38)))
	_build_title()
	_build_summary()
	_build_revive_card()
	_build_partial_rewards()
	_build_end_button()

func _build_title() -> void:
	var skull := UI.add_label(self, Vector2(0, _vp.y * 0.08),
		"💀", 96, UI.COLOR_TEXT)
	skull.size = Vector2(_vp.x, 110)
	skull.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var title := UI.add_label(self, Vector2(0, _vp.y * 0.20),
		"RUN FAILED", 52, UI.COLOR_DANGER)
	title.size = Vector2(_vp.x, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var stage_lbl := UI.add_label(self, Vector2(0, _vp.y * 0.27),
		"Stage %d" % MetaState.current_stage, 24, UI.COLOR_TEXT_DIM)
	stage_lbl.size = Vector2(_vp.x, 32)
	stage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_summary() -> void:
	var card_w: float = _vp.x - 64.0
	var card_h: float = 110.0
	var card_x: float = 32.0
	var card_y: float = _vp.y * 0.34
	var card := UI.make_panel(Vector2(card_x, card_y), Vector2(card_w, card_h))
	add_child(card)
	var top_edge := ColorRect.new()
	top_edge.color = Color(0.92, 0.42, 0.40, 0.95)
	top_edge.position = Vector2(card_x, card_y)
	top_edge.size = Vector2(card_w, 4)
	add_child(top_edge)

	var wave_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 16),
		"Wave %d / %d" % [MetaState.last_run_wave_reached, GameConfig.num_waves],
		22, UI.COLOR_TEXT)
	wave_lbl.size = Vector2(card_w - 48, 28)

	var cause: String = ""
	match MetaState.last_run_result:
		"lose": cause = "Cause: base HP 0"
		"stall_loss": cause = "Cause: out of moves"
		_: cause = "Cause: run ended"
	var cause_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 52),
		cause, 18, UI.COLOR_TEXT_DIM)
	cause_lbl.size = Vector2(card_w - 48, 24)

	var stats_lbl := UI.add_label(self, Vector2(card_x + 24, card_y + 80),
		"Damage %d   Bubbles %d" % [
			MetaState.last_run_damage_dealt, MetaState.last_run_bubbles_popped],
		15, UI.COLOR_TEXT_DIM)
	stats_lbl.size = Vector2(card_w - 48, 22)

func _build_revive_card() -> void:
	var card_w: float = _vp.x - 64.0
	var card_h: float = 130.0
	var card_x: float = 32.0
	var card_y: float = _vp.y * 0.50
	var card := UI.make_panel(Vector2(card_x, card_y), Vector2(card_w, card_h),
		Color(0.16, 0.22, 0.36, 0.92))
	add_child(card)
	var top_edge := ColorRect.new()
	top_edge.color = UI.COLOR_GEM
	top_edge.position = Vector2(card_x, card_y)
	top_edge.size = Vector2(card_w, 4)
	add_child(top_edge)

	var rev_label := UI.add_label(self, Vector2(card_x + 24, card_y + 14),
		"REVIVE for 💎 %d" % REVIVE_COST_GEMS, 22, UI.COLOR_GEM)
	rev_label.size = Vector2(card_w - 48, 28)

	var rev_hint := UI.add_label(self, Vector2(card_x + 24, card_y + 46),
		"Restart from wave %d, full HP, half heroes" % MetaState.last_run_wave_reached,
		15, UI.COLOR_TEXT_DIM)
	# last_run_wave_reached is the 1-based wave the player died on (see MetaState.record_loss).
	rev_hint.size = Vector2(card_w - 48, 22)

	var btn_w: float = card_w - 48.0
	var btn_h: float = 52.0
	var btn: Button = UI.make_button("REVIVE", Vector2(btn_w, btn_h),
		Color(0.36, 0.74, 0.98))
	btn.add_theme_font_size_override("font_size", 22)
	btn.position = Vector2(card_x + 24, card_y + card_h - btn_h - 10.0)
	var can_revive: bool = (MetaState.gems >= REVIVE_COST_GEMS
		and not MetaState.last_run_revive_used
		and MetaState.last_run_result != "win")
	btn.disabled = not can_revive
	if not can_revive:
		if MetaState.last_run_revive_used:
			btn.text = "REVIVE USED"
		elif MetaState.gems < REVIVE_COST_GEMS:
			btn.text = "NOT ENOUGH GEMS"
	btn.pressed.connect(_on_revive_pressed)
	add_child(btn)

func _build_partial_rewards() -> void:
	var y: float = _vp.y * 0.69
	var lbl := UI.add_label(self, Vector2(0, y),
		"Keep what you earned:", 18, UI.COLOR_TEXT_DIM)
	lbl.size = Vector2(_vp.x, 24)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var xp_lbl := UI.add_label(self, Vector2(0, y + 28),
		"⭐  +%d XP" % MetaState.PARTIAL_XP, 18, UI.COLOR_TEXT)
	xp_lbl.size = Vector2(_vp.x, 24)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var gold_lbl := UI.add_label(self, Vector2(0, y + 54),
		"💰  +%d gold" % MetaState.PARTIAL_GOLD, 18, UI.COLOR_GOLD)
	gold_lbl.size = Vector2(_vp.x, 24)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_end_button() -> void:
	var btn_w: float = _vp.x * 0.72
	var btn_h: float = 76.0
	var btn_x: float = (_vp.x - btn_w) * 0.5
	var btn_y: float = _vp.y * 0.86
	var btn: Button = UI.make_button("✕  END RUN", Vector2(btn_w, btn_h),
		Color(0.42, 0.18, 0.22))
	btn.position = Vector2(btn_x, btn_y)
	btn.pressed.connect(_on_end_pressed)
	add_child(btn)

func _on_revive_pressed() -> void:
	if MetaState.gems < REVIVE_COST_GEMS:
		return
	MetaState.gems -= REVIVE_COST_GEMS
	MetaState.last_run_revive_used = true
	MetaState.emit_signal("currencies_changed")
	# Restart the match. RunState resets on its own.
	get_tree().change_scene_to_file("res://scenes/MatchScene.tscn")

func _on_end_pressed() -> void:
	MetaState.apply_loss_partial_rewards()
	# Save best wave reached so the Stage Select card shows progress even on a loss.
	MetaState.record_best_wave(MetaState.current_stage,
		MetaState.last_run_wave_reached)
	get_tree().change_scene_to_file("res://scenes/MetaHub.tscn")
