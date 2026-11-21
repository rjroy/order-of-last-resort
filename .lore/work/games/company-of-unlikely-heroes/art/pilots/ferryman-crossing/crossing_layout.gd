extends RefCounted
## Plate-space projection from the Ferryman's Crossing guide, not the painted shoreline.

const PLATE_SIZE := Vector2(1536, 1024)
const GRID_SIZE := Vector2i(7, 5)
const ORIGIN := Vector2(272, 176)
const COLUMN := Vector2(184, 18)
const ROW := Vector2(-28, 146)
const GRID_TO_PLATE := Transform2D(COLUMN, ROW, ORIGIN)

const INVALID := Vector2i(-1, -1)
const SPAN := Vector2i(3, 2)
const KNIGHT := Vector2i(1, 1)
# The pilot moves the Healer one authored tile from A3 to A2 to face the ally.
const HEALER := Vector2i(0, 1)
const CRATE_START := Vector2i(2, 2)
const CRATE_END := Vector2i(2, 3)
const THREAT := Vector2i(2, 1)


static func project(cell: Vector2) -> Vector2:
	return GRID_TO_PLATE * cell


static func cell_at(plate_point: Vector2) -> Vector2i:
	return Vector2i((GRID_TO_PLATE.affine_inverse() * plate_point + Vector2(0.5, 0.5)).floor())


static func can_select(cell: Vector2i, span_intact: bool) -> bool:
	if not Rect2i(Vector2i.ZERO, GRID_SIZE).has_point(cell):
		return false
	return cell.x != SPAN.x or (cell == SPAN and span_intact)


static func address(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]
