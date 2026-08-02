extends CharacterBody3D
class_name MovingBlockPlatform

enum MovementDirection {
	UP,       # +Y (upward)
	DOWN,     # -Y (downward)
	LEFT,     # -X (left)
	RIGHT,    # +X (right)
	FORWARD,  # +Z (forward)
	BACKWARD, # -Z (backward)
	STOP      # Pause
}

enum ActivationType {
	AUTOMATIC,          # Always active
	LEVER_TOGGLE,       # Single lever toggle
	LEVER_PUZZLE,       # Requires specific lever states
	PRESSURE_PLATE      # Controlled by pressure plate
}

@export var movement_sequence: Array[MovementDirection] = [MovementDirection.RIGHT, MovementDirection.STOP]
@export var move_speed: float = 2.0
@export var loop_movement: bool = true
@export var start_automatically: bool = true
@export var require_activation: bool = false

@export var activation_type: ActivationType = ActivationType.AUTOMATIC
@export var puzzle_activator: PuzzleActivator

# Add export variable for pressure plate reference
@export var pressure_plate: PressurePlate  # Assign pressure plate node

var current_sequence_index: int = 0
var is_active: bool = false
var is_moving: bool = false
var grid_size: float = 2.0
var initial_position: Vector3
var movement_tween: Tween
var pingpong_direction: int = 1  # 1 = forward, -1 = backward
# Track if the platform has completed its non-looping sequence
var is_completed: bool = false
var is_reversed: bool = false
# Track the desired reverse state to apply after current movement completes
var pending_reverse_state: bool = false
var has_pending_reverse: bool = false

func _ready():
	initial_position = global_position
	
	# Initialize as inactive by default
	is_active = false
	is_moving = false
	
	# Connect to pressure plate signals if assigned
	if pressure_plate:
		pressure_plate.tile_activated.connect(_on_pressure_plate_activated)
		pressure_plate.tile_deactivated.connect(_on_pressure_plate_deactivated)
	
	# Defer activation checks to ensure levers are initialized first
	call_deferred("initialize_activation")
	
func initialize_activation():
	# Set initial active state based on activation type
	match activation_type:
		ActivationType.AUTOMATIC:
			is_active = true
		ActivationType.LEVER_TOGGLE:
			is_active = false
		ActivationType.LEVER_PUZZLE:
			update_active_state()
		ActivationType.PRESSURE_PLATE:
			is_active = false  # Start inactive, controlled by pressure plate
	
	# Start only if automatic and not requiring activation
	if is_active and (activation_type == ActivationType.AUTOMATIC) and not require_activation:
		execute_next_move()

# Pressure plate signal handlers
func _on_pressure_plate_activated():
	if activation_type == ActivationType.PRESSURE_PLATE:
		is_active = true
		is_reversed = false  # Reset to normal direction
		# Reset sequence index to start from beginning
		current_sequence_index = 0
		# Execute next move if not already moving
		if not is_moving:
			execute_next_move()

func _on_pressure_plate_deactivated():
	if activation_type == ActivationType.PRESSURE_PLATE:
		is_active = true  # Keep platform active but reverse direction
		is_reversed = true  # Set to reverse direction
		# Reset sequence index to start from beginning in reverse
		current_sequence_index = 0
		# Execute next move if not already moving
		if not is_moving:
			execute_next_move()
		
func update_active_state():
	if activation_type != ActivationType.LEVER_PUZZLE:
		return
	
	# Check puzzle solution status
	var should_be_active = puzzle_activator && puzzle_activator.is_puzzle_solved()
	
	# Only change state if different
	if is_active != should_be_active:
		is_active = should_be_active
		if is_active && !is_moving:
			execute_next_move()

# Add this toggle function for lever interaction
func toggle():
	if require_activation:
		is_active = !is_active
		if is_active and not is_moving:
			execute_next_move()

func activate():
	match activation_type:
		ActivationType.LEVER_TOGGLE:
			is_active = !is_active
			if is_active && !is_moving:
				execute_next_move()
		ActivationType.LEVER_PUZZLE:
			update_active_state()
		_: 
			pass
			
	if not is_moving and is_active:
		execute_next_move()
		
func _on_lever_toggled():
	if activation_type == ActivationType.LEVER_PUZZLE:
		update_active_state()

func execute_next_move():
	if movement_sequence.size() == 0:
		return
	
	# Check for pending reverse state before starting movement
	if has_pending_reverse:
		is_reversed = pending_reverse_state
		has_pending_reverse = false
	
	# Add bounds checking to prevent out-of-range errors
	if current_sequence_index >= movement_sequence.size():
		current_sequence_index = 0
	if current_sequence_index < 0:
		current_sequence_index = 0
		
	var direction = movement_sequence[current_sequence_index]
	
	# If we're reversed, get the opposite direction
	if is_reversed and direction != MovementDirection.STOP:
		direction = _get_opposite_direction(direction)
	
	if direction == MovementDirection.STOP:
		# Pause before next move
		is_moving = true
		movement_tween = create_tween()
		movement_tween.tween_interval(1.0 / move_speed)
		movement_tween.tween_callback(_on_move_completed)
	else:
		# Calculate movement vector
		var move_vector = _get_direction_vector(direction) * grid_size
		var target_position = global_position + move_vector
		
		# Create smooth movement tween
		is_moving = true
		movement_tween = create_tween()
		movement_tween.tween_property(self, "global_position", target_position, 1.0 / move_speed)
		movement_tween.tween_callback(_on_move_completed)

# Set the reverse direction for pressure plate control
func set_reverse_direction(reverse: bool):
	is_reversed = reverse

func _on_move_completed():
	is_moving = false
	
	# Check for pending reverse state before updating sequence index
	if has_pending_reverse:
		is_reversed = pending_reverse_state
		has_pending_reverse = false
	
	# Update sequence index based on direction
	if is_reversed:
		# Move backwards through the sequence
		if loop_movement:
			current_sequence_index -= 1
			if current_sequence_index < 0:
				current_sequence_index = movement_sequence.size() - 1
		else:
			current_sequence_index -= 1
			if current_sequence_index < 0:
				is_active = false
				is_completed = true
				return
	else:
		# Original forward movement logic
		if loop_movement:
			current_sequence_index += 1
			if current_sequence_index >= movement_sequence.size():
				current_sequence_index = 0
		else:
			current_sequence_index += 1
			if current_sequence_index >= movement_sequence.size():
				is_active = false
				is_completed = true
				return
	
	# Execute next move if active
	if is_active and not is_moving:
		execute_next_move()

func _get_direction_vector(direction: MovementDirection) -> Vector3:
	match direction:
		MovementDirection.UP:
			return Vector3.UP        # +Y (upward)
		MovementDirection.DOWN:
			return Vector3.DOWN      # -Y (downward)
		MovementDirection.LEFT:
			return Vector3.LEFT      # -X (left)
		MovementDirection.RIGHT:
			return Vector3.RIGHT     # +X (right)
		MovementDirection.FORWARD:
			return Vector3.FORWARD   # +Z (forward)
		MovementDirection.BACKWARD:
			return Vector3.BACK      # -Z (backward)
		_:
			return Vector3.ZERO

func reset():
	if movement_tween and movement_tween.is_valid():
		movement_tween.kill()
	current_sequence_index = 0
	pingpong_direction = 1
	is_moving = false
	is_completed = false  # Reset completion state
	is_reversed = false  # Reset reverse state
	has_pending_reverse = false  # Clear any pending reverse
	global_position = initial_position
	
	# Reset active state based on requirements
	if start_automatically and not require_activation:
		is_active = true
		execute_next_move()
	else:
		is_active = false

# NOTE: LOA2 had an _on_body_entered() + _physics_process() velocity pair here
# meant to carry a rider, but CharacterBody3D has no body_entered signal and it
# was never connected — velocity stayed zero. Dropped as dead code. The platform
# moves purely by tweening global_position, so it acts as a sliding obstacle
# (open/close a path), not an elevator you stand on.

# Clean up tween when platform is removed
func _exit_tree():
	if movement_tween and movement_tween.is_valid():
		movement_tween.kill()
		
func reverse_movement_sequence() -> Array[MovementDirection]:
	var reversed_sequence: Array[MovementDirection] = []
	
	# Create a reversed sequence with opposite directions
	for i in range(movement_sequence.size() - 1, -1, -1):
		var original_direction = movement_sequence[i]
		var opposite_direction = _get_opposite_direction(original_direction)
		reversed_sequence.append(opposite_direction)
	
	return reversed_sequence

# Add this function to get the opposite direction
func _get_opposite_direction(direction: MovementDirection) -> MovementDirection:
	match direction:
		MovementDirection.UP:
			return MovementDirection.DOWN
		MovementDirection.DOWN:
			return MovementDirection.UP
		MovementDirection.LEFT:
			return MovementDirection.RIGHT
		MovementDirection.RIGHT:
			return MovementDirection.LEFT
		MovementDirection.FORWARD:
			return MovementDirection.BACKWARD
		MovementDirection.BACKWARD:
			return MovementDirection.FORWARD
		MovementDirection.STOP:
			return MovementDirection.STOP
		_:
			return direction

# Add this function to set the reverse sequence
func set_reverse_sequence(reverse: bool):
	if reverse:
		# Store the original sequence if we haven't already
		if not has_meta("original_sequence"):
			set_meta("original_sequence", movement_sequence.duplicate())
		
		# Use the reversed sequence
		movement_sequence = reverse_movement_sequence()
	else:
		# Restore the original sequence
		if has_meta("original_sequence"):
			movement_sequence = get_meta("original_sequence")
	
	# Reset to start from the beginning of the new sequence
	current_sequence_index = 0
