extends RefCounted
## A separate shuffled bag per music set. The supplied RNG is not gameplay RNG.

var _tracks: Array
var _remaining: Array = []
var _rng: RandomNumberGenerator
var _last: Variant = null


func _init(tracks: Array, rng: RandomNumberGenerator) -> void:
	_tracks = tracks.duplicate()
	_rng = rng


func next_track() -> Variant:
	if _tracks.is_empty():
		return null
	if _remaining.is_empty():
		_remaining = _tracks.duplicate()
		for i in range(_remaining.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var item: Variant = _remaining[i]
			_remaining[i] = _remaining[j]
			_remaining[j] = item
		# The next draw comes from the back; avoid an immediate repeat at a
		# bag boundary where another track is available.
		if _remaining.size() > 1 and _remaining.back() == _last:
			var swap := _rng.randi_range(0, _remaining.size() - 2)
			var item: Variant = _remaining[swap]
			_remaining[swap] = _remaining.back()
			_remaining[_remaining.size() - 1] = item
	_last = _remaining.pop_back()
	return _last
