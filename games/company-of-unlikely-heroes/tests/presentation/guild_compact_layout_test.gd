extends SceneTree
## Headless Control geometry and input checks; rendered evidence is captured separately.
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/guild_compact_layout_test.gd

const Book = preload("res://presentation/book/guild_book_page.gd")
const Petitions = preload("res://presentation/book/guild_petitions_page.gd")
const Debrief = preload("res://presentation/book/mission_debrief_page.gd")
const Art = preload("res://presentation/book/guild_book_art.gd")
const FULL := Vector2i(1280, 820)
const COMPACT := Vector2i(960, 615)

var _viewport := SubViewport.new()
var _book: Book
var _failures := 0
var _activated := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_viewport.size = FULL
	root.add_child(_viewport)
	await _check_petition("recruit_blacksmith", "Recruit the Hobby Smith", "Hobby Smith", [
		"Recruit with Hammer Time, Try This and the Try This standing order.",
		"Choose this hero for one of your three party places.",
	])
	await _check_petition("recruit_bard", "The Bad Bard", "Bad Bard", [
		"Recruit with both songs and the Inspiring Melody standing order.",
		"Choose him for one of your three party places.",
	])
	await _check_offers([_smith_offer()])
	await _check_offers([
		_offer("wizard", "Enthusiastic Caster", "wizard_conductive_personality", "Conductive Personality",
			"After Blast hits, half the damage, rounded up, jumps to the nearest other damageable entity. " +
			"Exclude the first target, not the Caster."),
		_smith_offer(),
		_offer("healer", "Unimpressed Healer", "healer_long_staff", "Long Staff", "Bonk gains 1 range."),
	])
	await _check_settled()
	_book.free()
	if _failures == 0:
		print("PASS: petitions and pending/settled rewards fit at 960×615 and 1280×820")
	quit(1 if _failures else 0)


func _check_petition(id: String, title: String, hero: String, details: Array) -> void:
	var page := _new_book(Book.new())
	var presenter := Petitions.new()
	presenter.purchase_requested.connect(func(petition_id: String) -> void: _activated = petition_id)
	presenter.build(_book, page, {"selected_id": id, "balance": 9,
		"return_summary": "4 roads won: +4 · Destination won: +5", "petitions": [{
			"id": id, "title": title, "recipient_label": hero, "details": details,
			"cost": 5, "can_buy": true, "note": "Party and loadouts stay unchanged.",
		}]})
	var reading := _find("PetitionPreviewScroll") as ScrollContainer
	var art := _find("PetitionActionPlate") as TextureRect
	var effect := _find("PetitionEffect_0")
	var purchase := _find("PurchasePetition_" + id) as Button
	purchase.grab_focus()
	for size in [FULL, COMPACT, FULL]:
		await _resize(size)
		var case := "%s at %s" % [id, size]
		_expect(art.texture == Art.petition("bard" if id == "recruit_bard" else id),
			case + ": the approved painting stays in use")
		for name in ["PetitionPreviewTitle", "PetitionRecipient", "PetitionActionPlate",
				"PetitionEffect_0", "PetitionEffect_1", "PetitionNote"]:
			var control := _find(name)
			_expect(_inside(control, reading),
				"%s: first view %s includes %s %s" % [case, _rect(reading), name, _rect(control)])
		if size == FULL:
			_expect(_rect(art).end.y <= _rect(effect).position.y and art.size.y >= 215,
				case + ": full leaf keeps the large art above the effects")
		else:
			_expect(_rect(art).end.x <= _rect(effect).position.x,
				case + ": art and reading share the short leaf side-by-side")
		_expect(_inside(purchase) and purchase.has_focus() and _rect(reading).end.y <= _rect(purchase).position.y,
			case + ": purchase is separate, visible and remains focused")
		if size == COMPACT:
			_activated = ""
			await _click(purchase)
			_expect(_activated == id, case + ": mouse input reaches the purchase at the bottom")


func _check_offers(offers: Array) -> void:
	var book := Debrief.new()
	var page := _new_book(book)
	book.populate(page, _model(offers))
	var first := _find("Reward_" + offers[0].hero_id) as Button
	var selected := first
	if offers.size() > 1:
		await _resize(FULL)
		await _key(KEY_RIGHT)
		selected = _find("Reward_" + offers[1].hero_id) as Button
	for size in [FULL, COMPACT, FULL]:
		await _resize(size)
		var case := "%d pending offers at %s" % [offers.size(), size]
		var reading := _find("RewardScroll") as ScrollContainer
		var next := _find("ContinueAdventure") as Button
		var carry := _find("PendingCarryScroll")
		var scout := _find("PendingScoutScroll")
		_expect(selected.has_focus(), case + ": resize preserves the compared offer's focus")
		_expect(_inside(next) and next.disabled, case + ": gated continuation stays on the leaf")
		_expect(_inside(carry) and _inside(scout)
			and maxf(_rect(carry).end.y, _rect(scout).end.y) < _rect(next).position.y,
			case + ": carry and scout notes stay above the footer")
		for offer in offers:
			var claim := _find("Reward_" + offer.hero_id) as Button
			var details := _find("RewardDetails_" + offer.hero_id) as ScrollContainer
			for name in ["RewardIllustration", "RewardTitle"]:
				_expect(_inside(details.find_child(name, true, false) as Control, details),
					case + ": " + offer.label + " starts with visible " + name)
			var description := details.find_child("RewardDescription", true, false) as Label
			if size == COMPACT or offers.size() == 1:
				_expect(_inside(description, details), case + ": entire effect is visible for " + offer.label)
			else:
				# Keep the full leaf's large art and scrollable long descriptions.
				_expect(_rect(details).has_point(_rect(description).position),
					case + ": effect begins in view for " + offer.label)
			if size == COMPACT:
				_expect(_inside(details.find_child("RewardProgress", true, false) as Control, details),
					case + ": cap and remaining count are visible for " + offer.label)
			_expect(_inside(claim, reading) and _rect(details).end.y <= _rect(claim).position.y
				and offer.label in claim.accessibility_name and offer.description in claim.accessibility_description,
				case + ": " + offer.label + " keeps a separate, named claim action")
		if size == COMPACT:
			_activated = ""
			await _key(KEY_ENTER)
			_expect(_activated == selected.get_meta("hero_id"), case + ": Enter claims the focused offer")
			_activated = ""
			await _click(first)
			_expect(_activated == first.get_meta("hero_id"), case + ": mouse reaches the first claim")
			selected = first


func _check_settled() -> void:
	# Open directly in compact mode, rather than only arriving here via resize.
	_viewport.size = COMPACT
	var book := Debrief.new()
	var page := _new_book(book)
	var model := _model([])
	model.pending = false
	model.can_continue = true
	model.claimed = _smith_offer()
	model.carry = (model.carry + "\n\n").repeat(5)
	book.populate(page, model)
	var details := _find("RewardDetails_blacksmith") as ScrollContainer
	var scroll := _find("SettledCarryScroll") as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	var next := _find("ContinueAdventure") as Button
	for size in [COMPACT, FULL, COMPACT]:
		await _resize(size)
		_expect(_inside(_find("RewardDescription"), details), "Claimed reward is readable at %s" % size)
		_expect(next.has_focus() and _inside(next) and not next.disabled,
			"Settled continuation is visible and focused with a long carry report at %s" % size)
	var action_area := _rect(next)
	_expect(bar.focus_mode == Control.FOCUS_ALL and not bar.accessibility_name.is_empty(),
		"Overflowing carry notes have a named keyboard scroll control")
	bar.grab_focus()
	await _key(KEY_DOWN)
	_expect(scroll.scroll_vertical > 0 and _rect(next).is_equal_approx(action_area),
		"Keyboard can scroll long notes without moving Continue")
	_activated = ""
	await _click(next)
	_expect(_activated == "continue", "Mouse can use the fixed Continue button")


func _smith_offer() -> Dictionary:
	return _offer("blacksmith", "Hobby Smith", "smith_follow_through", "Follow Through",
		"When Hammer Time defeats its target, step onto its tile if you survive the defeat effects and can still enter it.")


func _offer(hero: String, hero_name: String, upgrade: String, label: String, description: String) -> Dictionary:
	return {"hero_id": hero, "hero_name": hero_name, "class_name": "", "upgrade_id": upgrade,
		"label": label, "description": description, "rarity": "uncommon", "progress": "0 of 1 acquired  ·  1 remaining",
		"art": Art.upgrade(upgrade), "portrait": Art.class_portrait(hero),
		"claim": func() -> void: _activated = hero}


func _model(offers: Array) -> Dictionary:
	return {"mission": "The Last One Standing", "pending": true, "offers": offers,
		"receipt": "Road: 1 point (1 win)  ·  Destination: 0 points (not reached)  ·  Total: 1 point",
		"carry": "Unimpressed Healer  7/7 HP → 7/7 HP  ·  Order: Support\n" +
			"Anxious Knight  8/8 HP → 8/8 HP  ·  Order: Guard\nEnthusiastic Caster  6/6 HP → 6/6 HP",
		"scout_note": "The scout recommends leaving room to step back after the first clash.",
		"next_title": "The Bridge Is Out", "next_is_fork": false, "can_continue": false,
		"advance": func() -> void: _activated = "continue"}


func _new_book(book: Book) -> VBoxContainer:
	if is_instance_valid(_book):
		_book.free()
	_book = book
	_viewport.add_child(_book)
	return _book.build(-1.0)


func _resize(size: Vector2i) -> void:
	_viewport.size = size
	for tick in 5:
		await process_frame
	_expect(_rect(_book).is_equal_approx(Rect2(Vector2.ZERO, Vector2(size))), "Book fits %s" % size)


func _click(button: Button) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = _rect(button).get_center()
		event.pressed = down
		_viewport.push_input(event, true)
		await process_frame


func _key(keycode: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = down
		_viewport.push_input(event, true)
		await process_frame


func _find(node_name: String) -> Control:
	return _book.find_child(node_name, true, false) as Control


func _rect(control: Control) -> Rect2:
	return control.get_global_rect() if control != null else Rect2()


func _inside(control: Control, region: Control = null) -> bool:
	var area := _rect(control)
	var bounds := _rect(region) if region != null else Rect2(Vector2.ZERO, Vector2(_viewport.size))
	return area.has_area() and control.is_visible_in_tree() and bounds.grow(1.0).encloses(area)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
