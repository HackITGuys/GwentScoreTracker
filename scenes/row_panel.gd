class_name RowPanel
extends PanelContainer
## One combat row of one player: header (name, badges, horn, clear, score),
## the deployed cards as tappable tokens, and an action bar for the selected
## card. Tapping the row makes it the target of the player's keypad.
## Emits `action` requests only; main.gd validates and applies them.

signal action(name: StringName, args: Dictionary)

var player := 0
var key := "close"

var _title: Label
var _badges: Label
var _score: Label
var _horn: Button
var _tokens: HFlowContainer
var _empty: Label
var _bar: HBoxContainer
var _bar_label: Label
var _unit_only: Array[Button] = []
var _bond: Button
var _morale: Button


func _init(p: int, row_key: String) -> void:
	player = p
	key = row_key
	name = "P%d_%s" % [p, row_key]
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme_type_variation = &"RowPanel"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(vb)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(head)
	_title = Label.new()
	_title.text = GwentRules.ROW_TITLES[row_key]
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", 19)
	head.add_child(_title)
	_badges = Label.new()
	_badges.theme_type_variation = &"MutedLabel"
	_badges.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badges.clip_text = true
	_badges.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_badges)
	_horn = _button(head, "Horn x2", "Horn", &"toggle_horn")
	_horn.toggle_mode = true
	_horn.tooltip_text = "Commander's Horn: doubles all unit cards in this row"
	_button(head, "Clear", "Clear", &"clear_row").tooltip_text = "Remove every card from this row"
	_score = Label.new()
	_score.theme_type_variation = &"RowScoreLabel"
	_score.custom_minimum_size = Vector2(56, 0)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_score)

	_tokens = HFlowContainer.new()
	_tokens.mouse_filter = Control.MOUSE_FILTER_PASS
	_tokens.custom_minimum_size = Vector2(0, 44)
	vb.add_child(_tokens)
	_empty = Label.new()
	_empty.theme_type_variation = &"MutedLabel"
	_empty.text = "No cards. Tap this row, then a value on the keypad."
	_tokens.add_child(_empty)

	_bar = HBoxContainer.new()
	_bar.visible = false
	vb.add_child(_bar)
	_bar_label = Label.new()
	_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.add_child(_bar_label)
	_unit_only.append(_card_button("-1", "Minus", &"adjust_card", {"delta": -1}))
	_unit_only.append(_card_button("+1", "Plus", &"adjust_card", {"delta": 1}))
	_bond = _card_button("Bond", "Bond", &"toggle_card_flag", {"flag": "bond"})
	_bond.toggle_mode = true
	_bond.tooltip_text = "Tight Bond: multiplied by the number of bonded cards with the same base strength"
	_morale = _card_button("Morale", "Morale", &"toggle_card_flag", {"flag": "morale"})
	_morale.toggle_mode = true
	_morale.tooltip_text = "Morale Boost: +1 to every other unit in this row"
	_unit_only.append_array([_bond, _morale])
	_card_button("Remove", "Remove", &"remove_card", {})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action.emit(&"select_row", {"p": player, "row": key})
		accept_event()


func _button(parent: Control, text: String, suffix: String, act: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.name = "%s_%s" % [name, suffix]
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: action.emit(act, {"p": player, "row": key}))
	parent.add_child(b)
	return b


func _card_button(text: String, suffix: String, act: StringName, extra: Dictionary) -> Button:
	var b := Button.new()
	b.text = text
	b.name = "%s_%s" % [name, suffix]
	b.custom_minimum_size = Vector2(64, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: action.emit(act, extra.duplicate()))
	_bar.add_child(b)
	return b


func refresh(state: Dictionary, active: bool, selected: Dictionary) -> void:
	var row: Dictionary = state["players"][player]["rows"][key]
	var weather: bool = state["weather"][key]
	if weather:
		theme_type_variation = &"RowPanelWeatherActive" if active else &"RowPanelWeather"
	else:
		theme_type_variation = &"RowPanelActive" if active else &"RowPanel"
	_score.text = str(GwentRules.row_score(state, player, key))
	_horn.set_pressed_no_signal(row["horn"])

	var badges: Array[String] = []
	if weather:
		badges.append("%s: units = 1" % GwentRules.WEATHER_NAMES[key])
	if row["horn"]:
		badges.append("Horn x2")
	if row["units"].any(func(u: Dictionary) -> bool: return u["bond"]):
		badges.append("Tight Bond")
	if row["units"].any(func(u: Dictionary) -> bool: return u["morale"]):
		badges.append("Morale")
	_badges.text = "   " + "  |  ".join(badges) if not badges.is_empty() else ""

	for child in _tokens.get_children():
		if child != _empty:
			_tokens.remove_child(child)
			child.queue_free()
	var sel_here: bool = selected.get("p") == player and selected.get("row") == key
	var units: Array = row["units"]
	for i in units.size():
		var u: Dictionary = units[i]
		var s := GwentRules.unit_strength(row, i, weather)
		var label := str(s)
		if u["bond"]:
			label += " B"
		if u["morale"]:
			label += " M"
		var is_sel: bool = sel_here and selected.get("kind") == "unit" and selected.get("i") == i
		var variation := &"SelectedToken" if is_sel else (&"BondToken" if u["bond"] else &"UnitToken")
		_add_token("%s_U%d" % [name, i], label, variation, "unit", i,
			"Unit: base %d, now %d" % [u["base"], s])
	var heroes: Array = row["heroes"]
	for i in heroes.size():
		var is_sel: bool = sel_here and selected.get("kind") == "hero" and selected.get("i") == i
		_add_token("%s_H%d" % [name, i], "H %d" % heroes[i],
			&"SelectedToken" if is_sel else &"HeroToken", "hero", i,
			"Hero: immune to weather, horn, bond and morale")
	_empty.visible = units.is_empty() and heroes.is_empty()
	_tokens.move_child(_empty, 0)

	_bar.visible = sel_here
	if sel_here:
		var kind: String = selected["kind"]
		var i: int = selected["i"]
		if kind == "unit":
			var u: Dictionary = units[i]
			var adj: int = u["adj"]
			_bar_label.text = "Unit %d (base %d%s)" % [GwentRules.unit_strength(row, i, weather), u["base"],
				", %+d" % adj if adj != 0 else ""]
			_bond.set_pressed_no_signal(u["bond"])
			_morale.set_pressed_no_signal(u["morale"])
		else:
			_bar_label.text = "Hero %d (immune)" % heroes[i]
		for b in _unit_only:
			b.visible = kind == "unit"


func _add_token(node_name: String, text: String, variation: StringName, kind: String, i: int, tip: String) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tip
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(56, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		action.emit(&"select_card", {"p": player, "row": key, "kind": kind, "i": i}))
	_tokens.add_child(b)
