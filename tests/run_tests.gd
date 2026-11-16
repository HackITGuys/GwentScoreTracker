extends SceneTree
## Headless logic tests:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits 0 when everything passes, 1 otherwise.

var _checks := 0
var _failures := 0
var _section := ""


func _initialize() -> void:
	SaveStore.persist = false
	_test_unit_strength()
	_test_row_and_player_scores()
	_test_card_actions()
	_test_scorch()
	_test_round_resolution()
	_test_faction_perks()
	_test_pass_and_match_end()
	_test_solo_mode()
	_test_new_match()
	_test_name_sanitizing()
	_test_state_normalizing()
	_test_save_store()
	_test_factions_and_themes()
	print("")
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("  FAIL [%s] %s" % [_section, msg])


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [msg, got, want])


func _begin(name: String) -> void:
	_section = name
	print("- " + name)


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Row with units given as [base, bond, morale, adj] and hero values.
func _row(units: Array, heroes: Array = [], horn := false) -> Dictionary:
	var row := GwentRules.new_row()
	row["horn"] = horn
	for u: Array in units:
		var unit := GwentRules.new_unit(u[0])
		unit["bond"] = u[1] if u.size() > 1 else false
		unit["morale"] = u[2] if u.size() > 2 else false
		unit["adj"] = u[3] if u.size() > 3 else 0
		row["units"].append(unit)
	row["heroes"].append_array(heroes)
	return row


func _state_with(p: int, key: String, row: Dictionary) -> Dictionary:
	var s := GwentRules.new_state()
	s["players"][p]["rows"][key] = row
	return s


# ---------------------------------------------------------------------------

func _test_unit_strength() -> void:
	_begin("unit strength (Witcher 3 order)")
	_eq(GwentRules.unit_strength(_row([[5]]), 0, false), 5, "plain unit")
	_eq(GwentRules.unit_strength(_row([[8]]), 0, true), 1, "weather sets base to 1")
	_eq(GwentRules.unit_strength(_row([[0]]), 0, true), 0, "weather keeps 0 at 0")
	_eq(GwentRules.unit_strength(_row([[4]], [], true), 0, false), 8, "horn doubles")
	_eq(GwentRules.unit_strength(_row([[4]], [], true), 0, true), 2, "weather then horn")
	var bond := _row([[4, true], [4, true], [4, true], [4, false], [5, true]])
	_eq(GwentRules.unit_strength(bond, 0, false), 12, "bond x3 by same base")
	_eq(GwentRules.unit_strength(bond, 3, false), 4, "untagged unit not bonded")
	_eq(GwentRules.unit_strength(bond, 4, false), 5, "bond group of one = x1")
	_eq(GwentRules.unit_strength(bond, 0, true), 3, "weather then bond: 1 x 3")
	var morale := _row([[3, false, true], [5], [2, false, true]])
	_eq(GwentRules.unit_strength(morale, 0, false), 4, "morale card gets +1 from the other one only")
	_eq(GwentRules.unit_strength(morale, 1, false), 7, "+1 from each morale card")
	var order := _row([[2, true], [2, true], [6, false, true]], [], true)
	# (2 x 2 bond + 1 morale) x 2 horn = 10
	_eq(GwentRules.unit_strength(order, 0, false), 10, "bond -> morale -> horn")
	_eq(GwentRules.unit_strength(order, 2, false), 12, "morale card: not boosted by itself, horn x2")
	_eq(GwentRules.unit_strength(_row([[5, false, false, 1]], [], true), 0, false), 11, "manual +1 after horn")
	_eq(GwentRules.unit_strength(_row([[1, false, false, -5]]), 0, false), 0, "never below 0")


func _test_row_and_player_scores() -> void:
	_begin("row and player scores")
	var s := _state_with(0, "close", _row([[5], [3]], [10, 15], true))
	_eq(GwentRules.row_score(s, 0, "close"), 16 + 25, "heroes ignore horn")
	s["weather"]["close"] = true
	_eq(GwentRules.row_score(s, 0, "close"), 4 + 25, "heroes ignore weather")
	s["players"][0]["rows"]["siege"] = _row([[8]])
	_eq(GwentRules.player_score(s, 0), 29 + 8, "player total = sum of rows")
	_eq(GwentRules.leader(s), 0, "player 0 leads")
	s["players"][1]["rows"]["ranged"] = _row([[10], [10], [10], [8]])
	_eq(GwentRules.leader(s), 1, "player 1 leads (38 vs 37)")
	s["players"][1]["rows"]["ranged"] = _row([[10], [10], [10], [7]])
	_eq(GwentRules.leader(s), GwentRules.DRAW, "level scores (37 vs 37): no leader")


func _test_card_actions() -> void:
	_begin("card actions validate their input")
	var s := GwentRules.new_state()
	_check(GwentRules.add_unit(s, 0, "close", 5), "add a 5")
	_check(not GwentRules.add_unit(s, 0, "close", 11), "11 is not an allowed unit value")
	_check(not GwentRules.add_unit(s, 0, "close", 5.0), "floats rejected")
	_check(not GwentRules.add_unit(s, 0, "melee", 5), "unknown row rejected")
	_check(not GwentRules.add_unit(s, 2, "close", 5), "unknown player rejected")
	_check(not GwentRules.add_unit(s, -1, "close", 5), "negative player rejected")
	_check(GwentRules.add_hero(s, 0, "close", 15), "add hero 15")
	_check(not GwentRules.add_hero(s, 0, "close", 5), "5 is not a hero value")
	for i in GwentRules.MAX_UNITS_PER_ROW:
		GwentRules.add_unit(s, 1, "siege", 1)
	_check(not GwentRules.add_unit(s, 1, "siege", 1), "row capped at %d units" % GwentRules.MAX_UNITS_PER_ROW)

	_check(GwentRules.adjust_unit(s, 0, "close", 0, 1), "+1")
	_eq(GwentRules.row_score(s, 0, "close"), 6 + 15, "adjusted score")
	_check(not GwentRules.adjust_unit(s, 0, "close", 0, 2), "only +1/-1")
	_check(not GwentRules.adjust_unit(s, 0, "close", 7, 1), "index out of range")
	GwentRules.add_unit(s, 0, "ranged", 0)
	_check(not GwentRules.adjust_unit(s, 0, "ranged", 0, -1), "can't go below 0")
	_check(GwentRules.toggle_unit_flag(s, 0, "close", 0, "bond"), "toggle bond")
	_check(not GwentRules.toggle_unit_flag(s, 0, "close", 0, "adj"), "only bond/morale flags")
	_check(GwentRules.toggle_horn(s, 0, "close"), "horn on")
	_check(s["players"][0]["rows"]["close"]["horn"], "horn stored")
	_check(GwentRules.remove_card(s, 0, "close", "hero", 0), "remove hero")
	_check(not GwentRules.remove_card(s, 0, "close", "spell", 0), "unknown kind rejected")
	_check(GwentRules.clear_row(s, 0, "close"), "clear row")
	_eq(GwentRules.row_score(s, 0, "close"), 0, "cleared row is empty")
	_check(GwentRules.toggle_weather(s, "ranged") and s["weather"]["ranged"], "weather on")
	_check(GwentRules.clear_weather(s) and not s["weather"]["ranged"], "clear weather")
	_check(GwentRules.tap_gem(s, 0, 2) and s["players"][0]["lives"] == 1, "tap lit gem 2 -> 1 life")
	_check(GwentRules.tap_gem(s, 0, 1) and s["players"][0]["lives"] == 0, "tap lit gem 1 -> 0 lives")
	_check(GwentRules.tap_gem(s, 0, 2) and s["players"][0]["lives"] == 2, "tap dark gem 2 -> 2 lives")
	_check(not GwentRules.tap_gem(s, 0, 3), "only 2 gems")
	_check(not GwentRules.set_mode(s, 3), "mode must be 1 or 2")
	_check(not GwentRules.set_option(s, "round", true), "only known options")
	_check(not GwentRules.set_faction(s, 0, "redania"), "unknown faction rejected")
	_check(GwentRules.set_faction(s, 0, "skellige"), "known faction accepted")


func _test_scorch() -> void:
	_begin("scorch")
	var s := GwentRules.new_state()
	s["players"][0]["rows"]["close"] = _row([[8], [3]], [15])
	s["players"][1]["rows"]["siege"] = _row([[4, false, false, 4], [8]])
	_eq(GwentRules.scorch(s), 3, "kills all units at the top strength, both sides")
	_eq(GwentRules.player_score(s, 0), 3 + 15, "hero survives, weaker unit survives")
	_eq(GwentRules.player_score(s, 1), 0, "both 8s on player 1 gone")
	var e := GwentRules.new_state()
	_eq(GwentRules.scorch(e), 0, "empty board: nothing happens")
	s["mode"] = 1
	_eq(GwentRules.scorch(s), 0, "solo mode: disabled")
	var bonded := GwentRules.new_state()
	bonded["players"][0]["rows"]["close"] = _row([[4, true], [4, true], [7]])
	_eq(GwentRules.scorch(bonded), 2, "uses current strength (bonded 8s beat a 7)")


func _test_round_resolution() -> void:
	_begin("round resolution")
	var s := GwentRules.new_state()
	s["players"][0]["rows"]["close"] = _row([[10]])
	s["players"][1]["rows"]["close"] = _row([[5]])
	s["weather"]["close"] = true
	s["players"][0]["rows"]["close"]["units"][0]["adj"] = 9   # 1 + 9 = 10
	_check(GwentRules.end_round(s, _rng()), "round ended")
	_eq(s["players"][1]["lives"], 1, "loser loses a life")
	_eq(s["players"][0]["lives"], 2, "winner keeps lives")
	_eq(s["round"], 2, "round advances")
	_eq(s["history"].size(), 1, "history recorded")
	_eq(s["history"][0]["scores"], [10, 1], "history scores")
	_eq(s["history"][0]["winner"], 0, "history winner")
	_check(not s["weather"]["close"], "weather cleared")
	_eq(GwentRules.player_score(s, 0) + GwentRules.player_score(s, 1), 0, "boards cleared")
	_check(s["message"].contains("Player 1 wins round 1"), "message names the winner: " + s["message"])
	GwentRules.end_round(s, _rng())
	_eq(s["players"][0]["lives"], 1, "draw: both lose a life (p0)")
	_eq(s["players"][1]["lives"], 0, "draw: both lose a life (p1)")
	_check(GwentRules.is_match_over(s), "match over at 0 lives")
	_eq(GwentRules.match_winner(s), 0, "player with lives left wins")
	_check(not GwentRules.end_round(s, _rng()), "no rounds after the match ends")
	_check(s["message"].contains("wins the match"), "match message: " + s["message"])

	var no_lives := GwentRules.new_state()
	no_lives["show_lives"] = false
	GwentRules.end_round(no_lives, _rng())
	_eq(no_lives["players"][0]["lives"], 2, "life gems off: no life loss")
	_check(not GwentRules.is_match_over(no_lives), "life gems off: never over")


func _test_faction_perks() -> void:
	_begin("faction perks")
	var s := GwentRules.new_state()
	s["players"][1]["faction"] = "nilfgaard"
	GwentRules.end_round(s, _rng())
	_eq(s["history"][0]["winner"], 1, "Nilfgaard wins a draw")
	_eq(s["players"][0]["lives"], 1, "non-Nilfgaard loses the life")
	_eq(s["players"][1]["lives"], 2, "Nilfgaard keeps lives")
	var both := GwentRules.new_state()
	both["players"][0]["faction"] = "nilfgaard"
	both["players"][1]["faction"] = "nilfgaard"
	GwentRules.end_round(both, _rng())
	_eq(both["history"][0]["winner"], GwentRules.DRAW, "two Nilfgaard players: normal draw")

	var nr := GwentRules.new_state()
	nr["players"][0]["faction"] = "northern"
	nr["players"][0]["rows"]["siege"] = _row([[8]])
	GwentRules.end_round(nr, _rng())
	_check(nr["message"].contains("draws a card"), "Northern Realms reminder: " + nr["message"])

	var m := GwentRules.new_state()
	m["players"][0]["faction"] = "monsters"
	m["players"][0]["rows"]["close"] = _row([[6, true, true, 3], [2]], [], true)
	m["players"][0]["rows"]["ranged"] = _row([], [10])
	m["players"][1]["rows"]["close"] = _row([[9]])
	GwentRules.end_round(m, _rng(7))
	var kept := 0
	for key in GwentRules.ROWS:
		var r: Dictionary = m["players"][0]["rows"][key]
		kept += r["units"].size() + r["heroes"].size()
		_check(not r["horn"], "horn discarded in " + key)
		for u: Dictionary in r["units"]:
			_eq(u["adj"], 0, "kept unit loses manual adjustments")
	_eq(kept, 1, "Monsters keep exactly one card")
	_check(m["message"].contains("Monsters"), "Monsters message: " + m["message"])
	_eq(GwentRules.player_score(m, 1), 0, "opponent board cleared")
	var empty_m := GwentRules.new_state()
	empty_m["players"][0]["faction"] = "monsters"
	GwentRules.end_round(empty_m, _rng())
	_check(not empty_m["message"].contains("Monsters"), "nothing to keep: no message")

	var sk := GwentRules.new_state()
	sk["show_lives"] = false
	sk["players"][1]["faction"] = "skellige"
	GwentRules.end_round(sk, _rng())
	_check(not sk["message"].contains("Skellige"), "no Skellige reminder before round 3")
	GwentRules.end_round(sk, _rng())
	_eq(sk["round"], 3, "round 3")
	_check(sk["message"].contains("Skellige"), "Skellige reminder at round 3: " + sk["message"])


func _test_pass_and_match_end() -> void:
	_begin("pass and auto end of round")
	var s := GwentRules.new_state()
	s["players"][0]["rows"]["close"] = _row([[5]])
	_check(GwentRules.toggle_pass(s, 0, _rng()), "player 1 passes")
	_check(s["players"][0]["passed"], "pass stored")
	_eq(s["round"], 1, "one pass doesn't end the round")
	_check(GwentRules.toggle_pass(s, 1, _rng()), "player 2 passes")
	_eq(s["round"], 2, "both passed: round ended")
	_check(not s["players"][0]["passed"] and not s["players"][1]["passed"], "pass flags reset")
	GwentRules.toggle_pass(s, 0, _rng())
	GwentRules.toggle_pass(s, 0, _rng())
	_check(not s["players"][0]["passed"], "pass can be undone")
	_eq(s["round"], 2, "un-pass doesn't end the round")


func _test_solo_mode() -> void:
	_begin("solo mode")
	var s := GwentRules.new_state()
	GwentRules.set_mode(s, 1)
	s["players"][0]["rows"]["siege"] = _row([[6]])
	GwentRules.toggle_pass(s, 0, _rng())
	_eq(s["round"], 1, "solo pass never ends the round")
	_check(not GwentRules.add_unit(s, 1, "close", 5), "hidden player 2 can't be edited")
	GwentRules.end_round(s, _rng())
	_eq(s["round"], 2, "solo end round")
	_eq(s["history"][0]["scores"], [6], "solo history has one score")
	_eq(s["players"][0]["lives"], 2, "solo end round doesn't touch lives")


func _test_new_match() -> void:
	_begin("new match")
	var s := GwentRules.new_state()
	GwentRules.set_player_name(s, 0, "Geralt")
	GwentRules.set_faction(s, 0, "scoiatael")
	GwentRules.add_unit(s, 0, "close", 5)
	GwentRules.end_round(s, _rng())
	GwentRules.new_match(s)
	_eq(s["round"], 1, "round reset")
	_eq(s["history"], [], "history reset")
	_eq(s["players"][0]["name"], "Geralt", "name kept")
	_eq(s["players"][0]["faction"], "scoiatael", "faction kept")
	_eq(s["players"][1]["lives"], 2, "lives reset")
	_check(s["message"].contains("decides who goes first"), "Scoia'tael reminder: " + s["message"])


func _test_name_sanitizing() -> void:
	_begin("name sanitizing")
	var S := InputSanitizer
	_eq(S.sanitize_name("Geralt", 0), "Geralt", "plain name")
	_eq(S.sanitize_name("  Ciri   of  Cintra ", 0), "Ciri of Cintra", "spaces collapsed and trimmed")
	_eq(S.sanitize_name("Gaunter O'Dimm", 0), "Gaunter O'Dimm", "apostrophe allowed")
	_eq(S.sanitize_name("Zoë Ærøskøbing", 0), "Zoë Ærøskøbing", "accents and Nordic letters kept")
	_eq(S.sanitize_name("名前", 0), "名前", "non-Latin letters kept")
	_eq(S.sanitize_name("\"><img src=x onerror=alert(1)>", 0), "img srcx onerroraler", "markup stripped, then capped")
	_eq(S.sanitize_name("[b]Bold[/b] {x}", 0), "bBoldb x", "BBCode / format brackets stripped")
	_eq(S.sanitize_name("Ger" + char(0x202E) + "alt", 0), "Geralt", "bidi override removed")
	_eq(S.sanitize_name("Ger" + char(0x200B) + "alt" + char(0xFEFF), 0), "Geralt", "zero-width removed")
	_eq(S.sanitize_name("a\nb\tc" + char(7) + "d", 0), "a b cd", "newline/tab -> space, control char removed")
	_eq(S.sanitize_name("A".repeat(500), 0), "A".repeat(20), "capped at 20 characters")
	_eq(S.sanitize_name("", 1), "Player 2", "empty -> default")
	_eq(S.sanitize_name("<<>>", 0), "Player 1", "nothing left -> default")
	_eq(S.sanitize_name(42, 0), "Player 1", "non-string -> default")
	_eq(S.sanitize_name(null, 1), "Player 2", "null -> default")
	_eq(S.sanitize_message("Round 1" + char(0x202E) + "\n!"), "Round 1!", "status message control chars removed")


func _test_state_normalizing() -> void:
	_begin("state normalizing (tampered saves)")
	var N := InputSanitizer
	var fresh := GwentRules.new_state()
	_eq(N.normalize_state(null), fresh, "null -> fresh")
	_eq(N.normalize_state("text"), fresh, "string -> fresh")
	_eq(N.normalize_state([1, 2]), fresh, "array -> fresh")
	_eq(N.normalize_state({}), fresh, "empty dict -> fresh")

	# Round trip through JSON (numbers become floats) keeps a valid state.
	var s := GwentRules.new_state()
	GwentRules.set_player_name(s, 0, "Yen")
	GwentRules.set_faction(s, 1, "monsters")
	GwentRules.add_unit(s, 0, "close", 7)
	GwentRules.toggle_unit_flag(s, 0, "close", 0, "morale")
	GwentRules.add_hero(s, 1, "siege", 10)
	GwentRules.end_round(s, _rng())
	var back := N.normalize_state(JSON.parse_string(JSON.stringify(s)))
	_eq(JSON.stringify(back), JSON.stringify(s), "JSON round trip is lossless")
	_check(back["round"] is int, "numbers converted back to int")

	var bad := {
		"__proto__": {"mode": 1}, "extra": "x", "mode": 7, "round": -3, "show_lives": "yes",
		"message": "<b>hi</b>" + char(0x202E),
		"weather": {"close": 1, "ranged": true, "lava": true},
		"history": [{"round": 1, "scores": [1e12, -5], "winner": 9}, "junk", {"scores": []}],
		"players": [
			{"name": "<script>alert(1)</script>", "faction": "../../etc", "lives": 99, "passed": 1,
			 "rows": {"close": {"horn": "true", "units": [{"base": 11}, {"base": 5, "adj": 1e9, "bond": "y"}, "u", {"base": 2.5}],
						"heroes": [15, 3, "10", 10.0]}, "melee": {}}},
			"not a player",
		],
	}
	var n := N.normalize_state(bad)
	_check(not n.has("__proto__") and not n.has("extra"), "unknown keys dropped")
	_eq(n["mode"], 2, "invalid mode -> 2")
	_eq(n["round"], 1, "invalid round -> 1")
	_eq(n["show_lives"], true, "non-bool option -> default")
	_eq(n["message"], "<b>hi</b>", "message only stripped of control chars (shown as plain text)")
	_eq(n["weather"], {"close": false, "ranged": true, "siege": false}, "weather allowlisted")
	_eq(n["history"].size(), 1, "junk history dropped")
	_eq(n["history"][0]["scores"], [0, 0], "out-of-range scores clamped to 0")
	_eq(n["history"][0]["winner"], GwentRules.DRAW, "invalid winner -> draw")
	var p0: Dictionary = n["players"][0]
	_eq(p0["name"], "scriptalert1script", "name sanitized")
	_eq(p0["faction"], "neutral", "unknown faction -> neutral")
	_eq(p0["lives"], 2, "lives out of range -> 2")
	_eq(p0["passed"], false, "non-bool passed -> false")
	_eq(p0["rows"]["close"]["horn"], false, "string horn -> false")
	_eq(p0["rows"]["close"]["units"].size(), 1, "only the valid unit survives")
	_eq(p0["rows"]["close"]["units"][0], {"base": 5, "bond": false, "morale": false, "adj": 0}, "unit fields rebuilt")
	_eq(p0["rows"]["close"]["heroes"], [15, 10], "hero values allowlisted")
	_check(not p0["rows"].has("melee"), "unknown row dropped")
	_eq(n["players"][1], GwentRules.new_player(1), "invalid player -> default")

	var big := {"players": [{"rows": {"close": {"units": []}}}, {}]}
	for i in 500:
		big["players"][0]["rows"]["close"]["units"].append({"base": 1})
	_eq(N.normalize_state(big)["players"][0]["rows"]["close"]["units"].size(), GwentRules.MAX_UNITS_PER_ROW, "units capped")
	_eq(N.normalize_state({"players": [{}]})["players"], fresh["players"], "wrong player count -> defaults")


func _test_save_store() -> void:
	_begin("save store")
	_check(OS.get_user_data_dir().replace("\\", "/").ends_with("/GwentScoreTracker"),
		"saves go to the per-user GwentScoreTracker folder: " + OS.get_user_data_dir())
	var old_path := SaveStore.path
	SaveStore.path = "user://test_state.json"
	SaveStore.persist = true
	var s := GwentRules.new_state()
	GwentRules.set_player_name(s, 1, "Triss")
	GwentRules.add_unit(s, 1, "ranged", 9)
	_check(SaveStore.save_state(s), "save")
	_check(SaveStore.save_state(s), "save again (replaces the file)")
	_check(not FileAccess.file_exists(SaveStore.path + ".tmp"), "temp file renamed away")
	_eq(JSON.stringify(SaveStore.load_state()), JSON.stringify(s), "load returns the saved state")

	var f := FileAccess.open(SaveStore.path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	_eq(SaveStore.load_state(), GwentRules.new_state(), "garbage file -> fresh state")
	f = FileAccess.open(SaveStore.path, FileAccess.WRITE)
	f.store_string(" ".repeat(SaveStore.MAX_BYTES + 1))
	f.close()
	_eq(SaveStore.load_state(), GwentRules.new_state(), "oversize file ignored")
	f = FileAccess.open(SaveStore.path, FileAccess.WRITE)
	f.store_string('[gd_resource type="Resource" format=3]\n[resource]\nscript = null')
	f.close()
	_eq(SaveStore.load_state(), GwentRules.new_state(), "resource text is not loaded as a resource")

	DirAccess.remove_absolute(SaveStore.path)
	_eq(SaveStore.load_state(), GwentRules.new_state(), "missing file -> fresh state")
	SaveStore.persist = false
	_check(not SaveStore.save_state(s), "persist off: no write")
	_check(not FileAccess.file_exists(SaveStore.path), "persist off: file not created")
	SaveStore.path = old_path


func _test_factions_and_themes() -> void:
	_begin("factions and themes")
	for id in Factions.IDS:
		var d := Factions.get_data(id)
		for k in ["name", "perk", "bg", "panel", "row", "accent", "accent_dark", "text", "muted"]:
			_check(d.has(k), "%s has %s" % [id, k])
		var t := FactionTheme.get_theme(id)
		_check(t.has_stylebox("panel", "RowPanelActive"), id + " theme has row styles")
		_check(t.has_stylebox("normal", "GemOn"), id + " theme has gem styles")
		# Text must stay readable on the column background (WCAG AA ~ 4.5).
		_check(_contrast(d["text"], d["panel"]) >= 4.5, id + " text contrast")
		_check(_contrast(d["accent"], d["panel"]) >= 3.0, id + " accent contrast")
	_eq(Factions.IDS.size(), Factions.DATA.size(), "every faction has data")
	_eq(Factions.get_data("bogus"), Factions.DATA["neutral"], "unknown faction -> neutral palette")

	_begin("hidden name looks")
	_eq(Factions.look_for("Øystein", "nilfgaard"), "egg_poo", "Øystein -> poo look")
	_eq(Factions.look_for("øYSTEIN", "neutral"), "egg_poo", "case-insensitive")
	_eq(Factions.look_for("Babbustaman", "monsters"), "egg_gold", "Babbustaman -> black and gold")
	_eq(Factions.look_for("Geralt", "skellige"), "skellige", "other names keep the faction look")
	_eq(Factions.look_for("Oystein", "northern"), "northern", "only the exact name")
	for id in Factions.HIDDEN:
		var d: Dictionary = Factions.HIDDEN[id]
		_check(not Factions.IDS.has(id) and not Factions.is_valid(id), id + " is not a selectable faction")
		_check(Factions.has_palette(id), id + " has a palette")
		_check(FactionTheme.get_theme(id).has_stylebox("panel", "RowPanelActive"), id + " theme builds")
		_check(_contrast(d["text"], d["panel"]) >= 4.5, id + " text contrast")
		_check(_contrast(d["accent"], d["panel"]) >= 3.0, id + " accent contrast")
	var s := GwentRules.new_state()
	_check(not GwentRules.set_faction(s, 0, "egg_poo"), "hidden look can't be set as a faction")
	GwentRules.set_player_name(s, 0, "Øystein")
	_eq(s["players"][0]["name"], "Øystein", "name survives sanitizing")
	_eq(s["players"][0]["faction"], "neutral", "faction unchanged by the name")
	var tampered := {"players": [{"faction": "egg_gold"}, {}]}
	_eq(InputSanitizer.normalize_state(tampered)["players"][0]["faction"], "neutral", "hidden look rejected in saves")


func _contrast(a: Color, b: Color) -> float:
	var la := a.get_luminance() + 0.05
	var lb := b.get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)
