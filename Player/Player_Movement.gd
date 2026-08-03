extends Node
class_name PlayerMovement

## Grid-based first-person movement: discrete 2-unit steps and 90-degree turns,
## both eased with tweens. Adapted from LOA2; teleporter and hazard hooks will be
## re-added in the level-mechanics and traps phases.

signal movement_started(direction: Vector3)
signal movement_finished()
signal turn_started(angle: float)
signal turn_finished()
signal movement_blocked(direction: Vector3, message: String)

# Constants
const GRID_SIZE = 2.0
const TURN_ANGLE = 90.0
const TURN_SPEED = 2.0
const MOVE_SPEED = 3.0
const DIALOGUE_COOLDOWN_TIME = 0.5

# Movement state
var movement_tween: Tween
var is_moving = false
var is_turning = false
var move_direction: Vector3 = Vector3.ZERO
var is_grounded: bool = true
var blocked_direction = Vector3.ZERO
var dialogue_cooldown = false
var dialogue_cooldown_timer = 0.0

# Reference to the player body
var player_body: RigidBody3D
var can_move: bool = true
# True while an external system (e.g. animated stairs) is driving the body's
# position by tween. Suppresses grid input, turning, and the ground-check freeze
# so the scripted motion isn't fought by physics.
var scripted_move: bool = false

func _init(player: RigidBody3D):
	player_body = player
	name = "MovementSystem"

func _ready():
	set_physics_process(true)

func _physics_process(delta: float):
	if dialogue_cooldown:
		dialogue_cooldown_timer -= delta
		if dialogue_cooldown_timer <= 0.0:
			dialogue_cooldown = false

	if not is_turning and can_move:
		handle_movement_input()

func handle_movement_input():
	move_direction = Vector3.ZERO

	if is_grounded:
		if Input.is_action_pressed("move_right"):
			move_direction += Vector3.RIGHT
		if Input.is_action_pressed("move_left"):
			move_direction += Vector3.LEFT
		if Input.is_action_pressed("move_forward"):
			move_direction += Vector3.FORWARD
		if Input.is_action_pressed("move_backward"):
			move_direction += Vector3.BACK

	move_direction = move_direction.normalized()

	if not is_moving and move_direction != Vector3.ZERO and is_grounded:
		if move_direction != blocked_direction or not dialogue_cooldown:
			attempt_move(move_direction)

func handle_turn_input():
	if Input.is_action_just_pressed("turn_right"):
		turn(-TURN_ANGLE)
	elif Input.is_action_just_pressed("turn_left"):
		turn(TURN_ANGLE)

func attempt_move(direction: Vector3):
	if is_moving:
		return

	var move_dir = direction.rotated(Vector3.UP, player_body.rotation.y).normalized()

	# Raycast a full grid cell ahead; anything solid blocks the step.
	var space_state = player_body.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player_body.global_position,
		player_body.global_position + move_dir * GRID_SIZE
	)
	query.exclude = [player_body]
	var result = space_state.intersect_ray(query)

	if not result:
		blocked_direction = Vector3.ZERO
		move(move_dir)
	elif not dialogue_cooldown:
		blocked_direction = direction
		movement_blocked.emit(direction, "You can't go that way.")
		dialogue_cooldown = true
		dialogue_cooldown_timer = DIALOGUE_COOLDOWN_TIME

func move(direction: Vector3):
	is_moving = true
	movement_started.emit(direction)

	var target_position = player_body.global_transform.origin + direction * GRID_SIZE

	movement_tween = player_body.create_tween()
	movement_tween.tween_property(player_body, "global_transform:origin", target_position, 1.0 / MOVE_SPEED).set_trans(Tween.TRANS_QUAD)
	movement_tween.tween_callback(func():
		is_moving = false
		movement_finished.emit()
	)

func turn(angle: float):
	is_turning = true
	turn_started.emit(angle)

	var target_rotation = player_body.rotation_degrees + Vector3(0, angle, 0)

	var tween = player_body.create_tween()
	tween.tween_property(player_body, "rotation_degrees", target_rotation, abs(angle) / (TURN_SPEED * 360)).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		is_turning = false
		turn_finished.emit()
	)

func check_ground():
	# While a scripted move owns the body, keep it frozen (kinematic) so gravity
	# doesn't fight the climb tween.
	if scripted_move:
		return
	var space_state = player_body.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player_body.global_position,
		player_body.global_position + Vector3.DOWN * 1.0
	)
	query.exclude = [player_body]
	var result = space_state.intersect_ray(query)

	if result:
		player_body.set_freeze_enabled(true)
		is_grounded = true
	else:
		player_body.set_freeze_enabled(false)
		is_grounded = false

func set_can_move(value: bool):
	can_move = value

# Begin a scripted, physics-free move (the caller tweens the body's position).
func begin_scripted_move():
	scripted_move = true
	can_move = false
	player_body.set_freeze_enabled(true)

# Hand control back after a scripted move; the next check_ground re-grounds.
func end_scripted_move():
	scripted_move = false
	can_move = true

func get_is_moving() -> bool:
	return is_moving

func get_is_turning() -> bool:
	return is_turning

func teleport_to(position: Vector3, duration: float):
	is_moving = true
	set_can_move(false)

	var tween = player_body.create_tween()
	tween.tween_property(player_body, "global_transform:origin", position, duration)
	tween.tween_callback(func():
		is_moving = false
		movement_finished.emit()
	)
