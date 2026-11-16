extends Control
## Gwent Score Tracker main screen.
##
## Owns the match state (a plain Dictionary, see GwentRules.new_state), the
## undo stack and persistence. The UI widgets never touch the state: they emit
## action requests, and do_action() is the single allowlisted entry point that
## validates every argument before calling the rules.

const UNDO_LIMIT := 50
const LANDSCAPE_SIZE := Vector2i(1280, 800)
const PORTRAIT_SIZE := Vector2i(800, 1500)
const ABOUT_TEXT := "Fan-made score tracker for the Gwent card game from The Witcher 3: Wild Hunt. " \
	+ "Not affiliated with or endorsed by CD PROJEKT. The Witcher and Gwent are trademarks of CD PROJEKT S.A. " \
	+ "Works offline; your match is saved only on this device."

var state: Dictionary = GwentRules.new_state()

var _undo: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _active_rows: Array[String] = ["close", "close"]
var _selected: Dictionary = {}   # {p, row, kind, i} of the tapped card, or {}

var _round_label: Label
var _history_label: Label
var _status: Label
var _weather_buttons := {}
var _scorch: Button
var _end_round: Button
var _undo_button: Button
var _banner: PanelContainer
var _banner_label: Label
var _board: BoxContainer
var _columns: Array[PlayerColumn] = []
var _settings: Control
var _mode_buttons: Array[Button] = []
var _lives_check: CheckButton
var _rounds_check: CheckButton


func _ready() -> void:
	_rng.randomize()
	theme = FactionTheme.get_theme(Factions.DEFAULT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	state = SaveStore.load_state()
	if not OS.has_feature("web"):
		get_window().min_size = Vector2i(800, 600)
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	_refresh()


# --- layout -------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Factions.get_data(Factions.DEFAULT)["bg"]
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	# Top bar
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	root.add_child(bar)
	var title := Label.new()
	title.text = "GWENT SCORE"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 26)
	bar.add_child(title)
	_round_label = Label.new()
	_round_label.theme_type_variation = &"TitleLabel"
	_round_label.custom_minimum_size = Vector2(100, 44)
	_round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_round_label)
	_history_label = Label.new()
	_history_label.theme_type_variation = &"MutedLabel"
	_history_label.custom_minimum_size = Vector2(0, 44)
	_history_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_history_label)
	for key in GwentRules.ROWS:
		var short: String = {"close": "Frost", "ranged": "Fog", "siege": "Rain"}[key]
		var b := _top_button(bar, short, "Weather_" + key, &"toggle_weather", {"row": key})
		b.toggle_mode = true
		b.tooltip_text = "%s: every unit in %s counts as 1 (both players)" % [GwentRules.WEATHER_NAMES[key], GwentRules.ROW_TITLES[key]]
		_weather_buttons[key] = b
	_top_button(bar, "Clear sky", "ClearWeather", &"clear_weather").tooltip_text = "Clear Weather: remove all weather"
	_scorch = _top_button(bar, "Scorch", "Scorch", &"scorch")
	_scorch.tooltip_text = "Destroy the strongest unit card(s) on the battlefield"
	_end_round = _top_button(bar, "End round", "EndRound", &"end_round")
	_undo_button = _top_button(bar, "Undo", "Undo", &"undo")
	_top_button(bar, "Settings", "SettingsButton", &"open_settings")

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_banner = PanelContainer.new()
	_banner.visible = false
	root.add_child(_banner)
	var banner_row := HBoxContainer.new()
	_banner.add_child(banner_row)
	_banner_label = Label.new()
	_banner_label.name = "BannerText"
	_banner_label.theme_type_variation = &"TitleLabel"
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_row.add_child(_banner_label)
	_top_button(banner_row, "New match", "Banner_NewMatch", &"new_match")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_board = BoxContainer.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 12)
	scroll.add_child(_board)
	for p in 2:
		var col := PlayerColumn.new(p)
		col.action.connect(do_action)
		_board.add_child(col)
		_columns.append(col)

	_build_settings()


func _top_button(parent: Control, text: String, node_name: String, act: StringName, args: Dictionary = {}) -> Button:
	var b := Button.new()
	b.text = text
	b.name = node_name
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: do_action(act, args.duplicate()))
	parent.add_child(b)
	return b


func _build_settings() -> void:
	_settings = Control.new()
	_settings.name = "Settings"
	_settings.visible = false
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_settings)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			do_action(&"close_settings"))
	_settings.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = &"TitleLabel"
	vb.add_child(title)

	var modes := HBoxContainer.new()
	vb.add_child(modes)
	var ml := Label.new()
	ml.text = "Players"
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(ml)
	for m in [1, 2]:
		var b := _top_button(modes, "1 player" if m == 1 else "2 players", "Settings_Mode%d" % m, &"set_mode", {"mode": m})
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(130, 44)
		_mode_buttons.append(b)
	_lives_check = _check(vb, "Life gems (best of three, ends the match)", "Settings_Lives", "show_lives")
	_rounds_check = _check(vb, "Pass and End round controls", "Settings_Rounds", "show_rounds")
	var hint := Label.new()
	hint.text = "1 player: track a single board (for example, one tablet per player)."
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	_top_button(vb, "New match (keeps names and factions)", "Settings_NewMatch", &"new_match")
	var about := Label.new()
	about.text = "%s\nVersion %s" % [ABOUT_TEXT, ProjectSettings.get_setting("application/config/version", "")]
	about.theme_type_variation = &"MutedLabel"
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(about)
	_top_button(vb, "Close", "Settings_Close", &"close_settings")


func _check(parent: Control, text: String, node_name: String, option: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.name = node_name
	c.custom_minimum_size = Vector2(0, 44)
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void: do_action(&"set_option", {"option": option, "value": on}))
	parent.add_child(c)
	return c


## Side by side in landscape, stacked in portrait; the base resolution follows
## the orientation so text stays readable on tablets held either way.
func _on_resized() -> void:
	var win := get_window()
	var portrait := win.size.y > win.size.x
	var base := PORTRAIT_SIZE if portrait else LANDSCAPE_SIZE
	if win.content_scale_size != base:
		win.content_scale_size = base
	_board.vertical = portrait


# --- actions ------------------------------------------------------------------

## Single, allowlisted entry point for every user action. Unknown actions and
## malformed arguments are ignored; the rules re-validate values as well.
func do_action(act: StringName, a: Dictionary = {}) -> void:
	var p: int = a["p"] if a.get("p") is int and (a["p"] == 0 or a["p"] == 1) else -1
	var row: String = a["row"] if GwentRules.valid_row(a.get("row")) else ""
	match act:
		&"add_unit":
			if p >= 0:
				_commit(func() -> bool: return GwentRules.add_unit(state, p, _active_rows[p], a.get("value")))
		&"add_hero":
			if p >= 0:
				_commit(func() -> bool: return GwentRules.add_hero(state, p, _active_rows[p], a.get("value")))
		&"select_row":
			if p >= 0 and row != "":
				_active_rows[p] = row
				if _selected.get("p") == p and _selected.get("row") != row:
					_selected = {}
				_refresh()
		&"select_card":
			_select_card(p, row, a.get("kind"), a.get("i"))
		&"adjust_card":
			if _selected.get("kind") == "unit":
				var s := _selected
				_commit(func() -> bool: return GwentRules.adjust_unit(state, s["p"], s["row"], s["i"], a.get("delta")))
		&"toggle_card_flag":
			if _selected.get("kind") == "unit":
				var s := _selected
				_commit(func() -> bool: return GwentRules.toggle_unit_flag(state, s["p"], s["row"], s["i"], a.get("flag")))
		&"remove_card":
			if not _selected.is_empty():
				var s := _selected
				_selected = {}
				_commit(func() -> bool: return GwentRules.remove_card(state, s["p"], s["row"], s["kind"], s["i"]))
		&"toggle_horn":
			if p >= 0 and row != "":
				_commit(func() -> bool: return GwentRules.toggle_horn(state, p, row))
		&"clear_row":
			if p >= 0 and row != "":
				_selected = {}
				_commit(func() -> bool: return GwentRules.clear_row(state, p, row))
		&"toggle_weather":
			if row != "":
				_commit(func() -> bool: return GwentRules.toggle_weather(state, row))
		&"clear_weather":
			_commit(func() -> bool: return GwentRules.clear_weather(state))
		&"scorch":
			_selected = {}
			_commit(func() -> bool: return GwentRules.scorch(state) > 0)
		&"end_round":
			_selected = {}
			_commit(func() -> bool: return GwentRules.end_round(state, _rng))
		&"toggle_pass":
			if p >= 0:
				_selected = {}
				_commit(func() -> bool: return GwentRules.toggle_pass(state, p, _rng))
		&"tap_gem":
			if p >= 0:
				_commit(func() -> bool: return GwentRules.tap_gem(state, p, a.get("gem")))
		&"set_name":
			if p >= 0:
				_commit(func() -> bool: return GwentRules.set_player_name(state, p, a.get("name")))
		&"set_faction":
			if p >= 0:
				_commit(func() -> bool: return GwentRules.set_faction(state, p, a.get("faction")))
		&"set_mode":
			_selected = {}
			_commit(func() -> bool: return GwentRules.set_mode(state, a.get("mode")))
		&"set_option":
			_commit(func() -> bool: return GwentRules.set_option(state, a.get("option"), a.get("value")))
		&"new_match":
			_selected = {}
			_settings.visible = false
			_commit(func() -> bool: return GwentRules.new_match(state))
		&"undo":
			_pop_undo()
		&"open_settings":
			_settings.visible = true
			_refresh()
		&"close_settings":
			_settings.visible = false


func _select_card(p: int, row: String, kind: Variant, i: Variant) -> void:
	if p < 0 or row == "" or not (kind == "unit" or kind == "hero") or not i is int:
		return
	var list: Array = state["players"][p]["rows"][row]["units" if kind == "unit" else "heroes"]
	if i < 0 or i >= list.size():
		return
	var pick := {"p": p, "row": row, "kind": kind, "i": i}
	_selected = {} if _selected == pick else pick
	_active_rows[p] = row
	_refresh()


func _commit(change: Callable) -> void:
	var before := JSON.stringify(state)
	if not change.call():
		_refresh()
		return
	_undo.push_back(before)
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_after_change()


func _pop_undo() -> void:
	if _undo.is_empty():
		return
	var json := JSON.new()
	if json.parse(_undo.pop_back()) == OK:
		state = InputSanitizer.normalize_state(json.data)
	_selected = {}
	_after_change()


func _after_change() -> void:
	if not _selected.is_empty():
		var list: Array = state["players"][_selected["p"]]["rows"][_selected["row"]][
			"units" if _selected["kind"] == "unit" else "heroes"]
		if _selected["p"] >= int(state["mode"]) or _selected["i"] >= list.size():
			_selected = {}
	SaveStore.save_state(state)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
		do_action(&"undo")
		get_viewport().set_input_as_handled()


# --- view -------------------------------------------------------------------------

func _refresh() -> void:
	var mode: int = state["mode"]
	var winner := GwentRules.match_winner(state)
	var over := winner != GwentRules.NOT_OVER

	_round_label.text = "Round %d" % state["round"]
	_history_label.text = _history_text()
	_history_label.visible = not _history_label.text.is_empty()
	_status.text = state["message"]
	_status.visible = not _status.text.is_empty()
	for key in GwentRules.ROWS:
		_weather_buttons[key].set_pressed_no_signal(state["weather"][key])
	_scorch.disabled = mode != 2 or over
	_end_round.visible = state["show_rounds"]
	_end_round.disabled = over
	_undo_button.disabled = _undo.is_empty()

	_banner.visible = over
	if over:
		_banner_label.text = "The match is a draw." if winner == GwentRules.DRAW \
			else "%s wins the match!" % state["players"][winner]["name"]

	for p in 2:
		_columns[p].visible = p < mode
		if p < mode:
			_columns[p].refresh(state, _active_rows[p], _selected)

	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(mode == i + 1)
	_lives_check.set_pressed_no_signal(state["show_lives"])
	_rounds_check.set_pressed_no_signal(state["show_rounds"])


func _history_text() -> String:
	var parts: Array[String] = []
	for e: Dictionary in state["history"]:
		var scores: Array = e["scores"]
		if scores.size() == 2:
			var who := "draw" if e["winner"] == GwentRules.DRAW else str(state["players"][e["winner"]]["name"])
			parts.append("R%d  %d - %d  %s" % [e["round"], scores[0], scores[1], who])
		else:
			parts.append("R%d  %d" % [e["round"], scores[0]])
	return "    |    ".join(parts)
