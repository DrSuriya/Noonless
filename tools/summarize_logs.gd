extends SceneTree
## Summarizes playtest event logs (Section 6.6) into one report.
##
## Run from the project folder:
##     godot --headless --path . -s res://tools/summarize_logs.gd
##     godot --headless --path . -s res://tools/summarize_logs.gd -- /path/to/folder
## With no folder it reads this computer's event logs (user://event_logs).
## Copy each tester's .jsonl files into one folder to summarize a playtest.

const DEFAULT_DIR := "user://event_logs"
## A chase swap with the monster at most this close counts as a narrow
## escape in the report. A reading aid, not a design value.
const NARROW_ESCAPE_M := 5.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else DEFAULT_DIR
	var files := log_files(dir)
	if files.is_empty():
		print("No event logs (.jsonl) in %s" % ProjectSettings.globalize_path(dir))
		quit(1)
		return
	print(report(files))
	quit()


static func log_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".jsonl"):
			out.append(dir.path_join(name))
	out.sort()
	return out


## Reads one log into {file, events, summary}; summary is the run_end entry,
## or null if the run never ended cleanly.
static func read_run(path: String) -> Dictionary:
	var events: Array = []
	var summary: Variant = null
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n", false):
		var entry: Variant = JSON.parse_string(line)
		if entry is Dictionary:
			events.append(entry)
			if entry.type == "run_end":
				summary = entry
	return {file = path.get_file(), events = events, summary = summary}


static func report(files: PackedStringArray) -> String:
	var lines := PackedStringArray()
	var totals := {runs = 0, minutes = 0.0, no_chase = 0, chase = 0, quick = 0, narrow = 0,
		runs_with_narrow = 0, escaped = 0, died = 0, still = 0.0}
	var deaths := {}
	for path in files:
		var run := read_run(path)
		var swaps: Array = run.events.filter(func(e: Dictionary) -> bool: return e.type == "swap")
		var seed_text := "?"
		for e in run.events:
			if e.type == "run_start":
				seed_text = str(int(e.seed))
		lines.append("%s  (seed %s)" % [run.file, seed_text])
		if run.summary == null:
			lines.append("  Didn't end cleanly; %d swaps logged." % swaps.size())
			lines.append("")
			continue
		var s: Dictionary = run.summary
		var minutes: float = maxf(s.run_seconds / 60.0, 0.0001)
		var narrow := swaps.filter(func(e: Dictionary) -> bool:
			return e.chase and e.get("chaser_distance_m") != null and e.chaser_distance_m <= NARROW_ESCAPE_M)
		lines.append("  Outcome: %s%s after %s" % [s.outcome,
			" (%s)" % s.death_cause if s.death_cause != null else "", _clock(s.run_seconds)])
		lines.append("  Swaps: %d without a chase (%.1f/min), %d during a chase (%.1f/min), %d quick" % [
			s.swaps_no_chase, s.swaps_no_chase / minutes, s.swaps_in_chase, s.swaps_in_chase / minutes, s.quick_swaps])
		lines.append("  Narrow escapes (chased, monster within %.0f m): %d" % [NARROW_ESCAPE_M, narrow.size()])
		for letter in s.objectives:
			var o: Dictionary = s.objectives[letter]
			lines.append("  Map %s objective reached at %s (%s in that map)" % [letter, _clock(o.run_seconds), _clock(o.seconds_in_map)])
		for letter in s.ejections_near_objective:
			lines.append("  Ejected near map %s's objective: %d" % [letter, s.ejections_near_objective[letter]])
		if s.rush_seconds > 0.0:
			lines.append("  Rush %s, toll %.0f%% of the bar" % [_clock(s.rush_seconds), s.toll_paid_percent_of_max])
		lines.append("  Standing still: %s (%.0f%% of the run)" % [_clock(s.standing_still_seconds), 100.0 * s.standing_still_seconds / maxf(s.run_seconds, 0.001)])
		lines.append("")
		totals.runs += 1
		totals.minutes += minutes
		totals.no_chase += int(s.swaps_no_chase)
		totals.chase += int(s.swaps_in_chase)
		totals.quick += int(s.quick_swaps)
		totals.narrow += narrow.size()
		totals.runs_with_narrow += 1 if not narrow.is_empty() else 0
		totals.still += s.standing_still_seconds
		if s.outcome == "escaped":
			totals.escaped += 1
		elif s.outcome == "died":
			totals.died += 1
			deaths[s.death_cause] = deaths.get(s.death_cause, 0) + 1

	if totals.runs > 0:
		var all_swaps: int = totals.no_chase + totals.chase
		lines.append("All %d complete runs (%.0f minutes)" % [totals.runs, totals.minutes])
		var causes := PackedStringArray()
		for cause in deaths:
			causes.append("%s %d" % [str(cause).replace("_", " "), deaths[cause]])
		lines.append("  Escaped the collapse: %d   Died: %d%s" % [totals.escaped, totals.died,
			" (%s)" % ", ".join(causes) if not causes.is_empty() else ""])
		lines.append("  Swaps per minute: %.1f without a chase, %.1f during a chase" % [totals.no_chase / totals.minutes, totals.chase / totals.minutes])
		lines.append("  Quick swaps: %d of %d swaps (%.0f%%)" % [totals.quick, all_swaps, 100.0 * totals.quick / maxi(all_swaps, 1)])
		lines.append("  Runs with at least one narrow escape: %d of %d" % [totals.runs_with_narrow, totals.runs])
		lines.append("  Standing still: %.0f%% of play time" % (100.0 * totals.still / (totals.minutes * 60.0)))
		lines.append("")
		lines.append("Section 6.6 pass criteria the logs can speak to:")
		lines.append("  Most sessions produce at least one narrow dead-end escape: %d of %d runs" % [totals.runs_with_narrow, totals.runs])
		lines.append("  Accidental swaps are rare: %d quick swaps (the proxy) of %d" % [totals.quick, all_swaps])
		lines.append("  (Explaining the rule and reacting to the reveal need watching and asking; see docs/playtest_1.md.)")
	return "\n".join(lines)


static func _clock(seconds: float) -> String:
	var whole := int(round(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
