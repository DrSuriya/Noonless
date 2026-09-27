extends RefCounted
## Builds a map's gray-box geometry from its grid: a floor and wall boxes in
## the map's flat color, with collision. Walls in a straight line are merged
## into one box. The map's north-west corner sits at the node's origin.

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")

const FLOOR_THICKNESS_M := 0.2
## How much darker the floor is than the walls, so the two read apart.
const FLOOR_DARKEN := 0.35


static func build(m: MazeMap, p: MazeParams) -> Node3D:
	var root := Node3D.new()
	root.name = "Map" + String.chr(65 + m.map_index)
	var color := p.map_colors[m.map_index]
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = color
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = color.darkened(FLOOR_DARKEN)

	var cs := p.cell_size_m
	var span := Vector2(m.width, m.height) * cs
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	root.add_child(floor_body)
	_add_box(floor_body, Vector3(span.x / 2, -FLOOR_THICKNESS_M / 2, span.y / 2),
		Vector3(span.x, FLOOR_THICKNESS_M, span.y), floor_material)

	var walls_body := StaticBody3D.new()
	walls_body.name = "Walls"
	root.add_child(walls_body)
	var h := p.wall_height_m
	var t := p.wall_thickness_m
	# Walls running east-west, on each horizontal grid line.
	for line in m.height + 1:
		for run in _runs(m.width, func(x: int) -> bool: return _wall_on_horizontal_line(m, x, line)):
			var length := (run.y - run.x) * cs
			_add_box(walls_body, Vector3((run.x + run.y) * cs / 2, h / 2, line * cs),
				Vector3(length + t, h, t), wall_material)
	# Walls running north-south, on each vertical grid line.
	for line in m.width + 1:
		for run in _runs(m.height, func(y: int) -> bool: return _wall_on_vertical_line(m, line, y)):
			var length := (run.y - run.x) * cs
			_add_box(walls_body, Vector3(line * cs, h / 2, (run.x + run.y) * cs / 2),
				Vector3(t, h, length + t), wall_material)
	return root


## World position (relative to the map's node) of the middle of a cell, at floor level.
static func cell_position(c: Vector2i, p: MazeParams) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5) * p.cell_size_m


## Stretches of consecutive indexes in [0, count) where `has_wall` is true,
## as Vector2i(first, one past the last).
static func _runs(count: int, has_wall: Callable) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var i := 0
	while i < count:
		if not has_wall.call(i):
			i += 1
			continue
		var first := i
		while i < count and has_wall.call(i):
			i += 1
		runs.append(Vector2i(first, i))
	return runs


static func _wall_on_horizontal_line(m: MazeMap, x: int, line: int) -> bool:
	if line < m.height:
		return m.has_wall(Vector2i(x, line), MazeMap.N)
	return m.has_wall(Vector2i(x, line - 1), MazeMap.S)


static func _wall_on_vertical_line(m: MazeMap, line: int, y: int) -> bool:
	if line < m.width:
		return m.has_wall(Vector2i(line, y), MazeMap.W)
	return m.has_wall(Vector2i(line - 1, y), MazeMap.E)


static func _add_box(body: StaticBody3D, center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = center
	body.add_child(mesh_instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
