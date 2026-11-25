extends Node
## One shared player-owned effects service. Requests are emitted only after playback starts.

signal sound_requested(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float)

const Preferences = preload("res://battle_display_preferences.gd")
const Recipes = preload("res://presentation/sound_recipes.gd")
# Mix target for an ability impact at 80% SFX and full Master.
const IMPACT_REFERENCE_DB := -14.0
const REFERENCE_SFX_VOLUME := 0.8
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
	"bell": preload("res://assets/audio/approved_undead/grave_bell.wav"),
	"skeleton_summon": preload("res://assets/audio/approved_undead/summon_skeleton.wav"),
	"raise": preload("res://assets/audio/approved_undead/raise_dead.wav"),
	"nominate": preload("res://assets/audio/approved_undead/say_hello_to_that_one.wav"),
	"bone_wave": preload("res://assets/audio/approved_undead/skeleton_wave.wav"),
	"bone_hold": preload("res://assets/audio/approved_undead/skeleton_dont_go.wav"),
	"zombie_hello": preload("res://assets/audio/approved_undead/zombie_say_hello.wav"),
	"flower": preload("res://assets/audio/approved_undead/zombie_offer_flower.wav"),
	"sparks": preload("res://assets/audio/approved_undead/ring_of_sparks.wav"),
	"misdirect": preload("res://assets/audio/approved_undead/wasnt_me.wav"),
}

var volume := 0.8
var master_volume := 1.0
static var _tones := {}


func _ready() -> void:
	volume = Preferences.load_sound_effects_volume()
	master_volume = Preferences.load_master_volume()


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	Preferences.save_sound_effects_volume(volume)
	_update_players()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_update_players()


func _update_players() -> void:
	for player in get_children():
		if player is AudioStreamPlayer:
			if volume * master_volume == 0.0:
				player.stop()
				player.queue_free()
			else:
				player.volume_db = linear_to_db(volume * master_volume * float(player.get_meta("base_gain")))


func planning(unit_id: String) -> void:
	_play("planning", unit_id, "move", "pencil", 0.22 / 0.7)


func dispatch_beat(kind: String, unit_id: String, ability_id: String, handler: String, recipe: String) -> void:
	if kind == "step":
		_play(kind, unit_id, ability_id, "step", 0.45 / 0.7)
		return
	if kind != "impact":
		return
	var key := _family(ability_id, handler, recipe)
	if not key.is_empty():
		_play(kind, unit_id, ability_id, key, 1.0)


func _family(ability: String, handler: String, recipe: String) -> String:
	if handler == "repeat_batch":
		match recipe:
			"alchemist_potion":
				return "dose"
			"alchemist_acid":
				return "potion"
			"alchemist_etching_paste":
				return "paste"
		return "gesture"
	# IDs may be redefined by custom catalogs. Specialize only inside the
	# resolved handler; playback derives close_thrust and harmless_attack from
	# the actual action and its action-time context.
	match handler:
		"close_thrust":
			return "shaft"
		"harmless_attack":
			return "shepherd" if ability == "frontier_shepherd_wave" else "gesture"
		"attack":
			match ability:
				"knight_shield_throw": return "shield_throw"
				"offer_flower": return "flower"
				"goblin_jab", "trickster_strike": return "point"
				"duelist_strike": return "foil"
				"captain_strike", "grunt_strike", "bandit_strike": return "leather_iron"
				"bruiser_strike", "ogre_strike": return "maul"
				"frontier_wagon_strike": return "wagon"
				"bomber_strike": return "bomber"
				"rival_bonk": return "bonk"
				"enemy_harpoon", "archer_shot": return "bow"
			return "shield"
		"bonk":
			return "bonk" if ability == "healer_bonk" else "shield"
		"push":
			return "shunt" if ability == "knight_push" else "shield"
		"apply_status":
			return "aura" if ability == "knight_aura" else "shield"
		"blast":
			return "blast"
		"sweep":
			match ability:
				"wizard_ring_sparks": return "sparks"
				"wave": return "bone_wave"
			return "blast"
		"acid":
			return "paste" if ability == "alchemist_etching_paste" else "potion"
		"heal":
			return "dressing" if ability == "healer_field_dressing" else "heal"
		"enemy_heal":
			return "enemy_heal" if ability == "frontier_heal" else "heal"
		"healing_potion":
			return "dose" if ability == "alchemist_potion" else "heal"
		"plain_tonic":
			return "dose" if ability == "alchemist_plain_tonic" else "heal"
		"hook":
			return "rope"
		"pull":
			return "magic_pull"
		"repel":
			match ability:
				"necro_grave_bell": return "bell"
				"say_hello": return "zombie_hello"
			return "gesture"
		"summon":
			match ability:
				"raise_dead": return "raise"
				"summon_skeleton": return "skeleton_summon"
			return "bones"
		"perform":
			match ability:
				"frontier_war_drum": return "drum"
				"bard_take_the_stage": return "stage"
			return "melody" if ability == "inspiring_melody" else "sonnet"
		"misdirect":
			return "misdirect" if ability == "rogue_wasnt_me" else "gesture"
		"nominate":
			return "nominate" if ability == "necromancer_say_hello_to_that_one" else "gesture"
		"stop_target":
			match ability:
				"rogue_tripwire": return "tripwire"
				"dont_go": return "bone_hold"
			return "gesture"
		"swap_ally":
			return "ogre_swap" if ability == "ogre_swap" else "gesture"
		"swap_furthest":
			return "dodge" if ability == "rogue_confusing_dodge" else "gesture"
	return ""


func _play(kind: String, unit_id: String, ability_id: String, cue_id: String, relative_gain: float) -> void:
	if volume <= 0.0 or master_volume <= 0.0:
		return
	var stream: AudioStream = WAVS.get(cue_id)
	if stream == null:
		stream = Recipes.get_stream(cue_id)
	if stream == null:
		stream = _legacy_tone(cue_id)
	if stream == null:
		push_warning("Missing sound effect %s for %s." % [cue_id, ability_id])
		return
	var base_gain := db_to_linear(IMPACT_REFERENCE_DB) / REFERENCE_SFX_VOLUME * relative_gain
	var gain := volume * master_volume * base_gain
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(gain)
	player.set_meta("base_gain", base_gain)
	add_child(player)
	player.finished.connect(player.queue_free)
	print_verbose("Playing %s sound %s for %s (%s)." % [kind, cue_id, unit_id, ability_id])
	player.play()
	sound_requested.emit(kind, unit_id, ability_id, cue_id, gain)


static func _legacy_tone(key: String) -> AudioStreamWAV:
	if _tones.has(key):
		return _tones[key]
	var stream: AudioStreamWAV
	match key:
		"heal": stream = _tone([660.0, 990.0], 0.26)
		"melody": stream = _tone([523.25, 659.25, 783.99], 0.39)
		"sonnet": stream = _tone([440.0, 523.25, 622.25], 0.39)
		"stage": stream = _tone([440.0, 523.25, 622.25, 880.0], 0.52)
		"gesture": stream = _tone([392.0, 493.88], 0.19)
	if stream != null:
		_tones[key] = stream
	return stream


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
