extends Node
## The Dead-End Trigger and the swap (Sections 2.4 and 6.4).
##
## Each physics frame, if the player is in the last cell of a dead end, within
## distance_m of its end wall and looking at it within facing_angle_deg, a
## hold timer counts up; otherwise it resets. When it reaches
## normal_hold_seconds the player swaps to the other map: they land in one of
## its landing spots for the map they came from, facing the blended wall, and
## the grace timer starts. The swap-now key does the same from anywhere.
## Maps are never rebuilt, so returning to one finds it unchanged.

signal swapped(from_map: int, to_map: int, trigger: String)

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")
const EventLog := preload("res://scripts/event_log.gd")

## Below this horizontal speed (m/s) the player counts as standing still.
const STILL_SPEED := 0.05

## The map the player is in, by index.
var current_map := 0
## How long the player has held their gaze on the dead-end wall, in seconds.
var hold_seconds := 0.0
## The hold that fires the swap: normal_hold_seconds, or the one-second stare
## during a collapse (set by the collapse).
var hold_needed: float
var normal_hold: float
## The maps a dead end can still send the player to (the active pool).
var pool: Array[int] = []
## Seconds the player has spent in each map this run.
var seconds_in_map: Array[float] = []
## True while any monster in the player's map is chasing them (set by the
## monsters), for the swap metrics.
var chase := false
## Seconds left in the grace period after the last swap.
var grace_remaining := 0.0
var event_log: EventLog

var _main: Node
var _player: CharacterBody3D
## Picks landing spots. Seeded from the run seed, so the same seed and the
## same swaps land in the same places.
var _rng := RandomNumberGenerator.new()
var _distance_m: float
var _facing_rad: float
var _grace_seconds: float
var _quick_window: float
## False in playtest builds: the swap-now key does nothing.
var debug_keys_enabled := true
## For each map: cell index to the index of the dead end whose branch holds it.
var _branch_of: Array[Dictionary] = []
## The dead end whose branch the player is in, or -1, and when they entered.
var _branch := -1
var _branch_tip := Vector2i(-1, -1)
var _branch_entered_at := 0.0


func _ready() -> void:
	normal_hold = Tuning.get_value("trigger", "normal_hold_seconds")
	hold_needed = normal_hold
	_distance_m = Tuning.get_value("trigger", "distance_m")
	_facing_rad = deg_to_rad(Tuning.get_value("trigger", "facing_angle_deg"))
	_grace_seconds = Tuning.get_value("swap", "grace_period_seconds")
	_quick_window = Tuning.get_value("playtest", "quick_swap_window_seconds")
	debug_keys_enabled = Tuning.debug_keys_enabled()


## Starts tracking a new run. The player must already be at the start.
func start_run(main: Node, player: CharacterBody3D, new_log: EventLog) -> void:
	_main = main
	_player = player
	event_log = new_log
	_rng.seed = hash("swap:%d" % main.run_seed)
	current_map = 0
	hold_seconds = 0.0
	hold_needed = normal_hold
	grace_remaining = 0.0
	chase = false
	_branch = -1
	_branch_tip = Vector2i(-1, -1)
	pool.clear()
	seconds_in_map.clear()
	_branch_of.clear()
	for m: MazeMap in main.maps:
		pool.append(m.map_index)
		seconds_in_map.append(0.0)
		_branch_of.append(_branch_lookup(m))


## Call after a map's walls change (the collapse): re-reads its dead ends.
## Staying in the same dead end keeps the hold timer and the entry time.
func refresh_map(map_index: int) -> void:
	_branch_of[map_index] = _branch_lookup(_main.maps[map_index])
	if map_index != current_map:
		return
	var m: MazeMap = _main.maps[map_index]
	var c := player_cell()
	var now: int = _branch_of[map_index].get(m.index(c), -1) if c.x >= 0 else -1
	if now >= 0 and m.dead_ends[now].cell == _branch_tip:
		_branch = now
	else:
		_branch = -1
		_branch_tip = Vector2i(-1, -1)


static func _branch_lookup(m: MazeMap) -> Dictionary:
	var lookup := {}
	for i in m.dead_ends.size():
		for c: Vector2i in m.dead_ends[i].branch:
			lookup[m.index(c)] = i
	return lookup


func _physics_process(delta: float) -> void:
	if _main == null:
		return
	event_log.time += delta
	seconds_in_map[current_map] += delta
	grace_remaining = maxf(grace_remaining - delta, 0.0)
	var v := _player.get_real_velocity()
	if Vector2(v.x, v.z).length() < STILL_SPEED:
		event_log.standing_still_seconds += delta
	_track_branch()
	if _facing_dead_end_wall():
		hold_seconds += delta
		if hold_seconds >= hold_needed:
			swap("gaze")
	else:
		hold_seconds = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _main != null and debug_keys_enabled and event.is_action_pressed("swap_now"):
		swap("swap_now_key")


## The swap sequence (Section 6.4): pick the destination map and one of its
## landing spots for the origin map, place the player facing the blended
## wall, and start the grace timer. With two maps the destination is always
## the other one (D4 doesn't apply yet).
func swap(trigger: String) -> void:
	var from := current_map
	var others: Array[int] = []
	for i in pool:
		if i != from:
			others.append(i)
	if others.is_empty():
		return  # D1: what the last map's dead ends do isn't decided.
	var to := others[_rng.randi_range(0, others.size() - 1)]
	var dest: MazeMap = _main.maps[to]
	var spots := dest.landing_spots.filter(func(s: Dictionary) -> bool: return s.origin_map == from)
	var spot: Dictionary = spots[_rng.randi_range(0, spots.size() - 1)]

	var origin: MazeMap = _main.maps[from]
	var data := {
		from_map = _letter(from), to_map = _letter(to), trigger = trigger, chase = chase,
		dead_end = null, dead_end_distance_to_objective = null,
		seconds_since_branch_entered = null, quick = false, near_objective = false,
		landing_spot = [spot.cell.x, spot.cell.y], chaser_distance_m = null,
	}
	var chaser = _main.monsters.nearest_chaser_distance()
	if chaser != null:
		data.chaser_distance_m = snappedf(chaser, 0.1)
	if trigger == "gaze":
		var d: Dictionary = origin.dead_ends[_branch]
		var since := event_log.time - _branch_entered_at
		data.dead_end = [d.cell.x, d.cell.y]
		data.dead_end_distance_to_objective = snappedf(d.distance, 0.01)
		data.seconds_since_branch_entered = snappedf(since, 0.01)
		data.quick = not chase and since <= _quick_window
		data.near_objective = d.distance < origin.median_distance
		if data.near_objective and not origin.collapsed:
			var letter := _letter(from)
			event_log.ejections_near_objective[letter] = event_log.ejections_near_objective.get(letter, 0) + 1
	event_log.count_swap(chase, data.quick)
	event_log.add("swap", data)

	var wall_side := MazeMap.opposite(spot.faces)
	_player.place(_main.map_origin(to) + MazeBuilder.cell_position(spot.cell, _main.params),
		MazeBuilder.yaw_facing(wall_side))
	current_map = to
	hold_seconds = 0.0
	grace_remaining = _grace_seconds
	_branch = -1
	_branch_tip = Vector2i(-1, -1)
	swapped.emit(from, to, trigger)


## The cell the player stands in, in the current map, or (-1, -1) outside it.
func player_cell() -> Vector2i:
	var local: Vector3 = _player.global_position - _main.map_origin(current_map)
	var c := Vector2i(floori(local.x / _main.params.cell_size_m), floori(local.z / _main.params.cell_size_m))
	return c if _main.maps[current_map].in_bounds(c) else Vector2i(-1, -1)


## Notes when the player walks into a dead end's branch, for the
## quick-swap metric.
func _track_branch() -> void:
	var m: MazeMap = _main.maps[current_map]
	var c := player_cell()
	var now := -1
	if c.x >= 0:
		now = _branch_of[current_map].get(m.index(c), -1)
	if now == _branch:
		return
	_branch = now
	_branch_tip = m.dead_ends[now].cell if now >= 0 else Vector2i(-1, -1)
	if now >= 0:
		_branch_entered_at = event_log.time
		event_log.add("dead_end_branch_entered", {map = _letter(current_map), dead_end = [_branch_tip.x, _branch_tip.y]})


## True if the player is in a dead end's last cell, close enough to its end
## wall and looking at it.
func _facing_dead_end_wall() -> bool:
	if _branch < 0:
		return false
	var m: MazeMap = _main.maps[current_map]
	var d: Dictionary = m.dead_ends[_branch]
	if player_cell() != d.cell:
		return false
	var into := MazeBuilder.dir_vector(MazeMap.opposite(d.faces))
	var params = _main.params
	var face: Vector3 = (_main.map_origin(current_map) + MazeBuilder.cell_position(d.cell, params)
		+ into * (params.cell_size_m / 2 - params.wall_thickness_m / 2))
	if (face - _player.global_position).dot(into) > _distance_m:
		return false
	return _player.look_direction().angle_to(into) <= _facing_rad


static func _letter(map_index: int) -> String:
	return String.chr(65 + map_index)
