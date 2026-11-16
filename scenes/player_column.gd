class_name PlayerColumn
extends PanelContainer
## One player's side of the board, themed by the chosen faction:
## header (emblem, name, faction, life gems, pass, total), the three combat
## rows, and a keypad that adds cards to the active row.
## Emits `action` requests only; main.gd validates and applies them.

signal action(name: StringName, args: Dictionary)

var index := 0

var _faction_id := ""
var _look_id := ""
var _emblem: FactionEmblem
var _name_edit: LineEdit
var _faction: OptionButton
var _gems: Array[Button] = []
var _lives_box: HBoxContainer
var _pass: Button
var _total: Label
var _lead: Label
var _perk: Label
var _rows := {}
var _target: Label


func _init(p: int) -> void:
	index = p
	name = "Player%d" % p
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	# Header: emblem | name + faction | lives + pass | total
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	_emblem = FactionEmblem.new()
	_emblem.custom_minimum_size = Vector2(60, 60)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_emblem)
	var id_box := VBoxContainer.new()
	id_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(id_box)
	_name_edit = LineEdit.new()
	_name_edit.name = "P%d_Name" % p
	_name_edit.max_length = InputSanitizer.MAX_NAME_LEN
	_name_edit.placeholder_text = "Player %d" % (p + 1)
	_name_edit.context_menu_enabled = false
	_name_edit.custom_minimum_size = Vector2(0, 40)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(func() -> void: _emit_name(_name_edit.text))
	id_box.add_child(_name_edit)
	_faction = OptionButton.new()
	_faction.name = "P%d_Faction" % p
	_faction.custom_minimum_size = Vector2(0, 40)
	_faction.focus_mode = Control.FOCUS_NONE
	for i in Factions.IDS.size():
		_faction.add_item(Factions.display_name(Factions.IDS[i]), i)
	_faction.item_selected.connect(func(i: int) -> void:
		action.emit(&"set_faction", {"p": index, "faction": Factions.IDS[i]}))
	id_box.add_child(_faction)

	var side := VBoxContainer.new()
	head.add_child(side)
	_lives_box = HBoxContainer.new()
	_lives_box.add_theme_constant_override("separation", 8)
	_lives_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lives_box.custom_minimum_size = Vector2(0, 40)
	side.add_child(_lives_box)
	var lives_label := Label.new()
	lives_label.text = "Lives"
	lives_label.theme_type_variation = &"MutedLabel"
	_lives_box.add_child(lives_label)
	for gem in range(1, GwentRules.MAX_LIVES + 1):
		var g := Button.new()
		g.name = "P%d_Gem%d" % [p, gem]
		g.custom_minimum_size = Vector2(32, 32)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.focus_mode = Control.FOCUS_NONE
		g.tooltip_text = "Life gem: tap to correct lives by hand"
		g.pressed.connect(func() -> void: action.emit(&"tap_gem", {"p": index, "gem": gem}))
		_lives_box.add_child(g)
		_gems.append(g)
	_pass = Button.new()
	_pass.name = "P%d_Pass" % p
	_pass.toggle_mode = true
	_pass.custom_minimum_size = Vector2(140, 40)
	_pass.focus_mode = Control.FOCUS_NONE
	_pass.pressed.connect(func() -> void: action.emit(&"toggle_pass", {"p": index}))
	side.add_child(_pass)

	var score_box := VBoxContainer.new()
	score_box.custom_minimum_size = Vector2(88, 0)
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(score_box)
	_total = Label.new()
	_total.name = "P%d_Total" % p
	_total.theme_type_variation = &"ScoreLabel"
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(_total)
	_lead = Label.new()
	_lead.theme_type_variation = &"MutedLabel"
	_lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(_lead)

	_perk = Label.new()
	_perk.theme_type_variation = &"MutedLabel"
	_perk.clip_text = true
	_perk.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_perk.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(_perk)

	for key in GwentRules.ROWS:
		var r := RowPanel.new(p, key)
		r.action.connect(func(n: StringName, a: Dictionary) -> void: action.emit(n, a))
		vb.add_child(r)
		_rows[key] = r

	# Keypad: adds a card to the active row with one tap.
	_target = Label.new()
	_target.theme_type_variation = &"MutedLabel"
	vb.add_child(_target)
	var keys := HFlowContainer.new()
	keys.add_theme_constant_override("h_separation", 5)
	keys.add_theme_constant_override("v_separation", 5)
	vb.add_child(keys)
	for v in GwentRules.UNIT_VALUES:
		_key(keys, str(v), "P%d_Unit%d" % [p, v], &"add_unit", v, &"")
	for v in GwentRules.HERO_VALUES:
		_key(keys, "H %d" % v, "P%d_Hero%d" % [p, v], &"add_hero", v, &"HeroKey")


func _key(parent: Control, text: String, node_name: String, act: StringName, value: int, variation: StringName) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(46, 42)
	b.focus_mode = Control.FOCUS_NONE
	if variation != &"":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void: action.emit(act, {"p": index, "value": value}))
	parent.add_child(b)


func _on_name_submitted(text: String) -> void:
	_name_edit.release_focus()   # also triggers focus_exited -> _emit_name
	_emit_name(text)


func _emit_name(text: String) -> void:
	action.emit(&"set_name", {"p": index, "name": text})


## Rebuilds the visible state. `ui` holds the active row and selected card.
func refresh(state: Dictionary, active_row: String, selected: Dictionary) -> void:
	var pl: Dictionary = state["players"][index]
	var faction: String = pl["faction"]
	if faction != _faction_id:
		_faction_id = faction
		_faction.select(Factions.IDS.find(faction))
	var look := Factions.look_for(pl["name"], faction)
	if look != _look_id:
		_look_id = look
		theme = FactionTheme.get_theme(look)
		_emblem.faction = look

	if not _name_edit.has_focus() and _name_edit.text != pl["name"]:
		_name_edit.text = pl["name"]

	var total := GwentRules.player_score(state, index)
	_total.text = str(total)
	var lead := GwentRules.leader(state)
	var over := GwentRules.is_match_over(state)
	if pl["passed"]:
		_lead.text = "Passed"
	elif lead == index:
		_lead.text = "Leading"
	else:
		_lead.text = ""

	_lives_box.visible = state["show_lives"]
	for g in _gems.size():
		_gems[g].theme_type_variation = &"GemOn" if pl["lives"] > g else &"GemOff"

	_pass.visible = state["show_rounds"]
	_pass.disabled = over
	_pass.set_pressed_no_signal(pl["passed"])
	_pass.text = "Passed (undo)" if pl["passed"] else "Pass round"

	_perk.text = "%s: %s" % [Factions.display_name(faction), Factions.get_data(faction)["perk"]]
	_perk.tooltip_text = _perk.text
	_target.text = "Keypad adds to %s (tap a row to change; H = hero):" % GwentRules.ROW_TITLES[active_row]
	for key in GwentRules.ROWS:
		_rows[key].refresh(state, key == active_row, selected)
	modulate.a = 0.8 if pl["passed"] else 1.0
