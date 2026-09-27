extends RefCounted
## Validation rules for generated maps. The three from Section 6.4: the
## objective is reachable, no dead-end wall is visible from the objective, and
## landing spots never count as dead ends. Also checks the generator's own
## rules: the long walk, rooms, objective placement and consistent walls.
## Used by the generator after each map and by tests/test_maze_generator.gd.

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")

## Points checked along each dead-end wall, as fractions of its length.
const WALL_SAMPLES := [0.05, 0.25, 0.5, 0.75, 0.95]
## Sample points sit this far inside the dead-end cell (in cells), so a sight
## line stops just short of the wall it's looking at.
const INSET := 0.01


## Every rule broken, as readable text. Empty means the map is valid.
static func problems(m: MazeMap, p: MazeParams) -> PackedStringArray:
	var out := PackedStringArray()
	if not objective_reachable(m):
		out.append("the objective at %s can't be reached from the start" % m.objective_cell)
	for tip in visible_dead_ends(m):
		out.append("the dead-end wall at %s is visible from the objective" % tip)
	out.append_array(landing_spot_problems(m, p))
	out.append_array(generator_problems(m, p))
	return out


## Rule 1: the objective can be reached from the start.
static func objective_reachable(m: MazeMap) -> bool:
	return m.walk_distances(m.start_cell)[m.index(m.objective_cell)] >= 0


## Rule 2: dead ends whose end wall can be seen from the objective. A wall
## counts as seen if a straight line from the objective to any sample point on
## it crosses no other wall. Walls are treated as thin lines, which sees a
## little more than the thicker 3D walls would, so this errs on the safe side.
static func visible_dead_ends(m: MazeMap) -> Array[Vector2i]:
	var segments := m.wall_segments()
	var seen: Array[Vector2i] = []
	for tip in m.dead_end_tips():
		var faces: int = m.open_dirs(tip)[0]
		if _wall_visible(m.objective_pos, tip, MazeMap.opposite(faces), segments):
			seen.append(tip)
	return seen


## Rule 3: landing spots never count as dead ends. Each must be a one-cell
## alcove opening off a junction, and never tagged as a dead end.
static func landing_spot_problems(m: MazeMap, p: MazeParams) -> PackedStringArray:
	var out := PackedStringArray()
	for origin in m.origin_maps:
		var count := m.landing_spots.filter(func(s: Dictionary) -> bool: return s.origin_map == origin).size()
		if count != p.landing_spots_per_origin_map:
			out.append("%d landing spots for arrivals from map %d, not %d" % [count, origin, p.landing_spots_per_origin_map])
	for spot in m.landing_spots:
		var c: Vector2i = spot.cell
		if m.dead_ends.any(func(d: Dictionary) -> bool: return d.cell == c):
			out.append("landing spot %s is tagged as a dead end" % c)
		if m.degree(c) != 1:
			out.append("landing spot %s has %d openings instead of one" % [c, m.degree(c)])
			continue
		if m.open_dirs(c)[0] != spot.faces:
			out.append("landing spot %s faces the wrong way" % c)
		if m.degree(c + MazeMap.offset(spot.faces)) < 3:
			out.append("landing spot %s ends a corridor instead of opening off one" % c)
		if m.in_room(c):
			out.append("landing spot %s is inside a room" % c)
		if m.distance_to_objective(c) < m.median_distance:
			out.append("landing spot %s is in the half of the map nearer the objective" % c)
	return out


## The generator's own rules, beyond the three from Section 6.4.
static func generator_problems(m: MazeMap, p: MazeParams) -> PackedStringArray:
	var out := PackedStringArray()

	# Walls agree from both sides, and the border is closed.
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			for dir: int in MazeMap.DIRS:
				var n := c + MazeMap.offset(dir)
				if not m.in_bounds(n):
					if not m.has_wall(c, dir):
						out.append("cell %s is open to the outside" % c)
				elif m.has_wall(c, dir) != m.has_wall(n, MazeMap.opposite(dir)):
					out.append("the wall between %s and %s differs by side" % [c, n])

	# Every cell can be reached.
	var dist := m.walk_distances(m.start_cell)
	var unreachable := dist.count(-1)
	if unreachable > 0:
		out.append("%d cells can't be reached from the start" % unreachable)

	# The long walk: every dead-end branch is at least the minimum length.
	for tip in m.dead_end_tips():
		var length := m.branch_cells(tip).size()
		if length < p.min_branch_cells:
			out.append("the dead-end branch at %s is %d cells, under the minimum %d" % [tip, length, p.min_branch_cells])

	# The dead-end tags match the grid.
	var tagged: Array[Vector2i] = []
	for d in m.dead_ends:
		tagged.append(d.cell)
	if tagged != m.dead_end_tips():
		out.append("the tagged dead ends don't match the grid")

	# Rooms: count, size, spacing, and never over the start.
	if m.rooms.size() < p.room_count_min or m.rooms.size() > p.room_count_max:
		out.append("%d rooms, outside %d to %d" % [m.rooms.size(), p.room_count_min, p.room_count_max])
	for i in m.rooms.size():
		var room := m.rooms[i]
		var sides := [room.size.x, room.size.y]
		if sides.min() < p.room_size_min or sides.max() > p.room_size_max:
			out.append("room %s has a side outside %d to %d cells" % [room, p.room_size_min, p.room_size_max])
		if room.has_point(m.start_cell):
			out.append("room %s covers the start" % room)
		for j in range(i + 1, m.rooms.size()):
			if room.grow(1).intersects(m.rooms[j]):
				out.append("rooms %s and %s overlap or touch" % [room, m.rooms[j]])

	# The objective is in the middle of a room from the farther half by walking
	# distance from the start.
	if m.objective_room < 0:
		out.append("there's no objective")
	else:
		if not objective_in_farther_half(m):
			out.append("the objective's room isn't in the farther half of rooms")
		if m.objective_cell != MazeMap.room_center_cell(m.rooms[m.objective_room]):
			out.append("the objective isn't in the middle of its room")
	return out


## True if the objective's room is in the farther half of rooms by walking
## distance from the start, measured on the map as it is now.
static func objective_in_farther_half(m: MazeMap) -> bool:
	var far_rooms := m.rooms_by_walking_distance().slice(0, ceili(m.rooms.size() / 2.0))
	return m.objective_room in far_rooms


static func _wall_visible(from: Vector2, cell: Vector2i, side: int, segments: PackedVector2Array) -> bool:
	var wall := MazeMap.side_segment(cell, side)
	var inward := Vector2(-MazeMap.offset(side)) * INSET
	for f: float in WALL_SAMPLES:
		if _sight_clear(from, wall[0].lerp(wall[1], f) + inward, segments):
			return true
	return false


## True if the line from `from` to `to` crosses none of the wall segments.
## Touching a wall's end counts as blocked, as the 3D wall's thickness would.
static func _sight_clear(from: Vector2, to: Vector2, segments: PackedVector2Array) -> bool:
	for i in range(0, segments.size(), 2):
		if Geometry2D.segment_intersects_segment(from, to, segments[i], segments[i + 1]) != null:
			return false
	return true
