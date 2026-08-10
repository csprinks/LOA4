extends Node3D
class_name DoorGrate

@export var open_sound: AudioStream
@export var close_sound: AudioStream

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

var is_open: bool = false

func _ready() -> void:
	setup_audio_player()
	ensure_door_closed()
	add_to_group("map_door")  # shows a marker on the automap
	add_to_group("persistent")  # WorldState saves/restores our open/closed state

func setup_audio_player():
	if audio_player == null:
		audio_player = AudioStreamPlayer.new()
		add_child(audio_player)

func ensure_door_closed():
	animation_player.play("RESET")
	animation_player.advance(animation_player.current_animation_length)
	is_open = false
	print("Door initialized to closed position")

# Add this method for lever compatibility
func activate():
	toggle()

func toggle():
	if is_open:
		close()
	else:
		open()

func open():
	if not is_open:
		animation_player.play("Open")
		play_sound(open_sound)
		is_open = true
		print("Gate Opened")

func close():
	if is_open:
		animation_player.play("RESET")
		play_sound(close_sound)
		is_open = false
		print("Gate Closed")

func play_sound(sound: AudioStream):
	if audio_player and sound:
		audio_player.stream = sound
		audio_player.play()

#region Persistence (WorldState contract)
func get_persistent_state() -> Dictionary:
	return {"open": is_open}

# Snap silently to the saved pose — no sound, and don't route through open()/close()
# (those early-out on the current is_open and would play a transition).
func apply_persistent_state(state: Dictionary) -> void:
	if state.get("open", false):
		animation_player.play("Open")
		animation_player.advance(animation_player.current_animation_length)
		is_open = true
	else:
		ensure_door_closed()
#endregion
