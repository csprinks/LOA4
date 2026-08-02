# Player_Manager.gd
extends RigidBody3D
class_name Player

## Lean first-person grid-crawler player. Orchestrates the movement and free-look
## subsystems. Adapted from LOA2's componentized player; the automap camera, HUD,
## character data, interaction, and signal-manager layers are re-added in their
## own porting phases.

signal player_moved(direction)

@export var player_camera: Camera3D

# System components
var movement_system: PlayerMovement
var free_look_system: PlayerFreeLook
var interaction_system: PlayerInteraction

#region Initialization
func _ready():
	initialize_physics()
	setup_node_groups()
	validate_required_nodes()
	setup_systems()
	connect_signals()

func initialize_physics():
	set_physics_process(true)
	set_freeze_enabled(true)
	collision_layer = 1
	collision_mask = 2

func setup_node_groups():
	add_to_group("player")
	add_to_group("player_global")

func validate_required_nodes():
	if not player_camera:
		push_error("Player: player_camera not assigned!")

func setup_systems():
	movement_system = PlayerMovement.new(self)
	add_child(movement_system)

	# Rotate the camera rig (parent of the camera) so the grid facing is untouched.
	var camera_controller := player_camera.get_parent() as Node3D
	free_look_system = PlayerFreeLook.new(camera_controller, movement_system)
	add_child(free_look_system)

	interaction_system = PlayerInteraction.new(self, player_camera)
	add_child(interaction_system)

func connect_signals():
	movement_system.movement_started.connect(_on_movement_started)
	movement_system.movement_blocked.connect(_on_movement_blocked)
	interaction_system.interaction_completed.connect(_on_interaction_completed)
	interaction_system.interaction_failed.connect(_on_interaction_failed)
#endregion

#region Input Handling
func _input(event):
	# While free look is held it's modal: it owns all input until released.
	if free_look_system and free_look_system.is_active:
		free_look_system.handle_input(event)
		return

	# Otherwise let free look claim the right-mouse press to start.
	if free_look_system and free_look_system.handle_input(event):
		return

	# Left-click world interaction (keyboard interact runs off RC_Detection_Facing).
	if interaction_system:
		interaction_system.handle_mouse_click(event)

func _physics_process(_delta: float) -> void:
	movement_system.check_ground()
	# Turning is a grid action; suppress it while the player is glancing around.
	if not (free_look_system and free_look_system.is_active):
		movement_system.handle_turn_input()
	interaction_system.update_interaction_ray()
#endregion

#region System Event Handlers
func _on_movement_started(direction: Vector3):
	player_moved.emit(direction)

func _on_movement_blocked(_direction: Vector3, message: String):
	display_text(message)

func _on_interaction_completed(_target: Node, _interaction_type: String):
	pass # Available for future use

func _on_interaction_failed(reason: String):
	display_text(reason)
#endregion

#region Feedback
func display_text(text_content: String):
	GameTextBox.display_text(text_content)

func display_temporary_text(text_content: String, duration: float = 3.0):
	GameTextBox.display_temporary_text(text_content, duration)
#endregion

#region Public API
func get_movement_system() -> PlayerMovement:
	return movement_system

func can_move() -> bool:
	return movement_system.can_move if movement_system else false
#endregion

#region Cleanup
func cleanup():
	if free_look_system:
		free_look_system.cleanup()
	queue_free()
#endregion
