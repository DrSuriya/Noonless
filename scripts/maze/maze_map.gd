extends RefCounted
## One map's grid (Section 6.4 "Map data"): the walls of every cell, plus tags
## for rooms, the objective, landing spots and dead ends.
## Positions and distances are in cells; multiply by the cell size for metres.
## Grid x runs east and grid y runs south (world +X and +Z).

const N := 1
const E := 2
const S := 4
const W := 8
const DIRS := [N, E, S, W]

var width: int
var height: int
var map_seed: int
## 0 is map A, 1 is map B.
var map_index: int
## The maps whose players arrive here, one set of landing spots for each.
var origin_maps: Array[int] = []

## Bitmask of the walls each cell has (N, E, S, W), indexed by y * width + x.
var walls := PackedByteArray()
## Index into `rooms` for each cell, or -1 for cells outside rooms.
var room_of := PackedInt32Array()
var rooms: Array[Rect2i] = []

var start_cell: Vector2i
var objective_room := -1
var objective_cell: Vector2i
## Centre of the objective's room. Distances to the objective are measured
## from here, in a straight line.
var objective_pos: Vector2
## Distance from the objective to the farthest cell centre, and the median
## over all cells (the line between the near and far halves of the map).
var max_distance: float
var median_distance: float

## One entry per landing spot: {cell: Vector2i, faces: int, origin_map: int}.
## A landing spot is a one-cell alcove. Its blended wall is on the side
## opposite `faces`, which is the direction of the alcove's opening.
var landing_spots: Array[Dictionary] = []

## One entry per dead end: {cell: Vector2i, faces: int, branch: Array[Vector2i],
## distance: float}. The dead-end wall is on the side of `cell` opposite
## `faces` and faces back up the branch. `branch` runs from the dead end back
## to the first junction or room (the long walk). `distance` is to the objective.
var dead_ends: Array[Dictionary] = []


func _init(w: int, h: int) -> void:
	width = w
	height = h
	walls.resize(w * h)
	walls.fill(N | E | S | W)
	room_of.resize(w * h)
	room_of.fill(-1)


static func offset(dir: int) -> Vector2i:
	match dir:
		N:
			return Vector2i(0, -1)
		E:
			return Vector2i(1, 0)
		S:
			return Vector2i(0, 1)
	return Vector2i(-1, 0)


static func opposite(dir: int) -> int:
	match dir:
		N:
			return S
		E:
			return W
		S:
			return N
	return E


## The wall on `side` of cell `c`, as its two end points.
static func side_segment(c: Vector2i, side: int) -> PackedVector2Array:
	var x := float(c.x)
	var y := float(c.y)
	match side:
		N:
			return PackedVector2Array([Vector2(x, y), Vector2(x + 1, y)])
		E:
			return PackedVector2Array([Vector2(x + 1, y), Vector2(x + 1, y + 1)])
		S:
			return PackedVector2Array([Vector2(x, y + 1), Vector2(x + 1, y + 1)])
	return PackedVector2Array([Vector2(x, y), Vector2(x, y + 1)])


## The cell at the middle of a room (the upper-left one of the middle cells
## when a side is even).
static func room_center_cell(room: Rect2i) -> Vector2i:
	return room.position + Vector2i((room.size.x - 1) >> 1, (room.size.y - 1) >> 1)


## Room indexes sorted by walking distance from the start to each room's
## middle cell, farthest first (ties go to the lower index).
func rooms_by_walking_distance() -> Array[int]:
	var dist := walk_distances(start_cell)
	var order: Array[int] = []
	for i in rooms.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := dist[index(room_center_cell(rooms[a]))]
		var db := dist[index(room_center_cell(rooms[b]))]
		if da != db:
			return da > db
		return a < b
	)
	return order


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func index(c: Vector2i) -> int:
	return c.y * width + c.x


func has_wall(c: Vector2i, dir: int) -> bool:
	return (walls[index(c)] & dir) != 0


## Removes the wall on `dir` side of `c`, and the matching wall of the neighbour.
func open_wall(c: Vector2i, dir: int) -> void:
	var n := c + offset(dir)
	if not in_bounds(n):
		push_error("Can't open the map border at %s" % c)
		return
	walls[index(c)] &= ~dir
	walls[index(n)] &= ~opposite(dir)


func close_wall(c: Vector2i, dir: int) -> void:
	walls[index(c)] |= dir
	var n := c + offset(dir)
	if in_bounds(n):
		walls[index(n)] |= opposite(dir)


## Directions in which `c` has no wall.
func open_dirs(c: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for dir: int in DIRS:
		if not has_wall(c, dir):
			result.append(dir)
	return result


func degree(c: Vector2i) -> int:
	return open_dirs(c).size()


func in_room(c: Vector2i) -> bool:
	return room_of[index(c)] != -1


func is_landing(c: Vector2i) -> bool:
	for spot in landing_spots:
		if spot.cell == c:
			return true
	return false


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


func distance_to_objective(c: Vector2i) -> float:
	return (cell_center(c) - objective_pos).length()


## Steps from `from` to every cell through open walls, or -1 where unreachable.
func walk_distances(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	dist[index(from)] = 0
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir in open_dirs(c):
			var n := c + offset(dir)
			if dist[index(n)] == -1:
				dist[index(n)] = dist[index(c)] + 1
				queue.append(n)
	return dist


## Cells with exactly one opening, outside rooms, that aren't landing spots.
## These are the map's dead ends, in scan order.
func dead_end_tips() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if degree(c) == 1 and not in_room(c) and not is_landing(c):
				result.append(c)
	return result


## The corridor leading to the dead end at `tip`: the tip and the cells behind
## it, up to but not including the first junction, room or landing spot.
func branch_cells(tip: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [tip]
	var prev := tip
	var cur := tip + offset(open_dirs(tip)[0])
	while not in_room(cur) and not is_landing(cur) and degree(cur) == 2:
		cells.append(cur)
		var dirs := open_dirs(cur)
		var next := cur + offset(dirs[0])
		if next == prev:
			next = cur + offset(dirs[1])
		prev = cur
		cur = next
	return cells


## Every wall as a segment in cell units, each wall once. The result holds
## pairs of points: [a0, b0, a1, b1, ...].
func wall_segments() -> PackedVector2Array:
	var segments := PackedVector2Array()
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if has_wall(c, N):
				segments.append_array(side_segment(c, N))
			if has_wall(c, W):
				segments.append_array(side_segment(c, W))
			if x == width - 1 and has_wall(c, E):
				segments.append_array(side_segment(c, E))
			if y == height - 1 and has_wall(c, S):
				segments.append_array(side_segment(c, S))
	return segments
