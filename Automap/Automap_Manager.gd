extends Node

## Data core for the automap. Owns what the party has explored; the HUD (Automap /
## AutomapView) only reads from here and draws it.
##
## The map is a set of grid cells, each with a mask of which of its four sides are
## walled. Reveal is MOVEMENT based: whenever the player enters a new cell, the
## 3 x 3 block centred on them is revealed. Each newly revealed cell is probed once
## with a few physics rays (floor below? wall across each side?), so this works for
## any level built on the 2-unit grid, painted or hand-made.
##
## Explored cells are cached per level (keyed by scene path) across transitions and
## saved with the game through WorldState.

signal map_changed

const GRID_SIZE := 2.0
const REVEAL_RADIUS := 1          # 1 = a 3 x 3 block around the player

const WALL_N := 1                 # -Z
const WALL_E := 2                 # +X
const WALL_S := 4                 # +Z
const WALL_W := 8                 # -X
const WALL_ALL := 15
const SIDES := [
	[Vector2i(0, -1), WALL_N], [Vector2i(1, 0), WALL_E],
	[Vector2i(0, 1), WALL_S], [Vector2i(-1, 0), WALL_W]]

const PIT := 16                   # cell flag (not a wall): the floor here is sunk
const PIT_DEPTH := 1.3            # a floor this far below the level's is a pit

# Things marked on the map, by the scene they are instanced from. A mark holds
# its node, so ones that move (push blocks, platforms, fireballs) are drawn where
# they are right now.
const MARK_STAIRS := "stairs"
const MARK_CHEST := "chest"
const MARK_SPIKES := "spikes"
const MARK_DRAGON := "dragon"     # fireball trap; its fireball is drawn in flight
const MARK_PUSH_BLOCK := "push_block"
const MARK_PLATE := "pressure_plate"
const MARK_PLATFORM := "moving_platform"
const MARK_LEVER := "lever"
const MARK_LOCK := "wall_lock"
const MARKS_BY_SCENE := {
	"res://Stairs/level_stairs.tscn": MARK_STAIRS,
	"res://Treasure_Chest/treasure_chest.tscn": MARK_CHEST,
	"res://Spike_Trap/spike_trap.tscn": MARK_SPIKES,
	"res://Fireball_Trap/Fireball_Trap.tscn": MARK_DRAGON,
	"res://Push_Block/push_block.tscn": MARK_PUSH_BLOCK,
	"res://Pressure Plate/pressure_plate.tscn": MARK_PLATE,
	"res://Moving_Platform/moving_platform.tscn": MARK_PLATFORM,
	"res://Lever/Lever.tscn": MARK_LEVER,
	"res://Wall_Locks/wall_lock_basic.tscn": MARK_LOCK,
}
const MOVING_MARKS := [MARK_DRAGON, MARK_PUSH_BLOCK, MARK_PLATFORM]

const PROBE_HEIGHT := 1.0         # rays are cast this far above the player's origin
const FLOOR_PROBE_DEPTH := 3.0    # ... and floor rays reach this far below it
const EDGE_PROBE_REACH := 0.45    # wall rays span this far either side of a cell edge
const NO_CELL := Vector2i(2147483647, 2147483647)

# Explored floor cells of the current level: Vector2i -> wall mask (+ PIT flag).
var cells: Dictionary = {}
# Door edges of the current level, keyed by the edge midpoint in half-cell units
# (the edge between cell c and its neighbour c + d is 2c + d): Vector2i -> true.
var doors: Dictionary = {}
# Points of interest of the current level: [{ "type": MARK_*, "node": Node3D }].
var marks: Array[Dictionary] = []
# True while any mark can move, so the view keeps redrawing.
var has_moving_marks := false

# Explored cells of the levels we are not in: level_path -> cells Dictionary.
var _level_maps: Dictionary = {}
var _level_key: String = ""
var _level_id: int = 0
var _last_cell: Vector2i = NO_CELL
var _settle_frames: int = 0
# Cells that count as floor whatever the probe says, because a fixed mark (stairs,
# a chest) stands there: Vector2i -> true.
var _marked_cells: Dictionary = {}
# Height of the level's walking surface, taken from the player the first time we
# reveal. Probing from a fixed height keeps working while the party is down a pit.
var _floor_y: float = NAN

func _physics_process(_delta: float) -> void:
	var player := get_player()
	# During a level load the persistent player is briefly detached, then sits at
	# a stale position until LevelManager places it on the spawn; wait that out.
	if player == null or not player.is_inside_tree() or LevelManager.is_loading_level:
		return
	var level := _level_of(player)
	if level == null:
		return
	if level.get_instance_id() != _level_id:
		_activate_level(level)
		return
	# Give a freshly added level a couple of physics frames to register its
	# colliders before probing it.
	if _settle_frames > 0:
		_settle_frames -= 1
		return
	# A scripted move (climbing stairs) drags the player off the floor plane.
	var movement = player.get_movement_system() if player.has_method("get_movement_system") else null
	if movement and movement.scripted_move:
		return
	var cell := world_to_cell(player.global_position)
	if cell != _last_cell:
		_last_cell = cell
		_reveal_around(cell, player)

#region Public API
func get_player() -> Node3D:
	var p = LevelManager.get_player()
	if p and is_instance_valid(p):
		return p
	return get_tree().get_first_node_in_group("player") as Node3D

func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / GRID_SIZE), roundi(world_pos.z / GRID_SIZE))

# The cell rectangle enclosing everything explored in this level.
func get_bounds() -> Rect2i:
	if cells.is_empty():
		return Rect2i(0, 0, 1, 1)
	var first := true
	var bounds := Rect2i()
	for cell in cells:
		if first:
			bounds = Rect2i(cell, Vector2i.ONE)
			first = false
		else:
			bounds = bounds.expand(cell).expand(cell + Vector2i.ONE)
	return bounds

# Forget everything explored, in every level (new game, or the Level Editor
# test-playing a module whose floors may have been repainted).
func forget_all() -> void:
	_level_maps.clear()
	cells = {}
	_last_cell = NO_CELL
	map_changed.emit()

func to_dict() -> Dictionary:
	var levels: Dictionary = {}
	for path in _level_maps:
		levels[path] = _pack_cells(_level_maps[path])
	if _level_key != "":
		levels[_level_key] = _pack_cells(cells)
	return {"levels": levels}

func from_dict(data: Dictionary) -> void:
	forget_all()
	var levels = data.get("levels", {})
	if levels is Dictionary:
		for path in levels:
			if levels[path] is Array:
				_level_maps[path] = _unpack_cells(levels[path])
	# Loading while already standing in a level: pick its map back up.
	if _level_key != "" and _level_maps.has(_level_key):
		cells = _level_maps[_level_key]
		_level_maps.erase(_level_key)
		map_changed.emit()
#endregion

#region Reveal
func _reveal_around(center: Vector2i, player: Node3D) -> void:
	var space := player.get_world_3d().direct_space_state
	if is_nan(_floor_y):
		_floor_y = player.global_position.y
	var y := _floor_y
	var exclude: Array[RID] = [player.get_rid()]
	var changed := false
	for dz in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			var cell := center + Vector2i(dx, dz)
			if cells.has(cell):
				continue
			var drop := _floor_drop(space, cell, y, exclude)
			if cell != center and is_inf(drop):
				continue
			var mask := _probe_walls(space, cell, y, exclude)
			# Sealed on all four sides and not where we stand: solid rock that
			# happens to have floor under it, not a room.
			if mask == WALL_ALL and cell != center:
				continue
			if not is_inf(drop) and drop > PIT_DEPTH:
				mask |= PIT
			cells[cell] = mask
			changed = true
	if changed:
		map_changed.emit()

func _is_floor(space: PhysicsDirectSpaceState3D, cell: Vector2i, y: float, exclude: Array[RID]) -> bool:
	return not is_inf(_floor_drop(space, cell, y, exclude))

# How far below `y` the floor of `cell` lies, or INF if there is nothing to stand
# on there.
func _floor_drop(space: PhysicsDirectSpaceState3D, cell: Vector2i, y: float, exclude: Array[RID]) -> float:
	if _marked_cells.has(cell):
		return 0.0
	var top := Vector3(cell.x * GRID_SIZE, y + PROBE_HEIGHT, cell.y * GRID_SIZE)
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (PROBE_HEIGHT + FLOOR_PROBE_DEPTH))
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return INF
	return y - (hit["position"] as Vector3).y

# Which sides of `cell` are closed: a wall across the edge, or nothing to walk on
# beyond it. Door edges always count as open; the view draws the door instead.
func _probe_walls(space: PhysicsDirectSpaceState3D, cell: Vector2i, y: float, exclude: Array[RID]) -> int:
	var mask := 0
	var center := Vector3(cell.x * GRID_SIZE, y + PROBE_HEIGHT, cell.y * GRID_SIZE)
	for side in SIDES:
		var step: Vector2i = side[0]
		if doors.has(cell * 2 + step):
			continue
		var dir := Vector3(step.x, 0.0, step.y)
		var edge := center + dir * (GRID_SIZE * 0.5)
		var neighbour := cell + step
		if _is_blocked(space, edge - dir * EDGE_PROBE_REACH, edge + dir * EDGE_PROBE_REACH, exclude) \
				or not (cells.has(neighbour) or _is_floor(space, neighbour, y, exclude)):
			mask |= side[1]
	return mask

# True if fixed level geometry crosses the segment. Things that move (push blocks,
# moving platforms) and furniture (group "automap_ignore") are looked through, so
# they never get drawn as walls.
func _is_blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var skip: Array[RID] = exclude.duplicate()
	for _attempt in 4:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider = hit["collider"]
		if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D \
				or (collider is Node and collider.is_in_group("automap_ignore")):
			skip.append(hit["rid"])
			continue
		return true
	return false
#endregion

#region Level lifecycle
func _activate_level(level: Node) -> void:
	if _level_key != "":
		_level_maps[_level_key] = cells
	_level_id = level.get_instance_id()
	_level_key = level.scene_file_path if level.scene_file_path != "" else GameState.current_level
	cells = _level_maps.get(_level_key, {})
	_level_maps.erase(_level_key)
	doors = {}
	marks = []
	has_moving_marks = false
	_marked_cells = {}
	_floor_y = NAN
	_scan_features(level, level)
	_last_cell = NO_CELL
	_settle_frames = 2
	map_changed.emit()

func _level_of(player: Node3D) -> Node:
	var level = LevelManager.get_current_level()
	if level and is_instance_valid(level) and level.is_ancestor_of(player):
		return level
	return player.get_parent()

# Find the doors and the objects worth marking (see MARKS_BY_SCENE) in the level.
func _scan_features(node: Node, level: Node) -> void:
	for child in node.get_children():
		if child is DoorGrate or child is SceneDoor:
			doors[_edge_key_at(_anchor(child, level).global_position)] = true
		elif child is Node3D and MARKS_BY_SCENE.has(child.scene_file_path):
			var type: String = MARKS_BY_SCENE[child.scene_file_path]
			marks.append({"type": type, "node": child})
			if type in MOVING_MARKS:
				has_moving_marks = true
			elif type == MARK_STAIRS or type == MARK_CHEST:
				_marked_cells[world_to_cell(child.global_position)] = true
			# A marked object is drawn as its icon, so its own collider must not
			# also read as a wall. (Stairs keep theirs: their sides really are walls.)
			if type != MARK_STAIRS:
				_ignore_colliders(child)
			continue   # nothing to mark inside a marked object
		_scan_features(child, level)

func _ignore_colliders(node: Node) -> void:
	if node is CollisionObject3D:
		node.add_to_group("automap_ignore")
	for child in node.get_children():
		_ignore_colliders(child)

# The node that was placed on the grid: the root of the scene `node` belongs to
# when it is a part inside an instanced scene, else the node itself.
func _anchor(node: Node3D, level: Node) -> Node3D:
	if node.scene_file_path == "" and node.owner is Node3D and node.owner != level:
		return node.owner
	return node

# The cell edge nearest a world position, as a door key (see `doors`). An edge
# midpoint has one odd and one even half-cell coordinate.
func _edge_key_at(world_pos: Vector3) -> Vector2i:
	var hx := world_pos.x / (GRID_SIZE * 0.5)
	var hz := world_pos.z / (GRID_SIZE * 0.5)
	var odd_x := 2 * floori(hx / 2.0) + 1
	var odd_z := 2 * floori(hz / 2.0) + 1
	var even_x := 2 * roundi(hx / 2.0)
	var even_z := 2 * roundi(hz / 2.0)
	var across_x := Vector2(odd_x, even_z)   # edge between two cells side by side
	var across_z := Vector2(even_x, odd_z)   # edge between two cells front to back
	var here := Vector2(hx, hz)
	if here.distance_squared_to(across_x) <= here.distance_squared_to(across_z):
		return Vector2i(across_x)
	return Vector2i(across_z)
#endregion

#region Serialization
# Cells as a flat JSON-safe list: [x, z, mask, x, z, mask, ...].
func _pack_cells(map: Dictionary) -> Array:
	var out: Array = []
	for cell in map:
		out.append(cell.x)
		out.append(cell.y)
		out.append(map[cell])
	return out

func _unpack_cells(packed: Array) -> Dictionary:
	var map: Dictionary = {}
	for i in range(0, packed.size() - 2, 3):
		map[Vector2i(int(packed[i]), int(packed[i + 1]))] = int(packed[i + 2])
	return map
#endregion
