extends Node3D
## The prototype's one monster: a sight-based chaser (Section 6.2, roadmap
## Stage 6), driven by the state machine from Section 6.4.
##
## - PATROL: wanders between random cells of its map.
## - SUSPICIOUS: saw the player at a distance; walks toward where it saw them.
##   Seeing them for notice_seconds, or within close_range_m, starts a chase.
## - CHASE: runs at the player while it can see them, then to where it last
##   saw them. Hits within attack_range_m.
## - SEARCH: looks around the last known position for search_seconds.
## - RETURN: walks back to its spawn cell, then patrols again.
## - LOCKED: during its map's collapse it chases the player's exact position,
##   seen or not (Section 6.4's collapse override).
##
## Sight is a cone checked with a raycast from its eyes, so walls block it.
## It ignores the player during the grace period after a swap. It moves from
## cell centre to cell centre along grid paths, so it never walks through
## walls; inside the player's cell it steps straight at them.

signal state_changed(monster: Node3D, state: State)

enum State { PATROL, SUSPICIOUS, CHASE, SEARCH, RETURN, LOCKED }

const MazeMap := preload("res://scripts/maze/maze_map.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")

const EYE_HEIGHT_M := 1.6
const TURN_SPEED := 6.0  # Radians per second.
const PATROL_PAUSE_SECONDS := 1.5
const SEARCH_RADIUS_CELLS := 3
## Seconds between footsteps at walking and running pace.
const STEP_INTERVAL_SLOW := 0.6
const STEP_INTERVAL_FAST := 0.32

var state := State.PATROL
var map_index: int
var monster_index: int
## The cell it last stood in the middle of, and the one it's heading into.
var cell: Vector2i
var spawn_cell: Vector2i
## While false (the player is in another map) it doesn't move or look.
var active := false

var _main: Node
var _player: CharacterBody3D
var _m: MazeMap
var _rng := RandomNumberGenerator.new()
var _next: Vector2i
var _path: Array[Vector2i] = []
var _goal_position := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _seen_seconds := 0.0
var _state_seconds := 0.0
## After a hit it stands still and doesn't look for this long.
var _hit_pause := 0.0
## Between patrol goals it stands and looks around for this long.
var _idle_seconds := 0.0
var _cooldown := 0.0
var _step_timer := 0.0
var _cfg := {}

@onready var _footsteps: AudioStreamPlayer3D = $Footsteps


## `settings` holds the [monsters] values from tuning.cfg (see Monsters).
func setup(main: Node, player: CharacterBody3D, m: MazeMap, index: int, start: Vector2i,
		footstep: AudioStream, settings: Dictionary) -> void:
	_main = main
	_player = player
	_m = m
	map_index = m.map_index
	monster_index = index
	spawn_cell = start
	cell = start
	_next = start
	_rng.seed = hash("monster:%d:%d" % [m.map_seed, index])
	_cfg = settings
	global_position = _cell_world(start)
	$Footsteps.stream = footstep


## Back to idle behavior (Section 2.4: when the player leaves a map, its
## monsters return to idle). Keeps its position; picks a new patrol goal.
func revert_to_idle() -> void:
	_path.clear()
	_set_state(State.PATROL)
	_hit_pause = 0.0
	_idle_seconds = 0.0


## The collapse override: chase the player's exact position from now on.
func lock_on() -> void:
	_set_state(State.LOCKED)
	_path.clear()


func is_chasing() -> bool:
	return state == State.CHASE or state == State.LOCKED


func _physics_process(delta: float) -> void:
	if not active or _main.run_over:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_state_seconds += delta
	if _hit_pause > 0.0:
		_hit_pause -= delta
		return
	var sees := can_see_player()
	if sees:
		_last_seen = _player.global_position
	_think(delta, sees)
	_move(delta)
	_try_hit()


## True if the player is inside its sight cone and range, with no wall in
## the way, and the grace period is over.
func can_see_player() -> bool:
	if _main.swap_controller.grace_remaining > 0.0:
		return false
	var eye := global_position + Vector3(0, EYE_HEIGHT_M, 0)
	var target: Vector3 = _player.eye_position()
	var to_target := target - eye
	var sight_range: float = _cfg.sight_range_m * _main.monsters.sensitivity()
	if _player.crouching:
		sight_range *= _cfg.crouch_sight_factor
	if to_target.length() > sight_range:
		return false
	var facing := -global_transform.basis.z
	if facing.angle_to(Vector3(to_target.x, 0, to_target.z)) > deg_to_rad(_cfg.sight_half_angle_deg):
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == _player


func _think(_delta: float, sees: bool) -> void:
	var distance := _flat_distance(_player.global_position)
	match state:
		State.PATROL, State.RETURN, State.SEARCH:
			if sees:
				if distance <= _cfg.close_range_m:
					_set_state(State.CHASE)
				else:
					_seen_seconds = 0.0
					_set_state(State.SUSPICIOUS)
				_path.clear()
			elif state == State.SEARCH and _state_seconds >= _cfg.search_seconds:
				_set_state(State.RETURN)
				_path = _find_path(_next, spawn_cell)
			elif _path.is_empty() and _arrived():
				if state == State.RETURN:
					_set_state(State.PATROL)
				if _idle_seconds > 0.0:
					_idle_seconds -= get_physics_process_delta_time()
				else:
					_pick_wander_goal()
		State.SUSPICIOUS:
			if sees:
				_seen_seconds += get_physics_process_delta_time()
				if _seen_seconds >= _cfg.notice_seconds or distance <= _cfg.close_range_m:
					_set_state(State.CHASE)
					_path.clear()
					return
			if _path.is_empty() and not _arrived_near(_last_seen):
				_path = _find_path(_next, _world_cell(_last_seen))
			elif _path.is_empty():
				_set_state(State.SEARCH)
		State.CHASE:
			if sees:
				_path = _find_path(_next, _world_cell(_player.global_position))
			elif _path.is_empty():
				if _arrived_near(_last_seen):
					_set_state(State.SEARCH)
				else:
					_path = _find_path(_next, _world_cell(_last_seen))
		State.LOCKED:
			_last_seen = _player.global_position
			_path = _find_path(_next, _world_cell(_player.global_position))


func _move(delta: float) -> void:
	var speed: float = _cfg.patrol_speed_mps
	if state == State.SUSPICIOUS:
		speed = _cfg.suspicious_speed_mps
	elif is_chasing():
		speed = _cfg.chase_speed_mps
	var target: Vector3
	var player_cell := _world_cell(_player.global_position)
	if is_chasing() and (player_cell == _next or player_cell == cell) and _next == cell:
		# Same cell as the player: step straight at them.
		target = _player.global_position
	else:
		if _next == cell and not _path.is_empty():
			var step: Vector2i = _path.pop_front()
			if step != cell and _open_between(cell, step):
				_next = step
			else:
				_path.clear()
		if _next != cell and not _open_between(cell, _next):
			_next = cell  # A wall appeared (the collapse); go back to the centre.
			_path.clear()
		target = _cell_world(_next)
	var to_target := target - global_position
	to_target.y = 0.0
	var moving := to_target.length() > 0.05
	if moving:
		var step_length := minf(speed * delta, to_target.length())
		if is_chasing() and target == _player.global_position:
			step_length = minf(step_length, maxf(to_target.length() - _cfg.attack_range_m * 0.6, 0.0))
		global_position += to_target.normalized() * step_length
		_turn_toward(to_target, delta)
	elif state == State.SUSPICIOUS:
		_turn_toward(_last_seen - global_position, delta)
	if _next != cell and _flat_distance(_cell_world(_next)) < 0.05:
		cell = _next
	_play_footsteps(delta, moving)


func _try_hit() -> void:
	if not is_chasing() or _cooldown > 0.0 or _main.swap_controller.grace_remaining > 0.0:
		return
	if _flat_distance(_player.global_position) > _cfg.attack_range_m:
		return
	_cooldown = _cfg.attack_cooldown_seconds
	_hit_pause = _cfg.hit_pause_seconds
	var in_collapse: bool = _main.collapse.collapsing_map == map_index
	_main.survival.damage(in_collapse, "monster_in_collapse" if in_collapse else "monster")


func _play_footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = STEP_INTERVAL_FAST if is_chasing() else STEP_INTERVAL_SLOW
		_footsteps.play()


func _pick_wander_goal() -> void:
	var goal: Vector2i
	if state == State.SEARCH:
		var around := _world_cell(_last_seen)
		goal = around + Vector2i(_rng.randi_range(-SEARCH_RADIUS_CELLS, SEARCH_RADIUS_CELLS),
			_rng.randi_range(-SEARCH_RADIUS_CELLS, SEARCH_RADIUS_CELLS))
		goal = goal.clamp(Vector2i.ZERO, Vector2i(_m.width - 1, _m.height - 1))
	else:
		goal = Vector2i(_rng.randi_range(0, _m.width - 1), _rng.randi_range(0, _m.height - 1))
		_idle_seconds = PATROL_PAUSE_SECONDS  # Used on arrival.
	_path = _find_path(_next, goal)


## Shortest path of cells from `from` to `to` through open walls (not
## including `from`), or empty if unreachable.
func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not _m.in_bounds(from) or not _m.in_bounds(to) or from == to:
		return path
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			break
		for dir in _m.open_dirs(c):
			var n := c + MazeMap.offset(dir)
			if not came.has(n):
				came[n] = c
				queue.append(n)
	if not came.has(to):
		return path
	var c := to
	while c != from:
		path.push_front(c)
		c = came[c]
	return path


func _open_between(a: Vector2i, b: Vector2i) -> bool:
	for dir: int in MazeMap.DIRS:
		if a + MazeMap.offset(dir) == b:
			return not _m.has_wall(a, dir)
	return a == b


func _arrived() -> bool:
	return _next == cell and _flat_distance(_cell_world(cell)) < 0.05


func _arrived_near(point: Vector3) -> bool:
	return _arrived() and _world_cell(point) == cell


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	_state_seconds = 0.0
	state_changed.emit(self, new_state)


func _turn_toward(direction: Vector3, delta: float) -> void:
	if Vector2(direction.x, direction.z).length() < 0.001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, TURN_SPEED * delta)


func _cell_world(c: Vector2i) -> Vector3:
	return _main.map_origin(map_index) + MazeBuilder.cell_position(c, _main.params)


func _world_cell(p: Vector3) -> Vector2i:
	var local: Vector3 = p - _main.map_origin(map_index)
	var cs: float = _main.params.cell_size_m
	return Vector2i(floori(local.x / cs), floori(local.z / cs)).clamp(Vector2i.ZERO, Vector2i(_m.width - 1, _m.height - 1))


func _flat_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
