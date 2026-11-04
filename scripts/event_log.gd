extends RefCounted
## Event log (Section 6.4). Writes what happens in a run to a file, one JSON
## object per line, and keeps the Section 6.6 metrics: swaps per minute split
## by chase, quick swaps (the accidental-swap proxy), time to reach each
## objective and ejections near it, rush length and toll paid, deaths by
## cause, and time spent standing still.

const DIR := "user://event_logs"
## How many recent events the debug view shows.
const RECENT_COUNT := 6

## Seconds since the run started, advanced by the swap controller each
## physics frame.
var time := 0.0
## The log file's path on disk, or "" when not writing a file.
var path := ""
## Recent events as short text, newest first, for the debug view.
var recent: Array[String] = []

var swaps_in_chase := 0
var swaps_no_chase := 0
## Swaps with no chase within quick_swap_window_seconds of entering the dead
## end's branch.
var quick_swaps := 0
var standing_still_seconds := 0.0
## Map letter to {run_seconds, seconds_in_map} when its objective was reached.
var objectives := {}
## Map letter to gaze swaps out of a dead end in the half of the map nearer
## its objective, before the objective was reached.
var ejections_near_objective := {}
var rush_seconds := 0.0
var toll_paid := 0.0
## How the run ended: "escaped", "died" or "" (still running, or abandoned).
var outcome := ""
var death_cause := ""

var _file: FileAccess
var _closed := false


## Starts a log for a run. With `write_file` false it keeps the metrics in
## memory only (used by tests).
func _init(run_seed: int, write_file: bool) -> void:
	if not write_file:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file_path := "%s/run_%s_seed%d.jsonl" % [DIR, stamp, run_seed]
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_error("Event log: can't write %s (%s)" % [file_path, error_string(FileAccess.get_open_error())])
		return
	path = ProjectSettings.globalize_path(file_path)


## Records an event. Values in `data` must be JSON types (no Vector2i).
func add(type: String, data: Dictionary = {}) -> void:
	var entry := {t = snappedf(time, 0.001), type = type}
	entry.merge(data)
	if _file != null:
		_file.store_line(JSON.stringify(entry, "", false))
		_file.flush()
	recent.push_front("%6.1f s  %s" % [time, _describe(type, data)])
	if recent.size() > RECENT_COUNT:
		recent.pop_back()


func count_swap(chase: bool, quick: bool) -> void:
	if chase:
		swaps_in_chase += 1
	else:
		swaps_no_chase += 1
		if quick:
			quick_swaps += 1


func swaps_per_minute(count: int) -> float:
	return count / (time / 60.0) if time > 0.0 else 0.0


## The Section 6.6 metrics measured so far.
func summary() -> Dictionary:
	return {
		run_seconds = snappedf(time, 0.1),
		swaps_in_chase = swaps_in_chase,
		swaps_no_chase = swaps_no_chase,
		swaps_per_minute_in_chase = snappedf(swaps_per_minute(swaps_in_chase), 0.01),
		swaps_per_minute_no_chase = snappedf(swaps_per_minute(swaps_no_chase), 0.01),
		quick_swaps = quick_swaps,
		standing_still_seconds = snappedf(standing_still_seconds, 0.1),
		objectives = objectives,
		ejections_near_objective = ejections_near_objective,
		rush_seconds = snappedf(rush_seconds, 0.1),
		toll_paid_percent_of_max = snappedf(toll_paid, 0.1),
		outcome = outcome if outcome != "" else "abandoned",
		death_cause = death_cause if death_cause != "" else null,
	}


## Ends the run: writes the summary and closes the file.
func close() -> void:
	if _closed:
		return
	_closed = true
	add("run_end", summary())
	if _file != null:
		_file.close()
		_file = null


func _describe(type: String, data: Dictionary) -> String:
	match type:
		"swap":
			var how := "gaze" if data.trigger == "gaze" else "swap-now key"
			var text := "swap %s to %s (%s)" % [data.from_map, data.to_map, how]
			if data.seconds_since_branch_entered != null:
				text += ", %.1f s after entering the branch" % data.seconds_since_branch_entered
			if data.chase:
				text += " · chased"
				if data.get("chaser_distance_m") != null:
					text += ", monster %.1f m behind" % data.chaser_distance_m
			if data.quick:
				text += " · quick"
			return text
		"dead_end_branch_entered":
			return "entered a dead-end branch in map %s" % data.map
		"run_start":
			return "run started, seed %d" % data.seed
		"item_picked_up":
			return "picked up a %s" % data.item.replace("_", " ")
		"item_used":
			return "used a %s" % data.item.replace("_", " ")
		"hit":
			return "hit%s, fill %.0f" % [" (heavy)" if data.heavy else "", data.fill]
		"objective_activated":
			return "activated map %s's objective: collapse" % data.map
		"collapse_escaped":
			return "escaped the collapse after %.1f s, toll %.1f" % [data.rush_seconds, data.toll]
		"monster_state":
			return "monster %d in map %s: %s" % [data.monster, data.map, data.state]
	return type
