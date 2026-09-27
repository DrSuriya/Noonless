extends Node3D
## Main scene: generates the prototype's two maps from a run seed, keeps both
## built far apart (Section 6.4 "World and persistence") and starts the player
## in the middle of map A. The debug view's seed field regenerates the run.

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")
const MazeGenerator := preload("res://scripts/maze/maze_generator.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")

## The prototype has two maps.
const MAP_COUNT := 2
## Distance between the maps along the x axis, in metres.
const MAP_SPACING_M := 1000.0

var params: MazeParams
var run_seed: int
var maps: Array[MazeMap] = []

@onready var _player: CharacterBody3D = $Player
@onready var _maps_root: Node3D = $Maps
@onready var _debug_view: Control = $DebugLayer/DebugView


func _ready() -> void:
	params = MazeParams.new(Tuning.config)
	_debug_view.seed_submitted.connect(generate)
	generate(randi())


## Builds both maps from `new_seed` and puts the player at the start of map A.
func generate(new_seed: int) -> void:
	run_seed = new_seed
	print("Run seed: %d" % run_seed)
	maps = MazeGenerator.generate_run(run_seed, MAP_COUNT, params)
	for child in _maps_root.get_children():
		_maps_root.remove_child(child)
		child.queue_free()
	for m in maps:
		var node := MazeBuilder.build(m, params)
		node.position = map_origin(m.map_index)
		_maps_root.add_child(node)

	var first := maps[0]
	var start := map_origin(0) + MazeBuilder.cell_position(first.start_cell, params)
	_player.place(start, _yaw_facing(first.open_dirs(first.start_cell)[0]))
	_debug_view.show_run(self)


## Where a map's north-west corner sits in the world.
func map_origin(map_index: int) -> Vector3:
	return Vector3(map_index * MAP_SPACING_M, 0.0, 0.0)


## The player's yaw that looks along a grid direction. The player looks down
## -Z at yaw 0, which is grid north.
func _yaw_facing(dir: int) -> float:
	match dir:
		MazeMap.E:
			return -PI / 2
		MazeMap.S:
			return PI
		MazeMap.W:
			return PI / 2
	return 0.0
