extends Node3D
class_name PressurePlate

signal tile_activated
signal tile_deactivated

# Export an array of MovingBlockPlatform nodes to control
@export var connected_platforms: Array[MovingBlockPlatform] = []

var is_active = false
var is_cooldown = false

# Reference to player for raycast detection
var player: Player = null
var player_was_standing = false

# Track push blocks
var push_blocks_on_plate: Array[Node3D] = []
var push_blocks_were_on_plate: Array[Node3D] = []

# Cooldown timer to prevent spamming
var cooldown_timer: Timer

func _ready():
	print("PressurePlate ready at world position: ", global_position)
	
	# Create cooldown timer
	cooldown_timer = Timer.new()
	cooldown_timer.one_shot = true
	cooldown_timer.timeout.connect(_on_cooldown_timeout)
	add_child(cooldown_timer)
	
	# Find the player in the scene
	find_player()
	
	# Verify signal connections to platforms
	call_deferred("verify_platform_connections")

func find_player():
	player = get_tree().get_first_node_in_group("player")
	if player:
		print("PressurePlate found player: ", player.name)
	else:
		print("PressurePlate: No player found in group 'player'")
		# Try again after a short delay
		get_tree().create_timer(1.0).timeout.connect(find_player)

func verify_platform_connections():
	print("=== Verifying Platform Connections ===")
	for platform in connected_platforms:
		if platform and is_instance_valid(platform):
			var is_connected_activate = tile_activated.is_connected(platform._on_pressure_plate_activated)
			var is_connected_deactivate = tile_deactivated.is_connected(platform._on_pressure_plate_deactivated)
			print("Platform: ", platform.name, 
				  " | Activate Connected: ", is_connected_activate,
				  " | Deactivate Connected: ", is_connected_deactivate,
				  " | Activation Type: ", platform.activation_type)
	print("=====================================")

func _process(_delta):
	# Skip processing if in cooldown
	if is_cooldown:
		return
	
	# Check if player or push blocks are standing on this plate
	check_player_standing()
	check_push_blocks_standing()

func check_player_standing():
	if not player or not is_instance_valid(player):
		# Try to find player again if missing
		if player_was_standing:
			force_player_exited()
		find_player()
		return
	
	# Check if player is grounded and positioned above this pressure plate
	var player_is_standing = player.can_move() and is_object_above_plate(player)
	
	# Only trigger state changes when the standing state actually changes
	if player_is_standing != player_was_standing:
		if player_is_standing:
			player_entered()
		else:
			player_exited()
		
		player_was_standing = player_is_standing

func check_push_blocks_standing():
	# Skip if in cooldown
	if is_cooldown:
		return
		
	# Get all push blocks in the scene
	var push_blocks = get_tree().get_nodes_in_group("pushable_blocks")
	var current_blocks_on_plate: Array[Node3D] = []
	
	# Check which push blocks are currently on the plate
	for block in push_blocks:
		if block and is_instance_valid(block) and is_object_above_plate(block):
			current_blocks_on_plate.append(block)
	
	# Check for blocks that just entered
	for block in current_blocks_on_plate:
		if not push_blocks_were_on_plate.has(block):
			push_block_entered(block)
	
	# Check for blocks that just exited
	for block in push_blocks_were_on_plate:
		if not current_blocks_on_plate.has(block):
			push_block_exited(block)
	
	# Update the previous state
	push_blocks_were_on_plate = current_blocks_on_plate.duplicate()

func is_object_above_plate(object: Node3D) -> bool:
	if not object:
		return false
	
	var object_pos = object.global_position
	var plate_pos = global_position
	
	# Check if object is within the bounds of the pressure plate
	# Using a slightly smaller detection area to prevent edge flickering
	var plate_size = 1.8  # Slightly smaller than the visual plate
	var half_size = plate_size / 2.0
	
	var in_x_range = abs(object_pos.x - plate_pos.x) <= half_size
	var in_z_range = abs(object_pos.z - plate_pos.z) <= half_size
	
	# Also check if object is close enough vertically (on top of the plate)
	var vertical_distance = abs(object_pos.y - plate_pos.y)
	var max_vertical_distance = 3.0  # Adjust based on your scene setup
	
	return in_x_range and in_z_range and vertical_distance <= max_vertical_distance

# Handle player stepping on the pressure plate
func player_entered():
	print("Player entered pressure plate area")
	
	if not is_active and not is_cooldown:
		is_active = true
		print("Pressure plate activated. Connected platforms: ", connected_platforms.size())
		tile_activated.emit()
		activate_tile()
		# Start cooldown to prevent spamming
		start_cooldown()
		# Set connected platforms to move in normal direction
		set_platforms_direction(false)  # false = normal direction

# Handle player leaving the pressure plate
func player_exited():
	print("Player exited pressure plate area")
	
	# Only deactivate if no push blocks are still on the plate and not in cooldown
	if is_active and push_blocks_on_plate.is_empty() and not is_cooldown:
		is_active = false
		print("Pressure plate deactivated.")
		tile_deactivated.emit()
		deactivate_tile()
		# Start cooldown to prevent spamming
		start_cooldown()
		# Set connected platforms to move in reverse direction
		set_platforms_direction(true)   # true = reverse direction

# Handle push block stepping on the pressure plate
func push_block_entered(block: Node3D):
	print("Push block entered pressure plate area: ", block.name)
	push_blocks_on_plate.append(block)
	
	if not is_active and not is_cooldown:
		is_active = true
		print("Pressure plate activated by push block. Connected platforms: ", connected_platforms.size())
		tile_activated.emit()
		activate_tile()
		# Start cooldown to prevent spamming
		start_cooldown()
		set_platforms_direction(false)  # false = normal direction

# Handle push block leaving the pressure plate
func push_block_exited(block: Node3D):
	print("Push block exited pressure plate area: ", block.name)
	push_blocks_on_plate.erase(block)
	
	# Only deactivate if no objects are still on the plate and not in cooldown
	if is_active and push_blocks_on_plate.is_empty() and not player_was_standing and not is_cooldown:
		is_active = false
		print("Pressure plate deactivated.")
		tile_deactivated.emit()
		deactivate_tile()
		# Start cooldown to prevent spamming
		start_cooldown()
		set_platforms_direction(true)   # true = reverse direction

# Start cooldown period to prevent spamming
func start_cooldown():
	is_cooldown = true
	# Set cooldown time (adjust as needed - this waits for platforms to finish + 1 second buffer)
	cooldown_timer.start(1.0)  # 2 seconds should be enough for most platforms

func _on_cooldown_timeout():
	is_cooldown = false
	print("Pressure plate cooldown ended")
	# Check current state after cooldown to handle any missed state changes
	check_state_after_cooldown()

# Check the current state after cooldown to handle any state changes that occurred during cooldown
func check_state_after_cooldown():
	var should_be_active = player_was_standing or not push_blocks_on_plate.is_empty()
	
	if should_be_active != is_active:
		if should_be_active and not is_active:
			# Should be active but isn't
			is_active = true
			print("Pressure plate activated after cooldown.")
			tile_activated.emit()
			activate_tile()
			set_platforms_direction(false)
		elif not should_be_active and is_active:
			# Should be inactive but isn't
			is_active = false
			print("Pressure plate deactivated after cooldown.")
			tile_deactivated.emit()
			deactivate_tile()
			set_platforms_direction(true)

# Force immediate state change (used when player is lost)
func force_player_exited():
	player_was_standing = false
	if is_active and push_blocks_on_plate.is_empty() and not is_cooldown:
		player_exited()

# Set the movement direction for all connected platforms
func set_platforms_direction(should_reverse: bool):
	print("Setting platforms direction - reverse: ", should_reverse)
	for platform in connected_platforms:
		if platform and is_instance_valid(platform):
			print("Setting platform ", platform.name, " to reverse: ", should_reverse)
			# Only set reverse direction - the signal handlers handle activation
			platform.set_reverse_direction(should_reverse)

func activate_tile():
	# Add your tile activation logic here
	# For example: change material, play sound, trigger animation, etc.
	# You could change the mesh material to indicate activation
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		# Change to activated material
		pass

func deactivate_tile():
	# Add your tile deactivation logic here
	# For example: revert material, stop sound, reset animation, etc.
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		# Change to deactivated material
		pass
