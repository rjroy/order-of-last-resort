extends RefCounted

const MODULUS := 2147483647


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
