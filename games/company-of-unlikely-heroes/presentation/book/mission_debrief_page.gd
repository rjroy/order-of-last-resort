extends "res://presentation/book/guild_bound_page.gd"
## The debrief displays the settled report. It never changes the outing.

const PRINT_RULE := Color("#8e7753")
const ACTION_FILLS := {"normal": "#1e4132", "hover": "#2b5642", "pressed": "#183329"}

var _compact := false
var _layout_changes: Array[Callable] = []


func populate(page: VBoxContainer, model: Dictionary) -> void:
	bind_cover(36, 25, 36)
	_layout_changes.append(func(compact: bool) -> void:
		for side in ["left", "right"]:
			add_theme_constant_override("margin_" + side, 30 if compact else 36)
		add_theme_constant_override("margin_top", 23 if compact else 25)
		add_theme_constant_override("margin_bottom", 29 if compact else 36)
		page.add_theme_constant_override("separation", 6 if compact else 11))
	var title := "Choose one reward" if model.pending else "Reward claimed"
	var heading_row := row(page, 12)
	var heading := stack(heading_row, 0)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var utility := Control.new()
	utility.name = "HelpUtilitySlot"
	utility.custom_minimum_size = Vector2(166, 42)
	utility.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading_row.add_child(utility)
	_compact_font(strong_text(heading, title, 48), 36)
	var subtitle: String = model.mission
	if model.pending:
		subtitle += " cleared. The chosen hero keeps the upgrade until the outing ends."
	else:
		subtitle += " cleared."
	_bound_title(_compact_font(text(heading, subtitle, 23, SUBTLE, "italic"), 18), "DebriefMissionTitle")
	var hint := Control.new()
	hint.name = "HelpHintSlot"
	hint.set_meta("help_next_step", "Review the debrief and choose a reward before continuing." if model.pending
		else "Review the claimed reward, then continue.")
	hint.custom_minimum_size.y = 24
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(hint)
	rule(page, PRINT_RULE)
	if not model.receipt.is_empty():
		_compact_font(text(page, model.receipt, 19, FOREST, "display"), 16)
	if model.pending:
		_build_pending(page, model)
	else:
		_build_settled(page, model)
	_compact = _needs_compact_layout()
	_apply_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _needs_compact_layout() -> bool:
	var area := get_viewport_rect().size
	return area.x < 1100 or area.y < 700


func _on_viewport_size_changed() -> void:
	if not is_inside_tree():
		return
	var compact := _needs_compact_layout()
	if compact != _compact:
		_compact = compact
		_apply_layout()


func _apply_layout() -> void:
	# Resize the existing controls so focus, scroll regions and help anchors survive.
	for change in _layout_changes:
		change.call(_compact)


func _compact_font(label: Label, points: int) -> Label:
	var normal := label.get_theme_font_size("font_size")
	_layout_changes.append(func(compact: bool) -> void:
		label.add_theme_font_size_override("font_size", points if compact else normal))
	return label


func _build_pending(page: VBoxContainer, model: Dictionary) -> void:
	var reward_scroll := detail_scroll(page, "RewardScroll", 308, "Scroll reward offers")
	_layout_changes.append(func(compact: bool) -> void:
		reward_scroll.custom_minimum_size.y = 180 if compact else 308)
	var offers := stack(reward_scroll, 12)
	offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reward_rows: Array[HBoxContainer] = []
	var actions: Array[Button] = []
	for index in model.offers.size():
		if index % 3 == 0:
			reward_rows.append(row(offers, 13))
		var solo: bool = index % 3 == 0 and index == model.offers.size() - 1
		actions.append(_build_reward(reward_rows.back(), model.offers[index], true, solo))
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
	var reminder := _compact_font(strong_text(footer, "Choose a reward before continuing.", 24, RUST), 18)
	reminder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reminder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_continue(footer, model)
	if not actions.is_empty():
		actions[0].grab_focus()


func _build_pending_notes(page: VBoxContainer, carry: Variant, scout_note: String) -> void:
	rule(page)
	var folio := row(page, 16)
	var company := stack(folio, 4)
	company.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	company.size_flags_stretch_ratio = 1.16
	_compact_font(strong_text(company, "What carries forward", 24), 20)
	var carry_scroll := detail_scroll(company, "PendingCarryScroll", 78, "Scroll what carries forward")
	_layout_changes.append(func(compact: bool) -> void:
		carry_scroll.custom_minimum_size.y = 60 if compact else 78)
	_build_carry(carry_scroll, carry, true)
	if not scout_note.is_empty():
		var divider := VSeparator.new()
		divider.self_modulate = PRINT_RULE
		folio.add_child(divider)
		var note := stack(folio, 4)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_notes(note, "PendingScoutScroll", "Your scout’s note", scout_note, "DebriefScoutNote",
			19, 16)


func _build_settled(page: VBoxContainer, model: Dictionary) -> void:
	var leaves := spread(page, 0.5, 42)
	var spread_row := leaves[0].get_parent() as HBoxContainer
	_layout_changes.append(func(compact: bool) -> void:
		spread_row.add_theme_constant_override("separation", 26 if compact else 42))
	_build_reward(leaves[0], model.claimed, false, true)

	var account := material_panel(leaves[1], Surface.POSTING, 24, 30, 24)
	account.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout_changes.append(func(compact: bool) -> void:
		var inset := account.get_theme_stylebox("panel")
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			inset.set_content_margin(side, 17 if compact else 24))
	var notes := stack(account, 12)
	var reading := detail_scroll(notes, "SettledCarryScroll", 98, "Scroll carry and scout notes")
	var record := stack(reading, 12)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compact_font(strong_text(record, "What carries forward", 35), 28)
	_build_carry(record, model.carry, false)
	if not model.scout_note.is_empty():
		space(record, 12)
		rule(record, PRINT_RULE)
		_compact_font(strong_text(record, "Your scout’s note", 26), 21)
		_compact_font(text(record, model.scout_note, 20, INK, "display"), 17).name = "DebriefScoutNote"
	rule(notes, PRINT_RULE)
	if not model.next_title.is_empty():
		_add_next_title(notes, model.next_title)
	_add_continue(notes, model).grab_focus()


func _add_next_title(parent: Control, title: String) -> void:
	_bound_title(_compact_font(text(parent, "Next: " + title, 25, RUST, "italic"), 21), "DebriefNextMission")


func _bound_title(label: Label, node_name: String) -> void:
	label.name = node_name
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.accessibility_name = label.text
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_PASS


func _add_notes(parent: VBoxContainer, scroll_name: String, heading: String, words: String,
		label_name: String, points: int, compact_points: int) -> void:
	_compact_font(strong_text(parent, heading, 24), 20)
	var scroll := detail_scroll(parent, scroll_name, 78, "Scroll " + heading.to_lower())
	_layout_changes.append(func(compact: bool) -> void:
		scroll.custom_minimum_size.y = 60 if compact else 78)
	var lines := _compact_font(text(scroll, words, points, INK, "display"), compact_points)
	lines.name = label_name
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_carry(parent: Control, carry: Variant, pending: bool) -> void:
	if carry is String:
		var lines := _compact_font(text(parent, carry, 17 if pending else 21, INK, "display"),
			15 if pending else 17)
		lines.name = "CarryReport"
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return
	var entries := stack(parent, 7)
	entries.name = "CarryReport"
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: Dictionary in carry:
		var identity := stack(entries, 1)
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_compact_font(strong_text(identity, str(entry.get("name", "")), 18 if pending else 23),
			16 if pending else 19)
		var epithet := str(entry.get("epithet", ""))
		if not epithet.is_empty():
			_compact_font(text(identity, epithet, 15 if pending else 18, SUBTLE, "display"),
				13 if pending else 15)
		_compact_font(text(identity, str(entry.get("details", "")), 17 if pending else 21, INK, "display"),
			15 if pending else 17)


func _build_reward(parent: Control, offer: Dictionary, pending: bool, solo: bool) -> Button:
	var paper := material_panel(parent, Surface.POSTING, 19, 26, 20)
	paper.name = "RewardCard_" + offer.hero_id
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card := stack(paper, 6)
	var reading := detail_scroll(card, "RewardDetails_" + offer.hero_id, 0,
		"Scroll reward details for " + offer.hero_name)
	var prose := stack(reading, 7)
	prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var intro := BoxContainer.new()
	prose.add_child(intro)
	var print: TextureRect
	if offer.art != null:
		print = _add_reward_art(intro, offer.art)
	var recipient := _add_recipient(intro, offer)
	_layout_changes.append(func(compact: bool) -> void:
		var inset := paper.get_theme_stylebox("panel")
		inset.set_content_margin_all(13 if compact else 19)
		inset.set_content_margin(SIDE_TOP, 23 if compact else 26)
		inset.set_content_margin(SIDE_BOTTOM, 12 if compact else 20)
		card.add_theme_constant_override("separation", 4 if compact else 6)
		prose.add_theme_constant_override("separation", 4 if compact else 7)
		var inline := compact and pending
		intro.vertical = not inline
		intro.add_theme_constant_override("separation", 8 if inline else 7)
		recipient.size_flags_vertical = Control.SIZE_SHRINK_CENTER if inline else Control.SIZE_FILL
		if print != null:
			if inline:
				print.custom_minimum_size = Vector2(183, 90) if solo else Vector2(76, 52)
			else:
				print.custom_minimum_size = Vector2(0, 130 if pending else (156 if compact else 230)))
	rule(prose, PRINT_RULE)
	_compact_font(strong_text(prose, offer.label, 28 if pending else 38), 21).name = "RewardTitle"
	_compact_font(text(prose, offer.description, 18 if pending else 22, INK, "display"), 16).name = "RewardDescription"
	_compact_font(text(prose, offer.progress, 17, SUBTLE, "italic"), 15).name = "RewardProgress"
	if not pending:
		rule(prose, PRINT_RULE)
		_compact_font(strong_text(prose, "Awarded for this outing", 24, FOREST), 19)
		return null
	var claim := button(card, "Reward_" + offer.hero_id, "Take reward", "ClothButton")
	_style_action(claim, 24, 44, 44)
	claim.accessibility_name = "Award %s to %s" % [offer.label, offer.hero_name]
	claim.accessibility_description = "%s. %s. %s. This is your one reward for the mission." % [
		str(offer.rarity).capitalize(), offer.description, offer.progress]
	claim.set_meta("hero_id", offer.hero_id)
	claim.set_meta("upgrade_id", offer.upgrade_id)
	claim.pressed.connect(offer.claim)
	return claim


func _add_reward_art(parent: Control, image: Texture2D) -> TextureRect:
	var print := TextureRect.new()
	print.name = "RewardIllustration"
	print.texture = image
	print.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	print.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	print.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(print)
	return print


func _add_recipient(parent: Control, offer: Dictionary) -> HBoxContainer:
	var recipient := row(parent, 9)
	recipient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if offer.portrait != null:
		var portrait := plate(recipient, offer.portrait, Vector2(52, 52), "portrait")
		_layout_changes.append(func(compact: bool) -> void:
			portrait.custom_minimum_size = Vector2.ONE * (39 if compact else 52))
	var identity := stack(recipient, 0)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_compact_font(strong_text(identity, offer.hero_name, 24), 20)
	if not offer.class_name.is_empty():
		text(identity, offer.class_name, 15, SUBTLE, "display")
	_compact_font(text(identity, str(offer.rarity).capitalize(), 17,
		RARITY.get(offer.rarity, SUBTLE), "italic"), 15)
	return recipient


func _add_continue(parent: Control, model: Dictionary) -> Button:
	var caption := "Read field reports" if model.next_is_fork else "Continue to next mission"
	var advance := button(parent, "ContinueAdventure", caption, "ClothButton")
	_style_action(advance, 25, 48, 44)
	advance.accessibility_name = "Continue to " + model.next_title if not model.next_title.is_empty() else caption
	set_disabled(advance, not model.can_continue)
	if advance.disabled:
		advance.accessibility_description = "Choose one reward first."
	advance.pressed.connect(model.advance)
	return advance


func _style_action(action: Button, points: int, height: int, compact_height: int) -> void:
	action.add_theme_font_override("font", _strong_face)
	_layout_changes.append(func(compact: bool) -> void:
		action.custom_minimum_size.y = compact_height if compact else height
		action.add_theme_font_size_override("font_size", 20 if compact else points))
	for state in ACTION_FILLS:
		action.add_theme_stylebox_override(state, _box(Color(ACTION_FILLS[state]), Color("#193226"), 2, 5, 10, 5))
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(2)
	action.add_theme_stylebox_override("focus", focus)
