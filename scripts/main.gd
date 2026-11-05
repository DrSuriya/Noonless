extends Node3D
## Main scene: generates the prototype's two maps from a run seed, keeps both
## built far apart for the whole run (Section 6.4 "World and persistence") and
## starts the player in the middle of map A. The swap controller moves the
## player between maps, Survival runs the bar and items, Collapse runs the
## objectives, and Monsters runs the monsters. A run ends on the results screen when the player escapes the
## first collapse (the placeholder for D1 and D2) or dies. The debug view's
## seed field and the results screen start new runs.

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeParams := preload("res://scripts/maze/maze_params.gd")
const MazeGenerator := preload("res://scripts/maze/maze_generator.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")
const EventLog := preload("res://scripts/event_log.gd")

## The prototype has two maps.
const MAP_COUNT := 2
## Distance between the maps along the x axis, in metres.
const MAP_SPACING_M := 1000.0

## Tests turn this off so runs don't leave log files behind.
@export var write_event_log := true

var params: MazeParams
var run_seed: int
var maps: Array[MazeMap] = []
## True from the end of a run until the next one starts.
var run_over := false

@onready var swap_controller: Node = $SwapController
@onready var survival: Node = $Survival
@onready var collapse: Node = $Collapse
@onready var monsters: Node = $Monsters
@onready var _player: CharacterBody3D = $Player
@onready var _maps_root: Node3D = $Maps
@onready var _debug_view: Control = $DebugLayer/DebugView
@onready var _hud: Control = $HudLayer/Hud
@onready var _results: Control = $ResultsLayer/Results


func _ready() -> void:
	params = MazeParams.new(Tuning.config)
	_debug_view.seed_submitted.connect(generate)
	survival.died.connect(func(cause: String) -> void: end_run("died", cause))
	if not Tuning.debug_keys_enabled():
		print("Debug keys are off (playtest build, or debug_keys_enabled=false).")
	generate(randi())


func _exit_tree() -> void:
	if swap_controller.event_log != null:
		swap_controller.event_log.close()


## Builds both maps from `new_seed` and puts the player at the start of map A.
func generate(new_seed: int) -> void:
	if swap_controller.event_log != null:
		swap_controller.event_log.close()
	run_over = false
	get_tree().paused = false
	_results.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
	_player.place(start, MazeBuilder.yaw_facing(first.open_dirs(first.start_cell)[0]))

	var event_log := EventLog.new(run_seed, write_event_log)
	var map_seeds := []
	for m in maps:
		map_seeds.append(m.map_seed)
	event_log.add("run_start", {seed = run_seed, map_seeds = map_seeds})
	if event_log.path != "":
		print("Event log: %s" % event_log.path)
	swap_controller.start_run(self, _player, event_log)
	survival.start_run(self, _player)
	collapse.start_run(self, _player)
	monsters.start_run(self, _player)
	_hud.show_run(self)
	_debug_view.show_run(self)


## Ends the run: "escaped" (the first collapse) or "died" with its cause.
## Closes the event log and pauses the game under the results screen.
func end_run(outcome: String, cause: String) -> void:
	if run_over:
		return
	run_over = true
	var event_log = swap_controller.event_log
	event_log.outcome = outcome
	event_log.death_cause = cause
	if outcome == "died":
		event_log.add("died", {cause = cause})
	event_log.close()
	_results.show_results(self, outcome, event_log.summary(), event_log.path)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The built 3D node of a map.
func map_node(map_index: int) -> Node3D:
	return _maps_root.get_child(map_index)


## Where a map's north-west corner sits in the world.
func map_origin(map_index: int) -> Vector3:
	return Vector3(map_index * MAP_SPACING_M, 0.0, 0.0)
