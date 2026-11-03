extends RefCounted
## Seeded maze generator, following Section 6.4 "Generating the maze":
## a perfect maze, rooms, the objective, landing-spot alcoves, braiding
## weighted by distance to the objective, then the long-walk rule and the
## validation rules. The same seed and settings always give the same maps.

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")
const MazeValidator := preload("res://scripts/maze/maze_validator.gd")

## Tries at a layout that keeps the objective in the farther half and enough
## dead ends after braiding.
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
	# room out of the farther half, and can leave too few dead ends. If either
	# happens, try again from the same maze and rooms; the attempts come from
	# the same seed, so this reproduces too.
	var maze_with_rooms := m.walls.duplicate()
	var before_braiding := PackedByteArray()
	for attempt in MAX_OBJECTIVE_ATTEMPTS:
		m.walls = maze_with_rooms.duplicate()
		m.landing_spots.clear()
		_place_objective(m, rng)
		_measure_distances(m)
		_place_landing_spots(m, rng, p)
		before_braiding = m.walls.duplicate()
		_braid(m, rng, p.survival_near, p.survival_far)
		_apply_long_walk(m, rng, p, true)
		if MazeValidator.objective_in_farther_half(m) and m.dead_end_tips().size() >= p.min_dead_ends:
			break
	tag_dead_ends(m)
	_place_items(m, rng, p)
	_plan_collapse(m, before_braiding, p)

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


## Braiding: each dead end survives with a chance that changes linearly from
## `near` at the objective to `far` at the farthest cell. Normally near is
## high and far is low, so dead ends stay dense near the objective and thin
## out far away; the collapse layout swaps them.
static func _braid(m: MazeMap, rng: RandomNumberGenerator, near: float, far: float) -> void:
	var tips := m.dead_end_tips()
	_shuffle(tips, rng)
	for tip in tips:
		if m.degree(tip) != 1:
			continue  # An earlier opening already reached it.
		var t := m.distance_to_objective(tip) / m.max_distance
		var survival := lerpf(near, far, t)
		if rng.randf() >= survival:
			_open_dead_end(m, tip, rng)


## Opens dead ends until every branch is at least min_branch_cells long (the
## long walk) and, with `hide_from_objective`, no dead-end wall can be seen
## from the objective. Opening a wall can shorten other branches, so this
## repeats until nothing changes.
static func _apply_long_walk(m: MazeMap, rng: RandomNumberGenerator, p: MazeParams, hide_from_objective: bool) -> void:
	while true:
		var opened := false
		for tip in m.dead_end_tips():
			if m.degree(tip) == 1 and m.branch_cells(tip).size() < p.min_branch_cells:
				opened = _open_dead_end(m, tip, rng) or opened
		if opened:
			continue
		if not hide_from_objective:
			return
		for tip in MazeValidator.visible_dead_ends(m):
			if m.degree(tip) == 1:
				opened = _open_dead_end(m, tip, rng) or opened
		if not opened:
			return


## Records the map's dead ends from its current walls. Called again when the
## collapse rearranges the map.
static func tag_dead_ends(m: MazeMap) -> void:
	m.dead_ends.clear()
	for tip in m.dead_end_tips():
		m.dead_ends.append({
			cell = tip,
			faces = m.open_dirs(tip)[0],
			branch = m.branch_cells(tip),
			distance = m.distance_to_objective(tip),
		})


## Scatters bandages and hospital kits on random cells, kept apart, never in
## a dead-end branch, a landing spot, the start or the objective's cell.
static func _place_items(m: MazeMap, rng: RandomNumberGenerator, p: MazeParams) -> void:
	var blocked := {}
	for d in m.dead_ends:
		for c: Vector2i in d.branch:
			blocked[c] = true
	for spot in m.landing_spots:
		blocked[spot.cell] = true
	blocked[m.start_cell] = true
	blocked[m.objective_cell] = true
	var candidates: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			if not blocked.has(Vector2i(x, y)):
				candidates.append(Vector2i(x, y))
	_shuffle(candidates, rng)
	var kinds: Array[String] = []
	for i in p.hospital_kits_per_map:
		kinds.append("hospital_kit")
	for i in p.bandages_per_map:
		kinds.append("bandage")
	for c in candidates:
		if m.items.size() == kinds.size():
			break
		var clear := true
		for item in m.items:
			if Vector2(c - item.cell).length() < p.item_spacing_cells:
				clear = false
				break
		if clear:
			m.items.append({cell = c, kind = kinds[m.items.size()], taken = false})


## The collapse rearrangement (Section 6.4), precomputed so it causes no hitch:
## the same braiding pass with the weighting inverted, run on the maze as it
## was before braiding, then the long walk. Dead ends near the objective open
## up and new ones appear toward the edges. Braiding only opens walls of a
## connected maze, so the result stays connected; landing-spot alcoves are
## never opened, so they stay. It has its own generator, seeded from the map
## seed, so it doesn't change the normal layout.
static func _plan_collapse(m: MazeMap, before_braiding: PackedByteArray, p: MazeParams) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("collapse:%d" % m.map_seed)
	var normal := m.walls
	var best := PackedByteArray()
	var best_count := -1
	# Retry until the layout has enough dead ends to escape through.
	for attempt in MAX_OBJECTIVE_ATTEMPTS:
		m.walls = before_braiding.duplicate()
		_braid(m, rng, p.survival_far, p.survival_near)
		_apply_long_walk(m, rng, p, false)
		var count := m.dead_end_tips().size()
		if count > best_count:
			best = m.walls
			best_count = count
		if count >= p.min_dead_ends:
			break
	m.collapse_walls = best
	m.walls = normal


## Fisher-Yates with the map's own generator, so the order is reproducible.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
