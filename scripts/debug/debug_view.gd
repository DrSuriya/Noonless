extends Control
## Debug view (Section 6.4): Tab shows both maps from above. Dead ends are
## colored by straight-line distance to the objective, with their branches
## (the long walk) shaded, alongside landing spots, the objective, the start
## and the player. The seed field regenerates the run from a typed seed.

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
const MAPS_TOP := 88.0
const STATS_HEIGHT := 44.0
const FOOTER := 80.0
const FONT_SIZE := 14

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
		visible = not visible
		if not visible:
			_seed_field.release_focus()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # Keeps the player marker current.


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
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	draw_string(font, Vector2(MARGIN, 35), "Debug view  ·  Tab closes", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, Vector2(_seed_field.position.x - 40, 35), "Seed", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, Vector2(_seed_field.position.x + _seed_field.size.x + 12, 35),
		"To change it: Esc frees the mouse, click the field, type a seed, press Enter",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)

	var map_px := minf((size.x - MARGIN * 3) / 2, size.y - MAPS_TOP - STATS_HEIGHT - FOOTER)
	var left := (size.x - (map_px * 2 + MARGIN)) / 2
	for m: MazeMap in _main.maps:
		var origin := Vector2(left + m.map_index * (map_px + MARGIN), MAPS_TOP)
		_draw_map(font, m, origin, map_px / m.width)
	_draw_legend(font, size.y - FOOTER + 26)


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
	if player_here:
		_draw_player(origin, px, m)

	var near := m.dead_ends.filter(func(d: Dictionary) -> bool: return d.distance < m.median_distance).size()
	var below := origin + Vector2(0, m.height * px)
	draw_string(font, below + Vector2(0, 20), "%d rooms  ·  %d landing spots" % [m.rooms.size(), m.landing_spots.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM_TEXT_COLOR)
	draw_string(font, below + Vector2(0, 38), "%d dead ends: %d in the half nearer the objective, %d in the far half"
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
	_legend_text(font, x + 18, y, "room (lighter floor)")


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
