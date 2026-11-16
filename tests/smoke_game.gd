extends SceneTree
## Scripted play-through of the real main scene, pressing the actual UI
## buttons (no persistence):
##   godot --headless --path . --fixed-fps 60 --script res://tests/smoke_game.gd [-- 2|1]
## User arg: player mode (default 2). Exits 0 when everything passes.

var _frame := 0
var _main: Control
var _mode := 2
var _checks := 0
var _failures := 0


func _initialize() -> void:
	SaveStore.persist = false
	var args := OS.get_cmdline_user_args()
	_mode = 1 if args.size() > 0 and args[0] == "1" else 2
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main = current_scene
		if _main == null or not ("state" in _main):
			_fail("main scene did not load")
		elif _mode == 2:
			_play_versus()
		else:
			_play_solo()
		print("%d checks, %d failures" % [_checks, _failures])
		quit(1 if _failures > 0 else 0)
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fail(msg)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  FAIL " + msg)


func _node(path: String) -> Node:
	var n := _main.find_child(path, true, false)
	if n == null:
		_fail("missing node " + path)
	return n


func _press(path: String) -> void:
	var b := _node(path) as BaseButton
	if b == null:
		return
	if b.disabled or not b.is_visible_in_tree():
		_fail("button not usable: " + path)
		return
	b.pressed.emit()


func _total(p: int) -> int:
	var label := _node("P%d_Total" % p) as Label
	return int(label.text) if label else -1


func _play_versus() -> void:
	print("- versus match through the UI")
	var name_edit := _node("P0_Name") as LineEdit
	name_edit.text = "  Geralt <i>R</i>" + char(7) + " "
	name_edit.text_submitted.emit(name_edit.text)
	_check(_main.state["players"][0]["name"] == "Geralt iRi", "name sanitized: " + str(_main.state["players"][0]["name"]))
	(_node("P0_Faction") as OptionButton).item_selected.emit(Factions.IDS.find("northern"))
	(_node("P1_Faction") as OptionButton).item_selected.emit(Factions.IDS.find("nilfgaard"))
	_check(_main.state["players"][1]["faction"] == "nilfgaard", "faction set")
	var col := _node("Player1") as Control
	_check(col.theme == FactionTheme.get_theme("nilfgaard"), "column themed by faction")

	# Player 1: two bonded 4s + a morale 2 in close combat, horn on.
	_press("P0_Unit4")
	_press("P0_Unit4")
	_press("P0_Unit2")
	_press("P0_close_U0")
	_press("P0_close_Bond")
	_press("P0_close_U1")
	_press("P0_close_Bond")
	_press("P0_close_U2")
	_press("P0_close_Morale")
	_check(_total(0) == 8 + 1 + 8 + 1 + 2, "bond x2 and morale: %d" % _total(0))
	_press("P0_close_Horn")
	_check(_total(0) == 40, "horn doubles everything: %d" % _total(0))
	_press("P0_close_Plus")   # card 2 is still selected
	_check(_total(0) == 41, "+1 after horn: %d" % _total(0))
	_press("Undo")
	_check(_total(0) == 40, "undo: %d" % _total(0))

	# Player 2: switch row, add hero and units.
	_tap_row("P1_siege")
	_press("P1_Hero10")
	_press("P1_Unit8")
	_press("P1_Unit8")
	_check(_main.state["players"][1]["rows"]["siege"]["heroes"] == [10], "hero added to selected row")
	_press("Weather_siege")
	_check(_total(1) == 12, "rain: units = 1, hero immune: %d" % _total(1))
	_press("ClearWeather")
	_press("Scorch")
	_check(_total(0) == 4 and _total(1) == 10 + 16, "scorch kills the bonded/horned 18s: %d / %d" % [_total(0), _total(1)])
	_press("Undo")

	# Both pass -> round ends automatically.
	_press("P0_Pass")
	_press("P1_Pass")
	_check(_main.state["round"] == 2, "round ended after both passed")
	_check(_main.state["players"][1]["lives"] == 1, "loser lost a life")
	_check(_main.state["message"].contains("draws a card"), "Northern Realms perk message: " + _main.state["message"])
	_check(_total(0) == 0 and _total(1) == 0, "board cleared")

	# Round 2 is a 0-0 draw: Nilfgaard wins it, match over.
	_press("EndRound")
	_check(_main.state["players"][0]["lives"] == 1, "Nilfgaard won the draw")
	_press("EndRound")
	_check(GwentRules.is_match_over(_main.state), "match over")
	var banner := _node("BannerText") as Label
	_check(banner.is_visible_in_tree() and banner.text.contains("wins the match"), "winner banner: " + banner.text)
	_check((_node("EndRound") as Button).disabled, "End round disabled after the match")
	_press("Banner_NewMatch")
	_check(_main.state["round"] == 1 and not GwentRules.is_match_over(_main.state), "new match")
	_check(_main.state["players"][0]["faction"] == "northern", "faction kept")

	# Hidden look: typing a magic name re-themes the column, faction stays.
	var p1_name := _node("P1_Name") as LineEdit
	p1_name.text = "Babbustaman"
	p1_name.text_submitted.emit(p1_name.text)
	_check(col.theme == FactionTheme.get_theme("egg_gold"), "Babbustaman: black and gold column")
	_check(_main.state["players"][1]["faction"] == "nilfgaard", "faction (and perk) unchanged")
	p1_name.text = "Emhyr"
	p1_name.text_submitted.emit(p1_name.text)
	_check(col.theme == FactionTheme.get_theme("nilfgaard"), "other name: faction theme again")

	# Settings
	_press("SettingsButton")
	_check((_node("Settings") as Control).visible, "settings open")
	(_node("Settings_Lives") as CheckButton).toggled.emit(false)
	_check(not _main.state["show_lives"], "life gems off")
	_check(not (_node("P0_Gem1") as Control).is_visible_in_tree(), "gems hidden")
	_press("Settings_Close")

	# Android back button: closes Settings first, then clears the selection.
	_press("SettingsButton")
	_main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not (_node("Settings") as Control).visible, "back closes settings")
	_press("P0_Unit3")
	_press("P0_close_U0")
	_check(not _main._selected.is_empty(), "card selected")
	_main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(_main._selected.is_empty(), "back clears the card selection")
	_check((_main.find_child("Settings_AndroidApp", true, false) != null) == OS.has_feature("web"),
		"'Get the Android app' link only in the web build")


func _play_solo() -> void:
	print("- solo board through the UI")
	_press("SettingsButton")
	_press("Settings_Mode1")
	_press("Settings_Close")
	_check(_main.state["mode"] == 1, "solo mode")
	_check(not (_node("Player1") as Control).visible, "second column hidden")
	_check((_node("Scorch") as Button).disabled, "scorch needs two boards")
	(_node("P0_Faction") as OptionButton).item_selected.emit(Factions.IDS.find("monsters"))
	_tap_row("P0_ranged")
	_press("P0_Unit6")
	_press("P0_Unit5")
	_check(_total(0) == 11, "solo total: %d" % _total(0))
	_press("P0_Pass")
	_check(_main.state["round"] == 1, "solo pass doesn't end the round")
	_press("P0_Pass")
	_press("EndRound")
	_check(_main.state["round"] == 2, "solo end round")
	_check(_total(0) == 5 or _total(0) == 6, "Monsters kept one card: %d" % _total(0))
	_press("P0_ranged_U0")
	_press("P0_ranged_Remove")
	_check(_total(0) == 0, "card removed")


func _tap_row(path: String) -> void:
	var row := _node(path) as RowPanel
	if row:
		row._gui_input(_click())


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
