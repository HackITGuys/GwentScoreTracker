class_name GwentRules
extends RefCounted
## Witcher 3 Gwent scoring and round logic, as pure static functions.
##
## The match state is a plain JSON-shaped Dictionary (see new_state()), so it
## can be saved, restored and undone without ever deserialising objects. All
## mutators work in place, validate their arguments and return true when they
## changed something (the caller uses that to record undo + save).
##
## Unit strength, in Witcher 3 order:
##   base -> weather (base > 0 becomes 1) -> x tight bond -> + morale
##   -> x2 Commander's Horn -> + manual adjustment (never below 0).
## Hero cards ignore all of the above.

const ROWS: Array[String] = ["close", "ranged", "siege"]
const ROW_TITLES := {"close": "Close Combat", "ranged": "Ranged Combat", "siege": "Siege"}
const WEATHER_NAMES := {"close": "Biting Frost", "ranged": "Impenetrable Fog", "siege": "Torrential Rain"}

const UNIT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15]
const HERO_VALUES: Array[int] = [0, 7, 8, 10, 15]
const UNIT_FLAGS: Array[String] = ["bond", "morale"]

const MAX_LIVES := 2
const MAX_UNITS_PER_ROW := 40
const MAX_HEROES_PER_ROW := 20
const MAX_ADJ := 99
const MAX_ROUND := 99
const MAX_HISTORY := 20
const MAX_SCORE := 99999

## Round / match outcome codes.
const DRAW := -1
const NOT_OVER := -2

const SAVE_VERSION := 3


# --- construction -----------------------------------------------------------

static func new_row() -> Dictionary:
	return {"horn": false, "units": [], "heroes": []}


static func new_rows() -> Dictionary:
	var rows := {}
	for key in ROWS:
		rows[key] = new_row()
	return rows


static func new_player(index: int, player_name: String = "", faction: String = Factions.DEFAULT) -> Dictionary:
	return {
		"name": player_name if not player_name.is_empty() else "Player %d" % (index + 1),
		"faction": faction if Factions.is_valid(faction) else Factions.DEFAULT,
		"lives": MAX_LIVES,
		"passed": false,
		"rows": new_rows(),
	}


static func new_state() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"mode": 2,
		"show_lives": true,
		"show_rounds": true,
		"round": 1,
		"message": "",
		"history": [],
		"weather": {"close": false, "ranged": false, "siege": false},
		"players": [new_player(0), new_player(1)],
	}


static func new_unit(base: int) -> Dictionary:
	return {"base": base, "bond": false, "morale": false, "adj": 0}


# --- argument checks (shared with the UI dispatcher) ---------------------------

static func valid_player(state: Dictionary, p: Variant) -> bool:
	return p is int and p >= 0 and p < int(state["mode"])


static func valid_row(row: Variant) -> bool:
	return row is String and ROWS.has(row)


static func _row(state: Dictionary, p: int, row: String) -> Dictionary:
	return state["players"][p]["rows"][row]


# --- scoring ------------------------------------------------------------------

## Current strength of unit `i` in `row`.
static func unit_strength(row: Dictionary, i: int, weather: bool) -> int:
	var units: Array = row["units"]
	var u: Dictionary = units[i]
	var s: int = u["base"]
	if weather and s > 0:
		s = 1
	if u["bond"]:
		var group := 0
		for other: Dictionary in units:
			if other["bond"] and other["base"] == u["base"]:
				group += 1
		s *= group
	for j in units.size():
		if j != i and units[j]["morale"]:
			s += 1
	if row["horn"]:
		s *= 2
	return maxi(0, s + int(u["adj"]))


static func row_score(state: Dictionary, p: int, row_key: String) -> int:
	var row := _row(state, p, row_key)
	var weather: bool = state["weather"][row_key]
	var total := 0
	for i in row["units"].size():
		total += unit_strength(row, i, weather)
	for h: int in row["heroes"]:
		total += h
	return total


static func player_score(state: Dictionary, p: int) -> int:
	var total := 0
	for key in ROWS:
		total += row_score(state, p, key)
	return total


## Index of the player currently ahead, or DRAW when level / solo mode.
static func leader(state: Dictionary) -> int:
	if int(state["mode"]) != 2:
		return DRAW
	var a := player_score(state, 0)
	var b := player_score(state, 1)
	return 0 if a > b else (1 if b > a else DRAW)


## NOT_OVER while the match is running, otherwise the winner index or DRAW.
## Derived from lives, so a manual life correction re-opens the match.
static func match_winner(state: Dictionary) -> int:
	if int(state["mode"]) != 2 or not state["show_lives"]:
		return NOT_OVER
	var a: int = state["players"][0]["lives"]
	var b: int = state["players"][1]["lives"]
	if a > 0 and b > 0:
		return NOT_OVER
	if a == 0 and b == 0:
		return DRAW
	return 0 if a > 0 else 1


static func is_match_over(state: Dictionary) -> bool:
	return match_winner(state) != NOT_OVER


# --- card actions ---------------------------------------------------------------

static func add_unit(state: Dictionary, p: int, row: String, value: Variant) -> bool:
	if not (valid_player(state, p) and valid_row(row) and value is int and UNIT_VALUES.has(value)):
		return false
	var units: Array = _row(state, p, row)["units"]
	if units.size() >= MAX_UNITS_PER_ROW:
		return false
	units.append(new_unit(value))
	return true


static func add_hero(state: Dictionary, p: int, row: String, value: Variant) -> bool:
	if not (valid_player(state, p) and valid_row(row) and value is int and HERO_VALUES.has(value)):
		return false
	var heroes: Array = _row(state, p, row)["heroes"]
	if heroes.size() >= MAX_HEROES_PER_ROW:
		return false
	heroes.append(value)
	return true


static func _valid_unit(state: Dictionary, p: int, row: String, i: Variant) -> bool:
	return valid_player(state, p) and valid_row(row) and i is int \
		and i >= 0 and i < _row(state, p, row)["units"].size()


## +1 / -1 on a unit. A unit already at 0 strength can't go lower.
static func adjust_unit(state: Dictionary, p: int, row: String, i: Variant, delta: Variant) -> bool:
	if not (_valid_unit(state, p, row, i) and delta is int and (delta == 1 or delta == -1)):
		return false
	var r := _row(state, p, row)
	if delta < 0 and unit_strength(r, i, state["weather"][row]) <= 0:
		return false
	var u: Dictionary = r["units"][i]
	var adj: int = clampi(int(u["adj"]) + delta, -MAX_ADJ, MAX_ADJ)
	if adj == u["adj"]:
		return false
	u["adj"] = adj
	return true


static func toggle_unit_flag(state: Dictionary, p: int, row: String, i: Variant, flag: Variant) -> bool:
	if not (_valid_unit(state, p, row, i) and flag is String and UNIT_FLAGS.has(flag)):
		return false
	var u: Dictionary = _row(state, p, row)["units"][i]
	u[flag] = not u[flag]
	return true


static func remove_card(state: Dictionary, p: int, row: String, kind: Variant, i: Variant) -> bool:
	if not (valid_player(state, p) and valid_row(row) and i is int and i >= 0):
		return false
	var list: Array
	if kind == "unit":
		list = _row(state, p, row)["units"]
	elif kind == "hero":
		list = _row(state, p, row)["heroes"]
	else:
		return false
	if i >= list.size():
		return false
	list.remove_at(i)
	return true


static func toggle_horn(state: Dictionary, p: int, row: String) -> bool:
	if not (valid_player(state, p) and valid_row(row)):
		return false
	var r := _row(state, p, row)
	r["horn"] = not r["horn"]
	return true


static func clear_row(state: Dictionary, p: int, row: String) -> bool:
	if not (valid_player(state, p) and valid_row(row)):
		return false
	state["players"][p]["rows"][row] = new_row()
	return true


# --- battlefield actions --------------------------------------------------------

static func toggle_weather(state: Dictionary, row: String) -> bool:
	if not valid_row(row):
		return false
	state["weather"][row] = not state["weather"][row]
	return true


static func clear_weather(state: Dictionary) -> bool:
	var changed := false
	for key in ROWS:
		changed = changed or state["weather"][key]
		state["weather"][key] = false
	return changed


## Scorch: destroys every non-hero unit sharing the highest current strength
## on the whole battlefield (both players). Needs both boards, so 2-player only.
## Returns the number of units destroyed.
static func scorch(state: Dictionary) -> int:
	if int(state["mode"]) != 2 or is_match_over(state):
		return 0
	var best := 0
	var targets: Array = []   # [p, row, i]
	for p in 2:
		for key in ROWS:
			var r := _row(state, p, key)
			for i in r["units"].size():
				var s := unit_strength(r, i, state["weather"][key])
				if s > best:
					best = s
					targets = [[p, key, i]]
				elif s == best and s > 0:
					targets.append([p, key, i])
	if best <= 0:
		return 0
	# Remove from the highest index down so earlier indices stay valid.
	targets.reverse()
	for t: Array in targets:
		_row(state, t[0], t[1])["units"].remove_at(t[2])
	state["message"] = "Scorch destroyed %d unit%s with strength %d." % [targets.size(), "" if targets.size() == 1 else "s", best]
	return targets.size()


# --- players and settings ---------------------------------------------------------

static func set_player_name(state: Dictionary, p: Variant, raw: Variant) -> bool:
	if not (p is int and p >= 0 and p < 2):
		return false
	var clean := InputSanitizer.sanitize_name(raw, p)
	if clean == state["players"][p]["name"]:
		return false
	state["players"][p]["name"] = clean
	return true


static func set_faction(state: Dictionary, p: Variant, faction: Variant) -> bool:
	if not (p is int and p >= 0 and p < 2 and Factions.is_valid(faction)):
		return false
	if state["players"][p]["faction"] == faction:
		return false
	state["players"][p]["faction"] = faction
	return true


## Tapping life gem `gem` (1 or 2): if it is lit, it and the gems after it go
## out; if it is dark, it and the gems before it light up.
static func tap_gem(state: Dictionary, p: int, gem: Variant) -> bool:
	if not (valid_player(state, p) and gem is int and gem >= 1 and gem <= MAX_LIVES):
		return false
	var pl: Dictionary = state["players"][p]
	pl["lives"] = gem - 1 if pl["lives"] >= gem else gem
	return true


static func set_mode(state: Dictionary, mode: Variant) -> bool:
	if not (mode is int and (mode == 1 or mode == 2)) or state["mode"] == mode:
		return false
	state["mode"] = mode
	return true


static func set_option(state: Dictionary, option: Variant, value: Variant) -> bool:
	if not (option is String and ["show_lives", "show_rounds"].has(option) and value is bool):
		return false
	if state[option] == value:
		return false
	state[option] = value
	return true


## Pass / un-pass. In 2-player mode the round ends automatically once both
## players have passed.
static func toggle_pass(state: Dictionary, p: int, rng: RandomNumberGenerator) -> bool:
	if not valid_player(state, p) or is_match_over(state):
		return false
	var pl: Dictionary = state["players"][p]
	pl["passed"] = not pl["passed"]
	if int(state["mode"]) == 2 and state["players"][0]["passed"] and state["players"][1]["passed"]:
		end_round(state, rng)
	return true


# --- rounds and matches ------------------------------------------------------------

## Scores the round, applies life loss and faction perks, records history and
## clears the battlefield for the next round. No-op once the match is over.
static func end_round(state: Dictionary, rng: RandomNumberGenerator) -> bool:
	if is_match_over(state):
		return false
	var players: Array = state["players"]
	var round_no: int = state["round"]
	var msgs: Array[String] = []

	if int(state["mode"]) == 2:
		var s0 := player_score(state, 0)
		var s1 := player_score(state, 1)
		var winner := DRAW
		if s0 != s1:
			winner = 0 if s0 > s1 else 1
		else:
			var nil0: bool = players[0]["faction"] == "nilfgaard"
			var nil1: bool = players[1]["faction"] == "nilfgaard"
			if nil0 != nil1:
				winner = 0 if nil0 else 1
				msgs.append("Nilfgaard wins draws:")
		if winner == DRAW:
			msgs.append("Round %d is a draw (%d - %d)." % [round_no, s0, s1])
		else:
			var hi := maxi(s0, s1)
			var lo := mini(s0, s1)
			msgs.append("%s wins round %d (%d - %d)." % [players[winner]["name"], round_no, hi, lo])
			if players[winner]["faction"] == "northern":
				msgs.append("Northern Realms: %s draws a card." % players[winner]["name"])
		if state["show_lives"]:
			for p in 2:
				if winner == DRAW or winner != p:
					players[p]["lives"] = maxi(0, int(players[p]["lives"]) - 1)
		_push_history(state, {"round": round_no, "scores": [s0, s1], "winner": winner})
	else:
		var s := player_score(state, 0)
		msgs.append("Round %d finished with %d strength." % [round_no, s])
		_push_history(state, {"round": round_no, "scores": [s], "winner": DRAW})

	var result := match_winner(state)
	if result != NOT_OVER:
		# Leave the final board visible; New Match starts over.
		if result == DRAW:
			msgs.append("The match is a draw.")
		else:
			msgs.append("%s wins the match!" % players[result]["name"])
		state["message"] = " ".join(msgs)
		return true

	state["round"] = mini(round_no + 1, MAX_ROUND)
	clear_weather(state)
	for p in int(state["mode"]):
		players[p]["passed"] = false
		var kept := _clear_board(state, p, rng)
		if not kept.is_empty():
			msgs.append(kept)
	for p in range(int(state["mode"]), 2):
		players[p]["passed"] = false
		players[p]["rows"] = new_rows()
	if state["round"] == 3:
		for p in int(state["mode"]):
			if players[p]["faction"] == "skellige":
				msgs.append("Skellige: %s returns 2 random cards from the discard pile to the battlefield." % players[p]["name"])
	state["message"] = " ".join(msgs)
	return true


## Clears a player's rows (horns are discarded too). Monsters keep one random
## unit or hero card; returns the perk message, or "" when nothing was kept.
static func _clear_board(state: Dictionary, p: int, rng: RandomNumberGenerator) -> String:
	var pl: Dictionary = state["players"][p]
	var cards: Array = []   # [row, kind, i]
	if pl["faction"] == "monsters":
		for key in ROWS:
			var r: Dictionary = pl["rows"][key]
			for i in r["units"].size():
				cards.append([key, "unit", i])
			for i in r["heroes"].size():
				cards.append([key, "hero", i])
	var old_rows: Dictionary = pl["rows"]
	pl["rows"] = new_rows()
	if cards.is_empty():
		return ""
	var pick: Array = cards[rng.randi_range(0, cards.size() - 1)]
	var key: String = pick[0]
	var strength: int
	if pick[1] == "unit":
		var u: Dictionary = old_rows[key]["units"][pick[2]]
		var kept := new_unit(u["base"])
		kept["bond"] = u["bond"]
		kept["morale"] = u["morale"]
		pl["rows"][key]["units"].append(kept)
		strength = u["base"]
	else:
		strength = old_rows[key]["heroes"][pick[2]]
		pl["rows"][key]["heroes"].append(strength)
	return "Monsters: %s keeps a %s with strength %d in %s." % [
		pl["name"], "unit" if pick[1] == "unit" else "hero", strength, ROW_TITLES[key]]


static func _push_history(state: Dictionary, entry: Dictionary) -> void:
	var h: Array = state["history"]
	h.append(entry)
	while h.size() > MAX_HISTORY:
		h.pop_front()


## Starts over but keeps names, factions and settings.
static func new_match(state: Dictionary) -> bool:
	for p in 2:
		var old: Dictionary = state["players"][p]
		state["players"][p] = new_player(p, old["name"], old["faction"])
	state["round"] = 1
	state["history"] = []
	clear_weather(state)
	var msgs: Array[String] = ["New match started."]
	for p in int(state["mode"]):
		if state["players"][p]["faction"] == "scoiatael":
			msgs.append("Scoia'tael: %s decides who goes first." % state["players"][p]["name"])
	state["message"] = " ".join(msgs)
	return true
