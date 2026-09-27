extends CharacterBody3D
## First-person controller: walk with WASD, look with the mouse.
## Esc frees the mouse cursor; clicking in the window captures it again.
## Speed and mouse sensitivity come from the [player] section of tuning.cfg.

## Stops the view just short of straight up or down, so it never flips over.
const PITCH_LIMIT := deg_to_rad(89.0)

var _walk_speed: float
var _mouse_sensitivity: float  # Radians per pixel.

@onready var _head: Node3D = $Head


func _ready() -> void:
	_walk_speed = Tuning.get_value("player", "walk_speed_mps")
	_mouse_sensitivity = deg_to_rad(Tuning.get_value("player", "mouse_sensitivity_deg_per_px"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.screen_relative)


## Turns the body left and right and tilts the head up and down.
func look(mouse_delta: Vector2) -> void:
	rotate_y(-mouse_delta.x * _mouse_sensitivity)
	_head.rotation.x = clampf(
		_head.rotation.x - mouse_delta.y * _mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT
	)


## Puts the player at `pos` looking along `yaw` (radians about the y axis),
## level and standing still.
func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	_head.rotation.x = 0.0
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input := Vector2.ZERO
	# Don't walk while typing in a text field (the debug view's seed field).
	if not (get_viewport().gui_get_focus_owner() is LineEdit):
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	velocity.x = direction.x * _walk_speed
	velocity.z = direction.z * _walk_speed
	move_and_slide()
