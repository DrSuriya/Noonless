extends Node
## Spawns and runs the monsters (roadmap Stage 6): each map's monsters stand
## at its spawn cells from the start of a run. Only the monsters in the
## player's map are active; when the player leaves a map, its monsters go
## back to idle and pause (Sections 2.4 and 6.4). When a map's collapse
## starts, its monsters lock on. Tells the swap controller whether a chase is
## on, for the swap metrics, and logs every state change.

const MonsterScene := preload("res://scenes/monster.tscn")
const Monster := preload("res://scripts/monster.gd")

var monsters: Array[Node3D] = []

var _main: Node
var _player: CharacterBody3D
var _footstep: AudioStreamWAV
## Sensitivity multiplier by the number of maps still in the pool.
var _sensitivity := {}
## The [monsters] values each monster needs, read once.
var _settings := {}


func _ready() -> void:
	_footstep = make_footstep()
	_sensitivity = {
		3: Tuning.get_value("monsters", "sensitivity_multiplier_3_maps_active"),
		2: Tuning.get_value("monsters", "sensitivity_multiplier_2_maps_active"),
		1: Tuning.get_value("monsters", "sensitivity_multiplier_1_map_active"),
	}
	for key in ["patrol_speed_mps", "suspicious_speed_mps", "chase_speed_mps", "sight_half_angle_deg",
			"sight_range_m", "crouch_sight_factor", "notice_seconds", "close_range_m", "search_seconds",
			"attack_range_m", "attack_cooldown_seconds", "hit_pause_seconds"]:
		_settings[key] = Tuning.get_value("monsters", key)


func start_run(main: Node, player: CharacterBody3D) -> void:
	_main = main
	_player = player
	monsters.clear()  # The old ones were freed with their maps.
	for m in main.maps:
		for i in m.monster_spawns.size():
			var monster: Node3D = MonsterScene.instantiate()
			monster.name = "Monster%d" % i
			main.map_node(m.map_index).add_child(monster)
			monster.setup(main, player, m, i, m.monster_spawns[i], _footstep, _settings)
			monster.active = m.map_index == main.swap_controller.current_map
			monster.state_changed.connect(_on_state_changed)
			monsters.append(monster)
	if not main.swap_controller.swapped.is_connected(_on_swapped):
		main.swap_controller.swapped.connect(_on_swapped)
	if not main.collapse.started.is_connected(_on_collapse_started):
		main.collapse.started.connect(_on_collapse_started)


## The sensitivity multiplier for the number of maps left in the pool.
func sensitivity() -> float:
	return _sensitivity.get(clampi(_main.swap_controller.pool.size(), 1, 3), 1.0)


## Straight-line distance from the player to the nearest chasing monster in
## their map, or null if none is chasing. Logged with each swap, to spot
## narrow escapes (Section 6.6).
func nearest_chaser_distance() -> Variant:
	var nearest: Variant = null
	for monster in monsters:
		if monster.active and monster.is_chasing():
			var d: float = monster._flat_distance(_player.global_position)
			nearest = d if nearest == null else minf(nearest, d)
	return nearest


func in_map(map_index: int) -> Array[Node3D]:
	return monsters.filter(func(monster: Node3D) -> bool: return monster.map_index == map_index)


func _physics_process(_delta: float) -> void:
	if _main == null:
		return
	_main.swap_controller.chase = monsters.any(func(monster: Node3D) -> bool: return monster.active and monster.is_chasing())


func _on_swapped(from_map: int, to_map: int, _trigger: String) -> void:
	for monster in in_map(from_map):
		monster.revert_to_idle()
		monster.active = false
	for monster in in_map(to_map):
		monster.active = true


func _on_collapse_started(map_index: int) -> void:
	for monster in in_map(map_index):
		monster.lock_on()


func _on_state_changed(monster: Node3D, state: int) -> void:
	_main.swap_controller.event_log.add("monster_state", {
		monster = monster.monster_index, map = String.chr(65 + monster.map_index),
		state = Monster.State.keys()[state].to_lower(),
	})


## Placeholder footstep audio (Section 6.2): a short, dull thud made in code,
## so there's no imported asset.
static func make_footstep() -> AudioStreamWAV:
	var rate := 22050
	var length := int(rate * 0.09)
	var data := PackedByteArray()
	data.resize(length * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var low := 0.0
	for i in length:
		var t := float(i) / rate
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.12  # Low-passed noise.
		var sample := (low * 0.8 + sin(TAU * 70.0 * t) * 0.5) * exp(-t * 45.0)
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
