class_name InputSanitizer
extends RefCounted
## All untrusted input passes through here:
##  - the only free-text field (player names), and
##  - saved / undo state, which is rebuilt field by field from scratch.
##
## Nothing from a save file is ever used directly: every value is type-checked,
## clamped or matched against an allowlist, and unknown keys are dropped.

const MAX_NAME_LEN := 20
const MAX_RAW_LEN := 200        # bound the regex work on hostile input
const MAX_MESSAGE_LEN := 400

## Anything that is not a letter, combining mark, digit, space or . ' - _
## (this also removes control, format/bidi and zero-width characters).
const NAME_DISALLOWED := "[^\\p{L}\\p{M}\\p{N} .'\\-_]"
## Control / format / private-use / unassigned characters (Unicode category C).
const CONTROL_CHARS := "\\p{C}"

static var _re_name: RegEx
static var _re_ws: RegEx
static var _re_spaces: RegEx
static var _re_control: RegEx


static func _compile() -> void:
	if _re_name != null:
		return
	_re_name = RegEx.create_from_string(NAME_DISALLOWED)
	_re_ws = RegEx.create_from_string("\\s")
	_re_spaces = RegEx.create_from_string(" {2,}")
	_re_control = RegEx.create_from_string(CONTROL_CHARS)


## Returns a safe display name (1-20 allowed characters), or "Player N".
static func sanitize_name(raw: Variant, index: int) -> String:
	_compile()
	var fallback := "Player %d" % (index + 1)
	if not raw is String:
		return fallback
	var s: String = raw.substr(0, MAX_RAW_LEN)
	s = _re_ws.sub(s, " ", true)
	s = _re_name.sub(s, "", true)
	s = _re_spaces.sub(s, " ", true).strip_edges()
	if s.length() > MAX_NAME_LEN:
		s = s.substr(0, MAX_NAME_LEN).strip_edges()
	return s if not s.is_empty() else fallback


## Strips control characters and caps the length of generated status text.
static func sanitize_message(raw: Variant) -> String:
	_compile()
	if not raw is String:
		return ""
	return _re_control.sub(raw.substr(0, MAX_MESSAGE_LEN), "", true)


# --- typed readers (JSON numbers arrive as floats) --------------------------------

static func read_int(v: Variant, lo: int, hi: int, fallback: int) -> int:
	var n: int
	if v is int:
		n = v
	elif v is float and is_finite(v) and v == floorf(v) and absf(v) < 1e9:
		n = int(v)
	else:
		return fallback
	return n if n >= lo and n <= hi else fallback


static func read_int_in(v: Variant, allowed: Array[int], fallback: int) -> int:
	if not (v is int or v is float):
		return fallback
	var n := read_int(v, -1000000, 1000000, fallback)
	return n if allowed.has(n) else fallback


static func read_bool(v: Variant, fallback: bool) -> bool:
	return v if v is bool else fallback


## Rebuilds a complete, valid match state from untrusted data. Never fails:
## anything invalid falls back to the default for that field.
static func normalize_state(raw: Variant) -> Dictionary:
	var s := GwentRules.new_state()
	if not raw is Dictionary:
		return s
	var d: Dictionary = raw
	s["mode"] = read_int_in(d.get("mode"), [1, 2], 2)
	s["show_lives"] = read_bool(d.get("show_lives"), true)
	s["show_rounds"] = read_bool(d.get("show_rounds"), true)
	s["round"] = read_int(d.get("round"), 1, GwentRules.MAX_ROUND, 1)
	s["message"] = sanitize_message(d.get("message"))

	var weather: Variant = d.get("weather")
	if weather is Dictionary:
		for key in GwentRules.ROWS:
			s["weather"][key] = read_bool(weather.get(key), false)

	var history: Variant = d.get("history")
	if history is Array:
		for entry: Variant in history.slice(-GwentRules.MAX_HISTORY):
			var e := _read_history(entry)
			if not e.is_empty():
				s["history"].append(e)

	var players: Variant = d.get("players")
	if players is Array and players.size() == 2:
		for p in 2:
			s["players"][p] = _read_player(players[p], p)
	return s


static func _read_history(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var scores: Variant = raw.get("scores")
	if not (scores is Array and (scores.size() == 1 or scores.size() == 2)):
		return {}
	var clean_scores: Array = []
	for v: Variant in scores:
		clean_scores.append(read_int(v, 0, GwentRules.MAX_SCORE, 0))
	return {
		"round": read_int(raw.get("round"), 1, GwentRules.MAX_ROUND, 1),
		"scores": clean_scores,
		"winner": read_int_in(raw.get("winner"), [GwentRules.DRAW, 0, 1], GwentRules.DRAW),
	}


static func _read_player(raw: Variant, index: int) -> Dictionary:
	var pl := GwentRules.new_player(index)
	if not raw is Dictionary:
		return pl
	pl["name"] = sanitize_name(raw.get("name"), index)
	var faction: Variant = raw.get("faction")
	pl["faction"] = faction if Factions.is_valid(faction) else Factions.DEFAULT
	pl["lives"] = read_int(raw.get("lives"), 0, GwentRules.MAX_LIVES, GwentRules.MAX_LIVES)
	pl["passed"] = read_bool(raw.get("passed"), false)
	var rows: Variant = raw.get("rows")
	if rows is Dictionary:
		for key in GwentRules.ROWS:
			pl["rows"][key] = _read_row(rows.get(key))
	return pl


static func _read_row(raw: Variant) -> Dictionary:
	var row := GwentRules.new_row()
	if not raw is Dictionary:
		return row
	row["horn"] = read_bool(raw.get("horn"), false)
	var units: Variant = raw.get("units")
	if units is Array:
		for u: Variant in units.slice(0, GwentRules.MAX_UNITS_PER_ROW):
			if not u is Dictionary:
				continue
			var base := read_int_in(u.get("base"), GwentRules.UNIT_VALUES, -1)
			if base < 0:
				continue
			var unit := GwentRules.new_unit(base)
			unit["bond"] = read_bool(u.get("bond"), false)
			unit["morale"] = read_bool(u.get("morale"), false)
			unit["adj"] = read_int(u.get("adj"), -GwentRules.MAX_ADJ, GwentRules.MAX_ADJ, 0)
			row["units"].append(unit)
	var heroes: Variant = raw.get("heroes")
	if heroes is Array:
		for h: Variant in heroes.slice(0, GwentRules.MAX_HEROES_PER_ROW):
			var v := read_int_in(h, GwentRules.HERO_VALUES, -1)
			if v >= 0:
				row["heroes"].append(v)
	return row
