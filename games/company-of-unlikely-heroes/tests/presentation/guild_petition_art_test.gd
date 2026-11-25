extends SceneTree
## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/guild_petition_art_test.gd
## Exercises stock progression, the view model, and the selected live page without a save.

const Book = preload("res://presentation/book/guild_book_page.gd")
const Page = preload("res://presentation/book/guild_petitions_page.gd")
const ViewModel = preload("res://presentation/book/guild_petition_view_model.gd")
const Art = preload("res://presentation/book/guild_book_art.gd")
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")

# Independent of the resolver: approved-crops.tsv plus the two original action plates.
const PLATES := {
	"recruit_bard": "bard",
	"teach_healer_blast": "healer_blast",
	"recruit_alchemist": "recruit_alchemist",
	"alchemist_throw_samples": "alchemist_throw_samples",
	"alchemist_etching_paste": "alchemist_etching_paste",
	"alchemist_learn_pull": "alchemist_learn_pull",
	"song_weaving": "song_weaving",
	"bard_learn_push": "bard_learn_push",
	"bard_follow_company": "bard_follow_company",
	"healer_blast_order": "healer_blast_order",
	"healer_field_dressing": "healer_field_dressing",
	"healer_triage_order": "healer_triage_order",
	"knight_rescue_line": "knight_rescue_line",
	"knight_escort_order": "knight_escort_order",
	"knight_learn_bonk": "knight_learn_bonk",
	"recruit_necromancer": "recruit_necromancer",
	"necro_grave_bell": "necro_grave_bell",
	"necro_bell_order": "necro_bell_order",
	"necro_learn_melody": "necro_learn_melody",
	"recruit_rogue": "recruit_rogue",
	"rogue_tripwire": "rogue_tripwire",
	"rogue_tripwire_order": "rogue_tripwire_order",
	"rogue_learn_potion": "rogue_learn_potion",
	"wizard_ring_sparks": "wizard_ring_sparks",
	"wizard_stand_back": "wizard_stand_back",
	"wizard_learn_dodge": "wizard_learn_dodge",
	"recruit_blacksmith": "recruit_blacksmith",
	"blacksmith_learn_bonk": "blacksmith_learn_bonk",
	"blacksmith_learn_acid": "blacksmith_learn_acid",
}

var failures := 0
var viewport := SubViewport.new()
var book: Book


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	viewport.size = Vector2i(1280, 820)
	root.add_child(viewport)
	var defs: Dictionary = Catalog.read_default()
	var petitions := Progression.petitions(defs, {"points": 0, "recruited_ids": ["knight", "healer", "wizard"], "purchased_ids": []})
	var rows := ViewModel.rows(defs, petitions)
	var actual_ids := {}
	for row: Dictionary in rows:
		actual_ids[row.id] = true
	_check(PLATES.size() == 29 and actual_ids.size() == 29, "Expected exactly 29 stock petitions")
	for id in PLATES:
		_check(actual_ids.has(id), "Stock register includes " + id)
		var path := "res://assets/guild-book/petitions/%s.png" % PLATES[id]
		_check(FileAccess.file_exists(path) or ResourceLoader.exists(path, "Texture2D"), id + ": dedicated plate is packaged")
		var expected := Art.petition(PLATES[id])
		_check(expected != null, id + ": dedicated plate loads")
		_build(rows, id)
		var selected := book.find_child("Petition_" + id, true, false) as BaseButton
		var preview := book.find_child("PetitionPreviewScroll", true, false)
		var plate := preview.find_child("PetitionActionPlate", true, false) as TextureRect if preview != null else null
		_check(selected != null and selected.button_pressed, id + ": actual register selection is active")
		_check(plate != null and expected != null and plate.texture == expected,
			id + ": selected preview displays its dedicated plate " + path)
		_check(preview != null and preview.find_child("PetitionRecipientPortrait", true, false) == null,
			id + ": preview does not silently fall back to a portrait")
	_check_register_portraits(rows)
	_check_illustrated_recipient(rows)
	_check_custom_fallback()
	_check_reserved_legacy_names()
	if failures == 0:
		print("PASS: all stock petition previews and custom portrait fallback")
	quit(1 if failures else 0)


func _build(rows: Array, selected_id: String) -> void:
	if is_instance_valid(book):
		viewport.remove_child(book)
		book.free()
	book = Book.new()
	viewport.add_child(book)
	var parent := book.build(-1.0)
	Page.new().build(book, parent, {"selected_id": selected_id, "petitions": rows})


func _check_register_portraits(rows: Array) -> void:
	var checked := {}
	for row: Dictionary in rows:
		var hero := str(row.hero_id)
		var portrait := row.portrait as Texture2D
		if hero.is_empty() or checked.has(hero) or portrait == null:
			continue
		checked[hero] = true
		var group := book.find_child("PetitionGroup_" + hero, true, false)
		var found := false
		if group != null:
			for image: TextureRect in group.find_children("*", "TextureRect", true, false):
				if image.texture is AtlasTexture and image.texture.atlas == portrait:
					found = true
		_check(found, hero + ": register heading retains the opted-in class portrait")
	_check(checked.size() == 8, "All eight stock hero headings have portraits")


func _check_illustrated_recipient(rows: Array) -> void:
	var matches := rows.filter(func(row: Dictionary) -> bool: return row.id == "wizard_stand_back")
	_check(matches.size() == 1, "Stand Back fixture exists exactly once")
	if matches.size() != 1:
		return
	var row: Dictionary = matches[0]
	var recipient := str(row.recipient_label)
	_check(not recipient.is_empty() and recipient != str(row.preview_title),
		"Stand Back has a named recipient distinct from its title")
	_build(rows, "wizard_stand_back")
	var preview := book.find_child("PetitionPreviewScroll", true, false)
	var plate := preview.find_child("PetitionActionPlate", true, false) as TextureRect if preview != null else null
	_check(plate != null and plate.texture == Art.petition("wizard_stand_back"),
		"Stand Back fixture displays the illustrated stock preview")
	var recipient_visible := false
	if preview != null:
		for label: Label in preview.find_children("*", "Label", true, false):
			if label.text == recipient and label.is_visible_in_tree():
				recipient_visible = true
	_check(recipient_visible, "Stand Back illustrated preview visibly names its recipient")


func _check_custom_fallback() -> void:
	var portrait := Art.class_portrait("healer")
	var row := {"id": "custom_petition", "hero_id": "custom_hero", "title": "Custom petition",
		"recipient_label": "Custom healer", "portrait": portrait, "details": []}
	_build([row], "custom_petition")
	var preview := book.find_child("PetitionPreviewScroll", true, false)
	var mount := preview.find_child("PetitionRecipientPortrait", true, false) if preview != null else null
	_check(ViewModel.action_plate("custom_petition") == null, "Unknown custom petition has no stock action plate")
	_check(preview != null and preview.find_child("PetitionActionPlate", true, false) == null,
		"Custom petition does not gain a stock action plate")
	var images := mount.find_children("*", "TextureRect", true, false) if mount != null else []
	_check(images.size() == 1 and images[0].texture is AtlasTexture and images[0].texture.atlas == portrait,
		"Custom petition falls back to its supplied portrait")
	row.portrait = null
	_build([row], "custom_petition")
	preview = book.find_child("PetitionPreviewScroll", true, false)
	_check(preview != null and preview.find_child("PetitionRecipientPortrait", true, false) == null
		and preview.find_child("PetitionActionPlate", true, false) == null,
		"Custom petition without an opted-in portrait has no invented artwork")


func _check_reserved_legacy_names() -> void:
	var portrait := Art.class_portrait("healer")
	for id in ["bard", "healer_blast"]:
		_check(Art.petition(id) != null, id + ": reserved legacy plate exists for the fixture")
		var row := {"id": id, "hero_id": "custom_hero", "title": "Custom petition",
			"recipient_label": "Custom healer", "portrait": portrait, "details": []}
		_build([row], id)
		var preview := book.find_child("PetitionPreviewScroll", true, false)
		var mount := preview.find_child("PetitionRecipientPortrait", true, false) if preview != null else null
		var images: Array[Node] = []
		if mount != null:
			images = mount.find_children("*", "TextureRect", true, false)
		_check(preview != null and preview.find_child("PetitionActionPlate", true, false) == null,
			id + ": custom petition cannot borrow the reserved legacy plate")
		_check(images.size() == 1 and images[0].texture is AtlasTexture and images[0].texture.atlas == portrait,
			id + ": custom petition retains its supplied portrait fallback")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
