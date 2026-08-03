extends Node3D

## Put this on a level's ROOT node. It lets the level work two ways:
##  - Run standalone (F6 / launched directly): it spawns the persistent player
##    itself via LevelManager, so the level is playable on its own for testing.
##  - Loaded through LevelManager.load_level(): it stands down, because
##    LevelManager owns spawning/reparenting the player during a transition.

@export var player_spawn: Node3D  # assign the level's PlayerSpawn (auto-found if left empty)

func _ready() -> void:
	if not player_spawn:
		player_spawn = find_child("PlayerSpawn", true, false)
	# Defer so the whole tree is ready before we touch LevelManager.
	call_deferred("_deferred_level_setup")

func _deferred_level_setup() -> void:
	# Only claim "current level" on a standalone load; during a managed
	# transition LevelManager has already set itself up.
	if not LevelManager.has_current_level() or not is_instance_valid(LevelManager.get_current_level()):
		LevelManager.current_level = self
	_setup_level_with_manager()

func _setup_level_with_manager() -> void:
	# During a managed transition LevelManager spawns the player itself.
	if LevelManager.is_loading_level:
		return
	# Standalone / first load: create the player if we don't have one yet.
	if not LevelManager.get_player() or not is_instance_valid(LevelManager.get_player()):
		LevelManager.call_deferred("create_player_at_spawn", "PlayerSpawn")

func get_player_spawn() -> Node3D:
	return player_spawn

# Hook for per-level content once the player is present (overridable per level).
func initialize_level_specific_content() -> void:
	pass
