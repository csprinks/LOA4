extends Node3D
class_name PuzzleActivator

# Puzzle configuration
@export var puzzle_id: String = ""
@export var levers: Array[Lever] = []
@export var required_states: Array[Lever.LeverState] = []

# What happens when puzzle is solved
@export var platforms_to_activate: Array[MovingBlockPlatform] = []
@export var doors_to_open: Array[DoorGrate] = []
@export var play_sound_on_solve: bool = true
@export var sound_effect: AudioStream
@export var show_success_message: bool = true

# Internal state
var is_solved: bool = false
var _audio_player: AudioStreamPlayer3D

func _ready():
	# Validate inputs
	if levers.size() != required_states.size():
		push_error("PuzzleActivator: Number of levers doesn't match required states!")
		return
	
	# Connect to lever interactions
	for lever in levers:
		if lever and is_instance_valid(lever):
			lever.interacted.connect(_on_lever_interacted)
	
	# Create audio player if needed
	if sound_effect and play_sound_on_solve:
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.stream = sound_effect
		add_child(_audio_player)
	
	# Initial puzzle check
	_check_puzzle_state()

func _on_lever_interacted():
	_check_puzzle_state()

func _check_puzzle_state():
	# Don't check if already solved
	if is_solved:
		return
	
	if is_puzzle_solved():
		_solve_puzzle()

func _solve_puzzle():
	is_solved = true
	print("Puzzle solved: ", puzzle_id)
	
	# Activate platforms
	for platform in platforms_to_activate:
		if platform and is_instance_valid(platform):
			platform.activate()
	
	# Open doors
	for door in doors_to_open:
		if door and is_instance_valid(door):
			door.activate()
	
	# Play sound
	if _audio_player and play_sound_on_solve:
		_audio_player.play()
	
	# Show success message
	if show_success_message:
		ResourceManager.display_text("Puzzle solved! A path opens...")

func is_puzzle_solved() -> bool:
	if puzzle_id.is_empty() || levers.is_empty() || levers.size() != required_states.size():
		return false
	
	for i in range(levers.size()):
		var lever = levers[i]
		var required_state = required_states[i]
		
		if !lever or !is_instance_valid(lever):
			continue
		
		if lever.get_state() != required_state:
			return false
	
	return true

# Reset the puzzle (useful for level reset)
func reset_puzzle():
	is_solved = false
	
	# Reset all levers to their initial states
	for lever in levers:
		if lever and is_instance_valid(lever):
			lever.reset()

# Get debug information about lever states
func get_debug_info() -> String:
	var info = "Puzzle Activator (ID: %s):\n" % puzzle_id
	for i in range(levers.size()):
		var lever = levers[i]
		var required_state = required_states[i]
		var current_state = lever.get_state() if lever else null
		
		info += "Lever %d: Current=%s, Required=%s, Correct=%s\n" % [
			i + 1, 
			"UP" if current_state == Lever.LeverState.UP else "DOWN",
			"UP" if required_state == Lever.LeverState.UP else "DOWN",
			"YES" if current_state == required_state else "NO"
		]
	
	info += "Puzzle Solved: %s" % is_solved
	return info

# Get current state as string for debugging (from old EnhancedPuzzleActivator)
func get_puzzle_state() -> String:
	var state = ""
	for i in range(levers.size()):
		var lever = levers[i]
		var required = required_states[i]
		var current = lever.get_state() if lever else null
		
		state += "Lever %d: Current=%s, Required=%s\n" % [
			i + 1,
			"UP" if current == Lever.LeverState.UP else "DOWN",
			"UP" if required == Lever.LeverState.UP else "DOWN"
		]
	return state
