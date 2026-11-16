class_name FactionEmblem
extends Control
## Simple geometric faction emblem, drawn in code so it looks the same on web
## and desktop (no font glyphs or image files needed). Original designs:
## neutral = crossed swords, northern = crown, nilfgaard = sun,
## scoiatael = leaf, monsters = claw marks, skellige = round shield.

var faction := Factions.DEFAULT:
	set(value):
		faction = value if Factions.has_palette(value) else Factions.DEFAULT
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Dictionary = Factions.palette(faction)
	var s := minf(size.x, size.y) / 64.0
	var o := (size - Vector2(64, 64) * s) / 2.0
	draw_set_transform(o, 0.0, Vector2(s, s))
	draw_circle(Vector2(32, 32), 31, c["bg"])
	draw_arc(Vector2(32, 32), 30, 0, TAU, 48, c["accent_dark"], 2.0, true)
	var a: Color = c["accent"]
	var ink: Color = c["bg"]
	match faction:
		"northern":
			_crown(a)
		"nilfgaard":
			_sun(a)
		"scoiatael":
			_leaf(a, ink)
		"monsters":
			_claws(a)
		"skellige":
			_shield(a, ink)
		"egg_poo":
			_poo(a, ink)
		"egg_gold":
			_member(a)
		_:
			_swords(a)
	draw_set_transform(Vector2.ZERO)


func _swords(a: Color) -> void:
	for flip in [1.0, -1.0]:
		var hilt := Vector2(32 - 16 * flip, 48)
		var tip := Vector2(32 + 14 * flip, 12)
		draw_line(hilt, tip, a, 4.0, true)
		var d := (tip - hilt).normalized()
		var n := Vector2(-d.y, d.x)
		var guard := hilt + d * 7
		draw_line(guard - n * 6, guard + n * 6, a, 3.0, true)
		draw_circle(hilt - d * 3, 3.0, a)


func _crown(a: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(13, 44), Vector2(15, 22), Vector2(23, 33), Vector2(32, 16),
		Vector2(41, 33), Vector2(49, 22), Vector2(51, 44)]), a)
	draw_rect(Rect2(13, 46, 38, 5), a)
	for p in [Vector2(15, 20), Vector2(32, 14), Vector2(49, 20)]:
		draw_circle(p, 3.0, a)


func _sun(a: Color) -> void:
	draw_circle(Vector2(32, 32), 10, a)
	for k in 12:
		var ang := TAU * k / 12.0
		var dir := Vector2.from_angle(ang)
		var side := Vector2.from_angle(ang + PI / 2) * 3.2
		var inner := Vector2(32, 32) + dir * 13
		draw_colored_polygon(PackedVector2Array([
			inner + side, Vector2(32, 32) + dir * 25, inner - side]), a)


func _leaf(a: Color, ink: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2(32 + 15 * sin(PI * t), 10 + 42 * t))
	for i in range(steps - 1, 0, -1):
		var t := float(i) / steps
		pts.append(Vector2(32 - 15 * sin(PI * t), 10 + 42 * t))
	draw_colored_polygon(pts, a)
	draw_line(Vector2(32, 14), Vector2(32, 56), ink, 2.0, true)
	for y in [24, 33, 42]:
		draw_line(Vector2(32, y + 5), Vector2(41, y), ink, 1.5, true)
		draw_line(Vector2(32, y + 5), Vector2(23, y), ink, 1.5, true)


func _claws(a: Color) -> void:
	for k in 3:
		var x := 20.0 + k * 11
		draw_colored_polygon(PackedVector2Array([
			Vector2(x + 2, 10), Vector2(x + 8, 12), Vector2(x - 2, 54), Vector2(x - 5, 50)]), a)


func _shield(a: Color, ink: Color) -> void:
	draw_circle(Vector2(32, 32), 22, a)
	draw_line(Vector2(32, 11), Vector2(32, 53), ink, 2.5, true)
	draw_line(Vector2(11, 32), Vector2(53, 32), ink, 2.5, true)
	draw_circle(Vector2(32, 32), 8, ink)
	draw_circle(Vector2(32, 32), 5, a)


# --- hidden looks (see Factions.NAME_LOOKS) ----------------------------------------

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(center + Vector2.from_angle(TAU * i / 24.0) * radius)
	draw_colored_polygon(pts, color)


## Swirled pile with a pointy tip and a pair of eyes.
func _poo(a: Color, ink: Color) -> void:
	var dark := a.darkened(0.25)
	_ellipse(Vector2(32, 47), Vector2(20, 8), dark)
	_ellipse(Vector2(32, 44), Vector2(19, 7), a)
	_ellipse(Vector2(32, 35), Vector2(15, 6.5), dark)
	_ellipse(Vector2(32, 32.5), Vector2(14, 6), a)
	_ellipse(Vector2(32, 24.5), Vector2(10, 5.5), dark)
	_ellipse(Vector2(32, 22.5), Vector2(9, 5), a)
	draw_colored_polygon(PackedVector2Array([Vector2(26, 21), Vector2(36, 9), Vector2(38, 21)]), a)
	for x in [26.0, 38.0]:
		draw_circle(Vector2(x, 41), 4.0, Color.WHITE)
		draw_circle(Vector2(x + 1, 42), 2.0, ink)
	draw_arc(Vector2(32, 44), 6.0, 0.3, PI - 0.3, 12, ink, 1.5, true)


## Cartoon member: shaft with a rounded tip and two balls.
func _member(a: Color) -> void:
	var dark := a.darkened(0.2)
	draw_circle(Vector2(25, 47), 8.5, dark)
	draw_circle(Vector2(39, 47), 8.5, dark)
	draw_rect(Rect2(26, 17, 12, 30), a)
	draw_circle(Vector2(32, 17), 7.5, a.lightened(0.15))
	draw_line(Vector2(32, 11), Vector2(32, 14), dark, 1.5, true)
