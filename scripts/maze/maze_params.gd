extends RefCounted
## Maze generation and build settings, read from config/tuning.cfg. The
## comments there say which decision each value stands in for.

var width: int
var height: int
var room_count_min: int
var room_count_max: int
var room_size_min: int
var room_size_max: int
var min_branch_cells: int
var min_dead_ends: int
var tell_darken_entry: float
var tell_darken_tip: float
## Chance (0 to 1) that a dead end survives braiding, nearest and farthest
## from the objective. It scales linearly with distance in between.
var survival_near: float
var survival_far: float
var landing_spots_per_origin_map: int
var blended_wall_panels: int
var bandages_per_map: int
var hospital_kits_per_map: int
var item_spacing_cells: int
var monsters_per_map: int
var monster_spawn_min_distance: float
var cell_size_m: float
var wall_height_m: float
var wall_thickness_m: float
## One flat color per map, by map index.
var map_colors: Array[Color] = []


func _init(cfg: ConfigFile) -> void:
	width = _read(cfg, "maze", "width_cells")
	height = _read(cfg, "maze", "height_cells")
	room_count_min = _read(cfg, "maze", "room_count_min")
	room_count_max = _read(cfg, "maze", "room_count_max")
	room_size_min = _read(cfg, "maze", "room_size_min_cells")
	room_size_max = _read(cfg, "maze", "room_size_max_cells")
	min_branch_cells = _read(cfg, "maze", "min_dead_end_branch_cells")
	min_dead_ends = _read(cfg, "maze", "min_dead_ends_per_layout")
	tell_darken_entry = _read(cfg, "maze", "tell_darken_entry")
	tell_darken_tip = _read(cfg, "maze", "tell_darken_tip")
	survival_near = _read(cfg, "maze", "dead_end_survival_near_objective_percent") / 100.0
	survival_far = _read(cfg, "maze", "dead_end_survival_far_percent") / 100.0
	landing_spots_per_origin_map = _read(cfg, "swap", "landing_spots_per_origin_map")
	blended_wall_panels = _read(cfg, "swap", "blended_wall_panels")
	bandages_per_map = _read(cfg, "items", "bandages_per_map")
	hospital_kits_per_map = _read(cfg, "items", "hospital_kits_per_map")
	item_spacing_cells = _read(cfg, "items", "item_spacing_cells")
	monsters_per_map = _read(cfg, "monsters", "monsters_per_map")
	monster_spawn_min_distance = _read(cfg, "monsters", "spawn_min_distance_cells")
	cell_size_m = _read(cfg, "maze", "cell_size_m")
	wall_height_m = _read(cfg, "maze", "wall_height_m")
	wall_thickness_m = _read(cfg, "maze", "wall_thickness_m")
	map_colors.append(_read(cfg, "maps", "map_a_color"))
	map_colors.append(_read(cfg, "maps", "map_b_color"))


func _read(cfg: ConfigFile, section: String, key: String) -> Variant:
	if not cfg.has_section_key(section, key):
		push_error("config/tuning.cfg has no [%s] %s" % [section, key])
		return null
	return cfg.get_value(section, key)
