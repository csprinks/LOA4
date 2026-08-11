# Treasure_Chest.gd
extends StaticBody3D
class_name TreasureChest

# Configuration variables
@export var sound_effect: AudioStream
@export var interaction_distance: float = 3.0

@export_group("Contents")
# Item resources granted to the player when the chest is opened. Any resource
# extending InventoryData (weapons, potions, armor, etc.) can be dropped here.
@export var contents: Array[InventoryData] = []
# Crowns (money) awarded when the chest is opened.
@export var crowns_reward: int = 0

# Add this property for compatibility with interaction system
var is_opened: bool = false

# Internal references
var _player_ref: Node3D = null
var _audio_player: AudioStreamPlayer3D
var _used: bool = false

func _ready():
	add_to_group("interactable")
	add_to_group("persistent")  # WorldState saves/restores our opened state

	# Create audio player if sound effect is assigned
	if sound_effect:
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.stream = sound_effect
		add_child(_audio_player)

func interact():
	# Get player reference
	var player = _get_player_reference()
	if not player:
		return

	# Calculate distance to player
	var distance = global_position.distance_to(player.global_position)

	# Use a more lenient distance check since clicks can be imprecise
	var effective_distance = interaction_distance * PlayerInteraction.PROXIMITY_MULTIPLIER
	if distance > effective_distance:
		_display_text("Too far away!")
		return

	# An already-opened chest reports that it's empty rather than doing nothing.
	if _used:
		_display_text("The chest is empty.")
		return

	_execute_interaction()

func _execute_interaction():
	# Play animation if available
	var anim_player = $AnimationPlayer
	if anim_player:
		if anim_player.has_animation("Chest_Open"):
			anim_player.play("Chest_Open")
		else:
			push_error("Missing Chest_Open animation")
	
	# Play sound if available
	if _audio_player:
		_audio_player.play()

	# Grant the chest's contents to the player and report what was found
	_grant_contents()

	# Mark as used
	_used = true
	is_opened = true

#region Persistence (WorldState contract)
func get_persistent_state() -> Dictionary:
	return {"used": _used}

# Restore an already-looted chest to its open pose WITHOUT re-granting contents.
func apply_persistent_state(state: Dictionary) -> void:
	if not state.get("used", false):
		return
	_used = true
	is_opened = true
	var anim_player = $AnimationPlayer
	if anim_player and anim_player.has_animation("Chest_Open"):
		anim_player.play("Chest_Open")
		anim_player.advance(anim_player.current_animation_length)
#endregion

# Award crowns and items to the player, then display a summary of the loot.
func _grant_contents() -> void:
	var found: Array[String] = []

	if crowns_reward > 0:
		Crowns.add_crowns(crowns_reward)
		found.append("%d crowns" % crowns_reward)

	for data in contents:
		if data == null:
			continue

		var wanted: int = maxi(1, data.quantity)
		var added: int = InventoryManager.AddItem(data)
		var label: String = data.itemName if wanted == 1 else "%s x%d" % [data.itemName, added]

		if added == 0:
			found.append("%s (inventory full!)" % data.itemName)
		elif added < wanted:
			found.append("%s (inventory full!)" % label)
		else:
			found.append(label)

	if found.is_empty():
		_display_text("The chest is empty.")
	else:
		_display_text("You found: " + ", ".join(found))

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

# Text display using the same method as Player_Manager
func _display_text(text_content: String):
	# Use the same method as Player_Manager to find GameTextBox
	var game_text_box = null
	
	# Try multiple possible paths for the singleton
	var possible_paths = [
		"/root/Game_Text_Box",
		"/root/GameTextBox", 
		"/root/GameTextbox"
	]
	
	for path in possible_paths:
		if get_tree().root.has_node(path):
			game_text_box = get_tree().root.get_node(path)
			break
	
	# If not found by path, try to find by script type
	if not game_text_box:
		for node in get_tree().root.get_children():
			if node is CanvasLayer and node.has_method("display_text"):
				game_text_box = node
				break
	
	if game_text_box and game_text_box.has_method("display_text"):
		game_text_box.display_text(text_content)
	else:
		# Fallback: print to console
		print("TEXT: ", text_content)
