extends SceneTree
## Headless tests for the objective, the collapse and the end of a run
## (roadmap Stage 5).
##
## Run from the project folder:
##     godot --headless --path . -s res://tests/test_collapse.gd
## Prints each check and exits with the number of failures (0 = all passed).

const ErrorCounter := preload("res://tests/error_counter.gd")
const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")

const RUN_SEED := 2024

var _failures := 0
var _errors := ErrorCounter.new()
var _main: Node
var _player: CharacterBody3D
var _swaps: Node
var _collapse: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	OS.add_logger(_errors)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.write_event_log = false
	root.add_child(_main)
	await process_frame
	_main.generate(RUN_SEED)
	_player = _main.get_node("Player")
	_swaps = _main.swap_controller
	_collapse = _main.collapse
	await _frames(2)

	_test_tells_at_start()
	await _test_activation()
	await _test_rearrangement_hides_from_view()
	await _test_rearrangement_finishes()
	await _test_one_second_stare_and_escape()
	await _test_results_restart()
	await _test_death()
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


func _objective_world(map_index: int) -> Vector3:
	return _main.map_origin(map_index) + MazeBuilder.objective_position(_main.maps[map_index], _main.params)


## Sends an action press and waits until it has been handled. Input is
## delivered once per process frame, and several physics frames can run in
## one, so waiting on physics frames alone isn't enough.
func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	await physics_frame


## The environmental tells: every dead-end branch has darker floor tiles,
## darkest at the end wall, and nothing else does.
func _test_tells_at_start() -> void:
	for m: MazeMap in _main.maps:
		var shown := MazeBuilder.shown_tells(_main.map_node(m.map_index))
		var wanted := MazeBuilder.tell_shades(m, _main.params)
		var darker_at_tip := true
		for d in m.dead_ends:
			darker_at_tip = darker_at_tip and shown.get(d.cell, 0.0) > shown.get(d.branch.back(), 0.0)
		var on_landing := m.landing_spots.any(func(spot: Dictionary) -> bool: return shown.has(spot.cell))
		_check(shown == wanted and darker_at_tip and not on_landing,
			"map %s: every dead-end branch has floor tells, darkest at the end wall, and nothing else does (%d tiles)" % [String.chr(65 + m.map_index), shown.size()])


func _test_activation() -> void:
	var objective := _objective_world(0)
	_player.place(objective + Vector3(0, 0, 5), 0.0)
	await _frames(2)
	_check(not _collapse.can_activate, "the objective can't be activated from 5 m away")
	_player.place(objective + Vector3(0, 0, 1.5), 0.0)
	await _frames(2)
	_check(_collapse.can_activate, "the objective can be activated from 1.5 m")
	# Stop the collapse stepping on its own, so the next test can check every
	# step, including the first big one, against 3D raycasts.
	_collapse.set_physics_process(false)
	await _press("interact")
	_check(_collapse.collapsing_map == 0 and _main.maps[0].collapsed, "pressing E starts map A's collapse")
	_check(_player.rushing and is_equal_approx(_player.speed_multiplier, 1.25), "the player rushes: unlimited stamina and +25% speed")
	_check(is_equal_approx(_swaps.hold_needed, 1.0), "escaping now takes the one-second stare")
	var beam: Node3D = _main.map_node(0).get_node("Objective/Beam")
	_check(not beam.visible, "the objective's beam goes out")
	_check(_swaps.event_log.objectives.has("A"), "the event log records when the objective was reached: %s" % _swaps.event_log.objectives.get("A"))


## Every wall the rearrangement changes was out of view: checked with real 3D
## physics raycasts from the eyes, independent of the grid ray cast it uses.
func _test_rearrangement_hides_from_view() -> void:
	var m: MazeMap = _main.maps[0]
	var space := root.world_3d.direct_space_state
	var cs: float = _main.params.cell_size_m
	var origin: Vector3 = _main.map_origin(0)
	var violations := 0
	var tell_violations := 0
	var applied := 0
	var positions: Array[Vector2i] = [m.objective_cell, m.start_cell, Vector2i(2, 2), Vector2i(17, 17), Vector2i(2, 17), Vector2i(17, 2)]
	for c in positions:
		for yaw_step in 4:
			_player.place(origin + MazeBuilder.cell_position(c, _main.params), yaw_step * PI / 2)
			await _frames(1)
			var before := m.walls.duplicate()
			var tells_before := MazeBuilder.shown_tells(_main.map_node(0))
			var seen := {}
			var seen_floor := {}
			var eye: Vector3 = _player.eye_position()
			var look: Vector3 = _player.look_direction()
			for change in m.pending_collapse_changes():
				var wall := MazeMap.side_segment(change.cell, change.dir)
				for f in [0.05, 0.5, 0.95]:
					var p2: Vector2 = wall[0].lerp(wall[1], f) * cs
					var target := origin + Vector3(p2.x, eye.y, p2.y)
					var to_target := target - eye
					if look.angle_to(to_target) > deg_to_rad(60.0):
						continue
					# Stop short of the wall's own thickness.
					var end: Vector3 = eye + to_target * (1.0 - (_main.params.wall_thickness_m / 2 + 0.05) / to_target.length())
					var query := PhysicsRayQueryParameters3D.create(eye, end)
					query.exclude = [_player.get_rid()]
					if space.intersect_ray(query).is_empty():
						seen[[change.cell, change.dir]] = true
			for y in m.height:
				for x in m.width:
					var floor_point := origin + Vector3(x + 0.5, 0, y + 0.5) * cs + Vector3(0, 0.05, 0)
					var to_floor := floor_point - eye
					if look.angle_to(to_floor) > deg_to_rad(60.0):
						continue
					var query := PhysicsRayQueryParameters3D.create(eye, floor_point)
					query.exclude = [_player.get_rid()]
					if space.intersect_ray(query).is_empty():
						seen_floor[Vector2i(x, y)] = true
			applied += _collapse.rearrange_step()
			await _frames(1)
			for change in _changed_walls(m, before):
				if seen.has([change.cell, change.dir]):
					violations += 1
			var tells_after := MazeBuilder.shown_tells(_main.map_node(0))
			for floor_cell in seen_floor:
				if not is_equal_approx(tells_before.get(floor_cell, 0.0), tells_after.get(floor_cell, 0.0)):
					tell_violations += 1
	_check(applied > 0, "the rearrangement moved %d walls from those spots" % applied)
	_check(violations == 0, "no wall changed while a 3D raycast from the eyes could see it (%d did)" % violations)
	_check(tell_violations == 0, "no floor tell changed while a 3D raycast could see that floor (%d did)" % tell_violations)
	_check(m.walk_distances(m.start_cell).count(-1) == 0, "the map stays fully connected while it rearranges")
	_collapse.set_physics_process(true)


func _changed_walls(m: MazeMap, before: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			for dir: int in [MazeMap.N, MazeMap.W]:
				if (before[m.index(c)] & dir) != (m.walls[m.index(c)] & dir):
					out.append({cell = c, dir = dir})
	return out


## Walking around (here, standing in each corner looking at the wall) lets
## the whole collapse layout arrive, and the built walls match it.
func _test_rearrangement_finishes() -> void:
	var m: MazeMap = _main.maps[0]
	var origin: Vector3 = _main.map_origin(0)
	for attempt in 6:
		for c: Vector2i in [Vector2i(0, 0), Vector2i(19, 0), Vector2i(0, 19), Vector2i(19, 19), m.objective_cell]:
			for yaw_step in 4:
				_player.place(origin + MazeBuilder.cell_position(c, _main.params), yaw_step * PI / 2)
				await _frames(1)
				_collapse.rearrange_step()
		if m.pending_collapse_changes().is_empty() and MazeBuilder.shown_tells(_main.map_node(0)) == MazeBuilder.tell_shades(m, _main.params):
			break
	_check(m.pending_collapse_changes().is_empty() and m.walls == m.collapse_walls, "the map reaches its collapse layout")
	_check(MazeBuilder.shown_tells(_main.map_node(0)) == MazeBuilder.tell_shades(m, _main.params), "the floor tells follow the collapse layout's dead ends")
	var near := 0
	for d in m.dead_ends:
		if d.distance < m.median_distance:
			near += 1
	print("      collapse layout: %d dead ends, %d in the half nearer the objective" % [m.dead_ends.size(), near])
	_check(m.dead_ends.size() > 0, "the collapse layout has dead ends to escape through")

	var space := root.world_3d.direct_space_state
	var cs: float = _main.params.cell_size_m
	var mismatches := 0
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			for dir in [MazeMap.E, MazeMap.S]:
				var n: Vector2i = c + MazeMap.offset(dir)
				if not m.in_bounds(n):
					continue
				var a := origin + Vector3(c.x + 0.5, 0, c.y + 0.5) * cs + Vector3(0, 2.0, 0)
				var b := origin + Vector3(n.x + 0.5, 0, n.y + 0.5) * cs + Vector3(0, 2.0, 0)
				var query := PhysicsRayQueryParameters3D.create(a, b)
				query.exclude = [_player.get_rid()]
				if (not space.intersect_ray(query).is_empty()) != m.has_wall(c, dir):
					mismatches += 1
	_check(mismatches == 0, "the rebuilt 3D walls match the rearranged grid (%d mismatches)" % mismatches)


func _test_one_second_stare_and_escape() -> void:
	var m: MazeMap = _main.maps[0]
	var bar = _main.survival.bar
	bar.lower_ceiling(30.0)
	var d: Dictionary = m.dead_ends[0]
	var wall_side := MazeMap.opposite(d.faces)
	var into := MazeBuilder.dir_vector(wall_side)
	var p = _main.params
	var face: Vector3 = (_main.map_origin(0) + MazeBuilder.cell_position(d.cell, p)
		+ into * (p.cell_size_m / 2 - p.wall_thickness_m / 2))
	_player.place(face - into * 1.4, MazeBuilder.yaw_facing(wall_side))
	await _seconds(0.6)
	_check(_swaps.current_map == 0, "0.6 s of looking at a dead end doesn't escape a collapse")
	await _seconds(0.6)
	_check(_swaps.current_map == 1, "a full second does")
	var rush: float = _swaps.event_log.rush_seconds
	_check(_main.run_over and paused, "escaping the first collapse ends the run (placeholder for D1 and D2)")
	_check(is_equal_approx(bar.ceiling, 100.0 - minf(rush, 50.0)),
		"wounds heal, then the toll comes off: ceiling %.1f after %.1f s of rushing" % [bar.ceiling, rush])
	_check(not (0 in _swaps.pool), "map A leaves the pool")
	_check(not _player.rushing and is_equal_approx(_player.speed_multiplier, 1.0), "the rush ends")
	var summary: Dictionary = _swaps.event_log.summary()
	_check(summary.outcome == "escaped" and summary.toll_paid_percent_of_max > 0.0, "the log's summary records the escape and the toll")
	var results: Control = _main.get_node("ResultsLayer/Results")
	_check(results.visible, "the results screen shows")


func _test_results_restart() -> void:
	var results: Control = _main.get_node("ResultsLayer/Results")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.keycode = KEY_R
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	await process_frame
	await physics_frame
	_check(not _main.run_over and not paused and not results.visible and _main.run_seed == RUN_SEED,
		"R on the results screen replays the same seed")
	_check(not _main.maps[0].collapsed and _main.maps[0].walls != _main.maps[0].collapse_walls,
		"the new run starts with fresh maps")


func _test_death() -> void:
	for i in 4:
		_main.survival.damage(false, "test_cause")
	await _frames(1)
	var summary: Dictionary = _swaps.event_log.summary()
	_check(_main.run_over and summary.outcome == "died" and summary.death_cause == "test_cause",
		"an empty fill ends the run as a death, with its cause")
	_check(_main.get_node("ResultsLayer/Results").visible, "the results screen shows after a death")
	await _press("ui_accept")
	_check(not _main.run_over and _main.run_seed != RUN_SEED, "Enter on the results screen starts a run with a new seed")
