extends Node3D

@export var respawn_rate: float = 2.0  # Seconds between respawns
@export var speed: float = 10.0
@export var max_lifetime: float = 5.0  # Seconds before auto-deleting if no collision
@export var fireball_entity: RigidBody3D  # Assign the RigidBody3D child in the inspector

# New export variables for direction control
@export var direction_x: float = 0.0
@export var direction_y: float = 0.0
@export var direction_z: float = 1.0

# New export variables for sound and particles
@export var collision_sound: AudioStreamPlayer3D
@export var collision_particle_emitter_1: GPUParticles3D
@export var collision_particle_emitter_2: GPUParticles3D
@export var collision_particle_emitter_3: GPUParticles3D

var original_position: Vector3
var original_rotation: Basis
var has_collided: bool = false
var distance_traveled: float = 0.0
var start_position: Vector3
var raycast: RayCast3D
var direction_vector: Vector3
var fireball_template: RigidBody3D  # Store a copy for respawning
var lifetime_timer: Timer  # Timer for auto-deletion

func _ready():
	if fireball_entity == null:
		# Try to find the RigidBody3D child if not assigned
		for child in get_children():
			if child is RigidBody3D:
				fireball_entity = child
				break
	
	if fireball_entity == null:
		push_error("Fireball entity not assigned and no RigidBody3D child found!")
		return
	
	# Store a duplicate as a template (not in the scene tree)
	fireball_template = fireball_entity.duplicate()
	
	# Find the RayCast3D child of the fireball_entity
	for child in fireball_entity.get_children():
		if child is RayCast3D:
			raycast = child
			break
	
	if raycast == null:
		push_warning("No RayCast3D found as child of fireball_entity. Using RigidBody collision detection only.")
	
	original_position = fireball_entity.global_position
	original_rotation = fireball_entity.global_transform.basis
	start_position = fireball_entity.global_position
	
	# Create direction vector from export variables
	direction_vector = Vector3(direction_x, direction_y, direction_z).normalized()
	
	# Connect collision signal
	if not fireball_entity.body_entered.is_connected(_on_body_entered):
		fireball_entity.body_entered.connect(_on_body_entered)
	
	# Set up physics properties
	fireball_entity.gravity_scale = 0.0  # No gravity for fireball
	fireball_entity.continuous_cd = true  # Continuous collision detection
	
	# ENABLE CONTACT MONITORING - THIS IS CRITICAL!
	fireball_entity.contact_monitor = true
	fireball_entity.max_contacts_reported = 1  # At least 1, can be higher
	
	# Create and start lifetime timer
	start_lifetime_timer()
	
	# Start moving
	start_movement()

func start_lifetime_timer():
	# Create a new timer for this fireball's lifetime
	lifetime_timer = Timer.new()
	add_child(lifetime_timer)
	lifetime_timer.wait_time = max_lifetime
	lifetime_timer.one_shot = true
	lifetime_timer.timeout.connect(_on_lifetime_timeout)
	lifetime_timer.start()

func _on_lifetime_timeout():
	if not has_collided:
		destroy_fireball()

func start_movement():
	if fireball_entity:
		# Use the custom direction vector instead of the transform's forward direction
		fireball_entity.linear_velocity = direction_vector * speed

func _physics_process(delta):
	if has_collided or fireball_entity == null:
		return
	
	# Check RayCast for collisions if available
	if raycast and raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider and not has_collided:
			has_collided = true
			handle_collision(collider)
			return
		
	# Calculate distance traveled
	distance_traveled = start_position.distance_to(fireball_entity.global_position)

func _on_body_entered(body):
	if has_collided or fireball_entity == null:
		return
		
	has_collided = true
	handle_collision(body)

func handle_collision(body):
	# Stop the lifetime timer since we collided
	if lifetime_timer and lifetime_timer.is_inside_tree():
		lifetime_timer.stop()
	
	# Position effects at collision point before playing
	position_effects_at_collision()
	
	# Play collision effects
	play_collision_effects()
	
	# Check if we hit something in the player_global group
	if body.is_in_group("player_global"):
		destroy_fireball()
	else:
		# Hit a wall or other object
		destroy_fireball()

func position_effects_at_collision():
	# Position all effects at the fireball's current position
	var collision_position = fireball_entity.global_position
	
	if collision_sound:
		collision_sound.global_position = collision_position
	
	if collision_particle_emitter_1:
		collision_particle_emitter_1.global_position = collision_position
	
	if collision_particle_emitter_2:
		collision_particle_emitter_2.global_position = collision_position
	
	if collision_particle_emitter_3:
		collision_particle_emitter_3.global_position = collision_position

func play_collision_effects():
	# Play collision sound if assigned
	if collision_sound:
		if not collision_sound.playing:
			collision_sound.play()
		else:
			collision_sound.stop()
			collision_sound.play()
	
	# Emit particles if assigned
	if collision_particle_emitter_1:
		collision_particle_emitter_1.one_shot = true
		collision_particle_emitter_1.emitting = true
	
	if collision_particle_emitter_2:
		collision_particle_emitter_2.one_shot = true
		collision_particle_emitter_2.emitting = true
	
	if collision_particle_emitter_3:
		collision_particle_emitter_3.one_shot = true
		collision_particle_emitter_3.emitting = true

func destroy_fireball():
	if fireball_entity == null:
		return
	
	# Stop and clean up lifetime timer
	if lifetime_timer and lifetime_timer.is_inside_tree():
		lifetime_timer.stop()
		lifetime_timer.queue_free()
	
	# Actually remove the fireball from the scene
	fireball_entity.queue_free()
	fireball_entity = null
	raycast = null
	
	# Schedule respawn
	get_tree().create_timer(respawn_rate).timeout.connect(_on_respawn_timer_timeout)

func _on_respawn_timer_timeout():
	respawn_fireball()

func respawn_fireball():
	# Create a new instance from the template
	fireball_entity = fireball_template.duplicate()
	add_child(fireball_entity)
	
	# Find the RayCast3D child again
	for child in fireball_entity.get_children():
		if child is RayCast3D:
			raycast = child
			break
	
	# Set position and rotation
	fireball_entity.global_position = original_position
	fireball_entity.global_transform.basis = original_rotation
	start_position = original_position
	
	# Reset state
	has_collided = false
	distance_traveled = 0.0
	
	# Connect collision signal
	if not fireball_entity.body_entered.is_connected(_on_body_entered):
		fireball_entity.body_entered.connect(_on_body_entered)
	
	# Set up physics properties
	fireball_entity.gravity_scale = 0.0
	fireball_entity.continuous_cd = true
	fireball_entity.contact_monitor = true
	fireball_entity.max_contacts_reported = 1
	
	# Start new lifetime timer
	start_lifetime_timer()
	
	# Start moving
	start_movement()
