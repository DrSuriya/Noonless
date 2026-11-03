extends SceneTree
## Headless tests for the bar, movement and items (roadmap Stage 4).
##
## Run from the project folder:
##     godot --headless --path . -s res://tests/test_bar.gd
## Prints each check and exits with the number of failures (0 = all passed).

const ErrorCounter := preload("res://tests/error_counter.gd")
const Bar := preload("res://scripts/bar.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")

var _failures := 0
var _errors := ErrorCounter.new()
var _cfg := ConfigFile.new()


func _initialize() -> void:
	_run()


func _run() -> void:
	OS.add_logger(_errors)
	_check(_cfg.load("res://config/tuning.cfg") == OK, "config/tuning.cfg loads")
	_test_bar_rules()
	await _test_movement()
	await _test_items()
	OS.remove_logger(_errors)
	_check(_errors.count == 0, "no errors during the tests (%d; first: %s)" % [_errors.count, _errors.first])
	print("\n%s (%d failed)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	quit(_failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _near(a: float, b: float, tolerance := 0.05) -> bool:
	return absf(a - b) <= tolerance


func _seconds(s: float) -> void:
	for i in ceili(s * Engine.physics_ticks_per_second):
		await physics_frame


func _test_bar_rules() -> void:
	var bar := Bar.new(_cfg)
	_check(bar.fill == 100.0 and bar.ceiling == 100.0, "a new bar is full")

	bar.fill = 0.0
	bar.regenerate(30.0)
	_check(_near(bar.fill, 50.0), "regeneration refills half the bar in 30 s (60 s for all of it): %.1f" % bar.fill)
	bar.regenerate(60.0)
	_check(bar.fill == 100.0, "regeneration stops at the ceiling")

	bar.fill = 100.0
	bar.drain_sprint(7.5)
	_check(_near(bar.fill, 50.0), "sprinting drains half a full bar in 7.5 s (15 s for all of it): %.1f" % bar.fill)
	var still_can := bar.drain_sprint(60.0)
	_check(bar.fill == bar.sprint_floor and not still_can and not bar.is_dead(),
		"sprinting stops at the floor (%.0f) and can't kill (D17 lean)" % bar.sprint_floor)

	bar = Bar.new(_cfg)
	bar.hit(false)
	_check(bar.fill == 75.0 and bar.ceiling == 100.0, "a hit takes 25 off the fill")
	bar.hit(true)
	_check(bar.fill == 50.0 and bar.ceiling == 90.0, "a heavy hit also takes 10 off the ceiling")
	bar.fill = 90.0
	bar.lower_ceiling(30.0)
	_check(bar.ceiling == 60.0 and bar.fill == 60.0, "lowering the ceiling pulls the fill down with it")
	bar.regenerate(100.0)
	_check(bar.fill == 60.0, "the fill can't regenerate past the ceiling")

	bar.use_bandage()
	_check(bar.ceiling == 70.0 and bar.fill == 60.0, "a bandage raises the ceiling by 10 and leaves the fill")
	bar.use_hospital_kit()
	_check(bar.ceiling == 100.0 and bar.fill == 100.0, "a hospital kit raises the ceiling by 40 (capped at 100) and refills")
	bar.lower_ceiling(50.0)
	bar.heal_wounds()
	_check(bar.ceiling == 100.0, "clearing a map heals the ceiling")

	bar = Bar.new(_cfg)
	for i in 4:
		bar.hit(false)
	_check(bar.is_dead(), "four hits empty the fill, which kills")


## Speeds and the sprint floor, in the Stage 1 test room's open space.
func _test_movement() -> void:
	var room: Node = load("res://scenes/test_room.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var player: CharacterBody3D = room.get_node("Player")
	var bar := Bar.new(_cfg)
	player.bar = bar
	var start := Vector3(0, 0, 8)

	player.place(start, 0.0)
	await _seconds(0.1)
	Input.action_press("move_forward")
	await _seconds(1.0)
	_check(_near((player.global_position - start).length(), 3.0, 0.15), "walking covers 3 m in 1 s: %.2f m" % (player.global_position - start).length())
	_check(bar.fill == 100.0, "walking doesn't drain the bar")

	player.place(start, 0.0)
	Input.action_press("sprint")
	await _seconds(1.0)
	_check(_near((player.global_position - start).length(), 5.5, 0.2), "sprinting covers 5.5 m in 1 s: %.2f m" % (player.global_position - start).length())
	_check(_near(bar.fill, 100.0 - 100.0 / 15.0, 0.5), "a second of sprinting costs a fifteenth of the bar: %.1f" % bar.fill)
	Input.action_release("sprint")

	player.place(start, 0.0)
	Input.action_press("crouch")
	await _seconds(1.0)
	_check(_near((player.global_position - start).length(), 1.5, 0.15), "crouching covers 1.5 m in 1 s: %.2f m" % (player.global_position - start).length())
	_check(_near(player.eye_position().y, 1.0, 0.05), "crouching lowers the eyes to 1 m: %.2f" % player.eye_position().y)
	Input.action_press("sprint")
	await _seconds(0.3)
	_check(not player.sprinting, "you can't sprint while crouching")
	Input.action_release("sprint")
	Input.action_release("crouch")
	await _seconds(0.5)
	_check(_near(player.eye_position().y, 1.6, 0.05), "standing up raises the eyes back to 1.6 m")

	player.place(start, 0.0)
	bar.fill = 12.0
	Input.action_press("sprint")
	await _seconds(1.0)
	_check(not player.sprinting, "sprinting stops when the fill reaches the floor")
	await _seconds(0.5)
	_check(not player.sprinting and bar.fill > bar.sprint_floor,
		"holding sprint at the floor stays at walking pace while the fill regenerates")
	Input.action_release("sprint")
	await _seconds(0.05)
	Input.action_press("sprint")
	await _seconds(0.05)
	_check(player.sprinting, "releasing and pressing sprint again sprints once the fill is above the floor")
	Input.action_release("sprint")

	player.place(start, 0.0)
	bar.fill = 50.0
	player.rushing = true
	player.speed_multiplier = 1.25
	Input.action_press("sprint")
	await _seconds(1.0)
	_check(bar.fill >= 50.0, "sprinting while rushing costs nothing")
	_check(_near((player.global_position - start).length(), 5.5 * 1.25, 0.25),
		"the rush multiplier speeds up sprinting: %.2f m in 1 s" % (player.global_position - start).length())
	Input.action_release("sprint")
	Input.action_release("move_forward")
	room.queue_free()
	await process_frame


## Pickups and item use in a real run.
func _test_items() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.write_event_log = false
	root.add_child(main)
	await process_frame
	main.generate(777)
	await physics_frame
	var player: CharacterBody3D = main.get_node("Player")
	var survival: Node = main.survival
	var m = main.maps[0]
	var item: Dictionary = m.items[0]

	player.place(main.map_origin(0) + MazeBuilder.cell_position(item.cell, main.params), 0.0)
	await _seconds(0.1)
	_check(item.taken and survival.inventory.slots[0] == item.kind, "walking onto a %s picks it up into slot 1" % item.kind)
	_check(not main.map_node(0).get_node("Items").has_node("Item0"), "the picked-up item is gone from the map")
	_check(main.swap_controller.event_log.recent[0].contains("picked up a"), "the pickup is in the event log: " + main.swap_controller.event_log.recent[0])

	survival.bar.lower_ceiling(50.0)
	var ceiling_before: float = survival.bar.ceiling
	survival.use_slot(0)
	_check(survival.bar.ceiling > ceiling_before and survival.inventory.slots[0] == "", "using slot 1 applies the item and empties the slot")

	survival.inventory.slots.fill("bandage")
	var next: Dictionary = m.items[1]
	player.place(main.map_origin(0) + MazeBuilder.cell_position(next.cell, main.params), 0.0)
	await _seconds(0.1)
	_check(not next.taken, "with every slot full, an item stays where it lies")

	main.swap_controller.swap("test")
	main.swap_controller.swap("test")
	_check(item.taken and not main.map_node(0).get_node("Items").has_node("Item0"),
		"a taken item stays gone after swapping away and back")

	var hits := 0
	while not survival.bar.is_dead() and hits < 10:
		survival.damage(false, "test")
		hits += 1
	_check(survival.bar.is_dead() and hits == 4, "four hits from full kill (%d hits)" % hits)
	main.queue_free()
	await process_frame
