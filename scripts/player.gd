extends CharacterBody3D
## First-person controller: walk with WASD, sprint with Shift, crouch with
## Ctrl, look with the mouse. Esc frees the mouse cursor; clicking in the
## window captures it again. Speeds and mouse sensitivity come from the
## [player] section of tuning.cfg.
##
## Sprinting drains the bar's fill; when it reaches the bar's floor, sprinting
## stops until the sprint key is released and pressed again. Not sprinting
## lets the fill regenerate. During a collapse (`rushing`) sprinting costs
## nothing and every speed is multiplied by `speed_multiplier`.

## Stops the view just short of straight up or down, so it never flips over.
const PITCH_LIMIT := deg_to_rad(89.0)
## How fast the eyes move between standing and crouching heights, in m/s.
const CROUCH_EYE_SPEED := 4.0

## The run's bar, set by the main scene. Null means no bar (sprinting is free).
var bar: RefCounted
## True during a collapse: unlimited stamina.
var rushing := false
var speed_multiplier := 1.0
## Set each physics frame, for the HUD, the debug overlay and the monsters.
var sprinting := false
var crouching := false

var _walk_speed: float
var _sprint_speed: float
var _crouch_speed: float
var _stand_eye_height: float
var _crouch_eye_height: float
var _mouse_sensitivity: float  # Radians per pixel.
## Set when the fill hits the floor, cleared when the sprint key is released.
var _sprint_spent := false

@onready var _head: Node3D = $Head


func _ready() -> void:
	_walk_speed = Tuning.get_value("player", "walk_speed_mps")
	_sprint_speed = Tuning.get_value("player", "sprint_speed_mps")
	_crouch_speed = Tuning.get_value("player", "crouch_speed_mps")
	_crouch_eye_height = Tuning.get_value("player", "crouch_eye_height_m")
	_stand_eye_height = _head.position.y
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


## Where the camera points, as a unit vector (includes looking up and down).
func look_direction() -> Vector3:
	return -_head.global_transform.basis.z


## The camera's position in the world.
func eye_position() -> Vector3:
	return _head.global_position


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
	var sprint_held := false
	crouching = false
	# Don't move while typing in a text field (the debug view's seed field).
	if not (get_viewport().gui_get_focus_owner() is LineEdit):
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sprint_held = Input.is_action_pressed("sprint")
		crouching = Input.is_action_pressed("crouch")
	if not sprint_held:
		_sprint_spent = false
	var can_sprint: bool = rushing or bar == null or bar.can_sprint()
	sprinting = sprint_held and not crouching and not _sprint_spent and can_sprint and input != Vector2.ZERO

	var speed := _walk_speed
	if crouching:
		speed = _crouch_speed
	elif sprinting:
		speed = _sprint_speed
	speed *= speed_multiplier
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	if bar != null:
		if sprinting and not rushing:
			if not bar.drain_sprint(delta):
				_sprint_spent = true
		elif not sprinting:
			bar.regenerate(delta)
	var eye := _crouch_eye_height if crouching else _stand_eye_height
	_head.position.y = move_toward(_head.position.y, eye, CROUCH_EYE_SPEED * delta)
