extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/guild_book_art_test.gd
const ART_SCRIPT := "res://presentation/book/guild_book_art.gd"
const ILLUSTRATED_REPORTS := [
	"bridge_is_out", "bridge_patrol", "company_rescue", "cowardly_captain",
	"dont_wake_the_giant", "duelists", "explosive_situation", "goblin_mob",
	"great_sheep_escape", "harpoon_squad", "hold_the_line", "last_one_standing",
	"last_wagon", "mirror_company", "odd_couple", "shield_wall",
	"unfortunate_healer", "unfortunate_ritual", "unwelcome_guest", "wrong_side_of_the_door",
]
var failures: Array[String] = []


func _initialize() -> void:
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default()
	_check(not defs.is_empty(), "Stock catalog loads")
	if not ResourceLoader.exists(ART_SCRIPT):
		_check(false, "Guild book artwork resolver exists")
	else:
		var art = load(ART_SCRIPT)
		for method in ["class_portrait", "destination", "report", "upgrade"]:
			_check(art.has_method(method), "Artwork resolver exposes " + method)
		if ["class_portrait", "destination", "report", "upgrade"].all(func(method): return art.has_method(method)):
			for id in defs.commission_settings.recruitment_roster:
				var portrait_id: String = defs.characters[id].get("guild_portrait", "")
				_check(not portrait_id.is_empty(), "Recruit %s opts into a portrait identity" % id)
				_check_texture(art.call("class_portrait", portrait_id), "classes", portrait_id)
			_check(defs.characters.blacksmith.get("guild_portrait", "") == "blacksmith",
				"Stock Hobby Smith explicitly selects the accepted portrait identity")
			var destinations: Dictionary = {}
			for id in defs.mission_reports:
				if defs.mission_reports[id].has("destination_descriptors"):
					destinations[id] = true
			for id in ILLUSTRATED_REPORTS:
				_check(defs.mission_reports.has(id), "Illustrated original %s remains reportable" % id)
				_check_texture(art.call("report", id), "reports", id)
			for id in destinations:
				_check_texture(art.call("destination", id), "destinations", id)
			for id in defs.get("upgrades", {}):
				_check_texture(art.call("upgrade", id), "upgrades", id)
			_check(art.call("class_portrait", "custom_edda") == null,
				"Unknown custom identity does not inherit a stock portrait")
	if failures.is_empty():
		print("PASS: guild book art")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check_texture(value: Variant, category: String, id: String) -> void:
	var path := "res://assets/guild-book/%s/%s.png" % [category, id]
	_check(value is Texture2D, path + " resolves to a texture")
	_check(FileAccess.file_exists(path) or ResourceLoader.exists(path, "Texture2D"),
		path + " is packaged in the project")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
