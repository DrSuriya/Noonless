extends Control
## Heads-up display (Stage 4): the bar and the item slots, always on screen.
##
## The bar is drawn against the full maximum. The bright part is the fill
## (stamina). The ceiling (health) is the end of the dark part; anything past
## it, shown in dark red, is lost until healed. The thin tick is the floor
## sprinting stops at. During a collapse the fill turns red.

const BAR_SIZE := Vector2(360, 16)
const SLOT_SIZE := 40.0
const SLOT_GAP := 8.0
const BOTTOM_MARGIN := 28.0
const FONT_SIZE := 14

const FILL_COLOR := Color(0.92, 0.88, 0.75)
const RUSH_FILL_COLOR := Color(0.95, 0.3, 0.25)
const EMPTY_COLOR := Color(0.18, 0.18, 0.2, 0.85)
const LOST_COLOR := Color(0.45, 0.08, 0.08, 0.85)
const FLOOR_COLOR := Color(1, 1, 1, 0.5)
const SLOT_COLOR := Color(0.1, 0.1, 0.12, 0.8)
const TEXT_COLOR := Color(0.85, 0.85, 0.85)

var _main: Node


func show_run(main: Node) -> void:
	_main = main
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _main == null:
		return
	var bar = _main.survival.bar
	var font := get_theme_default_font()
	var origin := Vector2((size.x - BAR_SIZE.x) / 2, size.y - BOTTOM_MARGIN - BAR_SIZE.y)
	var scale: float = BAR_SIZE.x / bar.MAX
	draw_rect(Rect2(origin, BAR_SIZE), EMPTY_COLOR)
	var lost_from: float = bar.ceiling * scale
	draw_rect(Rect2(origin + Vector2(lost_from, 0), Vector2(BAR_SIZE.x - lost_from, BAR_SIZE.y)), LOST_COLOR)
	var fill_color := RUSH_FILL_COLOR if _main.get_node("Player").rushing else FILL_COLOR
	draw_rect(Rect2(origin, Vector2(bar.fill * scale, BAR_SIZE.y)), fill_color)
	var floor_x: float = origin.x + bar.sprint_floor * scale
	draw_line(Vector2(floor_x, origin.y - 3), Vector2(floor_x, origin.y + BAR_SIZE.y + 3), FLOOR_COLOR, 1.0)
	draw_rect(Rect2(origin, BAR_SIZE), Color(1, 1, 1, 0.35), false, 1.0)

	if _main.collapse.can_activate:
		var prompt := "E   Activate"
		var width := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 2).x
		var at := Vector2((size.x - width) / 2, origin.y - 22)
		draw_rect(Rect2(at + Vector2(-12, -20), Vector2(width + 24, 28)), SLOT_COLOR)
		draw_string(font, at, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 2, Color.WHITE)

	var slots: Array[String] = _main.survival.inventory.slots
	var x := origin.x + BAR_SIZE.x + 24
	var y := origin.y + BAR_SIZE.y - SLOT_SIZE
	for i in slots.size():
		var rect := Rect2(x + i * (SLOT_SIZE + SLOT_GAP), y, SLOT_SIZE, SLOT_SIZE)
		draw_rect(rect, SLOT_COLOR)
		draw_rect(rect, Color(1, 1, 1, 0.3), false, 1.0)
		draw_string(font, rect.position + Vector2(4, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		match slots[i]:
			"bandage":
				draw_rect(rect.grow(-11), Color(0.95, 0.95, 0.9))
			"hospital_kit":
				var inner := rect.grow(-9)
				draw_rect(inner, Color(0.8, 0.12, 0.12))
				var c := inner.get_center()
				draw_rect(Rect2(c - Vector2(7, 2), Vector2(14, 4)), Color.WHITE)
				draw_rect(Rect2(c - Vector2(2, 7), Vector2(4, 14)), Color.WHITE)
