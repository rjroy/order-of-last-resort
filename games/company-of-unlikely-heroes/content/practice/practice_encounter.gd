extends RefCounted
## A stock-only drill. Never added to the launch catalog or commission pools.

const Catalog := preload("res://content/catalog.gd")
const Rules := preload("res://rules.gd")
const MISSION_ID := "founders_practice"
const CATALOG_PATH := "res://content/practice/catalog.json"
const FOUNDERS := ["knight", "healer", "wizard"]

static var _opening: Dictionary


static func open() -> Dictionary:
	if _opening.is_empty():
		var source := Catalog.read_source(CATALOG_PATH)
		if source.has("error"):
			push_error(str(source.error))
			return {}
		var state := Rules.open_mission(source.definitions, MISSION_ID)
		if state.is_empty():
			return {}
		# The fixed placements include a wounded founder; no guild or chosen kit
		# participates in the setup. The opening catalog is frozen by Rules.
		state["party"] = FOUNDERS.duplicate()
		_opening = state
	return _opening.duplicate(true)
