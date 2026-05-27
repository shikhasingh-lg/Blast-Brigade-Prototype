extends Node2D
## MatchScene — gameplay root.
##
## Phase 1: gate seed + cannon + match/pop.
## Phase 2: + enemy depth lane (telegraph, walk, breach, base damage).
## Phase 4: 5-wave loop — intermission overlay + run-end overlay + stall-loss detection.
## Press R to reseed gate. Press N to advance wave. Press K to kill all enemies (debug).

## Layout (flipped vs spec §1.1 — concept.md ASCII is authoritative here).
## Gate hangs from the sky at the top; lane is the perspective ground in front
## of the gate stretching toward the camera; heroes near the bottom; cannon at
## the player POV. Enemies materialize at the gate base, then emerge into the
## lane and walk DOWN toward the camera (growing in scale).
const GATE_TOP_PCT: float = 0.042  # bubble top edge ≈ y=62, flush with HUD chip bottom (no gap)
const LANE_TOP_PCT: float = 0.32      # shortened lane (0.32→0.78 = 16/20 of prior 0.20→0.78 span)
const LANE_BOTTOM_PCT: float = 0.78   # = hero row top, pushed down for depth
const HERO_ROW_TOP_PCT: float = 0.78
const CANNON_Y_PCT: float = 0.92

## Sky palette — sampled from the mockup's painted background (sky → warm horizon
## glow above the lane). We paint this procedurally so the baked-in lane / heroes /
## cannon from the mockup composite don't ghost through behind the real game nodes.
const SKY_TOP: Color = Color(0.46, 0.74, 0.93)
const SKY_MID: Color = Color(0.99, 0.85, 0.60)
const SKY_HORIZON: Color = Color(1.00, 0.74, 0.48)
const SUN_COLOR: Color = Color(1.00, 0.95, 0.62, 0.95)

var gate: Gate
var enemy_lane: EnemyLane
var lane_backdrop: LaneBackdrop
const BASE_PLATFORM_SCRIPT: GDScript = preload("res://scripts/BasePlatform.gd")
const BombProjectileScript: GDScript = preload("res://scripts/BombProjectile.gd")
var cannon: Cannon
var base_platform: Node2D
var hero_row: HeroRow
var hud: Label                          # legacy debug label kept as bottom-of-screen hint
var hud_wave_label: Label               # "W 2/5" inside the yellow wave chip
var hud_moves_label: Label              # legacy — not shown in Blast Brigade
var hud_enemies_label: Label            # debug-only tiny line (alive/queued counts)
var hud_hp_bar_fill: ColorRect          # green fill rect we shrink as base HP drops
var hud_hp_bar_fill_w: float = 0.0      # full-width pixels of the green fill region (computed once)
var hud_hp_label: Label                 # "HP  87%" overlay text on the bar
var hud_energy_label: Label             # number next to lightning chip
# Blast Brigade — currency HUD chip + spawn button.
var hud_currency_label: Label = null
var spawn_button_root: Node2D = null
var spawn_button_label: Label = null
var spawn_button_cost_label: Label = null
var spawn_button_bg: Polygon2D = null
var spawn_button_rect: Rect2 = Rect2()
var _spawn_btn_flash_t: float = 0.0
var active_projectile: Projectile = null
var _vp: Vector2 = Vector2.ZERO
var _wave_start_time: float = 0.0
var _moves_used_this_wave: int = 0
# Run summary tally — fed into MetaState on run_ended so RunClear/RunFail can
# show real numbers instead of placeholders.
var _bubbles_popped_total: int = 0

# Phase 4 — intermission + run-end overlays.
var intermission_overlay: CanvasLayer
var intermission_title: Label
var intermission_preview: Label
var intermission_countdown_bar: ColorRect
var intermission_countdown_bg: ColorRect
var _intermission_elapsed: float = 0.0
var _pre_run_active: bool = false      # legacy flag, kept for countdown-bar branch
var _pre_wave_grace_t: float = 0.0     # seconds remaining before enemy_lane.begin_wave fires
var pre_wave_label: Label = null       # in-scene non-blocking "WAVE 1 IN N" countdown
var _gate_field_cleared: bool = false  # fade_clear_all already fired this wave
var _stall_timer: float = 0.0
const STALL_GRACE_SEC: float = 1.5
var runend_overlay: CanvasLayer
var runend_title: Label
var runend_subtitle: Label

func _ready() -> void:
	_vp = get_viewport_rect().size
	_install_camera()
	_paint_background()
	_build_lane_backdrop()

	# Z-order: background → backdrop → lane (far) → gate (mid) → heroes/cannon (front).
	_build_enemy_lane()
	_build_gate_base_band()
	_build_gate()
	_build_hero_row()
	_build_base_platform()
	_build_cannon()
	_build_hud()
	_build_intermission_overlay()
	_build_runend_overlay()

	# Blast Brigade — bubble pop / hero-free signals are no-ops in this fork
	# (gate is kept in scene only to keep column-x geometry helpers wired).
	cannon.fired.connect(_on_cannon_fired)
	enemy_lane.enemy_reached_base.connect(_on_enemy_reached_base)
	enemy_lane.wave_cleared.connect(_on_wave_cleared)

	RunState.wave_changed.connect(_on_wave_changed)
	RunState.moves_changed.connect(_on_moves_changed)
	RunState.base_hp_changed.connect(_on_base_hp_changed)
	RunState.currency_changed.connect(_on_currency_changed)
	RunState.intermission_started.connect(_on_intermission_started)
	RunState.intermission_ended.connect(_on_intermission_ended)
	RunState.run_ended.connect(_on_run_ended)

	# Drop straight into the match. Gate seeds immediately so the player can
	# shoot; enemy_lane.begin_wave is deferred for `pre_run_countdown_sec` on
	# wave 0 so they get a free shooting window before the first telegraph.
	# An in-scene countdown label (non-blocking) shows the remaining seconds.
	_build_pre_wave_countdown_label()
	RunState.start_run()

func _install_camera() -> void:
	# Centered Camera2D so VFX.shake() has something to wiggle. With camera at
	# viewport center, the visible region matches the previous no-camera setup
	# (origin at top-left, world units == pixels). HUD lives on CanvasLayer so
	# it won't shake; world nodes (cannon, enemies, gate, lane) will.
	var cam := Camera2D.new()
	cam.name = "MainCamera"
	cam.position = _vp * 0.5
	cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()

func _paint_background() -> void:
	# Vertical sky gradient: sky blue at top → peach mid → warm orange just above
	# the lane horizon. Replaces the v2-b mockup composite, which had the lane /
	# heroes / cannon baked in and was bleeding through behind the real nodes.
	var grad := Gradient.new()
	grad.set_color(0, SKY_TOP)
	grad.set_color(1, SKY_HORIZON)
	grad.add_point(0.65, SKY_MID)

	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 16
	gt.height = 512

	var sky := TextureRect.new()
	sky.texture = gt
	sky.position = Vector2.ZERO
	sky.size = _vp
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	# Soft sun glow centered above the lane horizon — radial gradient, no rays.
	var sun_radius: float = _vp.x * 0.42
	var sun_grad := Gradient.new()
	sun_grad.set_color(0, SUN_COLOR)
	sun_grad.set_color(1, Color(SUN_COLOR.r, SUN_COLOR.g, SUN_COLOR.b, 0.0))
	var sun_tex := GradientTexture2D.new()
	sun_tex.gradient = sun_grad
	sun_tex.fill = GradientTexture2D.FILL_RADIAL
	sun_tex.fill_from = Vector2(0.5, 0.5)
	sun_tex.fill_to = Vector2(1.0, 0.5)
	sun_tex.width = 256
	sun_tex.height = 256
	var sun := TextureRect.new()
	sun.texture = sun_tex
	sun.size = Vector2(sun_radius * 2.0, sun_radius * 2.0)
	sun.position = Vector2(_vp.x * 0.5 - sun_radius, _vp.y * LANE_TOP_PCT - sun_radius * 0.85)
	sun.stretch_mode = TextureRect.STRETCH_SCALE
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sun)
func _build_lane_backdrop() -> void:
	lane_backdrop = LaneBackdrop.new()
	add_child(lane_backdrop)
	# Narrow end (top, near gate base): slightly inset from gate width so the
	# lane reads as "ground past the wall starts here." Wide end (bottom): a bit
	# wider than gate for stronger perspective at the camera-near side.
	var gate_w: float = GameConfig.gate_columns * Gate.CELL
	var narrow_w: float = gate_w * 0.55
	var wide_w: float = gate_w * 1.35
	var narrow_left: float = (_vp.x - narrow_w) * 0.5
	var narrow_right: float = narrow_left + narrow_w
	var wide_left: float = (_vp.x - wide_w) * 0.5
	var wide_right: float = wide_left + wide_w
	lane_backdrop.configure(
		_vp.y * LANE_TOP_PCT,         # narrow end (at gate base)
		_vp.y * LANE_BOTTOM_PCT,      # wide end (at hero row top)
		narrow_left, narrow_right,
		wide_left, wide_right,
		_vp.x,
	)

func _build_gate_base_band() -> void:
	# Bright "wall edge" line where the gate meets the lane ground.
	var base_y: float = _vp.y * LANE_TOP_PCT
	var gate_w: float = GameConfig.gate_columns * Gate.CELL
	var gl: float = (_vp.x - gate_w) * 0.5
	var bright := ColorRect.new()
	bright.color = Color(0.85, 0.88, 0.95, 0.55)
	bright.position = Vector2(gl, base_y - 3)
	bright.size = Vector2(gate_w, 4)
	bright.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bright)

func _build_enemy_lane() -> void:
	enemy_lane = EnemyLane.new()
	add_child(enemy_lane)
	var lane_top: float = _vp.y * LANE_TOP_PCT       # near gate (small enemies)
	var lane_bot: float = _vp.y * LANE_BOTTOM_PCT    # near camera (full size)
	# Damage triggers when an enemy reaches the bottom of the lane (= hero row).
	# In phase 2 (no heroes), that's where base damage happens. Pass the same Y.
	var post_target: float = lane_bot
	# Depth-aware column → x: at progress=0 (gate base, narrow end) columns are
	# squeezed into the trapezoid's narrow span; at progress=1 (hero row, wide
	# end) they line up with the gate columns so they hand off to heroes cleanly.
	# Enemies thus appear to converge near the horizon and spread as they walk.
	var gate_w: float = GameConfig.gate_columns * Gate.CELL
	var narrow_w: float = gate_w * 0.55
	var narrow_left: float = (_vp.x - narrow_w) * 0.5
	var col_x_fn: Callable = func(c: int, t: float) -> float:
		if gate == null:
			return _vp.x * 0.5
		var wide_x: float = gate.cell_world_pos(Vector2i(c, 0)).x
		var narrow_x: float = narrow_left + (float(c) + 0.5) * (narrow_w / float(GameConfig.gate_columns))
		return lerp(narrow_x, wide_x, clamp(t, 0.0, 1.0))
	enemy_lane.configure(gate, lane_top, lane_bot, post_target, col_x_fn)

func _build_gate() -> void:
	gate = Gate.new()
	add_child(gate)
	var gate_width: float = GameConfig.gate_columns * Gate.CELL
	var x_off: float = (_vp.x - gate_width) * 0.5
	gate.position = Vector2(x_off, _vp.y * GATE_TOP_PCT)
	if enemy_lane != null:
		enemy_lane.gate_ref = gate

func _build_hero_row() -> void:
	hero_row = HeroRow.new()
	add_child(hero_row)
	var col_x_fn: Callable = func(c: int) -> float:
		return gate.cell_world_pos(Vector2i(c, 0)).x
	# Pulled up from +0.04 → +0.01 so heroes sit right at the enemy-lane edge,
	# leaving more breathing room between row and cannon.
	var row_y: float = _vp.y * (HERO_ROW_TOP_PCT + 0.01)
	hero_row.configure(gate, enemy_lane, col_x_fn, row_y)
	if enemy_lane != null:
		enemy_lane.hero_row_ref = hero_row

func _build_base_platform() -> void:
	base_platform = Node2D.new()
	base_platform.set_script(BASE_PLATFORM_SCRIPT)
	base_platform.z_index = 5   # above lane/heroes, below cannon
	add_child(base_platform)
	var cannon_pos := Vector2(_vp.x * 0.5, _vp.y * CANNON_Y_PCT)
	base_platform.configure(_vp, cannon_pos, 70.0)

func _build_cannon() -> void:
	cannon = Cannon.new()
	cannon.gate = gate   # set before add_child so _ready can resolve palette + overlay
	cannon.z_index = 10  # ensure cannon paints on top of base_platform
	add_child(cannon)
	cannon.position = Vector2(_vp.x * 0.5, _vp.y * CANNON_Y_PCT)

# HUD layout constants — top bar mirrors match-screen-v2-b mockup + ui-spec §3.6.
const HUD_TOP_Y: float = 18.0
const HUD_CHIP_H: float = 44.0
const HUD_PAD: float = 12.0
const HUD_PAUSE_COLOR: Color   = Color(0.36, 0.74, 0.98, 1.0)   # blue button
const HUD_WAVE_COLOR: Color    = Color(0.99, 0.84, 0.30, 1.0)   # yellow shield
const HUD_ENERGY_COLOR: Color  = Color(0.36, 0.74, 0.98, 1.0)
const HUD_SPEED_COLOR: Color   = Color(0.78, 0.82, 0.92, 1.0)
const HUD_CHIP_STROKE: Color   = Color(0.10, 0.13, 0.20, 0.95)

func _build_hud() -> void:
	# HUD lives on a Node2D root so we can draw chips as simple Polygon2D /
	# ColorRect-equivalent rects positioned in viewport-space. CanvasLayer used
	# previously caused Panel children to stretch to fullscreen.
	var panel := CanvasLayer.new()
	panel.name = "HUD"
	add_child(panel)

	var root := Node2D.new()
	root.name = "HUDRoot"
	panel.add_child(root)

	# ── Top bar (left → right) per ui-spec §3.6 / match-screen-v2-b mockup ───
	var pause_size: float = HUD_CHIP_H
	var pause_x: float = HUD_PAD
	_build_pause_chip(root, Vector2(pause_x, HUD_TOP_Y), pause_size)

	var speed_w: float = 56.0
	var energy_w: float = 64.0
	var wave_w: float = 100.0
	var right_x: float = _vp.x - HUD_PAD

	var speed_x: float = right_x - speed_w
	_build_speed_chip(root, Vector2(speed_x, HUD_TOP_Y), Vector2(speed_w, HUD_CHIP_H))

	var energy_x: float = speed_x - 8.0 - energy_w
	_build_energy_chip(root, Vector2(energy_x, HUD_TOP_Y), Vector2(energy_w, HUD_CHIP_H))

	var wave_x: float = energy_x - 8.0 - wave_w
	_build_wave_chip(root, Vector2(wave_x, HUD_TOP_Y), Vector2(wave_w, HUD_CHIP_H))

	# HP bar stretches between pause and wave chips.
	var bar_x: float = pause_x + pause_size + 10.0
	var bar_right: float = wave_x - 10.0
	var bar_w: float = max(80.0, bar_right - bar_x)
	var bar_h: float = HUD_CHIP_H
	_build_hp_bar(root, Vector2(bar_x, HUD_TOP_Y), Vector2(bar_w, bar_h))

	# ── Blast Brigade: currency counter (bottom-left) + spawn button (bottom-right)
	_build_currency_chip(root, Vector2(HUD_PAD, _vp.y - 78))
	_build_spawn_button(root)

	# Legacy MOVES label kept as a hidden Label so any reference doesn't crash.
	hud_moves_label = Label.new()
	hud_moves_label.visible = false
	root.add_child(hud_moves_label)

	# ── Bottom-right: help chip placeholder ──────────────────────────────────
	# Disabled in Blast Brigade — spawn button occupies this corner.
	# _build_help_chip(root, Vector2(_vp.x - HUD_PAD - HUD_CHIP_H, _vp.y - HUD_PAD - HUD_CHIP_H), HUD_CHIP_H)

	# Dev-only counts (tiny + faint).
	hud_enemies_label = _hud_label_at(Vector2(HUD_PAD, _vp.y - 22), 11, Color(1, 1, 1, 0.35))
	root.add_child(hud_enemies_label)

	hud = Label.new()
	hud.position = Vector2(HUD_PAD, _vp.y - 12)
	hud.add_theme_font_size_override("font_size", 10)
	hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	hud.text = "R: +30💰   N: next wave   K: kill-all   S: spawn"
	root.add_child(hud)

	_refresh_hud()

# ── Chip builders — Polygon2D-based so they stay at the size we ask for. ──

func _draw_chip_rect(parent: Node2D, pos: Vector2, size: Vector2, fill: Color) -> Node2D:
	# A rounded chip is two stacked rects (body + 2px darker stroke band on the
	# bottom) plus a 2-px dark outline. Approximated as plain rects since
	# Polygon2D rounded corners aren't worth the points for chip-sized UI.
	var holder := Node2D.new()
	holder.position = pos
	parent.add_child(holder)
	# Dark drop-stroke under the body.
	var stroke := Polygon2D.new()
	stroke.color = HUD_CHIP_STROKE
	stroke.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(size.x + 2, -2),
		Vector2(size.x + 2, size.y + 3), Vector2(-2, size.y + 3),
	])
	holder.add_child(stroke)
	# Body fill.
	var body := Polygon2D.new()
	body.color = fill
	body.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y),
	])
	holder.add_child(body)
	return holder

func _build_pause_chip(parent: Node2D, pos: Vector2, size: float) -> void:
	var chip := _draw_chip_rect(parent, pos, Vector2(size, size), HUD_PAUSE_COLOR)
	# Two white pause bars.
	var bar_w: float = size * 0.13
	var bar_h: float = size * 0.46
	var cy: float = size * 0.5
	for cx in [size * 0.34, size * 0.66]:
		var bar := Polygon2D.new()
		bar.color = Color(1, 1, 1, 1)
		var x0: float = cx - bar_w * 0.5
		var x1: float = cx + bar_w * 0.5
		var y0: float = cy - bar_h * 0.5
		var y1: float = cy + bar_h * 0.5
		bar.polygon = PackedVector2Array([
			Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
		])
		chip.add_child(bar)

func _build_wave_chip(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	var chip := _draw_chip_rect(parent, pos, size, HUD_WAVE_COLOR)
	hud_wave_label = _hud_label_at(Vector2(0, size.y * 0.5 - 14), 22, Color(0.10, 0.13, 0.20, 1.0))
	hud_wave_label.size = Vector2(size.x, 28)
	hud_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_wave_label.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.55, 0.5))
	hud_wave_label.add_theme_constant_override("outline_size", 2)
	chip.add_child(hud_wave_label)

func _build_energy_chip(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	var chip := _draw_chip_rect(parent, pos, size, HUD_ENERGY_COLOR)
	var bolt := Label.new()
	bolt.text = "⚡"
	bolt.position = Vector2(6, size.y * 0.5 - 16)
	bolt.add_theme_font_size_override("font_size", 24)
	bolt.add_theme_color_override("font_color", Color(1, 0.95, 0.4, 1))
	bolt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	bolt.add_theme_constant_override("outline_size", 3)
	chip.add_child(bolt)
	hud_energy_label = _hud_label_at(Vector2(size.x * 0.50, size.y * 0.5 - 14), 22, Color(1, 1, 1, 1))
	hud_energy_label.size = Vector2(size.x * 0.45, 28)
	hud_energy_label.text = "1"
	chip.add_child(hud_energy_label)

func _build_speed_chip(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	var chip := _draw_chip_rect(parent, pos, size, HUD_SPEED_COLOR)
	var lbl := _hud_label_at(Vector2(0, size.y * 0.5 - 13), 20, Color(0.10, 0.13, 0.20, 1.0))
	lbl.size = Vector2(size.x, 26)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "1×"
	chip.add_child(lbl)

func _build_help_chip(parent: Node2D, pos: Vector2, size: float) -> void:
	var chip := _draw_chip_rect(parent, pos, Vector2(size, size), Color(0.20, 0.24, 0.32, 0.95))
	var q := _hud_label_at(Vector2(0, size * 0.5 - 17), 26, Color(1, 1, 1, 1))
	q.size = Vector2(size, 34)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.text = "?"
	chip.add_child(q)

# ── Blast Brigade — currency chip & spawn button ───────────────────────────

const BB_GOLD: Color = Color(1.00, 0.84, 0.30, 1.0)
const BB_SPAWN_GREEN: Color = Color(0.32, 0.78, 0.42, 1.0)
const BB_SPAWN_RED: Color = Color(0.85, 0.32, 0.32, 1.0)
const BB_SPAWN_BTN_W: float = 200.0
const BB_SPAWN_BTN_H: float = 88.0
const BB_SPAWN_BTN_PAD: float = 16.0

func _build_currency_chip(parent: Node2D, pos: Vector2) -> void:
	# Wide gold chip with coin + count: "🪙  60"
	var chip_size := Vector2(150.0, 44.0)
	var chip := _draw_chip_rect(parent, pos, chip_size, Color(0.18, 0.14, 0.06, 0.85))
	# Coin disc.
	var coin := Polygon2D.new()
	coin.color = BB_GOLD
	var cx: float = 22.0
	var cy: float = chip_size.y * 0.5
	var r: float = 14.0
	var pts := PackedVector2Array()
	for i in range(24):
		var ang: float = TAU * float(i) / 24.0
		pts.append(Vector2(cx + cos(ang) * r, cy + sin(ang) * r))
	coin.polygon = pts
	chip.add_child(coin)
	# Inner ring.
	var coin_inner := Polygon2D.new()
	coin_inner.color = Color(0.85, 0.62, 0.18, 1.0)
	var pts_inner := PackedVector2Array()
	for i in range(24):
		var ang: float = TAU * float(i) / 24.0
		pts_inner.append(Vector2(cx + cos(ang) * r * 0.62, cy + sin(ang) * r * 0.62))
	coin_inner.polygon = pts_inner
	chip.add_child(coin_inner)
	# Count label.
	hud_currency_label = _hud_label_at(Vector2(46, chip_size.y * 0.5 - 14), 22, Color(1, 0.95, 0.65, 1))
	hud_currency_label.size = Vector2(chip_size.x - 50, 28)
	hud_currency_label.text = "0"
	chip.add_child(hud_currency_label)

func _build_spawn_button(parent: Node2D) -> void:
	spawn_button_root = Node2D.new()
	var btn_pos := Vector2(
		_vp.x - BB_SPAWN_BTN_W - BB_SPAWN_BTN_PAD,
		_vp.y - BB_SPAWN_BTN_H - BB_SPAWN_BTN_PAD)
	spawn_button_root.position = btn_pos
	spawn_button_rect = Rect2(btn_pos, Vector2(BB_SPAWN_BTN_W, BB_SPAWN_BTN_H))
	parent.add_child(spawn_button_root)
	# Dark stroke band.
	var stroke := Polygon2D.new()
	stroke.color = Color(0.05, 0.07, 0.10, 0.95)
	stroke.polygon = PackedVector2Array([
		Vector2(-3, -3), Vector2(BB_SPAWN_BTN_W + 3, -3),
		Vector2(BB_SPAWN_BTN_W + 3, BB_SPAWN_BTN_H + 4), Vector2(-3, BB_SPAWN_BTN_H + 4),
	])
	spawn_button_root.add_child(stroke)
	# Body — green (afford) or red (denied); recolored in _refresh_hud.
	spawn_button_bg = Polygon2D.new()
	spawn_button_bg.color = BB_SPAWN_GREEN
	spawn_button_bg.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(BB_SPAWN_BTN_W, 0),
		Vector2(BB_SPAWN_BTN_W, BB_SPAWN_BTN_H), Vector2(0, BB_SPAWN_BTN_H),
	])
	spawn_button_root.add_child(spawn_button_bg)
	# "SPAWN HERO" big label.
	spawn_button_label = _hud_label_at(Vector2(0, 12), 28, Color(1, 1, 1, 1))
	spawn_button_label.size = Vector2(BB_SPAWN_BTN_W, 36)
	spawn_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawn_button_label.text = "SPAWN HERO"
	spawn_button_root.add_child(spawn_button_label)
	# Cost "🪙 30".
	spawn_button_cost_label = _hud_label_at(Vector2(0, 50), 22, Color(1, 0.95, 0.6, 1))
	spawn_button_cost_label.size = Vector2(BB_SPAWN_BTN_W, 28)
	spawn_button_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawn_button_cost_label.text = "🪙 %d" % GameConfig.hero_spawn_cost
	spawn_button_root.add_child(spawn_button_cost_label)

func _flash_spawn_button_denied() -> void:
	_spawn_btn_flash_t = 0.25

func _spawn_button_hit(pos: Vector2) -> bool:
	return spawn_button_rect.has_point(pos)

func _build_hp_bar(parent: Node2D, pos: Vector2, size: Vector2) -> void:
	# Dark capsule background.
	var chip := _draw_chip_rect(parent, pos, size, Color(0.10, 0.13, 0.20, 0.95))

	# Green fill — sized via Polygon2D points we'll just redraw on refresh.
	var inset_x: float = 6.0
	var inset_y: float = size.y * 0.30
	hud_hp_bar_fill_w = size.x - inset_x * 2.0
	hud_hp_bar_fill = ColorRect.new()
	hud_hp_bar_fill.color = Color(0.30, 0.78, 0.36)
	hud_hp_bar_fill.position = Vector2(inset_x, inset_y)
	hud_hp_bar_fill.size = Vector2(hud_hp_bar_fill_w, size.y * 0.40)
	hud_hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(hud_hp_bar_fill)

	# "HP" prefix label on the left.
	var hp_prefix := _hud_label_at(Vector2(12, size.y * 0.5 - 12), 18, Color(1, 1, 1, 1))
	hp_prefix.text = "HP"
	chip.add_child(hp_prefix)

	# Percent label on the right.
	hud_hp_label = _hud_label_at(Vector2(0, size.y * 0.5 - 12), 18, Color(1, 1, 1, 1))
	hud_hp_label.size = Vector2(size.x - 14, 24)
	hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.add_child(hud_hp_label)

# ── Small helpers ──────────────────────────────────────────────────────

func _hud_label_at(pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _refresh_hud() -> void:
	if hud_wave_label == null:
		return
	var alive: int = 0
	var queued: int = 0
	if enemy_lane != null:
		alive = enemy_lane.enemies.size()
		queued = enemy_lane.spawn_queue.size() - enemy_lane.spawn_index
	var hcount: int = 0
	var hqueue: int = 0
	if hero_row != null:
		for h in hero_row.heroes:
			if h != null:
				hcount += 1
		hqueue = hero_row.queue.size()

	# Wave: "W 2/5" (with " ★" suffix on the boss wave).
	var boss_tag: String = "  ★" if RunState.wave_index == GameConfig.num_waves - 1 else ""
	hud_wave_label.text = "W %d/%d%s" % [RunState.wave_index + 1, GameConfig.num_waves, boss_tag]

	# Blast Brigade — currency counter (instead of MOVES).
	if hud_currency_label != null:
		hud_currency_label.text = "%d" % RunState.currency
	# Spawn button color reflects affordability + denial flash.
	if spawn_button_bg != null:
		var can_afford: bool = RunState.can_afford(GameConfig.hero_spawn_cost)
		var col: Color = BB_SPAWN_GREEN if can_afford else Color(0.30, 0.35, 0.42, 1.0)
		if _spawn_btn_flash_t > 0.0:
			col = BB_SPAWN_RED
		spawn_button_bg.color = col

	# Debug line (kept tiny + faint).
	if hud_enemies_label != null:
		hud_enemies_label.text = "enemies %d (+%d)   heroes %d (+%d)" % [alive, max(queued, 0), hcount, hqueue]

	# HP bar fill + percentage label.
	var hp_max: int = GameConfig.base_max_hp
	var hp_pct: float = clamp(float(RunState.base_hp) / float(max(hp_max, 1)), 0.0, 1.0)
	if hud_hp_bar_fill != null:
		hud_hp_bar_fill.size.x = hud_hp_bar_fill_w * hp_pct
		if hp_pct < 0.25:
			hud_hp_bar_fill.color = Color(0.92, 0.30, 0.25)
		elif hp_pct < 0.50:
			hud_hp_bar_fill.color = Color(0.95, 0.62, 0.20)
		else:
			hud_hp_bar_fill.color = Color(0.30, 0.78, 0.36)
	if hud_hp_label != null:
		hud_hp_label.text = "HP  %d%%" % int(round(hp_pct * 100.0))

# ─── Run / wave signals ────────────────────────────────────────────────────

func _on_wave_changed(_idx: int) -> void:
	# Blast Brigade — do NOT seed bubbles. Gate remains empty; column_state
	# returns "open" everywhere so heroes can shoot freely.
	if RunState.wave_index == 0:
		_pre_wave_grace_t = GameConfig.pre_run_countdown_sec
		_show_pre_wave_label()
	else:
		_pre_wave_grace_t = 0.0
		enemy_lane.begin_wave(RunState.wave_index)
	_wave_start_time = Time.get_ticks_msec() / 1000.0
	_moves_used_this_wave = 0
	_gate_field_cleared = true   # never clear — there's nothing to clear
	Telemetry.wave_start(RunState.wave_index, {}, 0)
	_refresh_hud()

func _on_moves_changed(_remaining: int) -> void:
	# Blast Brigade — moves system unused (cannon fires freely). Kept as a stub.
	_refresh_hud()

func _on_currency_changed(_amount: int) -> void:
	_refresh_hud()

func _maybe_clear_gate_field() -> void:
	# Blast Brigade — no-op (gate never seeded with bubbles in this fork).
	pass

func _on_base_hp_changed(_hp: int) -> void:
	_refresh_hud()

func _on_enemy_reached_base(damage: int) -> void:
	RunState.damage_base(damage)

func _on_wave_cleared() -> void:
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _wave_start_time
	var heroes_alive: int = _count_live_heroes()
	Telemetry.wave_end("win", _moves_used_this_wave, elapsed, heroes_alive)
	# Mega VFX: confetti burst centered above the gate (screen-center, y at gate
	# zone) + bright 4-note sting per audio-brief WC.
	VFX.play("wave_clear", Vector2(360, 700))
	SFX.play("wave_clear")
	# If that was the last wave, jump straight to run-end "win".
	if RunState.wave_index + 1 >= GameConfig.num_waves:
		RunState.advance_wave()
		return
	RunState.begin_intermission()
	_intermission_elapsed = 0.0
	await get_tree().create_timer(GameConfig.intermission_duration_sec).timeout
	if RunState.run_over:
		return
	RunState.advance_wave()

func _on_intermission_started(_from_wave: int, to_wave: int) -> void:
	if intermission_overlay == null:
		return
	intermission_title.text = "Wave %d Cleared!" % (RunState.wave_index + 1)
	intermission_preview.text = _build_preview_text(to_wave)
	intermission_overlay.visible = true
	_intermission_elapsed = 0.0
	_refresh_countdown_bar()

func _on_intermission_ended() -> void:
	if intermission_overlay != null:
		intermission_overlay.visible = false

# ─── Pre-wave-1 in-scene countdown ────────────────────────────────────────
# Non-blocking label hovering above the lane that ticks down "WAVE 1 IN N".
# Player can shoot, aim, pop bubbles during the entire countdown.

func _build_pre_wave_countdown_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	pre_wave_label = Label.new()
	pre_wave_label.add_theme_font_size_override("font_size", 44)
	pre_wave_label.add_theme_color_override("font_color", Color(1, 0.95, 0.55, 1))
	pre_wave_label.add_theme_color_override("font_outline_color", Color(0.10, 0.13, 0.20, 0.95))
	pre_wave_label.add_theme_constant_override("outline_size", 8)
	pre_wave_label.position = Vector2(0, _vp.y * 0.13)
	pre_wave_label.size = Vector2(_vp.x, 64)
	pre_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pre_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pre_wave_label.visible = false
	layer.add_child(pre_wave_label)

func _show_pre_wave_label() -> void:
	if pre_wave_label == null:
		return
	pre_wave_label.visible = true
	_refresh_pre_wave_label()

func _hide_pre_wave_label() -> void:
	if pre_wave_label != null:
		pre_wave_label.visible = false

func _refresh_pre_wave_label() -> void:
	if pre_wave_label == null or not pre_wave_label.visible:
		return
	var secs: int = int(ceil(max(_pre_wave_grace_t, 0.0)))
	if secs <= 0:
		pre_wave_label.text = "WAVE 1 — GO!"
		pre_wave_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.40, 1))
	else:
		pre_wave_label.text = "WAVE 1 IN %d" % secs

# Legacy pre-run overlay (no longer called in normal flow). Kept so any external
# caller still resolves.
func _show_pre_run_overlay() -> void:
	if intermission_overlay == null:
		return
	intermission_title.text = "Wave 1 — Get Ready"
	intermission_preview.text = _build_preview_text(0)
	intermission_overlay.visible = true
	_intermission_elapsed = 0.0
	_pre_run_active = true
	_refresh_countdown_bar()

func _hide_pre_run_overlay() -> void:
	_pre_run_active = false
	if intermission_overlay != null:
		intermission_overlay.visible = false

func _build_preview_text(to_wave: int) -> String:
	if to_wave < 0 or to_wave >= GameConfig.num_waves:
		return ""
	var moves: int = GameConfig.moves_for_wave(to_wave)
	var rows: int = GameConfig.seed_rows_for_wave(to_wave)
	var heroes: int = GameConfig.hero_bubble_count_for_wave(to_wave)
	var totals: Dictionary = GameConfig.spawn_totals_for_wave(to_wave)
	var parts: Array[String] = []
	for c in ["RED", "BLUE", "YELLOW"]:
		if totals.has(c) and int(totals[c]) > 0:
			parts.append("%d %s" % [int(totals[c]), c])
	var enemies_str: String = ", ".join(parts) if not parts.is_empty() else "—"
	var boss_tag: String = "  (BOSS)" if to_wave == GameConfig.num_waves - 1 else ""
	return "Next: Wave %d%s\nMoves %d   Gate %d rows   %d hero bubbles\nEnemies: %s" % [
		to_wave + 1, boss_tag, moves, rows, heroes, enemies_str,
	]

func _count_live_heroes() -> int:
	if hero_row == null:
		return 0
	var n: int = 0
	for h in hero_row.heroes:
		if h != null and is_instance_valid(h):
			n += 1
	return n

func _on_run_ended(result: String) -> void:
	Telemetry.log_event("run_end", {"result": result})
	_show_runend_overlay(result)
	# Populate MetaState run summary for RunClear / RunFail.
	# Damage is approximated since we don't track per-hit damage end-to-end —
	# bubbles popped × 60 lands in the right ballpark per playtest.
	var damage_dealt: int = _bubbles_popped_total * 60
	if result == "win":
		# Pick a plausible MVP — placeholder until per-hero damage tracking lands.
		MetaState.record_win(damage_dealt, _bubbles_popped_total,
			MetaState.last_run_mvp_hero, int(damage_dealt * 0.40))
	else:
		# wave_index + 1 = 1-based wave the player died on (see MetaState.record_loss).
		MetaState.record_loss(result, RunState.wave_index + 1, damage_dealt, _bubbles_popped_total)
	await get_tree().create_timer(1.6).timeout
	_hide_runend_overlay()
	if result == "win":
		get_tree().change_scene_to_file("res://scenes/RunClear.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/RunFail.tscn")

# ─── Cannon → bomb → enemy damage (Blast Brigade) ──────────────────────────

func _on_cannon_fired(origin: Vector2, target: Vector2, _color: String) -> void:
	# Tap-to-target mortar model — the cannon emits a world-space landing
	# point (already clamped to cone + max-range by Cannon._update_aim) and
	# the bomb lobs to it. Color is irrelevant in Blast Brigade. Multiple
	# bombs in flight at once is fine; no `active_projectile` gating.
	var bomb: Node2D = BombProjectileScript.new()
	add_child(bomb)
	bomb.position = origin
	bomb.setup(target, GameConfig.bomb_damage, enemy_lane)

func _process(dt: float) -> void:
	_refresh_hud()
	if _spawn_btn_flash_t > 0.0:
		_spawn_btn_flash_t -= dt
	if (RunState.intermission_active or _pre_run_active) and intermission_overlay != null and intermission_overlay.visible:
		_intermission_elapsed += dt
		_refresh_countdown_bar()
	# Pre-wave-1 grace tick: count down, then fire enemy_lane.begin_wave once.
	if _pre_wave_grace_t > 0.0:
		_pre_wave_grace_t -= dt
		_refresh_pre_wave_label()
		if _pre_wave_grace_t <= 0.0:
			_pre_wave_grace_t = 0.0
			enemy_lane.begin_wave(RunState.wave_index)
			# Quick "GO" flash then hide.
			_refresh_pre_wave_label()
			await get_tree().create_timer(0.8).timeout
			_hide_pre_wave_label()
	# Blast Brigade — bombs self-destruct via BombProjectile._die. Nothing
	# more to drive from MatchScene here.

func _on_bubble_popped(_count: int, _color: String, _contains_hero: bool) -> void:
	# Blast Brigade — no bubbles. Stub kept so any stale Gate signal connection
	# wouldn't crash in case of debug-key reseed.
	pass

func _on_heroes_freed(_spawns: Array) -> void:
	# Blast Brigade — heroes spawn via the on-screen button (currency), not
	# from gate hero-bubbles.
	pass

# Blast Brigade — player taps SPAWN button to drop a tier-1 hero into the row.
const TD_HERO_CLASSES: Array[String] = ["FireKnight", "IceMage", "Druid", "Archer", "Wizard"]
var _td_spawn_idx: int = 0

func _try_spawn_hero() -> void:
	if RunState.run_over or RunState.intermission_active:
		return
	if not RunState.can_afford(GameConfig.hero_spawn_cost):
		_flash_spawn_button_denied()
		SFX.play("invalid")
		return
	if not RunState.spend_currency(GameConfig.hero_spawn_cost):
		return
	# Cycle through classes so the player sees variety. (Could be replaced with
	# per-class buttons later — for prototype, one button + cycling roster.)
	var hero_class: String = TD_HERO_CLASSES[_td_spawn_idx % TD_HERO_CLASSES.size()]
	_td_spawn_idx += 1
	hero_row.spawn_hero_td(hero_class)
	# Reuse v2's hero-freed VFX/SFX moment for the spawn.
	VFX.play("hero_freed", hero_row.global_position)
	SFX.play("hero_freed")
	_refresh_hud()

# ─── Intermission + run-end overlays (Phase 4) ─────────────────────────────

func _build_intermission_overlay() -> void:
	intermission_overlay = CanvasLayer.new()
	intermission_overlay.layer = 50
	intermission_overlay.visible = false
	add_child(intermission_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.position = Vector2.ZERO
	dim.size = _vp
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	intermission_overlay.add_child(dim)

	var panel_w: float = _vp.x * 0.86
	var panel_h: float = 240.0
	var panel := ColorRect.new()
	panel.color = Color(0.10, 0.13, 0.20, 0.92)
	panel.position = Vector2((_vp.x - panel_w) * 0.5, _vp.y * 0.32)
	panel.size = Vector2(panel_w, panel_h)
	intermission_overlay.add_child(panel)

	intermission_title = Label.new()
	intermission_title.text = "Wave Cleared!"
	intermission_title.add_theme_color_override("font_color", Color(1, 1, 1))
	intermission_title.add_theme_font_size_override("font_size", 36)
	intermission_title.position = panel.position + Vector2(20, 18)
	intermission_title.size = Vector2(panel_w - 40, 48)
	intermission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intermission_overlay.add_child(intermission_title)

	intermission_preview = Label.new()
	intermission_preview.text = ""
	intermission_preview.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	intermission_preview.add_theme_font_size_override("font_size", 22)
	intermission_preview.position = panel.position + Vector2(20, 78)
	intermission_preview.size = Vector2(panel_w - 40, 120)
	intermission_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intermission_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intermission_overlay.add_child(intermission_preview)

	# Countdown bar (drains over intermission_duration_sec).
	var bar_w: float = panel_w - 60.0
	var bar_h: float = 10.0
	var bar_pos: Vector2 = panel.position + Vector2(30, panel_h - 28)
	intermission_countdown_bg = ColorRect.new()
	intermission_countdown_bg.color = Color(1, 1, 1, 0.15)
	intermission_countdown_bg.position = bar_pos
	intermission_countdown_bg.size = Vector2(bar_w, bar_h)
	intermission_overlay.add_child(intermission_countdown_bg)
	intermission_countdown_bar = ColorRect.new()
	intermission_countdown_bar.color = Color(0.55, 0.85, 0.55)
	intermission_countdown_bar.position = bar_pos
	intermission_countdown_bar.size = Vector2(bar_w, bar_h)
	intermission_overlay.add_child(intermission_countdown_bar)

func _refresh_countdown_bar() -> void:
	if intermission_countdown_bar == null or intermission_countdown_bg == null:
		return
	var base_dur: float = GameConfig.pre_run_countdown_sec if _pre_run_active else GameConfig.intermission_duration_sec
	var dur: float = max(base_dur, 0.01)
	var pct: float = clamp(1.0 - (_intermission_elapsed / dur), 0.0, 1.0)
	intermission_countdown_bar.size = Vector2(intermission_countdown_bg.size.x * pct, intermission_countdown_bg.size.y)

func _build_runend_overlay() -> void:
	runend_overlay = CanvasLayer.new()
	runend_overlay.layer = 60
	runend_overlay.visible = false
	add_child(runend_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.position = Vector2.ZERO
	dim.size = _vp
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	runend_overlay.add_child(dim)

	runend_title = Label.new()
	runend_title.text = ""
	runend_title.add_theme_font_size_override("font_size", 64)
	runend_title.add_theme_color_override("font_color", Color.WHITE)
	runend_title.position = Vector2(0, _vp.y * 0.38)
	runend_title.size = Vector2(_vp.x, 80)
	runend_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	runend_overlay.add_child(runend_title)

	runend_subtitle = Label.new()
	runend_subtitle.text = ""
	runend_subtitle.add_theme_font_size_override("font_size", 24)
	runend_subtitle.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	runend_subtitle.position = Vector2(0, _vp.y * 0.48)
	runend_subtitle.size = Vector2(_vp.x, 60)
	runend_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	runend_overlay.add_child(runend_subtitle)

func _show_runend_overlay(result: String) -> void:
	if runend_overlay == null:
		return
	match result:
		"win":
			runend_title.text = "RUN COMPLETE"
			runend_title.add_theme_color_override("font_color", Color(0.70, 0.95, 0.70))
		"lose":
			runend_title.text = "BASE DESTROYED"
			runend_title.add_theme_color_override("font_color", Color(0.96, 0.55, 0.50))
		"stall_loss":
			runend_title.text = "OUT OF MOVES"
			runend_title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.50))
		_:
			runend_title.text = result.to_upper()
	runend_subtitle.text = "Wave %d / %d   Base HP %d" % [
		RunState.wave_index + 1, GameConfig.num_waves, RunState.base_hp,
	]
	runend_overlay.visible = true

func _hide_runend_overlay() -> void:
	if runend_overlay != null:
		runend_overlay.visible = false

# ─── Stall-loss detection (spec §5.4 cond 3) ───────────────────────────────

func _check_stall_loss(_dt: float) -> void:
	# Blast Brigade — stall loss disabled (no move budget). Player can always
	# fire the cannon, so the only loss condition is base HP reaching 0.
	pass

# ─── Debug input ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Intercept clicks on the Blast Brigade spawn button BEFORE the cannon
	# (which uses _unhandled_input) sees them.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if spawn_button_root != null and _spawn_button_hit(mb.position):
				_try_spawn_hero()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				# Blast Brigade: R adds 30 currency (debug).
				RunState.grant_currency(30)
			KEY_N:
				RunState.advance_wave()
			KEY_K:
				for e in enemy_lane.enemies.duplicate():
					if is_instance_valid(e):
						e.take_damage(99999.0)
			KEY_S:
				# Quick-spawn shortcut (debug).
				_try_spawn_hero()
