extends Node

## Owns the persistent player and swaps levels under it (LOA4 port of LOA2's
## LevelManager, trimmed). The player scene embeds the HUD (UI_Main), so when the
## player is reparented into a new level the HUD and its PartyManager wiring ride
## along automatically — LOA2's separate UI-await / character-load steps are gone.

signal level_loaded(level_node: Node)
signal level_unloading(level_node: Node)
signal player_loaded(player: Player)

var current_level: Node = null
var persistent_player: Player = null
var is_loading_level: bool = false

# Load a new level and carry the persistent player into it. The screen only fades
# back in once the player is positioned at the new level's spawn.
func load_level(level_path: String, player_spawn_name: String = "PlayerSpawn") -> void:
	if is_loading_level:
		push_warning("LevelManager: load_level ignored - a load is already in progress")
		return

	is_loading_level = true

	var fade_manager = get_node_or_null("/root/FadeManager")
	if fade_manager:
		await fade_manager.fade_out(0.5)

	# Load the new level resource FIRST so a bad path bails out before we tear
	# down the current level.
	var level_scene = load(level_path)
	if not level_scene:
		push_error("LevelManager: failed to load level: " + level_path)
		if fade_manager:
			await fade_manager.fade_in(0.5)
		is_loading_level = false
		return

	# Detach the persistent player so it survives the old level being freed.
	if persistent_player and is_instance_valid(persistent_player) and persistent_player.get_parent():
		persistent_player.get_parent().remove_child(persistent_player)

	# Remove the old level.
	var old_level = current_level
	if old_level and is_instance_valid(old_level):
		emit_signal("level_unloading", old_level)
		if old_level.is_inside_tree():
			var parent = old_level.get_parent()
			if parent:
				parent.remove_child(old_level)
		old_level.queue_free()
		# One frame is enough now that the player is already detached.
		await get_tree().process_frame

	# Instantiate and add the new level.
	current_level = level_scene.instantiate()

	if not is_inside_tree() or not get_tree() or not get_tree().root:
		push_error("LevelManager: scene tree is not available")
		is_loading_level = false
		return

	get_tree().root.add_child(current_level)
	await get_tree().process_frame

	emit_signal("level_loaded", current_level)

	# LevelManager owns player spawning on the managed path (player_loading.gd
	# stands down while is_loading_level is true).
	await create_player_at_spawn(player_spawn_name)

	# Let the level run any content hook now that the player is present.
	if current_level.has_method("initialize_level_specific_content"):
		current_level.initialize_level_specific_content()

	if fade_manager:
		await fade_manager.fade_in(0.5)

	GameState.current_level = level_path
	is_loading_level = false

# Create or reparent the persistent player and position it at the level's spawn.
# Idempotent: reuses the existing player across transitions.
func create_player_at_spawn(spawn_name: String = "PlayerSpawn") -> void:
	if not current_level or not is_instance_valid(current_level):
		push_error("LevelManager: cannot spawn player - no current level set")
		return

	if persistent_player and is_instance_valid(persistent_player):
		# Reuse the existing player, reparenting it into the new level.
		if persistent_player.get_parent() != current_level:
			if persistent_player.get_parent():
				persistent_player.get_parent().remove_child(persistent_player)
			current_level.add_child(persistent_player)
	else:
		persistent_player = ResourceManager.player_script.instantiate()
		current_level.add_child(persistent_player)

	# Wait until the player's _ready() has run, then one more frame so its global
	# transform is valid before we position it.
	if not persistent_player.is_node_ready():
		await persistent_player.ready
	await get_tree().process_frame

	_position_player_at_spawn(spawn_name)

	emit_signal("player_loaded", persistent_player)

# Position the player on the level's spawn point (falls back to origin).
func _position_player_at_spawn(spawn_name: String) -> void:
	if not persistent_player:
		return

	# A game-load arms WorldState with the exact transform the player saved at, so
	# loading drops them back where they were rather than at the level's spawn.
	var override = WorldState.consume_spawn_override() if WorldState else null
	if override != null:
		persistent_player.global_transform = override
	else:
		var spawn_point: Node = null
		if current_level.has_method("get_player_spawn"):
			spawn_point = current_level.get_player_spawn()
		elif "player_spawn" in current_level and current_level.player_spawn:
			spawn_point = current_level.player_spawn

		if not spawn_point or not is_instance_valid(spawn_point):
			spawn_point = current_level.find_child(spawn_name, true, false)

		if spawn_point and is_instance_valid(spawn_point) and spawn_point.is_inside_tree():
			persistent_player.global_transform = spawn_point.global_transform
		else:
			persistent_player.global_transform.origin = Vector3.ZERO
			push_warning("LevelManager: spawn point '" + spawn_name + "' not found, using origin")

	# Clear any scripted-move lock (e.g. left over from a stair-climb transition)
	# so the player always arrives grounded and controllable in the new level.
	var ms = persistent_player.get_movement_system() if persistent_player.has_method("get_movement_system") else null
	if ms and ms.has_method("end_scripted_move"):
		ms.end_scripted_move()

func get_player() -> Player:
	return persistent_player

func get_current_level() -> Node:
	return current_level

func has_current_level() -> bool:
	return current_level != null and is_instance_valid(current_level)

# Start the first level (call this from the boot flow, e.g. character creation).
func initialize_first_level(level_path: String, spawn_name: String = "PlayerSpawn") -> void:
	load_level(level_path, spawn_name)

func cleanup() -> void:
	if persistent_player:
		persistent_player.cleanup()
		persistent_player = null
	if current_level:
		current_level.queue_free()
		current_level = null
