extends SceneTree
## Checks live Control bounds, not pixels. No save, random commission, or battle needed.
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_preparation_layout_test.gd

const Book = preload("res://presentation/guild_book_page.gd")
const BoundPage = preload("res://presentation/guild_bound_page.gd")
const Art = preload("res://presentation/guild_book_art.gd")
const Petitions = preload("res://presentation/guild_petitions_page.gd")
const Recruitment = preload("res://presentation/guild_recruitment_page.gd")

var _viewport := SubViewport.new()
var _book: Book
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_viewport.size = Vector2i(1280, 820)
	root.add_child(_viewport)
	for size in [Vector2i(1280, 820), Vector2i(960, 615)]:
		_viewport.size = size
		for count in range(4):
			await _check_deployment(count)
	_viewport.size = Vector2i(1280, 820)
	for id in ["recruit_bard", "teach_healer_blast"]:
		await _check_petition(id)
	await _check_loadout(false)
	_viewport.size = Vector2i(960, 615)
	await _check_loadout(true)
	if _failures == 0:
		print("Guild preparation layout: both petition previews and the Healer loadout fit.")
	quit(1 if _failures else 0)


func _check_deployment(count: int) -> void:
	var presenter := Recruitment.new()
	var page := _new_book(BoundPage.new())
	var heroes := _founders()
	var party := heroes.slice(0, count)
	presenter.build(_book, page, {"commission_title": "The last ferryman", "mission_count": 5,
		"party": party, "heroes": heroes, "party_size": 3, "folio": "recruits",
		"can_depart": count == 3, "depart_blocked_reason": "Choose 3 recruits." if count < 3 else ""})
	await _layout()
	_expect(_book.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, Vector2(_viewport.size))),
		"Recruitment binding fits the viewport")
	var scenario := "%s, %d selected" % [_viewport.size, count]
	var scroll := _control("DeploymentScroll") as ScrollContainer
	if scroll == null:
		_expect(false, scenario + ": deployment list exists")
		return
	var leaves: Array[Label] = []
	for child in scroll.find_children("*", "Label", true, false):
		leaves.append(child as Label)
	var places := leaves.filter(func(label: Label) -> bool: return label.text == "Open place")
	var numbers := leaves.filter(func(label: Label) -> bool: return label.text in ["01", "02", "03"])
	_expect(places.size() == 3 - count and numbers.size() == 3, scenario + ": three numbered slots")
	for place: Label in places:
		var row := place.get_parent() as Control
		_expect(place.get_line_count() == 1 and place.size.x > place.size.y,
			scenario + ": Open place is readable on one horizontal line")
		_expect(row != null and row.size.y <= 76.0, scenario + ": an open row stays compact")
	for slot: Label in numbers:
		_expect(scroll.get_global_rect().grow(1.0).encloses(slot.get_global_rect()),
			scenario + ": all deployment numbers start in view")
	_expect(not scroll.get_v_scroll_bar().visible, scenario + ": all three places fit without scrolling")
	var depart := _control("StartAdventure") as Button
	_expect(depart != null and depart.disabled == (count < 3), scenario + ": departure respects the party count")
	for index in party.size():
		var id: String = party[index].id
		var edit := presenter.focus_control("EditHero_" + id) as Button
		var earlier := presenter.focus_control("PartyEarlier_" + id) as Button
		var later := presenter.focus_control("PartyLater_" + id) as Button
		_expect(edit != null and edit.focus_mode == Control.FOCUS_ALL
			and earlier != null and earlier.disabled == (index == 0)
			and later != null and later.disabled == (index == count - 1),
			scenario + ": filled slot %d preserves focus and valid reordering" % (index + 1))
		if edit != null:
			_expect(edit.is_visible_in_tree() and not edit.disabled
				and "edit loadout" in edit.text.to_lower(),
				scenario + ": " + id + " has a visibly labeled loadout action")
			var titles := edit.get_parent().find_children("*", "Label", true, false)
			var separate_title := false
			for title: Label in titles:
				if title.text == party[index].name and title.is_visible_in_tree():
					separate_title = true
					_expect(not title.get_global_rect().intersects(edit.get_global_rect()),
						scenario + ": title and loadout action do not overlap")
			_expect(separate_title, scenario + ": " + id + " has a separate plain class title")
			_expect(_visible_in(edit.name, "DeploymentScroll"),
				scenario + ": loadout action is unclipped")
			for other in [earlier, later]:
				if other != null:
					_expect(not edit.get_global_rect().intersects(other.get_global_rect()),
						scenario + ": loadout and reorder actions do not overlap")


func _check_petition(id: String) -> void:
	var presenter := Petitions.new()
	var page := _new_book()
	presenter.build(_book, page, {"selected_id": id, "balance": 4,
		"return_summary": "4 roads won: +4 · Destination forfeited: +0", "petitions": [
		_petition("recruit_bard", "Recruit the Bad Bard", "A new hero to choose", "bard",
			"Starts with Inspiring Melody and Healing Sonnet.",
			"Choose him for one of your three party places.", "Party and loadouts stay unchanged."),
		_petition("teach_healer_blast", "Teach the Healer: Blast", "Blast can replace Bonk", "healer",
			"Hits the nearest damageable target, even an ally or obstacle.",
			"At recruitment, equip Blast instead of Bonk.", "Bonk stays equipped until you switch."),
	]})
	await _layout()
	var unit := _control("GuildPointUnit")
	var selected := _control("PetitionStatus_" + id)
	_expect(unit != null and selected != null and unit.size.y < 46.0 and selected.size.y < 31.0,
		id + ": balance and stamp stay on one line")
	_expect(_bounds("GuildPointBalance").end.y < 136.0, id + ": the header cannot eat the folio")
	var scroll := _control("PetitionScroll") as ScrollContainer
	var selected_button := _control("Petition_" + id)
	_expect(scroll != null and selected_button != null, id + ": selected petition exists in the register")
	if scroll != null and selected_button != null:
		scroll.ensure_control_visible(selected_button)
		await _layout()
		_expect(_visible_in("Petition_" + id, "PetitionScroll"),
			id + ": selected petition can be scrolled into view")
	for name in ["PetitionActionPlate", "PetitionEffect_0", "PetitionEffect_1", "PetitionNote"]:
		_expect(_visible_in(name, "PetitionPreviewScroll"), id + ": " + name + " is visible before buying")
	var painting := _control("PetitionActionPlate") as TextureRect
	_expect(painting != null and painting.texture != null and painting.size.y >= 215.0,
		id + ": the live action plate keeps meaningful height")
	_expect(_book.get_global_rect().encloses(_bounds("PurchasePetition_" + id)),
		id + ": the purchase control stays on the leaf")


func _check_loadout(compact: bool) -> void:
	var presenter := Recruitment.new()
	var page := _new_book(BoundPage.new())
	var party := _founders()
	presenter.build(_book, page, {"commission_title": "The last ferryman", "mission_count": 5,
		"party": party, "heroes": party, "party_size": 3, "selected_hero_id": "healer",
		"folio": "loadout", "can_depart": true,
		"offense": [_row("healer_bonk", "Bonk and taunt"), _row("wizard_blast", "Blast nearest", true)],
		"utility": [_row("healer_heal", "Heal self or nearest ally", true, false)],
		"orders": [_row("order_support", "Support", true),
			_row("order_aggressive", "Pursue and bonk", false, false, "Requires: Bonk")],
	})
	await _layout()
	_expect(_bounds("UtilityStatus_healer_heal").size.y < 31.0, "Utility status stays on one line")
	_expect(_bounds("Offense_wizard_blast").end.y < _bounds("Offense_healer_bonk").position.y,
		"Equipped Blast is shown before Bonk")
	_expect(_book.get_global_rect().encloses(_bounds("StartAdventure")), "Departure remains on the leaf")
	var pursuit := _control("Order_order_aggressive") as Button
	var support := _control("Order_order_support") as Button
	_expect(pursuit != null and pursuit.disabled and pursuit.text == "Requires Bonk",
		"Incompatible pursuit displays the specific requirement")
	_expect(support != null and not support.disabled and support.text == "Selected",
		"Support remains the selected and available order")
	var editing := _control("EditingLoadout_healer")
	var later := _control("PartyLater_healer") as Button
	_expect(editing != null and _control("EditHero_healer") == null and _control("EditHero_knight") != null,
		"Only the active folio hero shows the persistent Editing loadout state")
	if later != null:
		later.grab_focus()
		_expect(later.has_focus() and editing != null and editing.is_visible_in_tree(),
			"Keyboard focus on a reorder button does not replace the editing state")
	if compact:
		var scroll := _control("LoadoutScroll") as ScrollContainer
		_expect(scroll != null and scroll.follow_focus, "Compact loadout scrolls to keyboard focus")
		if scroll != null and pursuit != null:
			scroll.ensure_control_visible(pursuit)
			await _layout()
	elif pursuit != null:
		_expect(_visible_in("Order_order_support", "LoadoutScroll"), "Support is visible without scrolling")
	_expect(_visible_in("Order_order_aggressive", "LoadoutScroll"), "Pursuit and its lock reason are readable")


func _new_book(book: Book = null) -> VBoxContainer:
	if is_instance_valid(_book):
		_viewport.remove_child(_book)
		_book.queue_free()
	_book = Book.new() if book == null else book
	_viewport.add_child(_book)
	return _book.build(-1.0)


func _layout() -> void:
	for tick in 3:
		await process_frame


func _control(node_name: String) -> Control:
	return _book.find_child(node_name, true, false) as Control


func _bounds(node_name: String) -> Rect2:
	var control := _control(node_name)
	_expect(control != null and control.is_visible_in_tree(), "Expected visible control: " + node_name)
	return Rect2() if control == null else control.get_global_rect()


func _visible_in(child: String, viewport_control: String) -> bool:
	var target := _bounds(child)
	return target.has_area() and _bounds(viewport_control).grow(1.0).encloses(target)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


static func _petition(id: String, title: String, summary: String, portrait: String,
		effect: String, use: String, note: String) -> Dictionary:
	return {"id": id, "title": title, "summary": summary, "preview_title": title,
		"cost": 4, "can_buy": true, "status": "available",
		"portrait": Art.class_portrait(portrait), "details": [effect, use], "note": note}


static func _row(id: String, label: String, selected := false, enabled := true, reason := "") -> Dictionary:
	return {"id": id, "label": label, "selected": selected, "enabled": enabled, "reason": reason}


static func _founders() -> Array:
	return [
		{"id": "knight", "name": "Anxious Knight", "portrait": Art.class_portrait("knight")},
		{"id": "healer", "name": "Unimpressed Healer", "portrait": Art.class_portrait("healer")},
		{"id": "wizard", "name": "Enthusiastic Caster", "portrait": Art.class_portrait("wizard")},
	]
