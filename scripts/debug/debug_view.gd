extends Control
## Debug overlay (Section 6.4). Tab cycles through three states: off; a
## status strip in the corner (the map you're in, the hold timer, the grace
## timer, the logged metrics and recent events), small enough to keep playing
## with; and the full view, which also shows both maps from above. In the
## maps, dead ends are colored by straight-line distance to the objective,
## with their branches (the long walk) shaded, alongside landing spots, the
## objective, the start and the player. The seed field regenerates the run.

signal seed_submitted(new_seed: int)

const MazeMap := preload("res://scripts/maze/maze_map.gd")

const NEAR_COLOR := Color(1.0, 0.78, 0.2)
const FAR_COLOR := Color(0.5, 0.38, 1.0)
const LANDING_COLOR := Color(0.3, 0.9, 0.45)
const PLAYER_COLOR := Color(0.3, 0.95, 1.0)
const WALL_COLOR := Color(0.88, 0.88, 0.88)
const TEXT_COLOR := Color(0.92, 0.92, 0.92)
const DIM_TEXT_COLOR := Color(0.65, 0.65, 0.65)
const BACKGROUND := Color(0.04, 0.04, 0.05, 0.9)
const MARGIN := 24.0
const MAPS_TOP := 140.0
const STATS_HEIGHT := 44.0
const FOOTER := 100.0
const FONT_SIZE := 14
const STRIP_EVENTS := 3
## Monster markers by state: patrol, suspicious, chase, search, return, locked.
const MONSTER_COLORS := [Color(0.6, 0.6, 0.6), Color(1.0, 0.85, 0.2), Color(1.0, 0.2, 0.2),
	Color(1.0, 0.55, 0.15), Color(0.6, 0.6, 0.6), Color(0.85, 0.1, 0.6)]
const MONSTER_LETTERS := ["P", "?", "C", "S", "R", "L"]

enum Mode { OFF, STRIP, FULL }

var mode := Mode.OFF
var _main: Node

@onready var _seed_field: LineEdit = $SeedField


func _ready() -> void:
	hide()
	_seed_field.text_submitted.connect(_on_seed_submitted)


## Shows the run that `main` has just generated.
func show_run(main: Node) -> void:
	_main = main
	_seed_field.text = str(main.run_seed)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		mode = (mode + 1) % Mode.size() as Mode
		visible = mode != Mode.OFF
		_seed_field.visible = mode == Mode.FULL
		if mode != Mode.FULL:
			_seed_field.release_focus()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # Keeps the timers and the player marker current.


func _on_seed_submitted(text: String) -> void:
	var entry := text.strip_edges()
	_seed_field.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if entry.is_valid_int():
		seed_submitted.emit(entry.to_int())
	else:
		_seed_field.text = str(_main.run_seed)


func _draw() -> void:
	if _main == null:
		return
	var font := get_theme_default_font()
	if mode == Mode.STRIP:
		_draw_strip(font)
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	draw_string(font, Vector2(MARGIN, 35), "Debug view  ·  Tab closes", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, Vector2(_seed_field.position.x - 40, 35), "Seed", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, Vector2(_seed_field.position.x + _seed_field.size.x + 12, 35),
		"To change it: Esc frees the mouse, click the field, type a seed, press Enter",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)
	# Status in two columns, so the maps keep their room.
	var lines := _status_lines()
	var per_column := ceili(lines.size() / 2.0)
	for i in lines.size():
		var at := Vector2(MARGIN + (i / per_column) * size.x / 2, 64 + (i % per_column) * 20)
		draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x / 2 - MARGIN, FONT_SIZE, TEXT_COLOR)

	var map_px := minf((size.x - MARGIN * 3) / 2, size.y - MAPS_TOP - STATS_HEIGHT - FOOTER)
	var left := (size.x - (map_px * 2 + MARGIN)) / 2
	for m: MazeMap in _main.maps:
		var origin := Vector2(left + m.map_index * (map_px + MARGIN), MAPS_TOP)
		_draw_map(font, m, origin, map_px / m.width)
	_draw_legend(font, size.y - FOOTER + 26)
	var log_path: String = _main.swap_controller.event_log.path
	draw_string(font, Vector2(MARGIN, size.y - FOOTER + 74), "Event log: " + (log_path if log_path != "" else "not written"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)


## The corner strip: status, a bar for the hold timer, and recent events.
func _draw_strip(font: Font) -> void:
	var lines := _status_lines()
	var events: Array[String] = _main.swap_controller.event_log.recent.slice(0, STRIP_EVENTS)
	var line_h := 18.0
	var width := 0.0
	for text in lines + events:
		width = maxf(width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box := Rect2(12, 12, width + 20, 22 + (lines.size() + events.size()) * line_h + 16)
	draw_rect(box, BACKGROUND)
	var y := box.position.y + 22
	for text in lines:
		draw_string(font, Vector2(box.position.x + 10, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		y += line_h
	var swaps: Node = _main.swap_controller
	var bar := Rect2(box.position.x + 10, y - 8, width, 6)
	draw_rect(bar, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(swaps.hold_seconds / swaps.hold_needed, 0, 1), bar.size.y)), NEAR_COLOR)
	y += 16
	for text in events:
		draw_string(font, Vector2(box.position.x + 10, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)
		y += line_h


## Where the player is, the hold and grace timers, and the metrics so far.
func _status_lines() -> Array[String]:
	var swaps: Node = _main.swap_controller
	var event_log = swaps.event_log
	var total: int = event_log.swaps_in_chase + event_log.swaps_no_chase
	return [
		"In map %s  ·  hold %.2f / %.2f s  ·  grace %.1f s" % [
			String.chr(65 + swaps.current_map), swaps.hold_seconds, swaps.hold_needed, swaps.grace_remaining],
		"Swaps %d (%.1f per min, %d quick)  ·  standing still %.0f s" % [
			total, event_log.swaps_per_minute(total), event_log.quick_swaps, event_log.standing_still_seconds],
		"Bar: fill %.0f, ceiling %.0f (of 100)%s" % [_main.survival.bar.fill, _main.survival.bar.ceiling,
			"  ·  sprinting" if _main.get_node("Player").sprinting else ""],
		_collapse_line(),
		_monster_line(),
	]


func _monster_line() -> String:
	var here: Array = _main.monsters.in_map(_main.swap_controller.current_map)
	var states := here.map(func(monster: Node3D) -> String: return monster.State.keys()[monster.state].to_lower())
	return "Monsters here: %s  ·  sensitivity x%.2f" % [", ".join(states), _main.monsters.sensitivity()]


func _collapse_line() -> String:
	var collapse: Node = _main.collapse
	if collapse.collapsing_map < 0:
		return "No collapse  ·  pool: %s" % ", ".join(_main.swap_controller.pool.map(func(i: int) -> String: return String.chr(65 + i)))
	var m = _main.maps[collapse.collapsing_map]
	return "COLLAPSE in map %s  ·  rush %.1f s  ·  %d walls still to move" % [
		String.chr(65 + collapse.collapsing_map), collapse.rush_seconds, m.pending_collapse_changes().size()]


func _draw_map(font: Font, m: MazeMap, origin: Vector2, px: float) -> void:
	var base: Color = _main.params.map_colors[m.map_index]
	var player_here := _player_in_map(m)
	var title := "Map %s" % String.chr(65 + m.map_index)
	if player_here:
		title += "  ·  you are here"
	draw_string(font, origin + Vector2(0, -10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

	# Floors: rooms lighter than corridors.
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			draw_rect(_cell_rect(c, origin, px), base.darkened(0.25 if m.in_room(c) else 0.6))

	# Dead ends by distance to the objective; faded cells are the branch.
	for d in m.dead_ends:
		var color := _gradient(d.distance / m.max_distance)
		for c: Vector2i in d.branch:
			draw_rect(_cell_rect(c, origin, px), Color(color, 0.35))
		draw_rect(_cell_rect(d.cell, origin, px), color)

	# Landing spots, lettered with the map arrivals come from.
	for spot in m.landing_spots:
		var rect := _cell_rect(spot.cell, origin, px)
		draw_rect(rect, LANDING_COLOR)
		draw_string(font, rect.position + Vector2(0, px * 0.72), String.chr(65 + spot.origin_map),
			HORIZONTAL_ALIGNMENT_CENTER, px, FONT_SIZE - 2, Color.BLACK)

	var segments := m.wall_segments()
	for i in range(0, segments.size(), 2):
		draw_line(origin + segments[i] * px, origin + segments[i + 1] * px, WALL_COLOR, 2.0)

	draw_rect(_cell_rect(m.start_cell, origin, px).grow(-px * 0.28), Color.WHITE, false, 2.0)
	_draw_objective(origin + m.objective_pos * px, px * 0.42)
	for monster in _main.monsters.in_map(m.map_index):
		var local: Vector3 = monster.global_position - _main.map_origin(m.map_index)
		var at: Vector2 = origin + Vector2(local.x, local.z) / _main.params.cell_size_m * px
		draw_circle(at, px * 0.38, MONSTER_COLORS[monster.state])
		draw_string(font, at + Vector2(-px * 0.5, px * 0.2), MONSTER_LETTERS[monster.state],
			HORIZONTAL_ALIGNMENT_CENTER, px, FONT_SIZE - 4, Color.BLACK)
	if player_here:
		_draw_player(origin, px, m)

	var near := m.dead_ends.filter(func(d: Dictionary) -> bool: return d.distance < m.median_distance).size()
	var below := origin + Vector2(0, m.height * px)
	draw_string(font, below + Vector2(0, 20), "%d rooms  ·  %d landing spots" % [m.rooms.size(), m.landing_spots.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)
	draw_string(font, below + Vector2(0, 38), "%d dead ends: %d near the objective, %d far"
		% [m.dead_ends.size(), near, m.dead_ends.size() - near], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)


func _draw_legend(font: Font, y: float) -> void:
	var x := MARGIN
	for i in 60:
		draw_rect(Rect2(x + i * 2, y - 11, 2, 12), _gradient(i / 59.0))
	x = _legend_text(font, x + 128, y, "dead end, near to far from the objective (faded: its branch)") + 28
	draw_rect(Rect2(x, y - 11, 12, 12), LANDING_COLOR)
	_legend_text(font, x + 18, y, "landing spot (letter: the map arrivals come from)")

	y += 24
	x = MARGIN
	_draw_objective(Vector2(x + 6, y - 5), 7)
	x = _legend_text(font, x + 18, y, "objective") + 28
	draw_rect(Rect2(x, y - 11, 12, 12), Color.WHITE, false, 2.0)
	x = _legend_text(font, x + 18, y, "start") + 28
	_draw_triangle(Vector2(x + 6, y - 5), Vector2.UP, 8)
	x = _legend_text(font, x + 18, y, "you") + 28
	draw_rect(Rect2(x, y - 11, 12, 12), Color(0.5, 0.5, 0.5))
	x = _legend_text(font, x + 18, y, "room (lighter floor)") + 28
	draw_circle(Vector2(x + 6, y - 5), 6, MONSTER_COLORS[2])
	_legend_text(font, x + 18, y, "monster: P patrol, ? suspicious, C chase, S search, R return, L locked on")


func _legend_text(font: Font, x: float, y: float, text: String) -> float:
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	return x + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _draw_objective(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0),
	])
	draw_colored_polygon(points, Color.WHITE)
	points.append(points[0])
	draw_polyline(points, Color.BLACK, 1.5)


func _draw_player(origin: Vector2, px: float, m: MazeMap) -> void:
	var player: Node3D = _main.get_node("Player")
	var local: Vector3 = player.global_position - _main.map_origin(m.map_index)
	var cells: Vector2 = Vector2(local.x, local.z) / _main.params.cell_size_m
	var forward := -player.global_transform.basis.z
	_draw_triangle(origin + cells * px, Vector2(forward.x, forward.z).normalized(), px * 0.5)


func _draw_triangle(tip_center: Vector2, facing: Vector2, length: float) -> void:
	var side := Vector2(-facing.y, facing.x)
	draw_colored_polygon(PackedVector2Array([
		tip_center + facing * length,
		tip_center - facing * length * 0.6 + side * length * 0.6,
		tip_center - facing * length * 0.6 - side * length * 0.6,
	]), PLAYER_COLOR)


func _player_in_map(m: MazeMap) -> bool:
	var player: Node3D = _main.get_node("Player")
	var local: Vector3 = player.global_position - _main.map_origin(m.map_index)
	var extent: Vector2 = Vector2(m.width, m.height) * _main.params.cell_size_m
	return local.x >= 0 and local.z >= 0 and local.x <= extent.x and local.z <= extent.y


func _cell_rect(c: Vector2i, origin: Vector2, px: float) -> Rect2:
	return Rect2(origin + Vector2(c) * px, Vector2(px, px))


func _gradient(t: float) -> Color:
	return NEAR_COLOR.lerp(FAR_COLOR, clampf(t, 0.0, 1.0))
