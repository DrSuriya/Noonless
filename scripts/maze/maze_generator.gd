extends RefCounted
## Seeded maze generator, following Section 6.4 "Generating the maze":
## a perfect maze, rooms, the objective, landing-spot alcoves, braiding
## weighted by distance to the objective, then the long-walk rule and the
## validation rules. The same seed and settings always give the same maps.

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")
const MazeValidator := preload("res://scripts/maze/maze_validator.gd")

## Tries at an objective that stays in the farther half after braiding.
const MAX_OBJECTIVE_ATTEMPTS := 20


## Generates every map of a run. Each map's seed is drawn from the run seed,
## and each map gets landing spots for arrivals from every other map.
static func generate_run(run_seed: int, map_count: int, p: MazeParams) -> Array[MazeMap]:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var map_seeds: Array[int] = []
	for i in map_count:
		map_seeds.append(rng.randi())
	var maps: Array[MazeMap] = []
	for i in map_count:
		var origins: Array[int] = []
		for j in map_count:
			if j != i:
				origins.append(j)
		maps.append(generate(map_seeds[i], i, origins, p))
	return maps


static func generate(map_seed: int, map_index: int, origin_maps: Array[int], p: MazeParams) -> MazeMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var m := MazeMap.new(p.width, p.height)
	m.map_seed = map_seed
	m.map_index = map_index
	m.origin_maps = origin_maps
	# The player starts in the middle of the maze (Section 2.2).
	m.start_cell = Vector2i(floori(p.width / 2.0), floori(p.height / 2.0))

	_carve_perfect_maze(m, rng)
	_carve_rooms(m, rng, p)
	# Braiding opens loops that shorten walks, which can move the objective's
	# room out of the farther half. If it does, try again from the same maze
	# and rooms; the attempts come from the same seed, so this reproduces too.
	var maze_with_rooms := m.walls.duplicate()
	for attempt in MAX_OBJECTIVE_ATTEMPTS:
		m.walls = maze_with_rooms.duplicate()
		m.landing_spots.clear()
		_place_objective(m, rng)
		_measure_distances(m)
		_place_landing_spots(m, rng, p)
		_braid(m, rng, p)
		_apply_long_walk_and_visibility(m, rng, p)
		if MazeValidator.objective_in_farther_half(m):
			break
	_tag_dead_ends(m)

	var problems := MazeValidator.problems(m, p)
	if not problems.is_empty():
		push_error("Map %d from seed %d breaks rules: %s" % [map_index, map_seed, "; ".join(problems)])
	return m


## Recursive backtracker: long, winding corridors that suit the long walk.
static func _carve_perfect_maze(m: MazeMap, rng: RandomNumberGenerator) -> void:
	var visited := PackedByteArray()
	visited.resize(m.width * m.height)
	var first := Vector2i(rng.randi_range(0, m.width - 1), rng.randi_range(0, m.height - 1))
	visited[m.index(first)] = 1
	var stack: Array[Vector2i] = [first]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var options: Array[int] = []
		for dir: int in MazeMap.DIRS:
			var n := c + MazeMap.offset(dir)
			if m.in_bounds(n) and visited[m.index(n)] == 0:
				options.append(dir)
		if options.is_empty():
			stack.pop_back()
			continue
		var dir := options[rng.randi_range(0, options.size() - 1)]
		var n := c + MazeMap.offset(dir)
		m.open_wall(c, dir)
		visited[m.index(n)] = 1
		stack.append(n)


## Places non-overlapping rooms, at least one cell apart and never over the
## start cell, and opens the walls inside them.
static func _carve_rooms(m: MazeMap, rng: RandomNumberGenerator, p: MazeParams) -> void:
	var count := rng.randi_range(p.room_count_min, p.room_count_max)
	var attempts := 0
	while m.rooms.size() < count and attempts < 1000:
		attempts += 1
		var size := Vector2i(
			rng.randi_range(p.room_size_min, p.room_size_max),
			rng.randi_range(p.room_size_min, p.room_size_max)
		)
		var pos := Vector2i(rng.randi_range(0, m.width - size.x), rng.randi_range(0, m.height - size.y))
		var room := Rect2i(pos, size)
		if room.has_point(m.start_cell):
			continue
		var clear := true
		for other in m.rooms:
			if room.grow(1).intersects(other):
				clear = false
				break
		if not clear:
			continue
		var room_index := m.rooms.size()
		m.rooms.append(room)
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				var c := Vector2i(x, y)
				m.room_of[m.index(c)] = room_index
				if x + 1 < room.end.x:
					m.open_wall(c, MazeMap.E)
				if y + 1 < room.end.y:
					m.open_wall(c, MazeMap.S)


## Puts the objective in the middle of a random room from the farther half of
## rooms, by walking distance from the start.
static func _place_objective(m: MazeMap, rng: RandomNumberGenerator) -> void:
	var order := m.rooms_by_walking_distance()
	var far_count := ceili(order.size() / 2.0)
	var room_index := order[rng.randi_range(0, far_count - 1)]
	var room := m.rooms[room_index]
	m.objective_room = room_index
	m.objective_cell = MazeMap.room_center_cell(room)
	m.objective_pos = Vector2(room.position) + Vector2(room.size) / 2.0


static func _measure_distances(m: MazeMap) -> void:
	var distances: Array[float] = []
	for y in m.height:
		for x in m.width:
			distances.append(m.distance_to_objective(Vector2i(x, y)))
	distances.sort()
	m.max_distance = distances.back()
	m.median_distance = distances[floori(distances.size() / 2.0)]


## Makes one-cell alcoves for landing spots in the half of the map farther from
## the objective. The first is random; each next one is the candidate farthest
## from those already placed, to keep them apart.
static func _place_landing_spots(m: MazeMap, rng: RandomNumberGenerator, p: MazeParams) -> void:
	var placed: Array[Vector2i] = []
	for origin in m.origin_maps:
		for k in p.landing_spots_per_origin_map:
			var candidates := _landing_candidates(m)
			if candidates.is_empty():
				push_error("Map %d from seed %d has no room for another landing spot" % [m.map_index, m.map_seed])
				return
			var pick := candidates[rng.randi_range(0, candidates.size() - 1)]
			if not placed.is_empty():
				var best := -1.0
				for c in candidates:
					var nearest := INF
					for other in placed:
						nearest = minf(nearest, Vector2(c - other).length())
					if nearest > best:
						best = nearest
						pick = c
			# The alcove opens off a junction, so it's a nook beside the
			# corridor rather than the end of one.
			var faces: int = m.open_dirs(pick)[0]
			var parent := pick + MazeMap.offset(faces)
			if m.degree(parent) < 3:
				var dirs := _openable_dirs(m, parent)
				m.open_wall(parent, dirs[rng.randi_range(0, dirs.size() - 1)])
			m.landing_spots.append({cell = pick, faces = faces, origin_map = origin})
			placed.append(pick)


## Cells that can become landing alcoves: current dead ends in the far half,
## outside rooms, not next to a map corner or another landing spot, whose one
## neighbour is a corridor cell that is, or can become, a junction.
static func _landing_candidates(m: MazeMap) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.degree(c) != 1 or m.in_room(c) or m.is_landing(c) or c == m.start_cell:
				continue
			if m.distance_to_objective(c) < m.median_distance:
				continue
			if _touches_corner_or_landing(m, c):
				continue
			var parent := c + MazeMap.offset(m.open_dirs(c)[0])
			if m.in_room(parent):
				continue
			if m.degree(parent) < 3 and _openable_dirs(m, parent).is_empty():
				continue
			result.append(c)
	return result


## A dead end next to a map corner could otherwise be left with no wall it can
## open, if the corner's other neighbour were a landing spot.
static func _touches_corner_or_landing(m: MazeMap, c: Vector2i) -> bool:
	for dir: int in MazeMap.DIRS:
		var n := c + MazeMap.offset(dir)
		if not m.in_bounds(n):
			continue
		var is_corner := (n.x == 0 or n.x == m.width - 1) and (n.y == 0 or n.y == m.height - 1)
		if is_corner or m.is_landing(n):
			return true
	return false


## Walls of `c` that can be opened: inside the map and not into a landing spot.
static func _openable_dirs(m: MazeMap, c: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for dir: int in MazeMap.DIRS:
		var n := c + MazeMap.offset(dir)
		if m.has_wall(c, dir) and m.in_bounds(n) and not m.is_landing(n):
			result.append(dir)
	return result


## Removes a dead end by opening one of its walls into a loop.
static func _open_dead_end(m: MazeMap, tip: Vector2i, rng: RandomNumberGenerator) -> bool:
	var dirs := _openable_dirs(m, tip)
	if dirs.is_empty():
		push_error("Dead end at %s has no wall that can be opened" % tip)
		return false
	m.open_wall(tip, dirs[rng.randi_range(0, dirs.size() - 1)])
	return true


## Braiding: each dead end survives with a chance that falls linearly from
## survival_near at the objective to survival_far at the farthest cell, so
## dead ends stay dense near the objective and thin out far away.
static func _braid(m: MazeMap, rng: RandomNumberGenerator, p: MazeParams) -> void:
	var tips := m.dead_end_tips()
	_shuffle(tips, rng)
	for tip in tips:
		if m.degree(tip) != 1:
			continue  # An earlier opening already reached it.
		var t := m.distance_to_objective(tip) / m.max_distance
		var survival := lerpf(p.survival_near, p.survival_far, t)
		if rng.randf() >= survival:
			_open_dead_end(m, tip, rng)


## Opens dead ends until every branch is at least min_branch_cells long (the
## long walk) and no dead-end wall can be seen from the objective. Opening a
## wall can shorten other branches, so this repeats until nothing changes.
static func _apply_long_walk_and_visibility(m: MazeMap, rng: RandomNumberGenerator, p: MazeParams) -> void:
	while true:
		var opened := false
		for tip in m.dead_end_tips():
			if m.degree(tip) == 1 and m.branch_cells(tip).size() < p.min_branch_cells:
				opened = _open_dead_end(m, tip, rng) or opened
		if opened:
			continue
		for tip in MazeValidator.visible_dead_ends(m):
			if m.degree(tip) == 1:
				opened = _open_dead_end(m, tip, rng) or opened
		if not opened:
			return


static func _tag_dead_ends(m: MazeMap) -> void:
	m.dead_ends.clear()
	for tip in m.dead_end_tips():
		m.dead_ends.append({
			cell = tip,
			faces = m.open_dirs(tip)[0],
			branch = m.branch_cells(tip),
			distance = m.distance_to_objective(tip),
		})


## Fisher-Yates with the map's own generator, so the order is reproducible.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
