extends Node
## The objective and the collapse (Sections 2.5 and 6.4, roadmap Stage 5).
##
## Each map's objective stands in the middle of its room under a beam of
## light. Pressing E within activate_distance_m of it starts the collapse:
## - the player rushes: unlimited stamina and rush_speed_boost_percent extra
##   speed;
## - escaping takes the one-second stare (collapse_hold_seconds);
## - every monster in the map locks on (the monsters listen for `started`);
## - the map rearranges into its precomputed collapse layout, a few walls at a
##   time, only where the player can't see and never right next to them, and
##   never cutting any part of the map off.
## Escaping through a dead end ends the collapse: earlier wounds heal, then
## the toll (toll_percent_of_max_per_rush_second, capped) comes off the
## ceiling (D17's lean), and the map leaves the pool. As a placeholder for
## D1 and D2, that ends the run on the results screen.

signal started(map_index: int)

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")
const MazeGenerator := preload("res://scripts/maze/maze_generator.gd")

## How often pending wall changes are checked, in seconds.
const REARRANGE_INTERVAL := 0.25
## Walls within this angle of where the player looks count as in view. Wider
## than the camera's own horizontal half-angle (about 53 degrees at 16:9).
const VIEW_HALF_ANGLE := deg_to_rad(65.0)
## Points checked along a wall to see if any of it is in view.
const WALL_SAMPLES := [0.05, 0.5, 0.95]
## A wall this close to the player never changes, seen or not.
const KEEP_CLEAR_M := 1.5

## The map whose collapse is running, or -1.
var collapsing_map := -1
## True while the player is close enough to activate the objective.
var can_activate := false
var rush_seconds := 0.0

var _main: Node
var _player: CharacterBody3D
var _activate_distance: float
var _collapse_hold: float
var _rush_multiplier: float
var _toll_per_second: float
var _toll_cap: float
var _rearrange_timer := 0.0


func _ready() -> void:
	_activate_distance = Tuning.get_value("objective", "activate_distance_m")
	_collapse_hold = Tuning.get_value("trigger", "collapse_hold_seconds")
	_rush_multiplier = 1.0 + Tuning.get_value("collapse", "rush_speed_boost_percent") / 100.0
	_toll_per_second = Tuning.get_value("collapse", "toll_percent_of_max_per_rush_second")
	_toll_cap = Tuning.get_value("collapse", "toll_cap_percent_of_max")


func start_run(main: Node, player: CharacterBody3D) -> void:
	_main = main
	_player = player
	collapsing_map = -1
	can_activate = false
	rush_seconds = 0.0
	player.rushing = false
	player.speed_multiplier = 1.0
	if not main.swap_controller.swapped.is_connected(_on_swapped):
		main.swap_controller.swapped.connect(_on_swapped)


func _physics_process(delta: float) -> void:
	if _main == null:
		return
	if collapsing_map >= 0:
		can_activate = false
		rush_seconds += delta
		_rearrange_timer -= delta
		if _rearrange_timer <= 0.0:
			_rearrange_timer = REARRANGE_INTERVAL
			rearrange_step()
		return
	var index: int = _main.swap_controller.current_map
	var m: MazeMap = _main.maps[index]
	var objective: Vector3 = _main.map_origin(index) + MazeBuilder.objective_position(m, _main.params)
	var gap := Vector2(objective.x - _player.global_position.x, objective.z - _player.global_position.z)
	can_activate = not m.collapsed and gap.length() <= _activate_distance


func _unhandled_input(event: InputEvent) -> void:
	if _main != null and event.is_action_pressed("interact") and can_activate:
		activate()


## Activates the objective of the map the player is in.
func activate() -> void:
	var index: int = _main.swap_controller.current_map
	var m: MazeMap = _main.maps[index]
	m.collapsed = true
	collapsing_map = index
	rush_seconds = 0.0
	can_activate = false
	_player.rushing = true
	_player.speed_multiplier = _rush_multiplier
	_main.swap_controller.hold_needed = _collapse_hold
	MazeBuilder.mark_objective_spent(_main.map_node(index))
	var swaps: Node = _main.swap_controller
	var letter := String.chr(65 + index)
	var reached := {run_seconds = snappedf(swaps.event_log.time, 0.1), seconds_in_map = snappedf(swaps.seconds_in_map[index], 0.1)}
	swaps.event_log.objectives[letter] = reached
	var data := {map = letter}
	data.merge(reached)
	swaps.event_log.add("objective_activated", data)
	_rearrange_timer = 0.0
	started.emit(index)


## Applies every pending collapse change the player can't see. Returns how
## many walls changed.
func rearrange_step() -> int:
	var index := collapsing_map
	var m: MazeMap = _main.maps[index]
	var cs: float = _main.params.cell_size_m
	var local: Vector3 = _player.global_position - _main.map_origin(index)
	var eye := Vector2(local.x, local.z) / cs
	var look3: Vector3 = _player.look_direction()
	var look := Vector2(look3.x, look3.z).normalized()
	var changed := 0
	for change in m.pending_collapse_changes():
		if _might_see(m, change, eye, look, cs):
			continue
		if change.present:
			m.close_wall(change.cell, change.dir)
			if m.walk_distances(m.start_cell).has(-1):
				m.open_wall(change.cell, change.dir)  # Would cut the map; try later.
				continue
		else:
			m.open_wall(change.cell, change.dir)
		changed += 1
	if changed > 0:
		MazeBuilder.rebuild_walls(_main.map_node(index), m, _main.params)
		MazeGenerator.tag_dead_ends(m)
		_main.swap_controller.refresh_map(index)
	return changed


## True if the player could see any part of a wall (present or not yet), or
## stands too close to it to change it safely.
func _might_see(m: MazeMap, change: Dictionary, eye: Vector2, look: Vector2, cs: float) -> bool:
	var wall := MazeMap.side_segment(change.cell, change.dir)
	var nearest := Geometry2D.get_closest_point_to_segment(eye, wall[0], wall[1])
	if (nearest - eye).length() * cs < KEEP_CLEAR_M:
		return true
	for f: float in WALL_SAMPLES:
		var to_point: Vector2 = wall[0].lerp(wall[1], f) - eye
		if absf(look.angle_to(to_point)) > VIEW_HALF_ANGLE:
			continue
		# Stop just short of the wall, so the wall itself doesn't block the view.
		if m.sight_clear(eye, eye + to_point * (1.0 - 0.02 / to_point.length())):
			return true
	return false


func _on_swapped(from_map: int, _to_map: int, trigger: String) -> void:
	if from_map != collapsing_map:
		return
	var swaps: Node = _main.swap_controller
	var bar = _main.survival.bar
	var toll := minf(rush_seconds * _toll_per_second, _toll_cap)
	bar.heal_wounds()
	bar.lower_ceiling(toll)
	_player.rushing = false
	_player.speed_multiplier = 1.0
	swaps.hold_needed = swaps.normal_hold
	swaps.pool.erase(from_map)
	swaps.event_log.rush_seconds = rush_seconds
	swaps.event_log.toll_paid = toll
	swaps.event_log.add("collapse_escaped", {
		map = String.chr(65 + from_map), trigger = trigger,
		rush_seconds = snappedf(rush_seconds, 0.1), toll = snappedf(toll, 0.1),
	})
	collapsing_map = -1
	# Placeholder for D1 and D2 (CLAUDE.md): escaping the first collapse ends
	# the run on the results screen.
	_main.end_run("escaped", "")
