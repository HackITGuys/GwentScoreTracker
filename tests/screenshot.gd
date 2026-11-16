extends SceneTree
## Dev helper: renders the main screen with a sample match and saves a PNG.
## Needs a display (not --headless):
##   godot --path . --script res://tests/screenshot.gd -- 1280 800 out.png [faction0 faction1 [name0 name1]]

var _frame := 0
var _main: Node
var _out := ""


func _initialize() -> void:
	SaveStore.persist = false
	var a := OS.get_cmdline_user_args()
	DisplayServer.window_set_size(Vector2i(int(a[0]), int(a[1])))
	_out = a[2]
	change_scene_to_file("res://scenes/main.tscn")


func _process(_d: float) -> bool:
	_frame += 1
	var a := OS.get_cmdline_user_args()
	if _frame == 3:
		_main = current_scene
		var s: Dictionary = _main.state
		s["players"][0]["faction"] = a[3] if a.size() > 3 else "northern"
		s["players"][1]["faction"] = a[4] if a.size() > 4 else "nilfgaard"
		s["players"][0]["name"] = a[5] if a.size() > 5 else "Geralt"
		s["players"][1]["name"] = a[6] if a.size() > 6 else "Emhyr"
		for v in [4, 4, 6, 2]:
			GwentRules.add_unit(s, 0, "close", v)
		s["players"][0]["rows"]["close"]["units"][0]["bond"] = true
		s["players"][0]["rows"]["close"]["units"][1]["bond"] = true
		s["players"][0]["rows"]["close"]["units"][3]["morale"] = true
		GwentRules.add_hero(s, 0, "ranged", 10)
		GwentRules.add_unit(s, 0, "siege", 8)
		GwentRules.add_unit(s, 1, "close", 10)
		GwentRules.add_unit(s, 1, "ranged", 5)
		GwentRules.add_unit(s, 1, "ranged", 3)
		GwentRules.add_hero(s, 1, "siege", 15)
		s["players"][1]["rows"]["siege"]["horn"] = true
		GwentRules.add_unit(s, 1, "siege", 6)
		s["weather"]["ranged"] = true
		s["players"][1]["lives"] = 1
		s["history"] = [{"round": 1, "scores": [41, 37], "winner": 0}]
		s["round"] = 2
		s["message"] = "Geralt wins round 1 (41 - 37). Northern Realms: Geralt draws a card."
		_main.do_action(&"select_card", {"p": 0, "row": "close", "kind": "unit", "i": 3})
	if _frame == 12:
		get_root().get_texture().get_image().save_png(_out)
		quit()
	return false
