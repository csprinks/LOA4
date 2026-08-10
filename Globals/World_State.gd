extends Node

## Per-session store for WORLD state (as opposed to PartyManager's party state):
## the state of interactive objects in each level, plus where the player is. It is
## what makes a door you opened stay open when you walk back into a level, and what
## drops a loaded game back into the right level at the right spot.
##
## Design mirrors AutomapManager's per-level cache: state is keyed by level scene
## path and carried in memory across level transitions, then serialized to disk on
## an explicit Save (through SaveSystem, alongside the party files).
##
## Interactives opt in with a tiny duck-typed contract:
##   - add themselves to group "persistent" in _ready()
##   - get_persistent_state() -> Dictionary   (JSON-safe values)
##   - apply_persistent_state(state: Dictionary) -> void
## apply_* must restore VISUALS + FLAGS ONLY, with no side effects on connected
## nodes (a restored lever must not re-fire its door; a restored chest must not
## re-grant its loot) — every linked node persists independently and is restored
## to a self-consistent state.

const PERSISTENT_GROUP := "persistent"

# level_path (String) -> { node_id (String) -> state (Dictionary) }
var _level_states: Dictionary = {}

# Where the player is, for game-load restore.
var player_level: String = ""
var player_position: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0

# One-shot transform consumed by LevelManager the next time it spawns the player
# (set by a game-load so the player lands where they saved instead of at the spawn
# marker). null the rest of the time, so ordinary level transitions use the spawn.
var _spawn_override = null  # Transform3D or null

func _ready() -> void:
	var lm := get_node_or_null("/root/LevelManager")
	if lm:
		if lm.has_signal("level_unloading"):
			lm.level_unloading.connect(_on_level_unloading)
		if lm.has_signal("level_loaded"):
			lm.level_loaded.connect(_on_level_loaded)

#region Level lifecycle hooks
# Capture a level's interactives just before it is freed, so returning to it later
# restores them. LevelManager emits this while the old level is still in the tree.
func _on_level_unloading(old_level: Node) -> void:
	if old_level and is_instance_valid(old_level):
		_capture_level(old_level)

# Restore a level's interactives right after it is instantiated (its children's
# _ready() have already run by the time LevelManager emits this).
func _on_level_loaded(new_level: Node) -> void:
	if new_level and is_instance_valid(new_level):
		_restore_level(new_level)
#endregion

#region Capture / restore
# Snapshot every "persistent" node under `level` into _level_states, keyed by the
# level's scene path and each node's path relative to the level root.
func _capture_level(level: Node) -> void:
	var level_path := _level_path_of(level)
	if level_path == "":
		return

	var states: Dictionary = {}
	for node in _persistent_nodes_under(level):
		if node.has_method("get_persistent_state"):
			var node_id := str(level.get_path_to(node))
			states[node_id] = node.get_persistent_state()

	if states.is_empty():
		_level_states.erase(level_path)
	else:
		_level_states[level_path] = states

# Apply any saved state to the matching nodes under a freshly loaded level.
func _restore_level(level: Node) -> void:
	var level_path := _level_path_of(level)
	if level_path == "" or not _level_states.has(level_path):
		return

	var states: Dictionary = _level_states[level_path]
	for node in _persistent_nodes_under(level):
		if not node.has_method("apply_persistent_state"):
			continue
		var node_id := str(level.get_path_to(node))
		if states.has(node_id):
			node.apply_persistent_state(states[node_id])

# Persistent-group nodes that are descendants of `level` (group membership is
# global, so filter by ancestry — during a transition both levels can briefly
# coexist, but only ever one is being captured/restored at a time).
func _persistent_nodes_under(level: Node) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group(PERSISTENT_GROUP):
		if is_instance_valid(node) and level.is_ancestor_of(node):
			result.append(node)
	return result

func _level_path_of(level: Node) -> String:
	if level and level.scene_file_path != "":
		return level.scene_file_path
	# Fallback to what GameState thinks is current (used if a level was built
	# without a backing .tscn, which shouldn't happen for managed levels).
	var gs := get_node_or_null("/root/GameState")
	if gs and "current_level" in gs:
		return gs.current_level
	return ""
#endregion

#region Public API — save side
# Capture the LIVE level's interactives and the player's position/facing. Called
# from the save chokepoint (PartyManager.save_party). No-op when there's no live
# level or player (e.g. spending crowns from a menu), so it never clobbers a good
# capture with an empty one.
func capture_current_level_and_player() -> void:
	var lm := get_node_or_null("/root/LevelManager")
	if lm == null:
		return

	var level: Node = lm.get_current_level() if lm.has_method("get_current_level") else null
	if level == null or not is_instance_valid(level):
		return

	_capture_level(level)

	var player = lm.get_player() if lm.has_method("get_player") else null
	if player and is_instance_valid(player) and player.is_inside_tree():
		var xform: Transform3D = player.global_transform
		player_position = xform.origin
		player_yaw = xform.basis.get_euler().y
		player_level = _level_path_of(level)

func to_dict() -> Dictionary:
	var levels: Dictionary = {}
	for level_path in _level_states:
		levels[level_path] = _level_states[level_path].duplicate(true)
	return {
		"player_level": player_level,
		"player_position": [player_position.x, player_position.y, player_position.z],
		"player_yaw": player_yaw,
		"levels": levels,
	}
#endregion

#region Public API — load side
func from_dict(data: Dictionary) -> void:
	reset()
	if data == null or data.is_empty():
		return

	player_level = data.get("player_level", "")
	player_yaw = float(data.get("player_yaw", 0.0))
	var pos = data.get("player_position", null)
	if pos is Array and pos.size() == 3:
		player_position = Vector3(pos[0], pos[1], pos[2])

	var levels = data.get("levels", {})
	if levels is Dictionary:
		for level_path in levels:
			_level_states[level_path] = (levels[level_path] as Dictionary).duplicate(true)

# Load a slot's world blob into memory and arm the spawn override. Returns the
# level scene path to load, or "" when the slot has no world save (caller falls
# back to its default world scene and the player spawns at the marker).
func prepare_load(slot: int) -> String:
	var save_system := get_node_or_null("/root/SaveSystem")
	var data: Dictionary = {}
	if save_system and save_system.has_method("load_world"):
		data = save_system.load_world(slot)
	from_dict(data)

	if player_level == "":
		return ""

	_spawn_override = Transform3D(Basis(Vector3.UP, player_yaw), player_position)
	return player_level

# Returns the armed spawn transform once, then disarms it (so only the load that
# armed it uses it; subsequent transitions fall through to the spawn marker).
func consume_spawn_override():
	var override = _spawn_override
	_spawn_override = null
	return override
#endregion

func reset() -> void:
	_level_states.clear()
	player_level = ""
	player_position = Vector3.ZERO
	player_yaw = 0.0
	_spawn_override = null
