class_name FactionTheme
extends RefCounted
## Builds a Godot Theme from a faction palette (scripts/logic/factions.gd).
## The main screen uses the "neutral" theme; each player column gets the theme
## of its chosen faction, which overrides it for that subtree only.
##
## Type variations used by the UI:
##   RowPanel / RowPanelActive / RowPanelWeather / RowPanelWeatherActive (PanelContainer)
##   UnitToken / BondToken / HeroToken / SelectedToken, HeroKey, GemOn / GemOff (Button)
##   TitleLabel / ScoreLabel / RowScoreLabel / MutedLabel (Label)

const FONT_SIZE := 18
const WEATHER_TINT := Color("16364f")
const WEATHER_BORDER := Color("7cc4ff")
const GEM_ON := Color("e53935")
const GEM_OFF := Color("2a2420")

static var _cache := {}


## `faction` may be a faction id or a hidden look id (see Factions.HIDDEN).
static func get_theme(faction: String) -> Theme:
	var id := faction if Factions.has_palette(faction) else Factions.DEFAULT
	if not _cache.has(id):
		_cache[id] = _build(Factions.palette(id))
	return _cache[id]


static func box(bg: Color, border: Color, border_w: int, radius: int, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb


static func _bold_font(strength: float) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = strength
	return fv


static func _build(c: Dictionary) -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var text: Color = c["text"]
	var muted: Color = c["muted"]
	var accent: Color = c["accent"]
	var accent_dark: Color = c["accent_dark"]
	var panel: Color = c["panel"]
	var row: Color = c["row"]
	var bg: Color = c["bg"]
	var bold := _bold_font(0.6)

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(panel, accent, 2, 12, 10))
	t.set_stylebox("panel", "Panel", box(panel, accent, 2, 12, 10))
	_variation(t, "RowPanel", "PanelContainer", box(row, accent_dark, 1, 8, 8))
	_variation(t, "RowPanelActive", "PanelContainer", box(row.lightened(0.05), accent, 3, 8, 8))
	_variation(t, "RowPanelWeather", "PanelContainer", box(WEATHER_TINT, WEATHER_BORDER, 1, 8, 8))
	_variation(t, "RowPanelWeatherActive", "PanelContainer", box(WEATHER_TINT.lightened(0.05), accent, 3, 8, 8))

	# Labels
	t.set_color("font_color", "Label", text)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", bold)
	t.set_font_size("font_size", "TitleLabel", 22)
	t.set_color("font_color", "TitleLabel", accent)
	t.set_type_variation("ScoreLabel", "Label")
	t.set_font("font", "ScoreLabel", bold)
	t.set_font_size("font_size", "ScoreLabel", 40)
	t.set_color("font_color", "ScoreLabel", accent)
	t.set_type_variation("RowScoreLabel", "Label")
	t.set_font("font", "RowScoreLabel", bold)
	t.set_font_size("font_size", "RowScoreLabel", 26)
	t.set_color("font_color", "RowScoreLabel", accent)
	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", 15)
	t.set_color("font_color", "MutedLabel", muted)

	# Buttons (also used for toggles: "pressed" = on)
	_button_styles(t, "Button", panel.lightened(0.07), accent_dark, accent, text, bg)
	_button_styles(t, "OptionButton", panel.lightened(0.07), accent_dark, accent, text, bg)
	t.set_type_variation("UnitToken", "Button")
	_button_styles(t, "UnitToken", panel.lightened(0.12), accent_dark, accent, text, bg, 10)
	t.set_type_variation("BondToken", "Button")
	_button_styles(t, "BondToken", Color("1d4424"), Color("66bb6a"), accent, Color("e8f5e9"), bg, 10)
	t.set_type_variation("HeroToken", "Button")
	_button_styles(t, "HeroToken", Color("4a2c09"), Color("ffb300"), accent, Color("ffe082"), bg, 10)
	t.set_type_variation("SelectedToken", "Button")
	_button_styles(t, "SelectedToken", accent, text, accent, bg, bg, 10)
	t.set_type_variation("HeroKey", "Button")
	_button_styles(t, "HeroKey", Color("3d2408"), Color("ff9800"), accent, Color("ffe082"), bg)
	for token in ["UnitToken", "BondToken", "HeroToken", "SelectedToken"]:
		t.set_font("font", token, bold)
		t.set_font_size("font_size", token, 20)

	# Life gems: round buttons
	t.set_type_variation("GemOn", "Button")
	t.set_type_variation("GemOff", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var on := box(GEM_ON if state != "hover" else GEM_ON.lightened(0.15), accent, 2, 16, 0)
		var off := box(GEM_OFF if state != "hover" else GEM_OFF.lightened(0.15), accent_dark, 2, 16, 0)
		if state == "focus":
			on.draw_center = false
			off.draw_center = false
		t.set_stylebox(state, "GemOn", on)
		t.set_stylebox(state, "GemOff", off)

	# Text entry
	t.set_stylebox("normal", "LineEdit", box(bg.darkened(0.2), accent_dark, 1, 6, 6))
	t.set_stylebox("focus", "LineEdit", _focus_box(accent))
	t.set_color("font_color", "LineEdit", accent.lightened(0.3))
	t.set_color("caret_color", "LineEdit", accent)
	t.set_color("font_placeholder_color", "LineEdit", muted)
	t.set_font("font", "LineEdit", bold)
	t.set_font_size("font_size", "LineEdit", 20)

	# Check buttons (settings)
	t.set_color("font_color", "CheckButton", text)
	t.set_color("font_hover_color", "CheckButton", accent)
	t.set_color("font_pressed_color", "CheckButton", text)
	t.set_color("font_hover_pressed_color", "CheckButton", accent)

	# Drop-down list of the faction OptionButton
	t.set_stylebox("panel", "PopupMenu", box(panel, accent, 2, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(accent_dark, accent_dark, 0, 4, 4))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)

	# Scrollbars
	t.set_stylebox("scroll", "VScrollBar", box(bg, bg, 0, 4, 2))
	t.set_stylebox("grabber", "VScrollBar", box(accent_dark, accent_dark, 0, 4, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(accent, accent, 0, 4, 2))
	return t


static func _variation(t: Theme, name: StringName, base: StringName, sb: StyleBox) -> void:
	t.set_type_variation(name, base)
	t.set_stylebox("panel", name, sb)


static func _focus_box(accent: Color) -> StyleBoxFlat:
	var sb := box(Color.TRANSPARENT, accent, 2, 6, 6)
	sb.draw_center = false
	return sb


static func _button_styles(t: Theme, type: StringName, fill: Color, border: Color,
		accent: Color, text: Color, ink: Color, pad: int = 8) -> void:
	var normal := box(fill, border, 1, 6, pad)
	var hover := box(fill.lightened(0.12), accent, 1, 6, pad)
	var pressed := box(accent, accent.lightened(0.3), 1, 6, pad)
	var disabled := box(fill.darkened(0.35), border.darkened(0.4), 1, 6, pad)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _focus_box(accent))
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, text.lightened(0.2))
	t.set_color("font_focus_color", type, text)
	t.set_color("font_pressed_color", type, ink)
	t.set_color("font_hover_pressed_color", type, ink)
	t.set_color("font_disabled_color", type, Color(text, 0.35))
