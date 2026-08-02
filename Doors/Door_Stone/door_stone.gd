extends Node3D
class_name SceneDoor

## Path to the scene this door loads
@export_file("*.tscn") var target_scene_path: String = ""
## Sound to play when door is activated
@export var activation_sound: AudioStream
## Fade duration for transitions
@export_range(0.1, 3.0) var fade_duration: float = 0.8

@onready var area_3d: Area3D = $Area3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var is_active: bool = true

func _ready():
	# Set up input processing
	area_3d.input_event.connect(_on_area_input_event)
	
	## Configure audio player
	#if activation_sound:
		#audio_player.stream = activation_sound
	#else:
		#push_warning("No activation sound set for door at %s" % global_position)

func _on_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	# Only handle left mouse clicks
	if not is_active or not event is InputEventMouseButton:
		return
		
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
		
	# Verify we have a valid scene path
	if target_scene_path.is_empty():
		push_error("Door at %s has no target scene set!" % global_position)
		return
		
	# Start transition process
	activate_door()

func activate_door():
	if not is_active:
		return
		
	is_active = false
	
	# Play sound effect
	if audio_player.stream:
		audio_player.play()
	
	# Get fade manager
	var fade_manager = get_node_or_null("/root/FadeManager")
	if not fade_manager:
		push_error("FadeManager not found! Make sure it's added as an autoload")
		get_tree().change_scene_to_file(target_scene_path)
		return
	
	# Use FadeManager's built-in scene transition with fade
	fade_manager.transition_to_scene(target_scene_path, fade_duration)

# Allow external activation
func interact():
	activate_door()
