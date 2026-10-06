extends Node3D
class_name SceneDoor

## Path to the level this door loads (through LevelManager, so the persistent
## player/HUD carry over and WorldState remembers the level being left).
@export_file("*.tscn") var target_scene_path: String = ""
## Marker in the target level the player arrives at
@export var target_spawn_marker_name: String = "PlayerSpawn"
## Sound to play when door is activated
@export var activation_sound: AudioStream

@onready var area_3d: Area3D = $Area3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var is_active: bool = true

func _ready():
	# Set up input processing
	area_3d.input_event.connect(_on_area_input_event)

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
	if not is_active or LevelManager.is_loading_level:
		return
	if target_scene_path.is_empty():
		push_error("Door at %s has no target scene set!" % global_position)
		return

	is_active = false

	# Play sound effect
	if audio_player.stream:
		audio_player.play()

	# LevelManager fades, captures this level's state (via WorldState), swaps the
	# level under the persistent player, and frees this door along with the old
	# level. If we are still here afterwards the load failed, so re-arm the door.
	await LevelManager.load_level(target_scene_path, target_spawn_marker_name)
	if is_instance_valid(self):
		is_active = true

# Allow external activation
func interact():
	activate_door()
