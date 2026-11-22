extends RefCounted

const MODULUS := 2147483647


## Stable across previews and independent of any reward or route draws.
static func mission_dose_seed(outing_seed: int, mission_index: int, mission_id: String) -> int:
	var key := "alchemy:%d:%d:%s" % [outing_seed, mission_index, mission_id]
	return 1 + key.sha256_text().left(8).hex_to_int() % (MODULUS - 1)


static func step(seed_value: int) -> int:
	return (seed_value * 48271) % MODULUS


## Draw without changing the snapshot. The caller retains the returned seed on execution.
static func uniform_draw(seed_value: int, count: int) -> Dictionary:
	# Park–Miller produces 1 through MODULUS - 1. Reject the uneven tail before reducing.
	var largest_bucket_end := (MODULUS - 1) - (MODULUS - 1) % count
	var next := step(seed_value)
	while next > largest_bucket_end:
		next = step(next)
	return {"index": (next - 1) % count, "seed": next}
