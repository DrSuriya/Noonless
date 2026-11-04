extends SceneTree
## Headless tests for the Dead-End Trigger and the swap (roadmap Stage 3).
##
## Run from the project folder:
##     godot --headless --path . -s res://tests/test_swap.gd
## Prints each check and exits with the number of failures (0 = all passed).

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const ErrorCounter := preload("res://tests/error_counter.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")

const RUN_SEED := 4242

var _failures := 0
var _errors := ErrorCounter.new()
var _main: Node
var _player: CharacterBody3D
var _swaps: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	OS.add_logger(_errors)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.write_event_log = false
	root.add_child(_main)
	await process_frame  # Lets the scene's _ready run.
	_main.generate(RUN_SEED)
	_player = _main.get_node("Player")
	_swaps = _main.swap_controller
	await _frames(2)

	var snapshot := _snapshot()
	await _test_gaze_swap_to_b()
	await _test_gaze_swap_back_to_a()
	await _test_no_swap_below_hold_time()
	await _test_no_swap_facing_away()
	await _test_no_swap_looking_at_floor()
	await _test_no_swap_too_far()
	await _test_swap_now_key()
	_check(_snapshot() == snapshot, "both maps are unchanged after the swaps (grid and built geometry)")
	await _test_same_seed_same_landing_spots()
	_test_blended_walls()

	OS.remove_logger(_errors)
	_check(_errors.count == 0, "no errors during the tests (%d; first: %s)" % [_errors.count, _errors.first])
	print("\n%s (%d failed)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	quit(_failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await _frames(ceili(s * Engine.physics_ticks_per_second))


## Puts the player in the current map's first dead end, `back_m` metres from
## its end wall's face, looking at the wall with the given pitch.
func _stand_in_dead_end(back_m: float, yaw_offset_deg := 0.0, pitch_px := 0.0) -> Dictionary:
	var m: MazeMap = _main.maps[_swaps.current_map]
	var d: Dictionary = m.dead_ends[0]
	var wall_side := MazeMap.opposite(d.faces)
	var into := MazeBuilder.dir_vector(wall_side)
	var p = _main.params
	var face: Vector3 = (_main.map_origin(_swaps.current_map) + MazeBuilder.cell_position(d.cell, p)
		+ into * (p.cell_size_m / 2 - p.wall_thickness_m / 2))
	_player.place(face - into * back_m, MazeBuilder.yaw_facing(wall_side) + deg_to_rad(yaw_offset_deg))
	if pitch_px != 0.0:
		_player.look(Vector2(0, pitch_px))
	return d


func _landing_spot_at_player(map_index: int) -> Dictionary:
	var c: Vector2i = _swaps.player_cell()
	for spot in _main.maps[map_index].landing_spots:
		if spot.cell == c:
			return spot
	return {}


func _test_gaze_swap_to_b() -> void:
	_stand_in_dead_end(1.4)
	await _seconds(0.5)
	_check(_swaps.current_map == 1, "looking at a dead-end wall for the hold time swaps from map A to map B")
	var spot := _landing_spot_at_player(1)
	_check(not spot.is_empty() and spot.origin_map == 0, "the player lands in one of map B's landing spots for map A")
	if not spot.is_empty():
		var facing: Vector3 = _player.look_direction()
		var wall := MazeBuilder.dir_vector(MazeMap.opposite(spot.faces))
		_check(facing.angle_to(wall) < 0.01, "the player arrives facing the blended wall")
	_check(_swaps.grace_remaining > 9.0, "the grace timer starts at the swap (%.2f s left)" % _swaps.grace_remaining)
	var events: Array[String] = _swaps.event_log.recent
	_check(events.size() > 0 and events[0].contains("swap A to B (gaze"), "the swap is in the event log: " + (events[0] if events.size() > 0 else "nothing"))
	_check(_swaps.event_log.swaps_no_chase == 1 and _swaps.event_log.quick_swaps == 1,
		"the log counts it as a no-chase swap, and as quick (0.3 s after entering the branch)")


func _test_gaze_swap_back_to_a() -> void:
	_stand_in_dead_end(1.4)
	await _seconds(0.5)
	_check(_swaps.current_map == 0, "a dead end in map B swaps back to map A")
	var spot := _landing_spot_at_player(0)
	_check(not spot.is_empty() and spot.origin_map == 1, "the player lands in one of map A's landing spots for map B")


func _test_no_swap_below_hold_time() -> void:
	_stand_in_dead_end(1.4)
	await _seconds(0.2)
	_player.place(_player.global_position, _player.rotation.y + PI)
	await _seconds(0.2)
	_stand_in_dead_end(1.4)
	await _seconds(0.2)
	_check(_swaps.current_map == 0, "two 0.2 s looks with a look away between don't add up to a swap")
	await _seconds(0.2)
	_check(_swaps.current_map == 1, "holding past 0.3 s then swaps")
	_swaps.swap("test")  # Back to map A.


func _test_no_swap_facing_away() -> void:
	_stand_in_dead_end(1.4, 35.0)
	await _seconds(1.0)
	_check(_swaps.current_map == 0, "no swap when turned 35 degrees from the wall (limit 30)")
	_stand_in_dead_end(1.4, 25.0)
	await _seconds(0.5)
	_check(_swaps.current_map == 1, "a swap when turned 25 degrees from the wall")
	_swaps.swap("test")


func _test_no_swap_looking_at_floor() -> void:
	_stand_in_dead_end(1.4, 0.0, 400.0)  # 400 px * 0.12 deg/px = 48 degrees down.
	await _seconds(1.0)
	_check(_swaps.current_map == 0, "no swap when looking 48 degrees down at the floor")
	_stand_in_dead_end(1.4, 0.0, 200.0)  # 24 degrees down.
	await _seconds(0.5)
	_check(_swaps.current_map == 1, "a swap when looking 24 degrees down")
	_swaps.swap("test")


func _test_no_swap_too_far() -> void:
	_stand_in_dead_end(2.5)
	await _seconds(1.0)
	_check(_swaps.current_map == 0, "no swap 2.5 m from the wall (limit 2 m)")
	_stand_in_dead_end(1.9)
	await _seconds(0.5)
	_check(_swaps.current_map == 1, "a swap 1.9 m from the wall")
	_swaps.swap("test")


func _test_swap_now_key() -> void:
	var before: int = _swaps.current_map
	var press := InputEventAction.new()
	press.action = "swap_now"
	press.pressed = true
	Input.parse_input_event(press)
	# Input is delivered once per process frame; several physics frames can
	# run in one, so wait on process frames.
	await process_frame
	await process_frame
	await physics_frame
	_check(_swaps.current_map != before, "the swap-now key swaps from anywhere")
	_check(_swaps.event_log.recent[0].contains("swap-now key"), "the event log records it as a swap-now key swap")

	# With debug keys off (for playtests), N does nothing.
	_swaps.debug_keys_enabled = false
	before = _swaps.current_map
	Input.parse_input_event(press.duplicate())
	await process_frame
	await process_frame
	await physics_frame
	_check(_swaps.current_map == before, "with debug keys off, the swap-now key does nothing")
	_swaps.debug_keys_enabled = true


## Two runs from the same seed, with the same swaps, land in the same spots.
func _test_same_seed_same_landing_spots() -> void:
	var visits: Array = []
	for attempt in 2:
		_main.generate(RUN_SEED)
		await _frames(1)
		var cells: Array[Vector2i] = []
		for i in 6:
			_swaps.swap("test")
			cells.append(_swaps.player_cell())
		visits.append(cells)
	_check(visits[0] == visits[1], "the same seed and swaps land in the same spots: %s" % [visits[0]])


func _test_blended_walls() -> void:
	var p = _main.params
	for m: MazeMap in _main.maps:
		var walls: Node3D = _main.get_node("Maps").get_child(m.map_index).get_node("BlendedWalls")
		_check(walls.get_child_count() == m.landing_spots.size() * p.blended_wall_panels,
			"map %s has %d blended-wall panels (%d landing spots x %d)" % [String.chr(65 + m.map_index),
			walls.get_child_count(), m.landing_spots.size(), p.blended_wall_panels])
		var first: Color = walls.get_child(0).mesh.material.albedo_color
		var last: Color = walls.get_child(p.blended_wall_panels - 1).mesh.material.albedo_color
		var origin: int = m.landing_spots[0].origin_map
		_check(first.is_equal_approx(p.map_colors[origin]) and last.is_equal_approx(p.map_colors[m.map_index]),
			"map %s's blended walls run from map %s's color to its own" % [String.chr(65 + m.map_index), String.chr(65 + origin)])


## Everything about both maps that a swap could change: the grids, the tags
## and the built nodes.
func _snapshot() -> Array:
	var out := []
	for m: MazeMap in _main.maps:
		out.append([m.walls, m.room_of, m.dead_ends, m.landing_spots, m.objective_cell])
	for node in _main.get_node("Maps").get_children():
		out.append([node.get_instance_id(), node.position, node.get_child_count()])
	return out
