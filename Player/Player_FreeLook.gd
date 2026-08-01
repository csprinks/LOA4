class_name PlayerFreeLook
extends Node

## Hold the right mouse button while standing still to glance around the current
## tile (up/down, left/right) without changing the grid facing. Releasing eases
## the view back to centre. Adapted from LOA2 (automap-state dependency removed).

# How far the view can swing from centre, in degrees.
const YAW_LIMIT := 80.0    # left / right
const PITCH_LIMIT := 60.0  # up / down

# Degrees of camera swing per pixel of mouse motion.
const MOUSE_SENSITIVITY := 0.15

# Seconds to ease the camera back to centre when free look ends.
const RESET_TIME := 0.2

# The Node3D that parents the camera; we rotate it rather than the player body so
# the grid facing (and movement) is unaffected.
var camera_controller: Node3D
var movement_system: PlayerMovement

var is_active: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _reset_tween: Tween
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

func _init(controller: Node3D, movement: PlayerMovement):
	camera_controller = controller
	movement_system = movement
	name = "FreeLookSystem"

# Returns true if the event was consumed by free look.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if _can_start():
				_start()
				return true
		elif is_active:
			_stop()
			return true
		return false

	if is_active and event is InputEventMouseMotion:
		_apply_motion(event.relative)
		return true

	return false

func _can_start() -> bool:
	if is_active or not is_instance_valid(camera_controller):
		return false
	# Free look is a "standing still" action: not mid-step, not mid-turn, and only
	# when the player is otherwise free to move (not during dialogue, etc.).
	if movement_system:
		if movement_system.get_is_moving() or movement_system.get_is_turning():
			return false
		if not movement_system.can_move:
			return false
	return true

func _start():
	is_active = true
	_yaw = 0.0
	_pitch = 0.0

	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()

	# Freeze grid movement while looking around; turning is gated in Player_Manager.
	if movement_system:
		movement_system.set_can_move(false)

	# Capture the mouse so motion isn't clipped at the window edge.
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _stop():
	is_active = false
	Input.mouse_mode = _prev_mouse_mode

	if movement_system:
		movement_system.set_can_move(true)

	_reset_camera()

func _apply_motion(relative: Vector2):
	# Mouse right -> look right (negative yaw), mouse up -> look up (positive pitch).
	_yaw = clamp(_yaw - relative.x * MOUSE_SENSITIVITY, -YAW_LIMIT, YAW_LIMIT)
	_pitch = clamp(_pitch - relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)

	if is_instance_valid(camera_controller):
		camera_controller.rotation_degrees = Vector3(_pitch, _yaw, 0.0)

func _reset_camera():
	if not is_instance_valid(camera_controller):
		return

	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()

	_yaw = 0.0
	_pitch = 0.0
	_reset_tween = camera_controller.create_tween()
	_reset_tween.tween_property(camera_controller, "rotation_degrees", Vector3.ZERO, RESET_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func cleanup():
	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()
	if is_active:
		Input.mouse_mode = _prev_mouse_mode
	camera_controller = null
	movement_system = null
