extends RefCounted
## Deterministic, dry mono effects. A layer is [kind, start, length, Hz,
## ending Hz, amplitude, decay, filter]. Noise uses a local integer generator.

const RATE := 22050
const RECIPES := {
	"shield_throw": [["noise", 0.0, 0.08, 0, 0, 0.12, 22, 0.30], ["mode", 0.01, 0.23, 390, 300, 0.13, 16, 0], ["mode", 0.02, 0.20, 810, 790, 0.07, 20, 0]],
	"shunt": [["noise", 0.0, 0.15, 0, 0, 0.15, 15, 0.12], ["mode", 0.01, 0.14, 145, 100, 0.12, 21, 0]],
	"aura": [["mode", 0.0, 0.36, 960, 1320, 0.09, 8, 0], ["mode", 0.04, 0.30, 1510, 1950, 0.06, 10, 0], ["noise", 0.0, 0.20, 0, 0, 0.025, 12, 0.7]],
	"sparks": [["noise", 0.0, 0.22, 0, 0, 0.11, 12, 0.8], ["mode", 0.0, 0.18, 1750, 900, 0.09, 20, 0], ["noise", 0.09, 0.12, 0, 0, 0.10, 25, 0.9]],
	"magic_pull": [["noise", 0.0, 0.28, 0, 0, 0.13, 5, 0.18], ["mode", 0.0, 0.30, 520, 110, 0.12, 7, 0], ["mode", 0.22, 0.15, 115, 65, 0.12, 20, 0]],
	"tripwire": [["noise", 0.0, 0.08, 0, 0, 0.06, 25, 0.4], ["mode", 0.01, 0.23, 430, 350, 0.15, 16, 0], ["mode", 0.01, 0.14, 860, 700, 0.06, 24, 0]],
	"dodge": [["noise", 0.0, 0.15, 0, 0, 0.13, 12, 0.35], ["noise", 0.09, 0.17, 0, 0, 0.11, 13, 0.22]],
	"misdirect": [["noise", 0.0, 0.09, 0, 0, 0.11, 24, 0.55], ["mode", 0.025, 0.10, 600, 450, 0.045, 25, 0]],
	"nominate": [["noise", 0.0, 0.10, 0, 0, 0.075, 20, 0.3], ["mode", 0.04, 0.16, 650, 840, 0.07, 16, 0]],
	"bonk": [["noise", 0.0, 0.08, 0, 0, 0.12, 28, 0.25], ["mode", 0.0, 0.14, 260, 210, 0.16, 22, 0], ["mode", 0.01, 0.10, 570, 500, 0.06, 28, 0]],
	"dressing": [["noise", 0.0, 0.20, 0, 0, 0.11, 10, 0.20], ["noise", 0.10, 0.13, 0, 0, 0.07, 18, 0.35]],
	"dose": [["mode", 0.0, 0.12, 540, 450, 0.09, 25, 0], ["noise", 0.02, 0.09, 0, 0, 0.07, 22, 0.16], ["mode", 0.08, 0.16, 900, 880, 0.055, 20, 0]],
	"paste": [["noise", 0.0, 0.25, 0, 0, 0.10, 10, 0.5], ["mode", 0.02, 0.20, 170, 260, 0.08, 15, 0], ["noise", 0.11, 0.12, 0, 0, 0.06, 20, 0.85]],
	"raise": [["noise", 0.0, 0.34, 0, 0, 0.15, 7, 0.12], ["mode", 0.08, 0.23, 160, 95, 0.08, 10, 0], ["noise", 0.17, 0.18, 0, 0, 0.09, 12, 0.25]],
	"bone_wave": [["mode", 0.0, 0.13, 640, 580, 0.12, 27, 0], ["mode", 0.08, 0.13, 810, 760, 0.11, 27, 0], ["noise", 0.0, 0.12, 0, 0, 0.07, 25, 0.5]],
	"bone_hold": [["mode", 0.0, 0.20, 350, 300, 0.13, 17, 0], ["mode", 0.09, 0.15, 530, 480, 0.08, 22, 0], ["noise", 0.03, 0.14, 0, 0, 0.06, 18, 0.3]],
	"zombie_hello": [["noise", 0.0, 0.30, 0, 0, 0.11, 8, 0.10], ["mode", 0.03, 0.24, 125, 95, 0.07, 8, 0]],
	"flower": [["noise", 0.0, 0.18, 0, 0, 0.10, 14, 0.55], ["mode", 0.08, 0.15, 240, 170, 0.11, 23, 0], ["mode", 0.08, 0.10, 670, 620, 0.045, 28, 0]],
	"shepherd": [["noise", 0.0, 0.22, 0, 0, 0.11, 10, 0.25], ["noise", 0.10, 0.13, 0, 0, 0.06, 18, 0.45]],
	"shaft": [["noise", 0.0, 0.08, 0, 0, 0.08, 27, 0.4], ["mode", 0.0, 0.12, 430, 390, 0.13, 24, 0]],
	"point": [["noise", 0.0, 0.06, 0, 0, 0.08, 35, 0.75], ["mode", 0.0, 0.09, 1050, 900, 0.09, 32, 0]],
	"foil": [["noise", 0.0, 0.11, 0, 0, 0.08, 20, 0.75], ["mode", 0.01, 0.15, 1500, 1200, 0.09, 22, 0]],
	"leather_iron": [["noise", 0.0, 0.10, 0, 0, 0.14, 22, 0.18], ["mode", 0.01, 0.16, 620, 570, 0.08, 20, 0]],
	"maul": [["noise", 0.0, 0.15, 0, 0, 0.17, 16, 0.10], ["mode", 0.0, 0.18, 115, 75, 0.17, 18, 0]],
	"wagon": [["noise", 0.0, 0.13, 0, 0, 0.13, 19, 0.20], ["mode", 0.01, 0.23, 210, 180, 0.15, 15, 0], ["mode", 0.05, 0.14, 450, 410, 0.06, 22, 0]],
	"bomber": [["noise", 0.0, 0.10, 0, 0, 0.13, 23, 0.28], ["mode", 0.0, 0.13, 330, 250, 0.10, 25, 0]],
	"ogre_swap": [["noise", 0.0, 0.25, 0, 0, 0.14, 9, 0.14], ["mode", 0.06, 0.20, 180, 280, 0.10, 12, 0]],
	"enemy_heal": [["mode", 0.0, 0.26, 440, 620, 0.09, 9, 0], ["mode", 0.05, 0.25, 660, 830, 0.07, 10, 0]],
}

static var _cache := {}


static func get_stream(key: String) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	if not RECIPES.has(key):
		return null
	var layers: Array = RECIPES[key]
	var duration := 0.0
	for layer in layers:
		duration = maxf(duration, float(layer[1]) + float(layer[2]))
	var samples := PackedFloat32Array()
	samples.resize(int(ceil(duration * RATE)))
	for layer_index in layers.size():
		var layer: Array = layers[layer_index]
		var start := int(float(layer[1]) * RATE)
		var count := mini(int(float(layer[2]) * RATE), samples.size() - start)
		var phase := 0.0
		var filtered := 0.0
		var state: int = 104729 + layer_index * 7919
		for i in count:
			var t := float(i) / RATE
			var u := float(i) / maxi(count - 1, 1)
			var envelope := minf(1.0, t * 500.0) * minf(1.0, (1.0 - u) * 25.0) * exp(-t * float(layer[6]))
			var value := 0.0
			if layer[0] == "noise":
				state = (state * 1664525 + 1013904223) & 0xffffffff
				var noise := float(state) / 2147483648.0 - 1.0
				filtered += float(layer[7]) * (noise - filtered)
				value = filtered
			else:
				phase += TAU * lerpf(float(layer[3]), float(layer[4]), u) / RATE
				value = sin(phase)
			samples[start + i] += value * float(layer[5]) * envelope
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	_cache[key] = stream
	return stream
