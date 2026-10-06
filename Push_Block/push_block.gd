extends AnimatableBody3D
class_name PushBlock

## Grid-locked pushable block.
##
## Moves in discrete GRID_SIZE steps via tween, snapped to the even-coordinate
## grid — the same grid the player and moving platforms use. Being an
## AnimatableBody3D it is a solid obstacle (the player's move raycast stops on it)
## and it is never shoved around by the physics solver, so motion is deterministic.
##
## Pressure plates are NOT handled here: PressurePlate polls the "pushable_blocks"
## group by position (see pressure_plate.gd), so this block only needs to join that
## group.

signal block_pushed(direction: Vector3)
signal block_reset()
signal block_stuck()

@export var slide_sound: AudioStream
@export var reset_sound: AudioStream
## Played when the block drops through a pit trap. Left empty, DEFAULT_FALL_SOUND
## is used if it exists.
@export var fall_sound: AudioStream
@export var fall_message: String = "The block drops out of sight."
## The fall sound fades out after this long (0 = play it to the end).
@export var fall_sound_seconds: float = 4.0
@export var stuck_message: String = "The block won't budge."
@export var reset_message: String = "The block grinds back into place."
@export var move_duration: float = 0.25   # seconds per one-cell slide
@export var fall_speed: float = 8.0        # units/sec while dropping into a gap
@export var reset_distance: float = 4.0    # how close the player must be to press R

const GRID_SIZE := 2.0
const HALF_HEIGHT := 1.0        # block is 2x2x2, so its centre sits 1.0 above the floor
const WORLD_MASK := 1           # layer 1 = walls, floor, and other blocks
const DEFAULT_FALL_SOUND := "res://Audio/Sound_Effects/Block_Fall.mp3"

var original_position: Vector3
var is_moving: bool = false
## True once the block has dropped through a pit trap to another level. It is
## gone from this one for good (the node stays, hidden, so WorldState remembers).
var has_fallen: bool = false

var _audio: AudioStreamPlayer3D
var _tween: Tween

# A restored position waiting to be applied on a physics frame (see
# apply_persistent_state). null when there is nothing pending.
var _pending_restore = null

func _ready() -> void:
	add_to_group("pushable_blocks")
	add_to_group("interactable")
	add_to_group("persistent")  # WorldState saves/restores our pushed position
	_audio = get_node_or_null("AudioStreamPlayer3D")
	if fall_sound == null and ResourceLoader.exists(DEFAULT_FALL_SOUND):
		fall_sound = load(DEFAULT_FALL_SOUND)
	snap_to_grid()
	original_position = global_position
	# Settle onto the floor in case it was placed over a gap.
	_settle()
	# Idle by default; only runs while a restore is pending.
	set_physics_process(false)

func _physics_process(_delta: float) -> void:
	if _pending_restore != null:
		# ONE assignment, already grid-aligned (in case it was saved mid-slide). With
		# sync_to_physics the node's own transform snaps back to the last physics
		# transform until the next step, so a follow-up snap_to_grid() here would
		# read the OLD position and send that to the server, undoing the restore.
		global_position = _cell_center(_pending_restore)
		_pending_restore = null
		set_physics_process(false)

#region Interaction
func interact() -> void:
	if is_moving or has_fallen:
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
	if is_moving or has_fallen or direction == Vector3.ZERO:
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
	if is_moving or has_fallen:
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

## Drop out of the level through a pit trap that has opened under the block. The
## trap sees to it that a block turns up on the level below.
func fall_away(depth: float) -> void:
	is_moving = true
	has_fallen = true
	_play(fall_sound)
	if fall_sound and _audio and fall_sound_seconds > 0.0 and fall_sound.get_length() > fall_sound_seconds:
		var fade := create_tween()
		fade.tween_interval(maxf(fall_sound_seconds - 1.0, 0.0))
		fade.tween_property(_audio, "volume_db", -40.0, 1.0)
		fade.tween_callback(_audio.stop)
		fade.tween_property(_audio, "volume_db", _audio.volume_db, 0.0)
	_show(fall_message)
	_kill_tween()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "global_position", global_position + Vector3.DOWN * depth,
		sqrt(2.0 * depth / 9.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_vanish)

func _vanish() -> void:
	is_moving = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group("pushable_blocks")
	remove_from_group("interactable")

## Shove the block one cell out of the way, `preferred` way first (the party has
## dropped onto it). Returns false if it is boxed in on every side.
func knock_aside(preferred: Vector3) -> bool:
	if is_moving or has_fallen:
		return false
	var forward := _snap_direction(preferred)
	var side := Vector3(-forward.z, 0, forward.x)
	for direction: Vector3 in [forward, side, -side, -forward]:
		if _is_path_clear(_cell_center(global_position + direction * GRID_SIZE)):
			attempt_push(direction)
			return true
	return false
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
	# The grid is centred on even coordinates (no GridMap half-cell offset).
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

#region Persistence (WorldState contract)
# Persist where the block currently rests (including a spot it slid to or a pit it
# dropped into). `original_position` is NOT saved — it's the authored home the R
# key resets to, and _ready re-derives it from the scene each load.
func get_persistent_state() -> Dictionary:
	var p := global_position
	return {"pos": [p.x, p.y, p.z], "fallen": has_fallen}

func apply_persistent_state(state: Dictionary) -> void:
	if state.get("fallen", false):
		has_fallen = true
		_vanish()
		return
	var arr = state.get("pos", null)
	if arr is Array and arr.size() == 3:
		# This is an AnimatableBody3D with sync_to_physics: the physics server owns
		# its transform, so setting global_position from the idle-frame level-load
		# signal gets reverted on the next tick (the push tween works precisely
		# because it runs in the physics step). Defer the move to _physics_process
		# so it lands on a physics frame and sticks.
		_pending_restore = Vector3(arr[0], arr[1], arr[2])
		set_physics_process(true)
#endregion
