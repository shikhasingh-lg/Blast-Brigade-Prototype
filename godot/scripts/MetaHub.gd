extends Node2D
## Meta Hub = Stage Select (Sand Zone-style).
##
## Single-stage card browser: tap ◄ / ► to scrub through stages, Start to play.
## Locked stages still preview but Start is disabled. No world map, no gacha
## tabs — just stage → match → return.

const UI := preload("res://scripts/UICommon.gd")

# Stage card palette — different hues per stage so each one reads as a new
# location. Picked to match Sunbloom-meadow vibe at low stages, sand at mid,
# stone at boss-range.
const STAGE_BG_COLORS: Array[Color] = [
	Color(0.62, 0.84, 0.50),   # 1 — meadow
	Color(0.92, 0.78, 0.46),   # 2 — sand
	Color(0.78, 0.66, 0.42),   # 3 — dunes
	Color(0.56, 0.74, 0.92),   # 4 — sky
	Color(0.62, 0.50, 0.78),   # 5 — twilight
	Color(0.46, 0.68, 0.58),   # 6 — forest
	Color(0.86, 0.56, 0.46),   # 7 — clay
	Color(0.50, 0.62, 0.76),   # 8 — overcast
	Color(0.68, 0.84, 0.78),   # 9 — pond
	Color(0.74, 0.46, 0.58),   # 10 — bramble
]
const SKY_TOP: Color    = Color(0.46, 0.74, 0.96)
const SKY_BOT: Color    = Color(0.30, 0.56, 0.90)
const WATER_TOP: Color  = Color(0.24, 0.54, 0.84)
const WATER_BOT: Color  = Color(0.18, 0.40, 0.70)

var _vp: Vector2 = Vector2.ZERO
var stage_name_label: Label
var record_label: Label
var lineup_panel: Node2D
var start_btn: Button
var energy_chip: Node2D
var gold_chip: Node2D
var gems_chip: Node2D
var prev_btn: Button
var next_btn: Button
var _pulse_t: float = 0.0

func _ready() -> void:
	_vp = get_viewport_rect().size
	MetaState.viewing_stage = MetaState.current_stage
	_paint_background()
	_build_top_bar()
	_build_stage_header()
	_build_stage_card()
	_build_arrows()
	_build_lineup_panel()
	_build_start_button()
	_refresh()
	set_process(true)
	MetaState.currencies_changed.connect(_refresh)
	MetaState.stage_changed.connect(func(_s): _refresh())

func _process(dt: float) -> void:
	_pulse_t += dt
	if start_btn != null and not start_btn.disabled:
		# Subtle Start pulse so it reads as the obvious next tap.
		var s: float = 1.0 + 0.02 * sin(_pulse_t * 4.0)
		start_btn.scale = Vector2(s, s)

# ─── Background ─────────────────────────────────────────────────────────────
func _paint_background() -> void:
	# Sky gradient up top, water gradient bottom — matches reference image.
	var grad := Gradient.new()
	grad.set_color(0, SKY_TOP)
	grad.set_color(1, WATER_BOT)
	grad.add_point(0.42, SKY_BOT)
	grad.add_point(0.46, WATER_TOP)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 16
	gt.height = 512
	var bg := TextureRect.new()
	bg.texture = gt
	bg.position = Vector2.ZERO
	bg.size = _vp
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true
	add_child(bg)

	# Wave pattern on the water — simple sawtooth band.
	var wave_y: float = _vp.y * 0.45
	var wave_h: float = 22.0
	for x in range(0, int(_vp.x) + 30, 30):
		var tri := Polygon2D.new()
		tri.color = Color(0.36, 0.62, 0.88, 0.65)
		tri.polygon = PackedVector2Array([
			Vector2(x, wave_y),
			Vector2(x + 15, wave_y - wave_h * 0.6),
			Vector2(x + 30, wave_y),
		])
		add_child(tri)

# ─── Top bar (gold / energy / gems) ─────────────────────────────────────────
func _build_top_bar() -> void:
	var top_y: float = 22.0
	var chip_h: float = 50.0
	var gold_w: float = 130.0
	var energy_w: float = 150.0
	var gems_w: float = 130.0
	var pad: float = 12.0
	var total_w: float = gold_w + energy_w + gems_w + pad * 2.0
	var start_x: float = (_vp.x - total_w) * 0.5

	gold_chip = UI.make_currency_chip(
		Vector2(start_x, top_y), Vector2(gold_w, chip_h),
		"👑", str(MetaState.gold), UI.COLOR_GOLD)
	add_child(gold_chip)

	energy_chip = UI.make_currency_chip(
		Vector2(start_x + gold_w + pad, top_y), Vector2(energy_w, chip_h),
		"⚡", "%d/%d" % [MetaState.energy, MetaState.MAX_ENERGY], UI.COLOR_ENERGY)
	add_child(energy_chip)

	gems_chip = UI.make_currency_chip(
		Vector2(start_x + gold_w + energy_w + pad * 2.0, top_y), Vector2(gems_w, chip_h),
		"💎", str(MetaState.gems), UI.COLOR_GEM)
	add_child(gems_chip)

# ─── Stage header (name + best record) ─────────────────────────────────────
func _build_stage_header() -> void:
	stage_name_label = UI.add_label(self, Vector2(0, _vp.y * 0.10),
		"", 44, UI.COLOR_TEXT)
	stage_name_label.size = Vector2(_vp.x, 60)
	stage_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	record_label = UI.add_label(self, Vector2(0, _vp.y * 0.10 + 60),
		"", 24, Color(1, 1, 1, 0.95))
	record_label.size = Vector2(_vp.x, 32)
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ─── Stage card (placeholder image) ─────────────────────────────────────────
var card_inner: Node2D            # rebuilt on stage change
var _card_pos: Vector2 = Vector2.ZERO
var _card_size: Vector2 = Vector2.ZERO

func _build_stage_card() -> void:
	var card_w: float = _vp.x * 0.68
	var card_h: float = _vp.y * 0.22
	var card_x: float = (_vp.x - card_w) * 0.5
	var card_y: float = _vp.y * 0.20
	_card_pos = Vector2(card_x, card_y)
	_card_size = Vector2(card_w, card_h)
	# Wooden frame.
	var frame := UI.make_chip(_card_pos, _card_size, Color(0.62, 0.45, 0.28))
	add_child(frame)
	# Inner inset that holds the per-stage art.
	card_inner = Node2D.new()
	card_inner.position = _card_pos + Vector2(10, 10)
	add_child(card_inner)
	_render_stage_inner(card_inner, _card_size - Vector2(20, 20))

func _render_stage_inner(parent: Node2D, size: Vector2) -> void:
	# Clear children.
	for c in parent.get_children():
		c.queue_free()
	var stage: int = MetaState.viewing_stage
	var is_locked: bool = MetaState.is_stage_locked(stage)
	var palette: Color = STAGE_BG_COLORS[(stage - 1) % STAGE_BG_COLORS.size()]
	# Background fill of the inner art.
	var bg := Polygon2D.new()
	bg.color = palette if not is_locked else palette.darkened(0.45)
	bg.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y),
	])
	parent.add_child(bg)
	# Two stylized "cannon barrel" silhouettes at the bottom-front to reuse the
	# game's iconography. Drawn as simple ellipses.
	if not is_locked:
		_draw_inner_motif(parent, size, palette)
	else:
		_draw_lock_overlay(parent, size)

func _draw_inner_motif(parent: Node2D, size: Vector2, palette: Color) -> void:
	# A simple parallax horizon — far hill + cluster of bubbles to suggest stage.
	var hill_h: float = size.y * 0.40
	var hill := Polygon2D.new()
	hill.color = palette.darkened(0.18)
	hill.polygon = PackedVector2Array([
		Vector2(-10, size.y - hill_h),
		Vector2(size.x * 0.30, size.y - hill_h * 1.20),
		Vector2(size.x * 0.55, size.y - hill_h * 0.85),
		Vector2(size.x * 0.85, size.y - hill_h * 1.15),
		Vector2(size.x + 10, size.y - hill_h * 0.95),
		Vector2(size.x + 10, size.y + 10),
		Vector2(-10, size.y + 10),
	])
	parent.add_child(hill)
	# Bubble icons clustered in the upper area.
	var bubble_colors: Array[Color] = [
		Color(0.95, 0.42, 0.36),
		Color(0.36, 0.74, 0.98),
		Color(1.00, 0.86, 0.30),
	]
	var b_y: float = size.y * 0.35
	for i in range(6):
		var bx: float = size.x * (0.18 + 0.12 * i)
		var by: float = b_y + (8.0 * sin(float(i) * 0.9))
		var col: Color = bubble_colors[i % bubble_colors.size()]
		var bubble := Node2D.new()
		bubble.position = Vector2(bx, by)
		parent.add_child(bubble)
		var inner := Polygon2D.new()
		inner.color = col
		var r: float = 14.0
		var pts := PackedVector2Array()
		for k in range(20):
			var a: float = TAU * float(k) / 20.0
			pts.append(Vector2(cos(a) * r, sin(a) * r))
		inner.polygon = pts
		bubble.add_child(inner)

func _draw_lock_overlay(parent: Node2D, size: Vector2) -> void:
	var dim := Polygon2D.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y),
	])
	parent.add_child(dim)
	# Big padlock icon.
	var lock_lbl: Label = UI.make_label("🔒", 96, Color(1, 1, 1, 0.92))
	lock_lbl.position = Vector2(size.x * 0.5 - 50, size.y * 0.5 - 60)
	lock_lbl.size = Vector2(100, 100)
	lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lock_lbl)
	var hint: Label = UI.make_label("Clear stage %d first" % MetaState.current_stage,
		18, Color(1, 1, 1, 0.75))
	hint.position = Vector2(0, size.y * 0.5 + 50)
	hint.size = Vector2(size.x, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(hint)

# ─── Arrows ─────────────────────────────────────────────────────────────────
func _build_arrows() -> void:
	var btn_h: float = 64.0
	var mid_y: float = _card_pos.y + _card_size.y * 0.5 - btn_h * 0.5
	prev_btn = UI.make_button("◄", Vector2(48, btn_h), Color(0.16, 0.20, 0.30))
	prev_btn.add_theme_font_size_override("font_size", 28)
	prev_btn.position = Vector2(_card_pos.x - 58, mid_y)
	prev_btn.pressed.connect(_on_prev_pressed)
	add_child(prev_btn)
	next_btn = UI.make_button("►", Vector2(48, btn_h), Color(0.16, 0.20, 0.30))
	next_btn.add_theme_font_size_override("font_size", 28)
	next_btn.position = Vector2(_card_pos.x + _card_size.x + 10, mid_y)
	next_btn.pressed.connect(_on_next_pressed)
	add_child(next_btn)

func _on_prev_pressed() -> void:
	if MetaState.viewing_stage > 1:
		MetaState.viewing_stage -= 1
		_refresh()

func _on_next_pressed() -> void:
	if MetaState.viewing_stage < MetaState.TOTAL_STAGES:
		MetaState.viewing_stage += 1
		_refresh()

# ─── Line-up panel ─────────────────────────────────────────────────────────
var lineup_root: Node2D
func _build_lineup_panel() -> void:
	var panel_w: float = _vp.x - 64.0
	var panel_h: float = 220.0
	var panel_x: float = 32.0
	var panel_y: float = _vp.y * 0.50
	# Title tab.
	var tab_w: float = 200.0
	var tab_h: float = 36.0
	var tab := UI.make_chip(Vector2(panel_x + (panel_w - tab_w) * 0.5, panel_y - tab_h * 0.5),
		Vector2(tab_w, tab_h), Color(0.16, 0.22, 0.36, 1.0))
	add_child(tab)
	var tab_lbl: Label = UI.make_label("Line-up", 20, Color(1, 1, 1, 0.95))
	tab_lbl.position = Vector2(0, 4)
	tab_lbl.size = Vector2(tab_w, 26)
	tab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.add_child(tab_lbl)
	# Panel body.
	var body := UI.make_chip(Vector2(panel_x, panel_y + tab_h * 0.5),
		Vector2(panel_w, panel_h - tab_h * 0.5), Color(0.16, 0.22, 0.36, 0.95))
	add_child(body)
	lineup_root = Node2D.new()
	lineup_root.position = Vector2(panel_x + 16, panel_y + tab_h * 0.5 + 16)
	add_child(lineup_root)
	_render_lineup(lineup_root, Vector2(panel_w - 32, panel_h - tab_h * 0.5 - 32))

func _render_lineup(parent: Node2D, size: Vector2) -> void:
	for c in parent.get_children():
		c.queue_free()
	# Power score row.
	var power_lbl: Label = UI.make_label("⚔  41.4K", 22, UI.COLOR_TEXT)
	power_lbl.position = Vector2(8, 0)
	power_lbl.size = Vector2(200, 30)
	parent.add_child(power_lbl)

	# 5 slots. Heroes fill left→right from the stage's lineup; remaining slots
	# show as LOCKED. So stage 1 (3 heroes) shows 3 unlocked + 2 locked, etc.
	var slot_count: int = 5
	var slot_w: float = (size.x - 10.0 * (slot_count - 1)) / float(slot_count)
	var slot_h: float = size.y - 50.0
	var slot_y: float = 40.0
	var lineup: Array = MetaState.lineup_for_stage(MetaState.viewing_stage)
	var is_locked_stage: bool = MetaState.is_stage_locked(MetaState.viewing_stage)
	for i in range(slot_count):
		var sx: float = i * (slot_w + 10.0)
		var slot_holder: Node2D = UI.make_chip(Vector2(sx, slot_y),
			Vector2(slot_w, slot_h), Color(0.30, 0.42, 0.48))
		parent.add_child(slot_holder)
		var slot_locked: bool = is_locked_stage or i >= lineup.size()
		if slot_locked:
			var dim := Polygon2D.new()
			dim.color = Color(0.10, 0.13, 0.20, 0.85)
			dim.polygon = PackedVector2Array([
				Vector2(0, 0), Vector2(slot_w, 0),
				Vector2(slot_w, slot_h), Vector2(0, slot_h),
			])
			slot_holder.add_child(dim)
			var lock_icon: Label = UI.make_label("🔒", 36, Color(1, 1, 1, 0.70))
			lock_icon.position = Vector2(slot_w * 0.5 - 22, slot_h * 0.5 - 26)
			lock_icon.size = Vector2(44, 44)
			lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot_holder.add_child(lock_icon)
		else:
			var hero_idx: int = i
			if hero_idx < lineup.size():
				var entry: Array = lineup[hero_idx]
				var hero_id: String = entry[0]
				var hero_color: Color = entry[1]
				# Hero "portrait" — coloured chip + initial label.
				var portrait := Polygon2D.new()
				portrait.color = hero_color
				var pad_x: float = 8.0
				var pad_y: float = 8.0
				portrait.polygon = PackedVector2Array([
					Vector2(pad_x, pad_y),
					Vector2(slot_w - pad_x, pad_y),
					Vector2(slot_w - pad_x, slot_h - pad_y - 22),
					Vector2(pad_x, slot_h - pad_y - 22),
				])
				slot_holder.add_child(portrait)
				var initial: Label = UI.make_label(hero_id, 28, Color.WHITE)
				initial.position = Vector2(0, pad_y + 12)
				initial.size = Vector2(slot_w, 40)
				initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				slot_holder.add_child(initial)
				# Level chip at the bottom.
				var lvl_lbl: Label = UI.make_label("Lv.%d" % (1 + (hero_idx % 3)),
					16, Color(1, 1, 1, 0.95))
				lvl_lbl.position = Vector2(0, slot_h - 22)
				lvl_lbl.size = Vector2(slot_w, 20)
				lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				slot_holder.add_child(lvl_lbl)
			else:
				# Empty unlocked slot.
				var plus_lbl: Label = UI.make_label("+", 40, Color(1, 1, 1, 0.55))
				plus_lbl.position = Vector2(0, slot_h * 0.5 - 28)
				plus_lbl.size = Vector2(slot_w, 44)
				plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				slot_holder.add_child(plus_lbl)

# ─── Start button ──────────────────────────────────────────────────────────
func _build_start_button() -> void:
	var btn_w: float = _vp.x * 0.62
	var btn_h: float = 110.0
	var btn_x: float = (_vp.x - btn_w) * 0.5
	var btn_y: float = _vp.y - btn_h - 60.0
	start_btn = UI.make_button("⚔  Start    ⚡ -%d" % MetaState.STAGE_ENERGY_COST,
		Vector2(btn_w, btn_h), UI.COLOR_SUCCESS)
	start_btn.add_theme_font_size_override("font_size", 30)
	start_btn.position = Vector2(btn_x, btn_y)
	start_btn.pivot_offset = Vector2(btn_w * 0.5, btn_h * 0.5)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

func _on_start_pressed() -> void:
	var stage: int = MetaState.viewing_stage
	if MetaState.is_stage_locked(stage):
		return
	if MetaState.energy < MetaState.STAGE_ENERGY_COST:
		return
	MetaState.select_stage(stage)
	MetaState.spend_energy_for_stage()
	MetaState.reset_last_run()
	get_tree().change_scene_to_file("res://scenes/MatchScene.tscn")

# ─── Refresh ───────────────────────────────────────────────────────────────
func _refresh() -> void:
	var stage: int = MetaState.viewing_stage
	var stage_name: String = MetaState.stage_name_for(stage)
	stage_name_label.text = "%d. %s" % [stage, stage_name]
	var best: int = MetaState.best_wave_for_stage(stage)
	record_label.text = "Highest record: %d" % best if best > 0 else "Highest record: —"

	if card_inner != null:
		_render_stage_inner(card_inner, _card_size - Vector2(20, 20))
	if lineup_root != null:
		var panel_w: float = _vp.x - 64.0
		var panel_h: float = 220.0
		_render_lineup(lineup_root, Vector2(panel_w - 32, panel_h - 36 * 0.5 - 32))

	# Currency chips.
	_set_chip_value(energy_chip, "%d/%d" % [MetaState.energy, MetaState.MAX_ENERGY])
	_set_chip_value(gold_chip, str(MetaState.gold))
	_set_chip_value(gems_chip, str(MetaState.gems))

	# Arrow enable/disable.
	if prev_btn != null:
		prev_btn.disabled = stage <= 1
	if next_btn != null:
		next_btn.disabled = stage >= MetaState.TOTAL_STAGES

	# Start button: disabled if locked or out of energy.
	if start_btn != null:
		var is_locked: bool = MetaState.is_stage_locked(stage)
		var out_of_energy: bool = MetaState.energy < MetaState.STAGE_ENERGY_COST
		if is_locked:
			start_btn.disabled = true
			start_btn.text = "🔒  LOCKED"
		elif out_of_energy:
			start_btn.disabled = true
			start_btn.text = "OUT OF ENERGY"
		else:
			start_btn.disabled = false
			start_btn.text = "⚔  Start    ⚡ -%d" % MetaState.STAGE_ENERGY_COST

func _set_chip_value(chip: Node2D, value: String) -> void:
	if chip == null:
		return
	# Currency chip children: stroke(0), body(1), icon(2), value(3).
	var lbl: Label = chip.get_child(3) as Label
	if lbl != null:
		lbl.text = value
