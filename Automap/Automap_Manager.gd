extends Node

## Data core for the automap (LOA4 redesign). Replaces LOA2's ~1000-node black fog
## grid + 13 per-frame raycasts with a single reveal-mask texture the fog shader
## samples. This node owns only DATA + the mask; the camera / fog quad / markers
## live in the world and read the mask from here.
##
## Reveal is PER TILE (crawler style, not RTS blobs): the mask is one texel per
## grid cell, sampled with nearest filtering, so each revealed cell is a crisp,
## grid-aligned square. On entering a new cell we reveal it plus the cells visible
## down the four cardinal directions (line of sight until a wall).

signal map_reset(level_path: String)
signal cell_revealed(cell: Vector2i)

const GRID_SIZE := 2.0
const MASK_CELLS := 256           # mask is MASK_CELLS x MASK_CELLS, one texel/cell
const CELL_OFFSET := 128          # cell (cx,cz) -> texel (cx+OFFSET, cz+OFFSET)
const MAX_SIGHT_CELLS := 14       # how far line of sight reveals down an open run
const SIGHT_HEIGHT := 1.0         # ray height for wall checks
const SIGHT_MASK := 1             # collide with walls/floor (layer 1)
const FADE_TIME := 0.45           # seconds for a newly-revealed tile's fog to fade out

# Per-level saved state: level_path -> { explored, features, image }
var _level_maps: Dictionary = {}

var _current_level_path: String = ""
var explored: Dictionary = {}     # Vector2i -> true
var features: Dictionary = {}     # Vector2i -> String (feature type)
var _mask_image: Image
var _mask_texture: ImageTexture
var _last_cell: Vector2i = Vector2i(2147483647, 2147483647)  # sentinel "none"
var _fading: Dictionary = {}      # Vector2i -> float (0..1) tiles mid fade-in

func _ready() -> void:
	_new_blank_mask()
	var lm = get_node_or_null("/root/LevelManager")
	if lm and lm.has_signal("level_loaded"):
		lm.level_loaded.connect(_on_level_loaded)

func _process(delta: float) -> void:
	var player := _get_player()
	# Only sample the player when it's actually in the world. During a level load
	# the persistent player is briefly detached from the tree (removed from the old
	# level before being added to the new one); in that gap it has no global
	# transform or World3D, so reading global_position / get_world_3d() would warn
	# and then crash in _reveal_from. Skip those frames.
	if player != null and player.is_inside_tree() and player.get_world_3d() != null:
		var cell := world_to_cell(player.global_position)
		if cell != _last_cell:
			_last_cell = cell
			_reveal_from(cell, player)
	# Advance any tiles mid fade-in every frame.
	_advance_fades(delta)

#region Public API
func get_mask_texture() -> Texture2D:
	return _mask_texture

func is_revealed(cell: Vector2i) -> bool:
	return explored.has(cell)

# Register a feature (stairs/door/chest/...) at a world position so markers can be
# shown on the map. Stored per level.
func register_feature(world_pos: Vector3, type: String) -> void:
	features[world_to_cell(world_pos)] = type

func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(round(world_pos.x / GRID_SIZE)), int(round(world_pos.z / GRID_SIZE)))

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * GRID_SIZE, 0.0, cell.y * GRID_SIZE)
#endregion

#region Reveal
# Reveal the current cell plus everything visible down the four cardinals.
func _reveal_from(cell: Vector2i, player: Node3D) -> void:
	var painted := _reveal_cell(cell)
	var space := player.get_world_3d().direct_space_state
	var origin := cell_to_world(cell) + Vector3.UP * SIGHT_HEIGHT
	for step_dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var dir := Vector3(step_dir.x, 0, step_dir.y)
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + dir * (GRID_SIZE * MAX_SIGHT_CELLS))
		query.collision_mask = SIGHT_MASK
		var hit := space.intersect_ray(query)
		var dist: float = (hit.position - origin).length() if hit else GRID_SIZE * MAX_SIGHT_CELLS
		var steps := int(dist / GRID_SIZE)
		for i in range(1, steps + 1):
			painted = _reveal_cell(cell + step_dir * i) or painted
	if painted:
		_mask_texture.update(_mask_image)

# Mark a cell revealed and start its fog fading out. The mask value is ramped
# 0->1 in _advance_fades, not painted instantly. Returns false (painting is
# handled by the fade), kept for _reveal_from's call shape.
func _reveal_cell(cell: Vector2i) -> bool:
	if explored.has(cell):
		return false
	explored[cell] = true
	_fading[cell] = 0.0
	emit_signal("cell_revealed", cell)
	return false

# Ramp each fading tile's mask value toward 1.0, repaint, and drop finished ones.
func _advance_fades(delta: float) -> void:
	if _fading.is_empty():
		return
	var rate := delta / FADE_TIME
	var finished: Array[Vector2i] = []
	for cell in _fading:
		var v: float = _fading[cell] + rate
		var px: int = cell.x + CELL_OFFSET
		var py: int = cell.y + CELL_OFFSET
		if px >= 0 and py >= 0 and px < MASK_CELLS and py < MASK_CELLS:
			_mask_image.set_pixel(px, py, Color(clampf(v, 0.0, 1.0), 0, 0, 1))
		if v >= 1.0:
			finished.append(cell)
		else:
			_fading[cell] = v
	for cell in finished:
		_fading.erase(cell)
	_mask_texture.update(_mask_image)
#endregion

#region Level lifecycle
func _on_level_loaded(level_node: Node) -> void:
	var path := ""
	var gs = get_node_or_null("/root/GameState")
	if gs and "current_level" in gs:
		path = gs.current_level
	if path == "":
		path = level_node.scene_file_path
	_activate_level(path)

func _activate_level(level_path: String) -> void:
	if _current_level_path != "":
		_level_maps[_current_level_path] = {"explored": explored, "features": features, "image": _mask_image}

	_current_level_path = level_path
	if _level_maps.has(level_path):
		var saved: Dictionary = _level_maps[level_path]
		explored = saved["explored"]
		features = saved.get("features", {})
		_mask_image = saved["image"]
	else:
		explored = {}
		features = {}
		_new_blank_mask_image()
	_mask_texture.set_image(_mask_image)
	_last_cell = Vector2i(2147483647, 2147483647)
	_fading.clear()
	emit_signal("map_reset", level_path)
#endregion

#region Mask
func _new_blank_mask() -> void:
	_new_blank_mask_image()
	_mask_texture = ImageTexture.create_from_image(_mask_image)

func _new_blank_mask_image() -> void:
	_mask_image = Image.create(MASK_CELLS, MASK_CELLS, false, Image.FORMAT_R8)
	_mask_image.fill(Color(0, 0, 0, 1))
#endregion

func _get_player() -> Node3D:
	var lm = get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("get_player"):
		var p = lm.get_player()
		if p and is_instance_valid(p):
			return p
	return get_tree().get_first_node_in_group("player")
