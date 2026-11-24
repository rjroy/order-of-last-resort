extends Node
## One shared player-owned effects service. Requests are emitted only after playback starts.

signal sound_requested(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float)

const Preferences = preload("res://battle_display_preferences.gd")
const WAVS := {
	"pencil": preload("res://assets/audio/pencil_flick.wav"),
	"step": preload("res://assets/audio/light_footfall.wav"),
	"shield": preload("res://assets/audio/shield_strike.wav"),
	"bow": preload("res://assets/audio/bow_harpoon.wav"),
	"blast": preload("res://assets/audio/magical_blast.wav"),
	"bones": preload("res://assets/audio/bone_summon.wav"),
	"rope": preload("res://assets/audio/rope_pull.wav"),
	"drum": preload("res://assets/audio/war_drum.wav"),
	"potion": preload("res://assets/audio/potion_smash.wav"),
}

var volume := 0.8
var _tones := {}


func _ready() -> void:
	volume = Preferences.load_sound_effects_volume()
	_tones = {
		"heal": _tone([660.0, 990.0], 0.26),
		"melody": _tone([523.25, 659.25, 783.99], 0.39),
		"sonnet": _tone([440.0, 523.25, 622.25], 0.39),
		"gesture": _tone([392.0, 493.88], 0.19),
		"paste": _tone([294.0, 349.23], 0.15),
		"bell": _bell(),
	}


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	Preferences.save_sound_effects_volume(volume)
	for player in get_children():
		if player is AudioStreamPlayer:
			if volume == 0.0:
				player.stop()
				player.queue_free()
			else:
				player.volume_db = linear_to_db(volume * float(player.get_meta("base_gain")))


func planning(unit_id: String) -> void:
	_play("planning", unit_id, "move", "pencil", 0.22)


func dispatch_beat(kind: String, unit_id: String, ability_id: String, handler: String, recipe: String) -> void:
	if kind == "step":
		_play(kind, unit_id, ability_id, "step", 0.45)
		return
	if kind != "impact":
		return
	var key := _family(ability_id, handler, recipe)
	if not key.is_empty():
		_play(kind, unit_id, ability_id, key, 0.7)


func _family(ability: String, handler: String, recipe: String) -> String:
	if handler == "repeat_batch":
		match recipe:
			"alchemist_potion":
				return "heal"
			"alchemist_acid":
				return "potion"
			"alchemist_etching_paste":
				return "paste"
		return "gesture"
	match handler:
		"attack":
			if ability in ["enemy_harpoon", "archer_shot"]:
				return "bow"
			if ability == "offer_flower":
				return "gesture"
			return "shield"
		"bonk", "push", "apply_status", "close_thrust":
			return "shield"
		"blast", "sweep":
			return "blast"
		"acid":
			return "paste" if ability == "alchemist_etching_paste" else "potion"
		"heal", "enemy_heal", "healing_potion", "plain_tonic":
			return "heal"
		"hook", "pull":
			return "rope"
		"repel":
			return "bell" if ability == "necro_grave_bell" else "gesture"
		"summon":
			return "bones"
		"perform":
			if ability == "frontier_war_drum":
				return "drum"
			return "melody" if ability == "inspiring_melody" else "sonnet"
		"misdirect", "nominate", "stop_target", "swap_ally", "swap_furthest", "harmless_attack":
			return "gesture"
	return ""


func _play(kind: String, unit_id: String, ability_id: String, cue_id: String, base_gain: float) -> void:
	if volume <= 0.0:
		return
	var stream: AudioStream = WAVS.get(cue_id, _tones.get(cue_id))
	if stream == null:
		push_warning("Missing sound effect %s for %s." % [cue_id, ability_id])
		return
	var gain := volume * base_gain
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(gain)
	player.set_meta("base_gain", base_gain)
	add_child(player)
	player.finished.connect(player.queue_free)
	print_verbose("Playing %s sound %s for %s (%s)." % [kind, cue_id, unit_id, ability_id])
	player.play()
	sound_requested.emit(kind, unit_id, ability_id, cue_id, gain)


static func _tone(notes: Array, duration: float) -> AudioStreamWAV:
	# Short, dry, deterministic tones for semantic families without approved foley.
	const RATE := 22050
	var count := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var note_index := mini(int(t / duration * notes.size()), notes.size() - 1)
		var local := fposmod(t, duration / notes.size())
		var envelope := minf(1.0, local * 80.0) * exp(-local * 11.0) * minf(1.0, (duration - t) * 40.0)
		var sample := sin(TAU * float(notes[note_index]) * local) * envelope * 0.28
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream


static func _bell() -> AudioStreamWAV:
	# A small struck bell: an immediate, decaying fundamental and metal partials.
	const RATE := 22050
	const DURATION := 0.45
	var count := int(RATE * DURATION)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var attack := minf(1.0, t * 300.0)
		var sample := attack * (0.20 * sin(TAU * 740.0 * t) * exp(-t * 7.0) \
			+ 0.08 * sin(TAU * 1850.0 * t) * exp(-t * 14.0) \
			+ 0.04 * sin(TAU * 2960.0 * t) * exp(-t * 20.0))
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
