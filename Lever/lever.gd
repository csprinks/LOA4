extends StaticBody3D
class_name Lever

enum LeverState {
	UP,
	DOWN
}

# Configuration variables
@export var start_position: LeverState = LeverState.DOWN
@export var connected_platforms: Array[MovingBlockPlatform] = []
@export var connected_doors: Array[DoorGrate] = []  # Doors this lever opens/closes
@export var puzzle_id: String = ""
@export var single_use: bool = false
@export var sound_effect: AudioStream
@export var interaction_distance: float = 3.0
@export var reverse_platform_movement: bool = false  # Reverses platform movement sequence
@export var cooldown_time: float = 1.0  # Cooldown between interactions

# Internal state
var current_state: LeverState
var _player_ref: Node3D = null
var _audio_player: AudioStreamPlayer3D
var _used: bool = false
var is_opened: bool = false  # For interaction system compatibility
var is_reversed: bool = false  # Track if platforms are currently reversed
var can_interact: bool = true  # Cooldown flag
var cooldown_timer: Timer  # Cooldown timer

signal interacted()

func _ready():
	add_to_group("interactable")
	add_to_group("persistent")  # WorldState saves/restores our pulled state
	current_state = start_position
	
	# Create audio player if sound effect is assigned
	if sound_effect:
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.stream = sound_effect
		add_child(_audio_player)
	
	# Create cooldown timer
	cooldown_timer = Timer.new()
	cooldown_timer.one_shot = true
	cooldown_timer.timeout.connect(_on_cooldown_timeout)
	add_child(cooldown_timer)
	
	# Play initial animation to set correct visual state
	_seek_animation_to_state()

func interact():
	# Prevent interaction if on cooldown
	if not can_interact:
		return
	
	# Prevent interaction if single-use and already used
	if single_use and _used:
		ResourceManager.display_text("The lever is stuck.")
		return
	
	# Get player reference
	var player = _get_player_reference()
	if not player:
		return
	
	# Calculate distance to player
	var distance = global_position.distance_to(player.global_position)
	
	# Use a more lenient distance check since clicks can be imprecise
	var effective_distance = interaction_distance * PlayerInteraction.PROXIMITY_MULTIPLIER
	if distance > effective_distance:
		ResourceManager.display_text("Too far away!")
		return
	
	# Start cooldown
	can_interact = false
	cooldown_timer.start(cooldown_time)
	
	_execute_interaction()

func _execute_interaction():
	# Toggle lever state
	if current_state == LeverState.UP:
		current_state = LeverState.DOWN
	else:
		current_state = LeverState.UP
	
	# Play animation
	var anim_player = $AnimationPlayer
	if anim_player:
		if current_state == LeverState.UP:
			if anim_player.has_animation("Lever_up"):
				anim_player.play("Lever_up")
			else:
				push_error("Missing Lever_up animation")
		else:
			if anim_player.has_animation("Lever_down"):
				anim_player.play("Lever_down")
			else:
				push_error("Missing Lever_down animation")
	
	# Play sound if available
	if _audio_player:
		_audio_player.play()

	# Toggle reverse state if this lever reverses platforms
	if reverse_platform_movement:
		is_reversed = !is_reversed

	# Activate connected platforms
	_activate_platforms()

	# Activate connected doors
	_activate_doors()

	interacted.emit()
	
	# Display simplified message
	ResourceManager.display_text("You pull the lever.")
	
	# Mark as used if single-use
	if single_use:
		_used = true
		is_opened = true

# NEW: Function to activate connected doors
func _activate_doors():
	# Activate all connected doors
	for door in connected_doors:
		if door and is_instance_valid(door):
			door.activate()

# Cooldown timeout handler
func _on_cooldown_timeout():
	can_interact = true

func _activate_platforms():
	# Activate all connected platforms
	for platform in connected_platforms:
		if platform and is_instance_valid(platform):
			if platform.activation_type == MovingBlockPlatform.ActivationType.LEVER_TOGGLE:
				# Set platform reverse sequence if this lever controls that
				if reverse_platform_movement:
					platform.set_reverse_sequence(is_reversed)
				platform.activate()
			elif platform.activation_type == MovingBlockPlatform.ActivationType.LEVER_PUZZLE:
				platform._on_lever_toggled()

# Get current lever state (useful for puzzle systems)
func get_state() -> LeverState:
	return current_state

func is_up() -> bool:
	return current_state == LeverState.UP

func is_down() -> bool:
	return current_state == LeverState.DOWN

# Safe player reference getter
func _get_player_reference() -> Node3D:
	# Try existing reference first
	if _player_ref and is_instance_valid(_player_ref):
		return _player_ref
	
	# Fallback: Search for player in scene
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player_ref = players[0]
		return _player_ref
	
	return null

# Reset function for respawning or level reset
func reset():
	current_state = start_position
	_used = false
	is_opened = false
	is_reversed = false
	can_interact = true
	
	# Stop and reset cooldown timer
	if cooldown_timer:
		cooldown_timer.stop()
	
	# Reset animation to starting position
	_seek_animation_to_state()

# Snap the lever mesh to the pose matching current_state, without animating.
func _seek_animation_to_state() -> void:
	var anim_player = $AnimationPlayer
	if not anim_player:
		return
	if current_state == LeverState.UP and anim_player.has_animation("Lever_up"):
		anim_player.play("Lever_up")
		anim_player.seek(anim_player.current_animation_length, true)
	elif current_state == LeverState.DOWN and anim_player.has_animation("Lever_down"):
		anim_player.play("Lever_down")
		anim_player.seek(anim_player.current_animation_length, true)

#region Persistence (WorldState contract)
func get_persistent_state() -> Dictionary:
	return {
		"state": int(current_state),
		"used": _used,
		"reversed": is_reversed,
	}

# Restore the lever's visible pose and flags only. Deliberately does NOT toggle or
# re-fire connected doors/platforms — each of those persists its own state, so the
# world is already coherent on load.
func apply_persistent_state(state: Dictionary) -> void:
	current_state = int(state.get("state", current_state)) as LeverState
	_used = state.get("used", false)
	is_opened = _used
	is_reversed = state.get("reversed", false)
	_seek_animation_to_state()
#endregion
