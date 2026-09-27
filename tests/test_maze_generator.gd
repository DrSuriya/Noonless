extends SceneTree
## Headless tests for the maze generator and the Section 6.4 validation rules.
##
## Run from the project folder:
##     godot --headless --path . -s res://tests/test_maze_generator.gd
## Prints each check and exits with the number of failures (0 = all passed).

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")
const MazeGenerator := preload("res://scripts/maze/maze_generator.gd")
const MazeValidator := preload("res://scripts/maze/maze_validator.gd")

## Run seeds swept by the checks that must hold for every map (two maps each).
const RUN_SEEDS := 200

var _params: MazeParams
var _failures := 0
## Every map from RUN_SEEDS, generated once and shared by the checks below.
var _sweep: Array = []


func _initialize() -> void:
	var cfg := ConfigFile.new()
	_check(cfg.load("res://config/tuning.cfg") == OK, "config/tuning.cfg loads")
	_params = MazeParams.new(cfg)
	for run_seed in RUN_SEEDS:
		_sweep.append_array(MazeGenerator.generate_run(run_seed, 2, _params))

	_test_same_seed_gives_same_maps()
	_test_the_two_maps_differ()
	_test_rules_hold_across_seeds()
	_test_catches_unreachable_objective()
	_test_catches_visible_dead_end_wall()
	_test_catches_landing_spot_as_dead_end()
	_test_dead_ends_denser_near_objective()

	print("\n%s (%d failed)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	quit(_failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _same(a: MazeMap, b: MazeMap) -> bool:
	return (a.walls == b.walls and a.room_of == b.room_of and a.rooms == b.rooms
		and a.objective_cell == b.objective_cell and a.landing_spots == b.landing_spots
		and a.dead_ends == b.dead_ends)


func _test_same_seed_gives_same_maps() -> void:
	var ok := true
	for run_seed in [0, 1, 42, 123456789, -7]:
		var first := MazeGenerator.generate_run(run_seed, 2, _params)
		var second := MazeGenerator.generate_run(run_seed, 2, _params)
		for i in 2:
			ok = ok and _same(first[i], second[i])
	_check(ok, "the same run seed gives identical maps")


func _test_the_two_maps_differ() -> void:
	var ok := true
	for i in range(0, _sweep.size(), 2):
		ok = ok and _sweep[i].walls != _sweep[i + 1].walls
		ok = ok and _sweep[i].map_seed != _sweep[i + 1].map_seed
	var a := MazeGenerator.generate_run(1, 2, _params)
	var b := MazeGenerator.generate_run(2, 2, _params)
	ok = ok and a[0].walls != b[0].walls
	_check(ok, "a run's two maps differ, and so do different runs")


func _test_rules_hold_across_seeds() -> void:
	var unreachable := 0
	var visible := 0
	var landing := 0
	var other := 0
	for m: MazeMap in _sweep:
		if not MazeValidator.objective_reachable(m):
			unreachable += 1
		if not MazeValidator.visible_dead_ends(m).is_empty():
			visible += 1
		if not MazeValidator.landing_spot_problems(m, _params).is_empty():
			landing += 1
		var generator_problems := MazeValidator.generator_problems(m, _params)
		if not generator_problems.is_empty():
			other += 1
			if other <= 3:
				print("      map seed %d: %s" % [m.map_seed, "; ".join(generator_problems)])
	var where := "in all %d maps" % _sweep.size()
	_check(unreachable == 0, "rule: the objective is reachable %s (%d failed)" % [where, unreachable])
	_check(visible == 0, "rule: no dead-end wall is visible from the objective %s (%d failed)" % [where, visible])
	_check(landing == 0, "rule: landing spots never count as dead ends %s (%d failed)" % [where, landing])
	_check(other == 0, "long walk, rooms, objective placement and walls hold %s (%d failed)" % [where, other])


func _test_catches_unreachable_objective() -> void:
	var m := MazeGenerator.generate_run(5, 2, _params)[0]
	var room := m.rooms[m.objective_room]
	# Wall the objective's room off from the rest of the map.
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			for dir: int in MazeMap.DIRS:
				var n := Vector2i(x, y) + MazeMap.offset(dir)
				if m.in_bounds(n) and not room.has_point(n):
					m.close_wall(Vector2i(x, y), dir)
	_check(not MazeValidator.objective_reachable(m), "validator catches a walled-off objective")


func _test_catches_visible_dead_end_wall() -> void:
	# A straight 5-cell corridor: the objective's one-cell room at the west
	# end can see the dead-end wall at the east end.
	var m := _corridor_map(Vector2i(5, 1), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	var seen := MazeValidator.visible_dead_ends(m)
	_check(seen.size() == 1 and seen[0] == Vector2i(4, 0), "validator catches a dead-end wall in sight of the objective")
	# Around a corner, the same kind of dead end is hidden.
	m = _corridor_map(Vector2i(3, 3), [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1)])
	_check(MazeValidator.visible_dead_ends(m).is_empty(), "validator allows a dead end hidden around a corner")


## A map whose only open path runs through `path`, with a one-cell objective
## room at its first cell.
func _corridor_map(size: Vector2i, path: Array[Vector2i]) -> MazeMap:
	var m := MazeMap.new(size.x, size.y)
	for i in path.size() - 1:
		var step := path[i + 1] - path[i]
		for dir: int in MazeMap.DIRS:
			if MazeMap.offset(dir) == step:
				m.open_wall(path[i], dir)
	m.rooms.append(Rect2i(path[0], Vector2i.ONE))
	m.room_of[m.index(path[0])] = 0
	m.objective_room = 0
	m.objective_cell = path[0]
	m.objective_pos = m.cell_center(path[0])
	m.start_cell = path[0]
	return m


func _test_catches_landing_spot_as_dead_end() -> void:
	var m := MazeGenerator.generate_run(9, 2, _params)[1]
	_check(MazeValidator.landing_spot_problems(m, _params).is_empty(), "a generated map's landing spots pass")
	var spot: Dictionary = m.landing_spots[0]
	m.dead_ends.append({cell = spot.cell, faces = spot.faces, branch = [spot.cell], distance = 0.0})
	_check(not MazeValidator.landing_spot_problems(m, _params).is_empty(),
		"validator catches a landing spot tagged as a dead end")

	m = MazeGenerator.generate_run(9, 2, _params)[1]
	spot = m.landing_spots[0]
	var cell: Vector2i = spot.cell
	for dir: int in MazeMap.DIRS:
		var n := cell + MazeMap.offset(dir)
		if m.has_wall(cell, dir) and m.in_bounds(n):
			m.open_wall(cell, dir)
			break
	_check(not MazeValidator.landing_spot_problems(m, _params).is_empty(),
		"validator catches a landing spot that isn't an alcove")


## Section 6.4: dead ends stay dense near the objective and thin out far away.
## Counted over every map, split at the median distance so both halves have
## the same number of cells.
func _test_dead_ends_denser_near_objective() -> void:
	var near := 0
	var far := 0
	for m: MazeMap in _sweep:
		for d in m.dead_ends:
			if d.distance < m.median_distance:
				near += 1
			else:
				far += 1
	var maps := float(_sweep.size())
	_check(near > far, "dead ends are denser near the objective: %.1f per map in the near half, %.1f in the far half"
		% [near / maps, far / maps])
