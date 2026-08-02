extends Node
class_name PlayerInteraction

signal interaction_completed(target: Node, interaction_type: String)
signal interaction_failed(reason: String)

static var PROXIMITY_MULTIPLIER = 1.5

const INTERACT_COOLDOWN = 0.5
const MOUSE_INTERACT_DISTANCE = 5.0

# Interaction State
var INTERACT_DISTANCE: float = 2.0
var can_interact = true
var interaction_ray: RayCast3D
var mouse_interaction_ray: RayCast3D

# Reference to player components
var player_body: RigidBody3D
var player_camera: Camera3D

func _init(player: RigidBody3D, camera: Camera3D):
	player_body = player
	player_camera = camera
	name = "InteractionSystem"

func _ready():
	setup_interaction_rays()

func setup_interaction_rays():
	setup_main_interaction_ray()
	setup_mouse_interaction_ray()

func setup_main_interaction_ray():
	interaction_ray = RayCast3D.new()
	interaction_ray.name = "InteractionRay"
	interaction_ray.enabled = true
	# Check both layer 1 (default) and layer 3 (interactables)
	interaction_ray.collision_mask = 5  # 1 (layer 1) + 4 (layer 3) = 5
	interaction_ray.target_position = Vector3.FORWARD * INTERACT_DISTANCE
	player_body.add_child(interaction_ray)

func setup_mouse_interaction_ray():
	if not player_camera:
		push_error("InteractionSystem: No camera provided for mouse interaction")
		return
		
	mouse_interaction_ray = RayCast3D.new()
	mouse_interaction_ray.name = "MouseInteractionRay"
	mouse_interaction_ray.enabled = true
	# Check both layer 1 (default) and layer 3 (interactables)
	mouse_interaction_ray.collision_mask = 5  # 1 (layer 1) + 4 (layer 3) = 5
	mouse_interaction_ray.target_position = Vector3(0, 0, -MOUSE_INTERACT_DISTANCE)
	player_camera.add_child(mouse_interaction_ray)

func update_interaction_ray():
	if is_instance_valid(interaction_ray):
		interaction_ray.global_transform = player_body.global_transform
		interaction_ray.target_position = Vector3.FORWARD * INTERACT_DISTANCE
		
func _process(_delta):
	update_mouse_interaction_ray()

func update_mouse_interaction_ray():
	if not mouse_interaction_ray or not player_camera:
		return
		
	# Update the mouse ray to point from camera through mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	var from = player_camera.project_ray_origin(mouse_pos)
	var to = from + player_camera.project_ray_normal(mouse_pos) * MOUSE_INTERACT_DISTANCE
	
	mouse_interaction_ray.global_position = from
	mouse_interaction_ray.target_position = mouse_interaction_ray.to_local(to)

func check_for_interactables() -> Node:
	if not interaction_ray:
		return null
		
	interaction_ray.force_raycast_update()
	if interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()
		if collider:
			print_debug("Interaction ray hit: ", collider.name, " on layer: ", collider.collision_layer)
		if collider and collider.has_method("interact") and not is_interactable_disabled(collider):
			return collider
	return null

func is_interactable_disabled(obj: Node) -> bool:
	if obj is Area3D and obj.has_method("initiate_teleport"):
		return false
		
	# Existing checks
	if "is_opened" in obj and obj.is_opened:
		return true
	if obj.has_meta("interaction_disabled") and obj.get_meta("interaction_disabled"):
		return true
	return false

func try_ray_interaction() -> bool:
	var interactable = check_for_interactables()
	if interactable:
		perform_interaction(interactable, "ray_cast")
		return true
	return false

func handle_mouse_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print_debug("Mouse click detected")
		
		# Check cooldown before processing click
		if not can_interact:
			print_debug("Interaction on cooldown")
			return
		
		if mouse_interaction_ray:
			mouse_interaction_ray.force_raycast_update()
			if mouse_interaction_ray.is_colliding():
				var collider = mouse_interaction_ray.get_collider()
				if collider:
					print_debug("Mouse ray hit: ", collider.name, " on layer: ", collider.collision_layer)
				
				# Look for interactable in the collider or its parents
				var interactable = find_interactable_node(collider)
				if interactable:
					print_debug("Found interactable: ", interactable.name)
					# Check if it's disabled before interacting
					if not is_interactable_disabled(interactable):
						perform_interaction(interactable, "mouse_click")
						start_interaction_cooldown()  # Add cooldown after interaction
					else:
						print_debug("Interactable is disabled")
				else:
					print_debug("No interactable found in hierarchy")
			else:
				print_debug("Mouse ray didn't hit anything")

# New function to find interactable nodes in hierarchy
func find_interactable_node(node: Node) -> Node:
	var current = node
	var depth = 0
	var max_depth = 10  # Prevent infinite loops
	
	while current and depth < max_depth:
		# Check if current node has interact method (REGARDLESS of type)
		if current.has_method("interact"):
			return current
		
		# Check if current node is in interactable group and has interact method
		if current.is_in_group("interactable") and current.has_method("interact"):
			return current
		
		# For Area3D and RigidBody3D, check if they have interact method
		if (current is Area3D or current is RigidBody3D) and current.has_method("interact"):
			return current
		
		# Move up to parent
		current = current.get_parent()
		depth += 1
	
	return null
					
func try_proximity_interaction():
	if not can_interact:
		return false
		
	if get_tree().get_nodes_in_group("interactable").size() == 0:
		return false
		
	var interactables = get_tree().get_nodes_in_group("interactable")
	if interactables.size() == 0:
		return
	
	var closest_interactable = find_closest_valid_interactable(interactables)
	
	if closest_interactable.obj:
		start_interaction_cooldown()
		perform_interaction(closest_interactable.obj, "proximity")

func find_closest_valid_interactable(interactables: Array) -> Dictionary:
	var closest = null
	var min_distance = INTERACT_DISTANCE
	
	for obj in interactables:
		if is_interactable_disabled(obj):
			continue
		
		if not obj.has_method("interact"):
			continue
			
		var distance = player_body.global_position.distance_to(obj.global_position)
		
		if distance < min_distance:
			min_distance = distance
			closest = obj
	
	return {"obj": closest, "distance": min_distance}

func perform_interaction(target: Node, interaction_type: String):
	if target.has_method("interact"):
		target.interact()
		interaction_completed.emit(target, interaction_type)
	else:
		interaction_failed.emit("Target not interactable")

func start_interaction_cooldown():
	can_interact = false
	get_tree().create_timer(INTERACT_COOLDOWN).timeout.connect(func(): 
		can_interact = true
	)

# Public interface methods
func set_can_interact(value: bool):
	can_interact = value

func get_can_interact() -> bool:
	return can_interact

func handle_interact_input() -> bool:
	if not can_interact:
		return false
		
	var ray_interactable = check_for_interactables()
	if ray_interactable:
		perform_interaction(ray_interactable, "keyboard")
		start_interaction_cooldown()  # Add cooldown here too
		return true
	else:
		try_proximity_interaction()
		return true

func cleanup():
	if interaction_ray:
		interaction_ray.queue_free()
	if mouse_interaction_ray:
		mouse_interaction_ray.queue_free()
