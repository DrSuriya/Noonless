extends SceneTree
## Headless test for the playtest tools: a real run writes an event log, and
## tools/summarize_logs.gd reads it back into the report.
##
## Run from the project folder:
##     godot --headless --path . -s res://tests/test_summary.gd
## Prints each check and exits with the number of failures (0 = all passed).

const ErrorCounter := preload("res://tests/error_counter.gd")
const DIR := "user://summary_test"

var _failures := 0
var _errors := ErrorCounter.new()


func _initialize() -> void:
	_run()


func _run() -> void:
	OS.add_logger(_errors)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.generate(555)
	await physics_frame
	var swaps: Node = main.swap_controller
	var log_path: String = swaps.event_log.path
	_check(log_path != "" and FileAccess.file_exists(log_path), "a run writes its event log: " + log_path)

	swaps.swap("swap_now_key")
	await physics_frame
	# A chase swap with the monster close behind.
	var monster: Node3D = main.monsters.in_map(1)[0]
	var player: Node3D = main.get_node("Player")
	monster.global_position = player.global_position + Vector3(0, 0, 3)
	monster._set_state(monster.State.CHASE)
	monster._hit_pause = 100.0  # Close behind, but not hitting.
	await physics_frame
	await physics_frame
	swaps.swap("swap_now_key")
	for i in 5:
		main.survival.damage(false, "test")
	await physics_frame

	DirAccess.make_dir_recursive_absolute(DIR)
	var copy := DIR.path_join("run.jsonl")
	DirAccess.copy_absolute(log_path, ProjectSettings.globalize_path(copy))
	var tools: GDScript = load("res://tools/summarize_logs.gd")
	var files: PackedStringArray = tools.log_files(DIR)
	_check(files.size() == 1, "the summarizer finds the log")
	var report: String = tools.report(files)
	print(report.indent("      "))
	_check(report.contains("Outcome: died (test)"), "the report has the outcome and cause of death")
	_check(report.contains("Swaps: 1 without a chase") and report.contains("1 during a chase"), "the report splits swaps by chase")
	_check(report.contains("Narrow escapes (chased, monster within 5 m): 1"), "the report counts the narrow escape")
	_check(report.contains("Runs with at least one narrow escape: 1 of 1"), "the report checks it against the pass criteria")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.remove_absolute(log_path)
	OS.remove_logger(_errors)
	_check(_errors.count == 0, "no errors during the tests (%d; first: %s)" % [_errors.count, _errors.first])
	print("\n%s (%d failed)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	quit(_failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1
