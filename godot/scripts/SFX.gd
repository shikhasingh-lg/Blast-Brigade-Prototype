extends Node
## Autoload SFX player. Loads AudioStream resources by name and plays one-shots.
## Safe to call before partner audio delivery: missing files no-op silently.
##
## Usage:
##   SFX.play("bubble_pop", {"pitch_cents": 20})     # ±cents jitter
##   SFX.play("hero_fire_FK")
##   SFX.play_music_layer("ambient_sunbloom", 1.0)   # fade in over 1.0 s
##   SFX.play_music_layer("ambient_sunbloom", 0.0)   # fade out
##
## File layout (Phase 10 delivery): res://assets/sfx/{category}/{name}.ogg
##   sfx/bubble/bubble_pop_red_v{1..5}.ogg     — 5 pitch variants per color
##   sfx/hero/fire_{FK,IM,AR,DR,WZ}.ogg
##   sfx/enemy/walk_{walker,runner,brute}.ogg  — loopable
##   sfx/enemy/breach.ogg / death.ogg
##   sfx/status/{slow,freeze,burn,poison,stun}.ogg
##   sfx/ui/{tap,confirm,cancel,error}.ogg
##   sfx/sting/{wave_clear,run_clear,final_move_warn,hero_freed}.ogg
##   sfx/music/{ambient_sunbloom,combat_sunbloom,boss_corrupter,frenzy_riser}.ogg
##
## All paths optional — see _resolve_path; missing files print a single warning
## and play nothing, so we can wire SFX.play() calls now and ship sound later.

const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"
const BUS_UI: StringName = &"UI"

# Per-color pitch fundamentals from audio-brief.md §6 — bubble pop pitches lift
# in semitones as the color "rises" through the spectrum. Encoded in cents
# (100 cents = 1 semitone). Each call adds ±20 cents random jitter on top.
const BUBBLE_PITCH_OFFSET_CENTS: Dictionary = {
	"RED":    0,       # 220 Hz fundamental — baseline
	"YELLOW": 300,     # 264 Hz ≈ +3 semitones
	"GREEN":  500,     # 294 Hz ≈ +5 semitones
	"BLUE":   700,     # 330 Hz ≈ +7 semitones
	"PURPLE": 1000,    # 392 Hz ≈ +10 semitones
}

var _missing_warned: Dictionary = {}   # path -> true, so we only warn once per file
var _music_players: Dictionary = {}    # layer_name -> AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_ensure_buses()

func _ensure_buses() -> void:
	# Add SFX / Music / UI buses if the project hasn't been configured with them
	# yet (default project only has Master). Idempotent.
	for bus_name in [BUS_SFX, BUS_MUSIC, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

# ─── Public API: one-shot SFX ──────────────────────────────────────────────

func play(sfx_name: String, opts: Dictionary = {}) -> void:
	var path: String = _resolve_path(sfx_name, opts)
	if path == "":
		return
	var stream: AudioStream = _load(path)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = opts.get("bus", BUS_SFX)
	p.volume_db = opts.get("volume_db", 0.0)
	var cents: float = float(opts.get("pitch_cents", 0))
	# ±jitter cents on every call (audio-brief.md §2 — "every SFX that fires
	# >1×/second needs 3–5 micro-variants that randomize on play"). The variants
	# come from picking a random file suffix in _resolve_path; the pitch jitter
	# is an additional fine-grain randomization on top.
	var jitter_cents: float = float(opts.get("jitter_cents", 20.0))
	if jitter_cents > 0.0:
		cents += _rng.randf_range(-jitter_cents, jitter_cents)
	p.pitch_scale = pow(2.0, cents / 1200.0)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func play_bubble_pop(color: String) -> void:
	# Convenience: bubble pop with per-color pitch offset (audio-brief §6).
	# Cluster-pop layering (4+ bubbles popping in one match) is the caller's
	# job — call play_bubble_pop() with a 30–50 ms stagger between hits.
	play("bubble_pop", {
		"color": color,
		"pitch_cents": BUBBLE_PITCH_OFFSET_CENTS.get(color, 0),
		"jitter_cents": 20.0,
	})

# ─── Music layering (audio-brief.md §4.1) ──────────────────────────────────

func play_music_layer(layer_name: String, fade_sec: float = 0.0, target_volume_db: float = 0.0) -> void:
	# Fades layer to target_volume_db over fade_sec. Use 0.0 fade for snap.
	# Call with -80.0 (or any "silent" value) target to fade out a layer.
	var p: AudioStreamPlayer = _music_players.get(layer_name)
	if p == null:
		var path: String = "res://assets/sfx/music/%s.ogg" % layer_name
		var stream: AudioStream = _load(path)
		if stream == null:
			return
		p = AudioStreamPlayer.new()
		p.stream = stream
		p.bus = BUS_MUSIC
		p.volume_db = -80.0
		add_child(p)
		_music_players[layer_name] = p
		p.play()
	if fade_sec <= 0.0:
		p.volume_db = target_volume_db
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_volume_db, fade_sec)

func stop_music_layer(layer_name: String, fade_sec: float = 0.5) -> void:
	play_music_layer(layer_name, fade_sec, -80.0)

# ─── Internals ─────────────────────────────────────────────────────────────

func _resolve_path(sfx_name: String, opts: Dictionary) -> String:
	# Map the logical event name to a file path. Files with multiple pitch
	# variants pick one at random per call (see audio-brief §2 variation rule).
	match sfx_name:
		"bubble_pop":
			var color: String = opts.get("color", "RED")
			var v: int = _rng.randi_range(1, 5)
			return "res://assets/sfx/bubble/bubble_pop_%s_v%d.ogg" % [color.to_lower(), v]
		"hero_fire_FireKnight": return "res://assets/sfx/hero/fire_FK.ogg"
		"hero_fire_IceMage":    return "res://assets/sfx/hero/fire_IM.ogg"
		"hero_fire_Archer":     return "res://assets/sfx/hero/fire_AR.ogg"
		"hero_fire_Druid":      return "res://assets/sfx/hero/fire_DR.ogg"
		"hero_fire_Wizard":     return "res://assets/sfx/hero/fire_WZ.ogg"
		"hero_freed":           return "res://assets/sfx/sting/hero_freed.ogg"
		"cannon_fire":
			# Blast Brigade — muzzle boom on cannon trigger. Multiple variants
			# expected so rapid fire doesn't feel robotic.
			var fv: int = _rng.randi_range(1, 3)
			return "res://assets/sfx/cannon/fire_v%d.ogg" % fv
		"bomb_impact":
			# Bomb detonation thud-crack — heavier, sub-bass. Variants so the
			# AOE wipe of a tight cluster doesn't stack identical samples.
			var iv: int = _rng.randi_range(1, 3)
			return "res://assets/sfx/cannon/impact_v%d.ogg" % iv
		"enemy_breach":         return "res://assets/sfx/enemy/breach.ogg"
		"enemy_death":
			var v2: int = _rng.randi_range(1, 3)
			return "res://assets/sfx/enemy/death_v%d.ogg" % v2
		"status_slow":          return "res://assets/sfx/status/slow.ogg"
		"status_freeze":        return "res://assets/sfx/status/freeze.ogg"
		"status_burn":          return "res://assets/sfx/status/burn.ogg"
		"status_poison":        return "res://assets/sfx/status/poison.ogg"
		"status_stun":          return "res://assets/sfx/status/stun.ogg"
		"wave_clear":           return "res://assets/sfx/sting/wave_clear.ogg"
		"final_move_warn":      return "res://assets/sfx/sting/final_move_warn.ogg"
		"ui_tap":               return "res://assets/sfx/ui/tap.ogg"
		"ui_confirm":           return "res://assets/sfx/ui/confirm.ogg"
		"ui_cancel":            return "res://assets/sfx/ui/cancel.ogg"
		"ui_error":             return "res://assets/sfx/ui/error.ogg"
	push_warning("SFX.play: unknown event '%s'" % sfx_name)
	return ""

func _load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path, "AudioStream"):
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			# Single line per missing file, then silence. This is the
			# "ship before audio partner delivers" path — expected to be loud
			# at boot, silent thereafter.
			print("[SFX] missing stream: %s (will no-op)" % path)
		return null
	return load(path) as AudioStream
