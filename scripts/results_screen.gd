extends Control
## Results screen: the end of a run. As a placeholder for D1 and D2, a run
## ends when the player escapes the first collapse (or dies, Section 2.6).
## Shows the Section 6.6 metrics from the event log. Enter starts a new run
## with a new seed; R replays the same seed.

const TEXT_COLOR := Color(0.92, 0.92, 0.92)
const DIM_TEXT_COLOR := Color(0.62, 0.62, 0.62)
const HEADING_SIZE := 26
const FONT_SIZE := 16
const LINE := 26.0

var _main: Node
var _title := ""
var _lines: Array[String] = []


func _ready() -> void:
	hide()


func show_results(main: Node, outcome: String, summary: Dictionary, log_path: String) -> void:
	_main = main
	_title = "You escaped the collapse" if outcome == "escaped" else "You died"
	var s := summary
	var minutes: float = maxf(s.run_seconds / 60.0, 0.0001)
	_lines = [
		"Run time  %s   ·   seed %d" % [_clock(s.run_seconds), main.run_seed],
		"",
		"Swaps without a chase  %d  (%.1f per minute)" % [s.swaps_no_chase, s.swaps_no_chase / minutes],
		"Swaps during a chase  %d  (%.1f per minute)" % [s.swaps_in_chase, s.swaps_in_chase / minutes],
		"Quick swaps (no chase, soon after entering the dead end)  %d" % s.quick_swaps,
	]
	for map_index in main.maps.size():
		var letter := String.chr(65 + map_index)
		var ejections: int = s.ejections_near_objective.get(letter, 0)
		if s.objectives.has(letter):
			var reached: Dictionary = s.objectives[letter]
			_lines.append("Map %s objective reached at %s (%s spent in map %s)  ·  ejected near it %d times" % [
				letter, _clock(reached.run_seconds), _clock(reached.seconds_in_map), letter, ejections])
		else:
			_lines.append("Map %s objective not reached  ·  ejected near it %d times" % [letter, ejections])
	if s.rush_seconds > 0.0:
		_lines.append("Rush  %s  ·  toll paid  %.0f%% of the bar" % [_clock(s.rush_seconds), s.toll_paid_percent_of_max])
	if s.death_cause != null:
		_lines.append("Death  %s" % str(s.death_cause).replace("_", " "))
	_lines.append("Time standing still  %s" % _clock(s.standing_still_seconds))
	_lines.append("")
	_lines.append("Event log: " + (log_path if log_path != "" else "not written"))
	show()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_main.generate(randi())
	elif event.is_action_pressed("restart_same_seed"):
		get_viewport().set_input_as_handled()
		_main.generate(_main.run_seed)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.04, 0.96))
	var x := maxf((size.x - 760) / 2, 24)
	var y := maxf((size.y - (_lines.size() * LINE + 120)) / 2, 40) + HEADING_SIZE
	draw_string(font, Vector2(x, y), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADING_SIZE, TEXT_COLOR)
	y += 44
	for line in _lines:
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 24, FONT_SIZE,
			DIM_TEXT_COLOR if line.begins_with("Event log") else TEXT_COLOR)
		y += LINE
	y += 12
	draw_string(font, Vector2(x, y), "Enter: new run (new seed)     R: same seed again", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)


static func _clock(seconds: float) -> String:
	var whole := int(round(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
