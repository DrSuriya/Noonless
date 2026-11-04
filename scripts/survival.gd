extends Node
## The bar and the items for a run (Stage 4). Walking within pickup_radius_m
## of an item puts it in the first free slot; keys 1 to 3 use a slot. A
## bandage raises the ceiling; a hospital kit raises it more and refills.
## Damage goes through here so a death ends the run with its cause.

signal died(cause: String)

const Bar := preload("res://scripts/bar.gd")
const Inventory := preload("res://scripts/inventory.gd")
const MazeBuilder := preload("res://scripts/maze/maze_builder.gd")

var bar: Bar
var inventory: Inventory

var _main: Node
var _player: CharacterBody3D
var _pickup_radius: float


func _ready() -> void:
	_pickup_radius = Tuning.get_value("items", "pickup_radius_m")


func start_run(main: Node, player: CharacterBody3D) -> void:
	_main = main
	_player = player
	bar = Bar.new(Tuning.config)
	inventory = Inventory.new(Tuning.config)
	player.bar = bar


func _physics_process(_delta: float) -> void:
	if _main == null or bar.is_dead():
		return
	_pick_up_items()


func _unhandled_input(event: InputEvent) -> void:
	if _main == null:
		return
	for i in inventory.slots.size():
		if event.is_action_pressed("use_slot_%d" % (i + 1)):
			use_slot(i)


func use_slot(slot: int) -> void:
	var kind := inventory.take(slot)
	match kind:
		Inventory.BANDAGE:
			bar.use_bandage()
		Inventory.HOSPITAL_KIT:
			bar.use_hospital_kit()
		_:
			return
	_main.swap_controller.event_log.add("item_used", {item = kind, fill = snappedf(bar.fill, 0.1), ceiling = snappedf(bar.ceiling, 0.1)})


## A monster hit. Ends the run if it empties the fill.
func damage(heavy: bool, cause: String) -> void:
	if bar.is_dead():
		return
	bar.hit(heavy)
	_main.swap_controller.event_log.add("hit", {cause = cause, heavy = heavy, fill = snappedf(bar.fill, 0.1), ceiling = snappedf(bar.ceiling, 0.1)})
	if bar.is_dead():
		died.emit(cause)


func _pick_up_items() -> void:
	var map_index: int = _main.swap_controller.current_map
	var m = _main.maps[map_index]
	for i in m.items.size():
		var item: Dictionary = m.items[i]
		if item.taken:
			continue
		var pos: Vector3 = _main.map_origin(map_index) + MazeBuilder.cell_position(item.cell, _main.params)
		var gap := Vector2(pos.x - _player.global_position.x, pos.z - _player.global_position.z)
		if gap.length() > _pickup_radius or not inventory.add(item.kind):
			continue
		item.taken = true
		var node: Node = _main.map_node(map_index).get_node("Items/Item%d" % i)
		node.queue_free()
		_main.swap_controller.event_log.add("item_picked_up", {item = item.kind, map = String.chr(65 + map_index)})
