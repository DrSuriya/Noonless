extends SceneTree
## Headless tests for the monster (roadmap Stage 6).
##
## Run from the project folder:
##     godot --headless --path . -s res://tests/test_monster.gd
## Prints each check and exits with the number of failures (0 = all passed).

const ErrorCounter := preload("res://tests/error_counter.gd")
const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")
const Monster := preload("res://scripts/monster.gd")

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
	await process_frame
	_player = _main.get_node("Player")
	_swaps = _main.swap_controller

	await _test_spawns_and_patrol()
	await _test_sight()
	await _test_hits_and_idle_reversion()
	await _test_lock_on()
	await _test_chase_ends_in_dead_end_escape()
	await _test_death_by_monster()
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


func _new_run(run_seed: int) -> void:
	_main.generate(run_seed)
	await _frames(2)


func _world(map_index: int, c: Vector2i) -> Vector3:
	return _main.map_origin(map_index) + MazeBuilder.cell_position(c, _main.params)


## Puts a monster in the middle of `c`, facing `dir`, standing still and
## looking (it won't wander off for a long while).
func _pose(monster: Node3D, c: Vector2i, dir: int, state := Monster.State.PATROL) -> void:
	monster.global_position = _world(monster.map_index, c)
	monster.cell = c
	monster._next = c
	monster._path.clear()
	monster.rotation.y = MazeBuilder.yaw_facing(dir)
	monster._set_state(state)
	monster._idle_seconds = 1000.0
	monster._hit_pause = 0.0
	monster._cooldown = 0.0
	monster._seen_seconds = 0.0


## The first straight, wall-free run of `length` cells in a map, outside
## rooms (so walls line it), as {cell, dir}.
func _straight_run(m: MazeMap, length: int) -> Dictionary:
	for y in m.height:
		for x in m.width:
			for dir: int in MazeMap.DIRS:
				var c := Vector2i(x, y)
				var ok := true
				for i in length - 1:
					var a := c + MazeMap.offset(dir) * i
					if not m.in_bounds(a) or not m.in_bounds(a + MazeMap.offset(dir)) or m.has_wall(a, dir):
						ok = false
						break
				if ok:
					return {cell = c, dir = dir}
	return {}


func _only_active(keep: Node3D) -> void:
	for monster in _main.monsters.monsters:
		monster.active = monster == keep


func _test_spawns_and_patrol() -> void:
	await _new_run(31)
	var in_a: Array = _main.monsters.in_map(0)
	var in_b: Array = _main.monsters.in_map(1)
	_check(in_a.size() == 2 and in_b.size() == 2, "each map has its 2 monsters")
	_check(in_a.all(func(x: Node3D) -> bool: return x.active) and in_b.all(func(x: Node3D) -> bool: return not x.active),
		"only the monsters in the player's map are active")

	# With a long grace period the monsters ignore the player and just patrol.
	_swaps.grace_remaining = 1000.0
	var illegal := 0
	var moved := 0
	var footsteps := false
	var last := {}
	for monster in in_a:
		last[monster] = monster.cell
	for i in 30 * Engine.physics_ticks_per_second:
		await physics_frame
		for monster in in_a:
			if monster.cell != last[monster]:
				moved += 1
				if not monster._open_between(last[monster], monster.cell):
					illegal += 1
				last[monster] = monster.cell
			footsteps = footsteps or monster.get_node("Footsteps").playing
	_check(moved > 10, "patrolling monsters wander the map (%d cell steps in 30 s)" % moved)
	_check(illegal == 0, "they only ever step between cells with no wall between (%d bad steps)" % illegal)
	_check(in_a.all(func(x: Node3D) -> bool: return x.state == Monster.State.PATROL), "they stay on patrol while the player is in grace")
	_check(footsteps, "their placeholder footsteps play as they walk")
	_swaps.grace_remaining = 0.0


func _test_sight() -> void:
	var run_seed := 40
	var run := {}
	while run.is_empty() and run_seed < 80:
		await _new_run(run_seed)
		run = _straight_run(_main.maps[0], 6)
		run_seed += 1
	_check(not run.is_empty(), "found a straight 6-cell corridor to test sight in (seed %d)" % (run_seed - 1))
	var monster: Node3D = _main.monsters.in_map(0)[0]
	_only_active(monster)
	var step := MazeMap.offset(run.dir)
	var far: Vector2i = run.cell + step * 4  # 12 m away.

	_pose(monster, run.cell, run.dir)
	_player.place(_world(0, far), 0.0)
	await _seconds(0.3)
	_check(monster.state == Monster.State.SUSPICIOUS, "seeing the player 12 m ahead makes it suspicious")
	await _seconds(1.0)
	_check(monster.state == Monster.State.CHASE, "seeing them for 0.75 s starts a chase")

	_pose(monster, run.cell, run.dir)
	_swaps.grace_remaining = 5.0
	await _seconds(0.5)
	_check(monster.state == Monster.State.PATROL, "during the grace period it ignores the player")
	_swaps.grace_remaining = 0.0

	Input.action_press("crouch")
	await _frames(5)  # Let the player crouch before the monster looks.
	_pose(monster, run.cell, run.dir)
	await _seconds(0.5)
	_check(monster.state == Monster.State.PATROL, "a crouching player 12 m away goes unseen (range x0.6)")
	Input.action_release("crouch")
	await _seconds(0.3)
	_check(monster.state == Monster.State.SUSPICIOUS, "standing up again gets them seen")

	_pose(monster, far, MazeMap.opposite(run.dir))
	_player.place(_world(0, run.cell), 0.0)
	monster.rotation.y = MazeBuilder.yaw_facing(run.dir)  # Facing away.
	await _seconds(0.5)
	_check(monster.state == Monster.State.PATROL, "a player behind it, outside its sight cone, goes unseen")

	var m: MazeMap = _main.maps[0]
	var walled := {}
	for y in m.height:
		for x in m.width:
			for dir: int in MazeMap.DIRS:
				var c := Vector2i(x, y)
				if walled.is_empty() and m.has_wall(c, dir) and m.in_bounds(c + MazeMap.offset(dir)):
					walled = {cell = c, dir = dir}
	_pose(monster, walled.cell, walled.dir)
	_player.place(_world(0, walled.cell + MazeMap.offset(walled.dir)), 0.0)
	await _seconds(0.5)
	_check(monster.state == Monster.State.PATROL, "a wall between them blocks its sight, even 3 m away")


func _test_hits_and_idle_reversion() -> void:
	await _new_run(52)
	var monster: Node3D = _main.monsters.in_map(0)[0]
	_only_active(monster)
	var bar = _main.survival.bar
	var c: Vector2i = monster.cell
	_pose(monster, c, MazeMap.N, Monster.State.CHASE)
	_player.place(_world(0, c) + Vector3(0, 0, -0.8), 0.0)
	await _frames(3)
	_check(absf(bar.fill - 75.0) < 1.0, "a chasing monster within reach hits: fill %.1f" % bar.fill)
	await _seconds(1.0)
	_check(bar.fill > 74.0, "it can't hit again before the cooldown")
	await _seconds(0.8)
	_check(bar.fill < 60.0 and bar.ceiling == 100.0, "it hits again after the cooldown; normal hits leave the ceiling")
	var log_recent: Array[String] = _swaps.event_log.recent
	_check(log_recent.any(func(e: String) -> bool: return e.contains("hit")), "hits are in the event log")

	_swaps.swap("swap_now_key")
	_check(monster.state == Monster.State.PATROL and not monster.active,
		"when the player leaves the map, its monsters go back to idle and pause")
	_check(_swaps.event_log.swaps_in_chase == 1, "a swap during a chase is counted as one")
	_swaps.swap("swap_now_key")
	_check(monster.active and monster.state == Monster.State.PATROL, "coming back finds them patrolling, not waiting")


func _test_lock_on() -> void:
	await _new_run(64)
	var objective: Vector3 = _main.map_origin(0) + MazeBuilder.objective_position(_main.maps[0], _main.params)
	_player.place(objective + Vector3(0, 0, 1.5), 0.0)
	_main.collapse.set_physics_process(false)  # Keep the walls still.
	_main.collapse.activate()
	var in_a: Array = _main.monsters.in_map(0)
	_check(in_a.all(func(x: Node3D) -> bool: return x.state == Monster.State.LOCKED), "the collapse locks every monster in the map on")
	# Walking distance in cells, since they follow the maze, not straight lines.
	var m: MazeMap = _main.maps[0]
	var walk := func(x: Node3D) -> int:
		return m.walk_distances(x._world_cell(_player.global_position))[m.index(x.cell)]
	var before := in_a.map(walk)
	await _seconds(3.0)
	var after := in_a.map(walk)
	var closed_in := 0
	for i in in_a.size():
		if after[i] <= 1 or after[i] <= before[i] - 3:
			closed_in += 1
	_check(closed_in == in_a.size(), "locked-on monsters close in without needing to see the player: %s cells to %s cells" % [before, after])

	var monster: Node3D = in_a[0]
	_only_active(monster)
	var bar = _main.survival.bar
	bar.fill = 100.0
	bar.ceiling = 100.0
	var fill_before: float = bar.fill
	monster.global_position = _player.global_position + Vector3(0, 0, 1.0)
	monster.cell = monster._world_cell(monster.global_position)
	monster._next = monster.cell
	monster._cooldown = 0.0
	monster._hit_pause = 0.0
	await _frames(3)
	_check(bar.ceiling == 90.0 and bar.fill < fill_before, "hits during a collapse are heavy: ceiling %.0f" % bar.ceiling)
	_main.collapse.set_physics_process(true)


## Done when (Section 6.1): chases end in dead-end escapes without any
## scripting. A bot sprints down a corridor toward a dead end with a monster
## chasing from behind, then looks at the end wall. Nothing in the game is
## told about the bot; the escape has to come from the normal rules.
func _test_chase_ends_in_dead_end_escape() -> void:
	await _new_run(77)
	var m: MazeMap = _main.maps[0]
	var d: Dictionary = m.dead_ends[0]
	# Walk back from the dead end: the player starts 6 cells out, the monster
	# 2 cells behind the player.
	var route := _route_from(m, d.cell, 8)
	_check(route.size() == 9, "found a route 8 cells back from a dead end")
	var monster: Node3D = _main.monsters.in_map(0)[0]
	_only_active(monster)
	var player_start: Vector2i = route[6]
	var monster_start: Vector2i = route[8]
	_player.place(_world(0, player_start), 0.0)
	_pose(monster, monster_start, _dir_between(route[8], route[7]), Monster.State.CHASE)
	monster._idle_seconds = 0.0
	monster._last_seen = _player.global_position

	var path: Array[Vector2i] = []
	for i in range(5, -1, -1):
		path.append(route[i])
	var wall_dir := MazeMap.opposite(d.faces)
	var escaped := false
	Input.action_press("sprint")
	for frame in 15 * Engine.physics_ticks_per_second:
		if _swaps.current_map != 0 or _main.run_over:
			escaped = _swaps.current_map != 0
			break
		var here: Vector3 = _player.global_position
		while not path.is_empty() and Vector2(_world(0, path[0]).x - here.x, _world(0, path[0]).z - here.z).length() < 0.6:
			path.pop_front()
		if path.is_empty():
			Input.action_release("move_forward")
			_player.rotation.y = MazeBuilder.yaw_facing(wall_dir)
		else:
			var to := _world(0, path[0]) - here
			_player.rotation.y = atan2(-to.x, -to.z)
			Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check(escaped, "sprinting to a dead end and looking at it escapes the chasing monster")
	var swap_lines: Array = _swaps.event_log.recent.filter(func(e: String) -> bool: return e.contains("swap A to B"))
	_check(_swaps.event_log.swaps_in_chase == 1, "the escape is logged as a swap during a chase")
	_check(_main.survival.bar.fill > 0.0 and not _main.run_over, "the player survived (fill %.0f)" % _main.survival.bar.fill)
	_check(monster.state == Monster.State.PATROL and not monster.active, "the monster left behind reverts to idle")


## Cells from `tip` back along its corridor, `count` steps, as a list
## starting at the tip (following the only way that doesn't go back).
func _route_from(m: MazeMap, tip: Vector2i, count: int) -> Array[Vector2i]:
	var dist := m.walk_distances(tip)
	var route: Array[Vector2i] = [tip]
	var c := tip
	for i in count:
		var next := Vector2i(-1, -1)
		for dir in m.open_dirs(c):
			var n := c + MazeMap.offset(dir)
			if dist[m.index(n)] == dist[m.index(c)] + 1 and not m.is_landing(n):
				next = n
				break
		if next.x < 0:
			break
		route.append(next)
		c = next
	return route


func _dir_between(a: Vector2i, b: Vector2i) -> int:
	for dir: int in MazeMap.DIRS:
		if a + MazeMap.offset(dir) == b:
			return dir
	return MazeMap.N


func _test_death_by_monster() -> void:
	await _new_run(88)
	var monster: Node3D = _main.monsters.in_map(0)[0]
	_only_active(monster)
	var c: Vector2i = monster.cell
	_pose(monster, c, MazeMap.N, Monster.State.CHASE)
	_player.place(_world(0, c) + Vector3(0, 0, -0.8), 0.0)
	await _seconds(8.0)  # Five hits at most, 1.5 s apart, with some regeneration between.
	var summary: Dictionary = _swaps.event_log.summary()
	_check(_main.run_over and summary.outcome == "died" and summary.death_cause == "monster",
		"standing still in front of a chasing monster ends in death by monster (%s)" % summary.death_cause)
	_main.generate(1)
	await _frames(2)
