extends AnimatableBody3D
class_name PushBlock

## Grid-locked pushable block (LOA4 kinematic rewrite of LOA2's RigidBody version).
##
## Moves in discrete GRID_SIZE steps via tween, snapped to LOA4's even-coordinate
## grid — the same grid the player and moving platforms use. Being an
## AnimatableBody3D it is a solid obstacle (the player's move raycast stops on it)
## and it is never shoved around by the physics solver, so motion is deterministic.
##
## Pressure plates are NOT handled here: PressurePlate polls the "pushable_blocks"
## group by position (see pressure_plate.gd), so this block only needs to join that
## group. The LOA2 self-detection raycast that called plate.player_entered() is gone.

signal block_pushed(direction: Vector3)
signal block_reset()
signal block_stuck()

@export var slide_sound: AudioStream
@export var reset_sound: AudioStream
@export var stuck_message: String = "The block won't budge."
@export var reset_message: String = "The block grinds back into place."
@export var move_duration: float = 0.25   # seconds per one-cell slide
@export var fall_speed: float = 8.0        # units/sec while dropping into a gap
@export var reset_distance: float = 4.0    # how close the player must be to press R

const GRID_SIZE := 2.0
const HALF_HEIGHT := 1.0        # block is 2x2x2, so its centre sits 1.0 above the floor
const WORLD_MASK := 1           # layer 1 = walls, floor, and other blocks

var original_position: Vector3
var is_moving: bool = false

var _audio: AudioStreamPlayer3D
var _tween: Tween

func _ready() -> void:
	add_to_group("pushable_blocks")
	add_to_group("interactable")
	_audio = get_node_or_null("AudioStreamPlayer3D")
	snap_to_grid()
	original_position = global_position
	# Settle onto the floor in case it was placed over a gap.
	_settle()

#region Interaction
func interact() -> void:
	if is_moving:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		return
	# Push away from the player, along their (grid-aligned) facing.
	var forward := -player.global_transform.basis.z
	attempt_push(_snap_direction(forward))

func _input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interact()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and not event.echo:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and global_position.distance_to(player.global_position) <= reset_distance:
			reset_block()
#endregion

#region Movement
func attempt_push(direction: Vector3) -> void:
	if is_moving or direction == Vector3.ZERO:
		return
	var target := _cell_center(global_position + direction * GRID_SIZE)
	if not _is_path_clear(target):
		_show(stuck_message)
		block_stuck.emit()
		return
	is_moving = true
	_play(slide_sound)
	_kill_tween()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "global_position", target, move_duration)
	_tween.tween_callback(func() -> void:
		block_pushed.emit(direction)
		# _settle re-sets is_moving if the block must drop into a gap.
		is_moving = false
		_settle()
	)

func reset_block() -> void:
	if is_moving:
		return
	is_moving = true
	_play(reset_sound)
	_show(reset_message)
	_kill_tween()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "global_position", original_position, move_duration)
	_tween.tween_callback(func() -> void:
		is_moving = false
		block_reset.emit()
	)

# Drop straight down until there is floor under the block (push-into-a-pit).
func _settle() -> void:
	if _has_ground_below():
		return
	var floor_y = _floor_below()
	if floor_y == null:
		return  # bottomless: leave it rather than fall forever
	var target := global_position
	target.y = floor_y + HALF_HEIGHT
	var distance := global_position.y - target.y
	if distance <= 0.01:
		return
	is_moving = true
	_kill_tween()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "global_position", target, max(0.05, distance / fall_speed))
	_tween.tween_callback(func() -> void: is_moving = false)
#endregion

#region Queries
func _is_path_clear(target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	# Sample a couple of heights so a low sill or a tall wall both register.
	for h in [0.0, 0.6]:
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * h,
			target + Vector3.UP * h)
		query.exclude = exclude
		query.collision_mask = WORLD_MASK
		if space.intersect_ray(query):
			return false
	return true

func _has_ground_below() -> bool:
	return _floor_below(HALF_HEIGHT + 0.2) != null

# Returns the Y of the first floor below the block, or null if none within `dist`.
func _floor_below(dist: float = 100.0):
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.1,
		global_position + Vector3.DOWN * dist)
	query.exclude = [get_rid()]
	query.collision_mask = WORLD_MASK
	var hit := space.intersect_ray(query)
	if hit:
		return hit.position.y
	return null
#endregion

#region Grid helpers
func _cell_center(pos: Vector3) -> Vector3:
	# LOA4 grid is centred on even coordinates (no GridMap half-cell offset).
	return Vector3(
		round(pos.x / GRID_SIZE) * GRID_SIZE,
		pos.y,
		round(pos.z / GRID_SIZE) * GRID_SIZE)

func snap_to_grid() -> void:
	global_position = _cell_center(global_position)

func _snap_direction(direction: Vector3) -> Vector3:
	var a := direction.abs()
	if a.x >= a.z:
		return Vector3(signf(direction.x), 0, 0)
	return Vector3(0, 0, signf(direction.z))
#endregion

#region Utils
func _play(sound: AudioStream) -> void:
	if sound and _audio:
		_audio.stream = sound
		_audio.play()

func _show(msg: String) -> void:
	if msg != "":
		GameTextBox.display_text(msg)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
#endregion
