extends "res://presentation/guild_bound_page.gd"
## The debrief displays the settled report. It never changes the outing.

const PRINT_RULE := Color("#8e7753")
const ACTION_FILLS := {"normal": "#1e4132", "hover": "#2b5642", "pressed": "#183329"}

var _compact := false


func populate(page: VBoxContainer, model: Dictionary) -> void:
	var viewport_size := get_viewport_rect().size
	_compact = viewport_size.x < 1100 or viewport_size.y < 700
	bind_cover(30 if _compact else 36, 23 if _compact else 25, 29 if _compact else 36)
	page.add_theme_constant_override("separation", 8 if _compact else 11)
	var title := "Choose one reward" if model.pending else "Reward claimed"
	var heading := stack(page, 0)
	strong_text(heading, title, 36 if _compact else 48)
	var subtitle: String = model.mission
	if model.pending:
		subtitle += " cleared. The chosen hero keeps the upgrade until the outing ends."
	else:
		subtitle += " cleared."
	_bound_title(text(heading, subtitle, 18 if _compact else 23, SUBTLE, "italic"), "DebriefMissionTitle")
	rule(page, PRINT_RULE)
	if not model.receipt.is_empty():
		text(page, model.receipt, 16 if _compact else 19, FOREST, "display")
	if model.pending:
		_build_pending(page, model)
	else:
		_build_settled(page, model)


func _build_pending(page: VBoxContainer, model: Dictionary) -> void:
	var reward_scroll := detail_scroll(page, "RewardScroll", 256 if _compact else 308, "Scroll reward offers")
	var offers := stack(reward_scroll, 12)
	offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reward_rows: Array[HBoxContainer] = []
	var actions: Array[Button] = []
	for index in model.offers.size():
		if index % 3 == 0:
			reward_rows.append(row(offers, 10 if _compact else 13))
		actions.append(_build_reward(reward_rows.back(), model.offers[index], true))
	# Each row has its own comparison space. A custom party with more offers can
	# scroll between rows, while prose scrolls inside each card above its action.
	var fit_rows := func() -> void:
		for offer_row in reward_rows:
			offer_row.custom_minimum_size.y = reward_scroll.size.y
	reward_scroll.resized.connect(fit_rows)
	fit_rows.call_deferred()
	for index in range(1, actions.size()):
		if index % 3 != 0:
			actions[index - 1].focus_neighbor_right = actions[index - 1].get_path_to(actions[index])
			actions[index].focus_neighbor_left = actions[index].get_path_to(actions[index - 1])

	_build_pending_notes(page, model.carry, model.scout_note)
	rule(page, PRINT_RULE)
	var footer := row(page, 16)
	var reminder := strong_text(footer, "Choose a reward before continuing.", 18 if _compact else 24, RUST)
	reminder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reminder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_continue(footer, model)
	if not actions.is_empty():
		actions[0].grab_focus()


func _build_pending_notes(page: VBoxContainer, carry: String, scout_note: String) -> void:
	rule(page)
	var folio := row(page, 16)
	var company := stack(folio, 4)
	company.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	company.size_flags_stretch_ratio = 1.16
	_add_notes(company, "PendingCarryScroll", "What carries forward", carry, "CarryReport",
		65 if _compact else 78, 15 if _compact else 17, 20 if _compact else 24)
	if not scout_note.is_empty():
		var divider := VSeparator.new()
		divider.self_modulate = PRINT_RULE
		folio.add_child(divider)
		var note := stack(folio, 4)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_notes(note, "PendingScoutScroll", "Your scout’s note", scout_note, "DebriefScoutNote",
			65 if _compact else 78, 16 if _compact else 19, 20 if _compact else 24)


func _build_settled(page: VBoxContainer, model: Dictionary) -> void:
	var leaves := spread(page, 0.5, 26 if _compact else 42)
	_build_reward(leaves[0], model.claimed, false)

	var account := material_panel(leaves[1], Surface.POSTING, 17 if _compact else 24, 30, 24)
	account.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var notes := stack(account, 12)
	var reading := detail_scroll(notes, "SettledCarryScroll", 98, "Scroll carry and scout notes")
	var record := stack(reading, 12)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strong_text(record, "What carries forward", 28 if _compact else 35)
	text(record, model.carry, 17 if _compact else 21, INK, "display").name = "CarryReport"
	if not model.scout_note.is_empty():
		space(record, 12)
		rule(record, PRINT_RULE)
		strong_text(record, "Your scout’s note", 21 if _compact else 26)
		text(record, model.scout_note, 17 if _compact else 20, INK, "display").name = "DebriefScoutNote"
	rule(notes, PRINT_RULE)
	if not model.next_title.is_empty():
		_add_next_title(notes, model.next_title)
	_add_continue(notes, model).grab_focus()


func _add_next_title(parent: Control, title: String) -> void:
	_bound_title(text(parent, "Next: " + title, 21 if _compact else 25, RUST, "italic"), "DebriefNextMission")


func _bound_title(label: Label, node_name: String) -> void:
	label.name = node_name
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.accessibility_name = label.text
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_PASS


func _add_notes(parent: VBoxContainer, scroll_name: String, heading: String, words: String,
		label_name: String, height: int, points: int, heading_size: int) -> void:
	strong_text(parent, heading, heading_size)
	var scroll := detail_scroll(parent, scroll_name, height, "Scroll " + heading.to_lower())
	var lines := text(scroll, words, points, INK, "display")
	lines.name = label_name
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_reward(parent: Control, offer: Dictionary, pending: bool) -> Button:
	var paper := material_panel(parent, Surface.POSTING, 13 if _compact else 19, 26, 17 if _compact else 20)
	paper.name = "RewardCard_" + offer.hero_id
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card := stack(paper, 4 if _compact else 6)
	var reading := detail_scroll(card, "RewardDetails_" + offer.hero_id, 0,
		"Scroll reward details for " + offer.hero_name)
	var prose := stack(reading, 4 if _compact else 7)
	prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if offer.art != null:
		var image_height := (88 if _compact else 130) if pending else (156 if _compact else 230)
		_add_reward_art(prose, offer.art, image_height)
	_add_recipient(prose, offer)
	rule(prose, PRINT_RULE)
	strong_text(prose, offer.label, 21 if _compact else (28 if pending else 38))
	text(prose, offer.description, 16 if _compact else (18 if pending else 22), INK, "display")
	text(prose, offer.progress, 15 if _compact else 17, SUBTLE, "italic")
	if not pending:
		rule(prose, PRINT_RULE)
		strong_text(prose, "Awarded for this outing", 19 if _compact else 24, FOREST)
		return null
	var claim := button(card, "Reward_" + offer.hero_id, "Take reward", "ClothButton")
	_style_action(claim, 20 if _compact else 24, 39 if _compact else 44)
	claim.accessibility_name = "Award %s to %s" % [offer.label, offer.hero_name]
	claim.accessibility_description = "%s. %s. %s. This is your one reward for the mission." % [
		str(offer.rarity).capitalize(), offer.description, offer.progress]
	claim.set_meta("hero_id", offer.hero_id)
	claim.set_meta("upgrade_id", offer.upgrade_id)
	claim.pressed.connect(offer.claim)
	return claim


func _add_reward_art(parent: Control, image: Texture2D, height: float) -> void:
	var print := TextureRect.new()
	print.texture = image
	print.custom_minimum_size.y = height
	print.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	print.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	print.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(print)


func _add_recipient(parent: Control, offer: Dictionary) -> void:
	var recipient := row(parent, 9)
	if offer.portrait != null:
		var side := 39 if _compact else 52
		plate(recipient, offer.portrait, Vector2(side, side), "portrait")
	var identity := stack(recipient, 0)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strong_text(identity, offer.hero_name, 20 if _compact else 24)
	if not offer.class_name.is_empty():
		text(identity, offer.class_name, 15, SUBTLE, "display")
	text(identity, str(offer.rarity).capitalize(), 15 if _compact else 17,
		RARITY.get(offer.rarity, SUBTLE), "italic")


func _add_continue(parent: Control, model: Dictionary) -> Button:
	var caption := "Read field reports" if model.next_is_fork else "Continue to next mission"
	var advance := button(parent, "ContinueAdventure", caption, "ClothButton")
	_style_action(advance, 20 if _compact else 25, 40 if _compact else 48)
	advance.accessibility_name = "Continue to " + model.next_title if not model.next_title.is_empty() else caption
	set_disabled(advance, not model.can_continue)
	if advance.disabled:
		advance.accessibility_description = "Choose one reward first."
	advance.pressed.connect(model.advance)
	return advance


func _style_action(action: Button, points: int, height: int) -> void:
	action.custom_minimum_size.y = height
	action.add_theme_font_override("font", _strong_face)
	action.add_theme_font_size_override("font_size", points)
	for state in ACTION_FILLS:
		action.add_theme_stylebox_override(state, _box(Color(ACTION_FILLS[state]), Color("#193226"), 2, 5, 10, 5))
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(2)
	action.add_theme_stylebox_override("focus", focus)
