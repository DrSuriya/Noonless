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
## Chance (0 to 1) that a dead end survives braiding, nearest and farthest
## from the objective. It scales linearly with distance in between.
var survival_near: float
var survival_far: float
var landing_spots_per_origin_map: int
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
	survival_near = _read(cfg, "maze", "dead_end_survival_near_objective_percent") / 100.0
	survival_far = _read(cfg, "maze", "dead_end_survival_far_percent") / 100.0
	landing_spots_per_origin_map = _read(cfg, "swap", "landing_spots_per_origin_map")
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
