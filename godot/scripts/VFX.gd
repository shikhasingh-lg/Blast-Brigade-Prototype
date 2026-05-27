extends Node
## Autoload VFX factory. Single entry-point for spawning short-lived visual
## effects on top of gameplay. Three intensity tiers per art-direction.md §8:
##   micro (100–200 ms, 3–8 particles) — per shot / per pop
##   macro (400–800 ms, 12–30 particles) — per moment (hero freed, frenzy, ult)
##   mega  (1.5–3.0 s, 60+ particles) — per outcome (wave/run clear, gacha legendary)
##
## Usage: VFX.play("bubble_pop", world_pos, {"color": "RED"})
##
## This is intentionally a procedural-draw scaffold for now. Each effect is a
## small Node2D + Tween that draws shapes — readable from the spec without
## needing the partner art atlases extracted. When the VFX sheets are sliced
## (Phase 2 of the implementation plan), replace the procedural _build_*
## methods with packed-scene instantiations of `res://scenes/vfx/<name>.tscn`.

const COLOR_HEX: Dictionary = {
	"RED":    Color(0.91, 0.29, 0.23),   # #E84A3A
	"BLUE":   Color(0.25, 0.64, 0.90),   # #3FA4E6
	"YELLOW": Color(0.95, 0.76, 0.22),   # #F2C337
	"GREEN":  Color(0.36, 0.76, 0.44),   # #5DC36F
	"PURPLE": Color(0.58, 0.33, 0.79),   # #9355C9
	"GOLD":   Color(1.0,  0.85, 0.30),
	"WHITE":  Color(1, 1, 1),
}

## Sprite-burst integration — single textures pre-extracted (with bg keyed out)
## from vfx-combat.png. When the requested effect has a sprite, we render a tween-
## driven Sprite2D burst instead of the procedural shape fallback. Each entry maps
## to a path under res://assets/vfx/.
const VFX_SPRITES: Dictionary = {
	"bubble_pop":             "res://assets/vfx/bubble_pop.png",
	"hero_fire_FireKnight":   "res://assets/vfx/fire_flash_fireknight.png",
	"hero_fire_IceMage":      "res://assets/vfx/fire_flash_icemage.png",
	"hero_fire_Archer":       "res://assets/vfx/fire_flash_archer.png",
	"hero_fire_Druid":        "res://assets/vfx/fire_flash_druid.png",
	"hero_fire_Wizard":       "res://assets/vfx/fire_flash_wizard.png",
	"hero_freed":             "res://assets/vfx/hero_freed.png",
	"enemy_breach":           "res://assets/vfx/enemy_breach.png",
	"enemy_hit":              "res://assets/vfx/hit_impact.png",
}
## Hero class lookup keyed by class-color (matches Hero.gd's CLASS → COLOR table).
const COLOR_TO_CLASS: Dictionary = {
	"RED": "FireKnight",
	"BLUE": "IceMage",
	"YELLOW": "Archer",
	"GREEN": "Druid",
	"PURPLE": "Wizard",
}
static var _sprite_cache: Dictionary = {}

var _layer: CanvasLayer
var _freeze_active: bool = false

# Camera shake state — VFX.shake() pushes a new shake, _process decays it.
# Currently-active shake's params; t counts up from 0.0 toward total.
var _shake_t: float = 0.0
var _shake_total: float = 0.0
var _shake_amp: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Float above gameplay nodes but below UI. CanvasLayer.layer = 5
	# (gameplay sits at default 0, HUD usually 10+).
	_layer = CanvasLayer.new()
	_layer.layer = 5
	_layer.name = "VFXLayer"
	add_child(_layer)
	# Process during time-scale freeze so the recovery timer can fire.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shake_rng.randomize()

func _process(dt: float) -> void:
	if _shake_total <= 0.0:
		return
	_shake_t += dt
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		_shake_t = 0.0
		_shake_total = 0.0
		return
	if _shake_t >= _shake_total:
		_shake_t = 0.0
		_shake_total = 0.0
		cam.offset = Vector2.ZERO
		return
	# Linear decay: amplitude shrinks as t approaches total. Random direction
	# each frame for that "fast jitter" feel rather than a smooth swing.
	var decay: float = 1.0 - (_shake_t / _shake_total)
	var amp: float = _shake_amp * decay
	cam.offset = Vector2(
		_shake_rng.randf_range(-amp, amp),
		_shake_rng.randf_range(-amp, amp))

# Public: trigger a screen shake. Larger amp+dur stomps any in-progress shake.
func shake(amp: float, dur: float) -> void:
	if dur <= 0.0 or amp <= 0.0:
		return
	# Only overwrite if the new shake is meaningfully bigger; otherwise small
	# rapid shakes would constantly reset bigger ones (e.g. a cannon-fire kick
	# wiping out an in-flight impact shake).
	if amp * dur >= _shake_amp * max(_shake_total - _shake_t, 0.0):
		_shake_t = 0.0
		_shake_total = dur
		_shake_amp = amp

# ─── Hit-feel API ──────────────────────────────────────────────────────────

# Floating damage number. Rises and fades over GameConfig.dmg_number_lifetime_sec.
# `crit=true` → larger, gold instead of white.
func spawn_damage_number(world_pos: Vector2, amount: float, crit: bool = false) -> void:
	var rounded: int = int(round(amount))
	if rounded <= 0:
		return
	var n := Node2D.new()
	n.position = world_pos + Vector2(randf_range(-10.0, 10.0), 0.0)
	_layer.add_child(n)
	var lbl := Label.new()
	lbl.text = str(rounded)
	var fs: int = GameConfig.dmg_number_crit_font_size if crit else GameConfig.dmg_number_font_size
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.25) if crit else Color(1.0, 1.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(90.0, 40.0)
	lbl.position = -lbl.size * 0.5
	n.add_child(lbl)
	var life: float = GameConfig.dmg_number_lifetime_sec
	var rise: float = GameConfig.dmg_number_rise_px
	# A short pop-in scale on crit only — keeps non-crit hits visually cheap.
	if crit:
		n.scale = Vector2(0.6, 0.6)
		n.create_tween().tween_property(n, "scale", Vector2(1.0, 1.0), 0.10) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "position:y", n.position.y - rise, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, life * 0.55).set_delay(life * 0.30)
	tw.chain().tween_callback(n.queue_free)

# Brief stutter — drops Engine.time_scale for `duration` real-time seconds.
# Re-entrant calls during an active freeze are ignored.
func hit_freeze(duration: float = -1.0) -> void:
	if _freeze_active:
		return
	if duration < 0.0:
		duration = GameConfig.hit_freeze_duration_sec
	_freeze_active = true
	Engine.time_scale = GameConfig.hit_freeze_time_scale
	# process_always = true, ignore_time_scale = true → fires in real time.
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(_end_freeze)

func _end_freeze() -> void:
	Engine.time_scale = 1.0
	_freeze_active = false

# ─── Public API ────────────────────────────────────────────────────────────

func play(effect_name: String, world_pos: Vector2, opts: Dictionary = {}) -> void:
	match effect_name:
		"bubble_pop":        _bubble_pop(world_pos, opts)
		"hero_fire_flash":   _hero_fire_flash(world_pos, opts)
		"hero_freed":        _hero_freed(world_pos, opts)
		"enemy_hit":         _enemy_hit(world_pos, opts)
		"bomb_blast":        _bomb_blast(world_pos, opts)
		"enemy_breach":      _enemy_breach(world_pos, opts)
		"wave_clear":        _wave_clear(world_pos, opts)
		"color_frenzy":      _color_frenzy(world_pos, opts)
		"ult_eruption":      _ult_eruption(world_pos, opts)
		"ult_cryo_wave":     _ult_cryo_wave(world_pos, opts)
		"ult_volley":        _ult_volley(world_pos, opts)
		"ult_verdant_surge": _ult_verdant_surge(world_pos, opts)
		"ult_forking_bolt":  _ult_forking_bolt(world_pos, opts)
		"boss_corruption":   _boss_corruption(world_pos, opts)
		_:
			push_warning("VFX.play: unknown effect '%s'" % effect_name)

# ─── Helpers ──────────────────────────────────────────────────────────────

func _spawn(world_pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = world_pos
	_layer.add_child(n)
	return n

func _color_of(opts: Dictionary, fallback: String = "WHITE") -> Color:
	var key: String = opts.get("color", fallback)
	return COLOR_HEX.get(key, COLOR_HEX["WHITE"])

func _get_sprite(key: String) -> Texture2D:
	if not VFX_SPRITES.has(key):
		return null
	if _sprite_cache.has(key):
		return _sprite_cache[key]
	var tex: Texture2D = load(VFX_SPRITES[key]) as Texture2D
	_sprite_cache[key] = tex
	return tex

## Spawn a Sprite2D burst at world_pos with start scale, scaling toward end_scale
## over duration while fading alpha to 0. Tinted by `tint` (Color.WHITE = no tint).
## Returns the node so callers can attach extra tweens if needed.
func _sprite_burst(world_pos: Vector2, key: String, draw_size: float, duration: float,
		start_scale: float = 0.55, end_scale: float = 1.10, tint: Color = Color.WHITE) -> Node2D:
	var tex: Texture2D = _get_sprite(key)
	if tex == null:
		return null
	var n := _spawn(world_pos)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	# Normalize to draw_size regardless of source resolution.
	var src: Vector2 = tex.get_size()
	var max_dim: float = max(src.x, src.y)
	var unit_scale: float = draw_size / max_dim
	sprite.scale = Vector2.ONE * unit_scale * start_scale
	sprite.modulate = tint
	n.add_child(sprite)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector2.ONE * unit_scale * end_scale, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(n.queue_free)
	return n

# ─── Micro tier ────────────────────────────────────────────────────────────

func _bubble_pop(world_pos: Vector2, opts: Dictionary) -> void:
	# 200 ms burst: painted pop sprite at the bubble center.
	var col: Color = _color_of(opts, "WHITE")
	if _sprite_burst(world_pos, "bubble_pop", 64.0, 0.22, 0.45, 1.05,
			Color(1.0, 1.0, 1.0, 1.0).lerp(col, 0.20)) != null:
		return
	# Procedural fallback if the sprite is missing.
	var n := _spawn(world_pos)
	var sparkles: Array[Node2D] = []
	for i in range(6):
		var s := Node2D.new()
		var ang: float = TAU * float(i) / 6.0
		s.set_meta("dir", Vector2(cos(ang), sin(ang)))
		s.set_meta("color", col)
		s.draw.connect(func() -> void:
			var c: Color = s.get_meta("color")
			s.draw_circle(Vector2.ZERO, 4.0, c))
		n.add_child(s)
		sparkles.append(s)
	var tw := n.create_tween().set_parallel(true)
	for s in sparkles:
		var dir: Vector2 = s.get_meta("dir")
		tw.tween_property(s, "position", dir * 22.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(n.queue_free)

func _hero_fire_flash(world_pos: Vector2, opts: Dictionary) -> void:
	# Painted muzzle flash for the firing class. Class is looked up via the
	# COLOR_TO_CLASS table (caller passes color = class color in opts).
	var color_key: String = opts.get("color", "RED")
	var class_name_: String = COLOR_TO_CLASS.get(color_key, "FireKnight")
	if _sprite_burst(world_pos, "hero_fire_" + class_name_, 56.0, 0.16, 0.55, 1.15) != null:
		return
	var col: Color = _color_of(opts, "RED")
	var n := _spawn(world_pos)
	n.draw.connect(func() -> void:
		n.draw_circle(Vector2.ZERO, 14.0, Color(col.r, col.g, col.b, 0.65)))
	n.queue_redraw()
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector2(1.6, 1.6), 0.12)
	tw.tween_property(n, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(n.queue_free)

func _enemy_hit(world_pos: Vector2, opts: Dictionary) -> void:
	# Painted star-burst spark sprite (hit_impact).
	if _sprite_burst(world_pos, "enemy_hit", 36.0, 0.14, 0.55, 1.25) != null:
		return
	var col: Color = _color_of(opts, "WHITE")
	var n := _spawn(world_pos)
	n.draw.connect(func() -> void:
		n.draw_circle(Vector2.ZERO, 8.0, Color(col.r, col.g, col.b, 0.80)))
	n.queue_redraw()
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector2(2.0, 2.0), 0.10)
	tw.tween_property(n, "modulate:a", 0.0, 0.10)
	tw.chain().tween_callback(n.queue_free)

# Cannon bomb AOE — bright flash core + expanding orange shockwave ring.
# Caller may pass {"radius": float} so the ring matches the gameplay AOE radius.
func _bomb_blast(world_pos: Vector2, opts: Dictionary) -> void:
	var radius: float = opts.get("radius", 110.0)
	var n := _spawn(world_pos)
	# Bright white core flash — fast pop, sells the "boom" instant.
	var core := Node2D.new()
	core.draw.connect(func() -> void:
		core.draw_circle(Vector2.ZERO, radius * 0.55, Color(1.0, 0.95, 0.75, 0.85)))
	n.add_child(core)
	var core_tw := core.create_tween().set_parallel(true)
	core_tw.tween_property(core, "scale", Vector2(1.4, 1.4), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	core_tw.tween_property(core, "modulate:a", 0.0, 0.12)
	# Orange shockwave ring — expands to full radius and fades.
	var ring := Node2D.new()
	ring.draw.connect(func() -> void:
		ring.draw_arc(Vector2.ZERO, radius * 0.35, 0, TAU, 36,
			Color(1.00, 0.55, 0.15, 0.95), 6.0, true))
	n.add_child(ring)
	var ring_tw := ring.create_tween().set_parallel(true)
	ring_tw.tween_property(ring, "scale", Vector2(3.2, 3.2), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tw.tween_property(ring, "modulate:a", 0.0, 0.35)
	get_tree().create_timer(0.45).timeout.connect(n.queue_free)

# ─── Macro tier ────────────────────────────────────────────────────────────

func _hero_freed(world_pos: Vector2, opts: Dictionary) -> void:
	# Painted hero-freed burst (musical notes + radial glow + sparkles). 600 ms.
	if _sprite_burst(world_pos, "hero_freed", 120.0, 0.60, 0.50, 1.10) != null:
		return
	# Fallback: 3 concentric gold rings.
	var n := _spawn(world_pos)
	for i in range(3):
		var ring := Node2D.new()
		ring.set_meta("idx", i)
		ring.draw.connect(func() -> void:
			ring.draw_arc(Vector2.ZERO, 8.0, 0, TAU, 24, COLOR_HEX["GOLD"], 3.0, true))
		n.add_child(ring)
		var tw := n.create_tween().set_parallel(true)
		tw.tween_interval(0.15 * i)
		tw.chain().tween_property(ring, "scale", Vector2(5.0, 5.0), 0.40) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.40)
	# Auto-free after worst-case duration.
	get_tree().create_timer(0.9).timeout.connect(n.queue_free)

func _enemy_breach(world_pos: Vector2, opts: Dictionary) -> void:
	# Heavy thud + painted impact crater. 400 ms.
	if _sprite_burst(world_pos, "enemy_breach", 110.0, 0.40, 0.55, 1.30) != null:
		return
	# Fallback: shock ring.
	var n := _spawn(world_pos)
	n.draw.connect(func() -> void:
		n.draw_arc(Vector2.ZERO, 18.0, 0, TAU, 32, Color(1, 1, 1, 0.85), 3.5, true))
	n.queue_redraw()
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector2(3.0, 3.0), 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 0.0, 0.40)
	tw.chain().tween_callback(n.queue_free)

func _color_frenzy(world_pos: Vector2, opts: Dictionary) -> void:
	# Screen-edge tint pulse. Spawns a fullscreen ColorRect on the VFX layer
	# and pulses it. Position arg ignored (it's a full-screen effect).
	var rect := ColorRect.new()
	var col: Color = _color_of(opts, "RED")
	col.a = 0.0
	rect.color = col
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", 0.35, 0.20)
	tw.tween_property(rect, "color:a", 0.0, 0.40)
	tw.tween_callback(rect.queue_free)

# ─── Mega tier ─────────────────────────────────────────────────────────────

func _wave_clear(world_pos: Vector2, opts: Dictionary) -> void:
	# Confetti burst — 40 colored particles in the 5 class colors. 1.5 s.
	var n := _spawn(world_pos)
	var palette: Array[String] = ["RED", "BLUE", "YELLOW", "GREEN", "PURPLE"]
	for i in range(40):
		var p := Node2D.new()
		var ang: float = randf() * TAU
		var spd: float = randf_range(80.0, 180.0)
		var col: Color = COLOR_HEX[palette[i % palette.size()]]
		p.set_meta("vel", Vector2(cos(ang), sin(ang)) * spd)
		p.draw.connect(func() -> void:
			p.draw_rect(Rect2(-3, -2, 6, 4), col))
		n.add_child(p)
		var tw := n.create_tween().set_parallel(true)
		tw.tween_property(p, "position", p.get_meta("vel") * 1.2, 1.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "rotation", randf_range(-TAU, TAU), 1.2)
		tw.tween_property(p, "modulate:a", 0.0, 1.2)
	get_tree().create_timer(1.5).timeout.connect(n.queue_free)

# ─── Ultimates (macro tier, 600–800 ms, bespoke per class per §8.2) ────────

func _ult_eruption(world_pos: Vector2, opts: Dictionary) -> void:
	# Fire Knight — vertical flame column from below + 200 ms shake hook.
	var n := _spawn(world_pos)
	var col: Color = COLOR_HEX["RED"]
	n.draw.connect(func() -> void:
		n.draw_rect(Rect2(-30, -240, 60, 240), Color(col.r, col.g, col.b, 0.70)))
	n.queue_redraw()
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector2(1.6, 1.0), 0.50).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(n, "modulate:a", 0.0, 0.70)
	tw.chain().tween_callback(n.queue_free)

func _ult_cryo_wave(world_pos: Vector2, opts: Dictionary) -> void:
	# Ice Mage — horizontal frost sweep. 700 ms.
	var n := _spawn(world_pos)
	var col: Color = COLOR_HEX["BLUE"]
	n.draw.connect(func() -> void:
		n.draw_rect(Rect2(-360, -20, 720, 40), Color(col.r, col.g, col.b, 0.55)))
	n.queue_redraw()
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector2(1.0, 2.0), 0.35).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(n, "modulate:a", 0.0, 0.70)
	tw.chain().tween_callback(n.queue_free)

func _ult_volley(world_pos: Vector2, opts: Dictionary) -> void:
	# Archer — arc of arrows from off-screen left.
	var n := _spawn(world_pos)
	for i in range(8):
		var arrow := Node2D.new()
		arrow.position = Vector2(-360, -200)
		arrow.set_meta("target", Vector2(randf_range(-200, 200), randf_range(-40, 40)))
		arrow.draw.connect(func() -> void:
			arrow.draw_line(Vector2.ZERO, Vector2(16, 0), COLOR_HEX["YELLOW"], 3.0))
		n.add_child(arrow)
		var tw := n.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(arrow, "position", arrow.get_meta("target"), 0.40) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(arrow, "modulate:a", 0.0, 0.10)
	get_tree().create_timer(1.0).timeout.connect(n.queue_free)

func _ult_verdant_surge(world_pos: Vector2, opts: Dictionary) -> void:
	# Druid — green ground bloom + rising healing motes.
	var n := _spawn(world_pos)
	var col: Color = COLOR_HEX["GREEN"]
	n.draw.connect(func() -> void:
		n.draw_circle(Vector2.ZERO, 100.0, Color(col.r, col.g, col.b, 0.40)))
	n.queue_redraw()
	for i in range(12):
		var mote := Node2D.new()
		mote.position = Vector2(randf_range(-60, 60), 0.0)
		mote.draw.connect(func() -> void:
			mote.draw_circle(Vector2.ZERO, 3.0, COLOR_HEX["GREEN"]))
		n.add_child(mote)
		var tw := n.create_tween().set_parallel(true)
		tw.tween_property(mote, "position:y", -80.0, 0.70)
		tw.tween_property(mote, "modulate:a", 0.0, 0.70)
	var ring_tw := n.create_tween().set_parallel(true)
	ring_tw.tween_property(n, "scale", Vector2(1.4, 1.4), 0.70)
	ring_tw.tween_property(n, "modulate:a", 0.0, 0.70)
	get_tree().create_timer(0.9).timeout.connect(n.queue_free)

func _ult_forking_bolt(world_pos: Vector2, opts: Dictionary) -> void:
	# Wizard — purple chain lightning, 3 hops. 600 ms.
	var n := _spawn(world_pos)
	var hops: Array = opts.get("hops", [Vector2(60, -40), Vector2(120, 10), Vector2(180, -30)])
	var prev: Vector2 = Vector2.ZERO
	for i in range(hops.size()):
		var hop := Node2D.new()
		var start: Vector2 = prev
		var end: Vector2 = hops[i]
		hop.set_meta("start", start)
		hop.set_meta("end", end)
		hop.draw.connect(func() -> void:
			hop.draw_line(hop.get_meta("start"), hop.get_meta("end"), COLOR_HEX["PURPLE"], 3.5))
		n.add_child(hop)
		hop.modulate.a = 0.0
		var tw := n.create_tween()
		tw.tween_interval(0.08 * i)
		tw.tween_property(hop, "modulate:a", 1.0, 0.05)
		tw.tween_property(hop, "modulate:a", 0.0, 0.35)
		prev = end
	get_tree().create_timer(0.8).timeout.connect(n.queue_free)

# ─── Boss ─────────────────────────────────────────────────────────────────

func _boss_corruption(world_pos: Vector2, opts: Dictionary) -> void:
	# Purple lightning crackle along boss tendril → target column. 500 ms.
	var n := _spawn(world_pos)
	var target: Vector2 = opts.get("target_local", Vector2(0, 200))
	n.set_meta("target", target)
	n.draw.connect(func() -> void:
		n.draw_line(Vector2.ZERO, n.get_meta("target"), COLOR_HEX["PURPLE"], 4.5))
	n.queue_redraw()
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "modulate:a", 0.2, 0.10)
	tw.tween_property(n, "modulate:a", 1.0, 0.10).set_delay(0.10)
	tw.tween_property(n, "modulate:a", 0.0, 0.30).set_delay(0.25)
	tw.chain().tween_callback(n.queue_free)
