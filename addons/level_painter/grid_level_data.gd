@tool
class_name GridLevelData
extends Resource

## The painted map for one level. Pure data: a bounded W x H grid of cells with
## three layers, saved as a .tres. The 3D level is produced from this by
## GridLevelBuilder, so this resource is the single source of truth you paint.
##
## Coordinates: cell (x, z), x in [0, width), z in [0, height). A cell maps to the
## world at (x * CELL, 0, z * CELL) once an origin offset is applied by the builder
## (see GridLevelBuilder). This matches the game's existing 2-unit grid.
##
## Layers
##  - floors: one id per cell. 0 = void (no floor / pit), else a floor tile id.
##  - edges:  one id per *edge* between cells. Walls live on edges, Grid-Cartographer
##            style. Each edge is owned once: a cell's West + North edges, plus the
##            grid's right/bottom border. 0 = none, else a wall/door tile id.
##  - objects: sparse per-cell placement (chest, lever, stairs, spawn, trap, ...),
##            each with a facing. Keyed by Vector2i so empty cells cost nothing.

const CELL := 2.0  # world units per cell; mirrors Player_Movement.GRID_SIZE

## Facing enum for objects (and door edges). Cardinal, matches the crawler.
enum Facing { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }

@export var level_name: String = "New Level"
## Stable identity within a dungeon (survives renaming/reordering floors). Stairs
## and doors that "lead to a floor" store this. Assigned by DungeonData.ensure_ids().
@export var uid: String = ""
## Where this floor was last built to (res://….tscn). Lets other floors' stairs and
## doors point at it without you typing the path. Set by the dock on every build.
@export var built_path: String = ""
## Grid dimensions. Assign these only via resize() (which reallocates the layers);
## on load Godot sets them directly and the saved layer arrays come with them.
## They are plain vars — NOT setter-backed — because a setter that reallocated on
## assignment would re-enter itself when the layers are restored during load.
@export var width: int = 16
@export var height: int = 16

## One int per cell, row-major (index = z * width + x). 0 = void.
@export var floors: PackedInt32Array = PackedInt32Array()

## Vertical edges (run north-south, separate horizontally-adjacent cells).
## Size (width + 1) * height, index = z * (width + 1) + x, x in [0, width].
## Edge x sits on the WEST side of cell x (and EAST side of cell x-1).
@export var edges_v: PackedInt32Array = PackedInt32Array()

## Horizontal edges (run east-west, separate vertically-adjacent cells).
## Size width * (height + 1), index = z * width + x, z in [0, height].
## Edge z sits on the NORTH side of cell z (and SOUTH side of cell z-1).
@export var edges_h: PackedInt32Array = PackedInt32Array()

## Sparse objects: Vector2i(x, z) -> { "id": StringName, "facing": int, "params": {} }.
@export var objects: Dictionary = {}

## Sparse per-edge parameters (e.g. a stone door's target_scene_path). Keyed by an
## edge string "V:x,z" / "H:x,z" -> { param_name: value }. Cleared when the edge is
## erased. Edges themselves are ints in edges_v/edges_h; this holds their extras.
@export var edge_params: Dictionary = {}

## Sparse per-cell floor textures (the Floor Textures layer): Vector2i(x, z) -> the
## name of a WallTextures set. A cell not listed wears its tile's plain material.
## Cleared when the cell's floor is erased.
@export var floor_textures: Dictionary = {}

## Sparse ceilings (the Ceilings layer): Vector2i(x, z) -> the name of a
## WallTextures set, or "" for one that takes the level's commonest wall texture. A cell not listed is open to the
## sky. Only floor can be roofed; erasing the floor removes its ceiling.
@export var ceilings: Dictionary = {}

## Sparse per-cell wear (the Wear layer): Vector2i(x, z) -> Wear.CLEAN or
## Wear.HEAVY. A cell not listed is Wear.NORMAL. It scales the grime, moss, cracks
## and puddles on the cell's floor, ceiling and the walls beside it (see
## WallTextures.set_level_wear). Cleared when the cell's floor is erased.
enum Wear { CLEAN, NORMAL, HEAVY }
@export var wear: Dictionary = {}

## This floor's sky (see LevelSky): its settings, edited in the Level Editor's Sky
## panel. Empty, or "enabled": false, means no sky - an underground level.
@export var sky: Dictionary = {}

## Painted trigger links (the Links layer): "this lever works that door". Each is
## { "from": key, "to": key } where a key names a placement on this floor —
## "obj:x,z" for an object, "V:x,z" / "H:x,z" for an edge (see object_key/edge_key).
## What a link actually sets on the built nodes comes from the source tile's
## TileDef.link_rules; LevelPaintedLinks applies them at build time.
@export var links: Array[Dictionary] = []

## Optional explicit spawn cell + facing. If spawn_cell.x < 0 the builder falls
## back to the first floor cell it finds.
@export var spawn_cell: Vector2i = Vector2i(-1, -1)
@export var spawn_facing: Facing = Facing.NORTH


func _init() -> void:
	# Ensure the arrays match width/height the first time (a freshly-constructed
	# resource has empty arrays; a loaded .tres already has them sized).
	if floors.size() != width * height:
		_reset_arrays()


#region Bounds / indexing
func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < width and z >= 0 and z < height

func _floor_idx(x: int, z: int) -> int:
	return z * width + x

func _v_idx(x: int, z: int) -> int:
	return z * (width + 1) + x

func _h_idx(x: int, z: int) -> int:
	return z * width + x
#endregion


#region Floors
func get_floor(x: int, z: int) -> int:
	if not in_bounds(x, z):
		return 0
	return floors[_floor_idx(x, z)]

func set_floor(x: int, z: int, id: int) -> void:
	if in_bounds(x, z):
		floors[_floor_idx(x, z)] = id
		if id == 0:
			floor_textures.erase(Vector2i(x, z))
			ceilings.erase(Vector2i(x, z))
			wear.erase(Vector2i(x, z))

func get_floor_texture(x: int, z: int) -> String:
	return floor_textures.get(Vector2i(x, z), "")

func has_ceiling(x: int, z: int) -> bool:
	return ceilings.has(Vector2i(x, z))

## The texture of the ceiling over a cell ("" = plain, or no ceiling at all).
func get_ceiling(x: int, z: int) -> String:
	return ceilings.get(Vector2i(x, z), "")

## Roof a cell with `texture` ("" = a plain ceiling). Does nothing where there is
## no floor.
func set_ceiling(x: int, z: int, texture: String) -> void:
	if get_floor(x, z) != 0:
		ceilings[Vector2i(x, z)] = texture

func erase_ceiling(x: int, z: int) -> void:
	ceilings.erase(Vector2i(x, z))

func get_wear(x: int, z: int) -> int:
	return wear.get(Vector2i(x, z), Wear.NORMAL)

## Set how worn a cell is (a Wear value). Does nothing where there is no floor.
func set_wear(x: int, z: int, level: int) -> void:
	if get_floor(x, z) == 0:
		return
	if level == Wear.NORMAL:
		wear.erase(Vector2i(x, z))
	else:
		wear[Vector2i(x, z)] = level

## Texture the floor at a cell ("" = back to plain). Does nothing where there is
## no floor.
func set_floor_texture(x: int, z: int, texture: String) -> void:
	if get_floor(x, z) == 0:
		return
	if texture == "":
		floor_textures.erase(Vector2i(x, z))
	else:
		floor_textures[Vector2i(x, z)] = texture
#endregion


#region Edges
## Vertical edge value (x in [0, width], z in [0, height)).
func get_edge_v(x: int, z: int) -> int:
	if x < 0 or x > width or z < 0 or z >= height:
		return 0
	return edges_v[_v_idx(x, z)]

func set_edge_v(x: int, z: int, id: int) -> void:
	if x >= 0 and x <= width and z >= 0 and z < height:
		if edges_v[_v_idx(x, z)] != id:
			remove_links_touching(edge_key("V", x, z))   # a different thing stands here now
		edges_v[_v_idx(x, z)] = id
		if id == 0:
			edge_params.erase(edge_key("V", x, z))

## Horizontal edge value (x in [0, width), z in [0, height]).
func get_edge_h(x: int, z: int) -> int:
	if x < 0 or x >= width or z < 0 or z > height:
		return 0
	return edges_h[_h_idx(x, z)]

func set_edge_h(x: int, z: int, id: int) -> void:
	if x >= 0 and x < width and z >= 0 and z <= height:
		if edges_h[_h_idx(x, z)] != id:
			remove_links_touching(edge_key("H", x, z))
		edges_h[_h_idx(x, z)] = id
		if id == 0:
			edge_params.erase(edge_key("H", x, z))

## Stable string key for an edge's params. axis is "V" (vertical) or "H" (horizontal).
func edge_key(axis: String, a: int, b: int) -> String:
	return "%s:%d,%d" % [axis, a, b]

func get_edge_params(axis: String, a: int, b: int) -> Dictionary:
	return edge_params.get(edge_key(axis, a, b), {})

func set_edge_param(axis: String, a: int, b: int, pname: String, value) -> void:
	var key := edge_key(axis, a, b)
	var d: Dictionary = edge_params.get(key, {})
	d[pname] = value
	edge_params[key] = d

## Edge value on a given SIDE of a cell. Convenience for painting.
func get_edge_on(x: int, z: int, side: Facing) -> int:
	match side:
		Facing.NORTH: return get_edge_h(x, z)
		Facing.SOUTH: return get_edge_h(x, z + 1)
		Facing.WEST:  return get_edge_v(x, z)
		Facing.EAST:  return get_edge_v(x + 1, z)
	return 0

func set_edge_on(x: int, z: int, side: Facing, id: int) -> void:
	match side:
		Facing.NORTH: set_edge_h(x, z, id)
		Facing.SOUTH: set_edge_h(x, z + 1, id)
		Facing.WEST:  set_edge_v(x, z, id)
		Facing.EAST:  set_edge_v(x + 1, z, id)
#endregion


#region Objects
func get_object(x: int, z: int) -> Dictionary:
	return objects.get(Vector2i(x, z), {})

## Place (or re-place) an object. Re-placing the same id at a cell keeps its params
## (so re-clicking to fix the facing doesn't wipe a chest's contents); a different
## id starts fresh.
func set_object(x: int, z: int, id: StringName, facing: Facing = Facing.NORTH) -> void:
	if not in_bounds(x, z):
		return
	var key := Vector2i(x, z)
	var params: Dictionary = {}
	if objects.has(key) and objects[key].get("id", &"") == id:
		params = objects[key].get("params", {})
	elif objects.has(key):
		remove_links_touching(object_key(x, z))   # replaced by a different object
	objects[key] = { "id": id, "facing": int(facing), "params": params }

## Set one per-placement parameter value on an existing object.
func set_object_param(x: int, z: int, pname: String, value) -> void:
	var key := Vector2i(x, z)
	if not objects.has(key):
		return
	var entry: Dictionary = objects[key]
	if not entry.has("params"):
		entry["params"] = {}
	entry["params"][pname] = value
	objects[key] = entry

func erase_object(x: int, z: int) -> void:
	objects.erase(Vector2i(x, z))
	remove_links_touching(object_key(x, z))
#endregion


#region Links
## Key naming the object at a cell, for links (edges use edge_key()).
func object_key(x: int, z: int) -> String:
	return "obj:%d,%d" % [x, z]

func has_link(from: String, to: String) -> bool:
	for l in links:
		if l.get("from", "") == from and l.get("to", "") == to:
			return true
	return false

## Add the link, or remove it if it is already there. Returns true when the pair
## ends up linked.
func toggle_link(from: String, to: String) -> bool:
	for i in links.size():
		if links[i].get("from", "") == from and links[i].get("to", "") == to:
			links.remove_at(i)
			return false
	links.append({ "from": from, "to": to })
	return true

## Drop every link that starts or ends at `key`. Returns how many were removed.
func remove_links_touching(key: String) -> int:
	if links.is_empty():
		return 0
	var kept: Array[Dictionary] = []
	for l in links:
		if l.get("from", "") != key and l.get("to", "") != key:
			kept.append(l)
	var removed := links.size() - kept.size()
	links = kept
	return removed
#endregion


#region Bulk edits (rectangle / room / fill / auto-wall tools)
## Set every floor cell in the inclusive rectangle (corners in any order; clipped
## to the grid). id 0 erases.
func fill_rect(x0: int, z0: int, x1: int, z1: int, id: int) -> void:
	for z in range(maxi(mini(z0, z1), 0), mini(maxi(z0, z1), height - 1) + 1):
		for x in range(maxi(mini(x0, x1), 0), mini(maxi(x0, x1), width - 1) + 1):
			floors[_floor_idx(x, z)] = id

## Put `edge_id` on the perimeter of the inclusive rectangle. Only EMPTY edges are
## written, so doors (or other walls) already on the outline are kept.
func wall_rect(x0: int, z0: int, x1: int, z1: int, edge_id: int) -> void:
	var lx := maxi(mini(x0, x1), 0)
	var hx := mini(maxi(x0, x1), width - 1)
	var lz := maxi(mini(z0, z1), 0)
	var hz := mini(maxi(z0, z1), height - 1)
	for x in range(lx, hx + 1):
		if get_edge_h(x, lz) == 0: set_edge_h(x, lz, edge_id)
		if get_edge_h(x, hz + 1) == 0: set_edge_h(x, hz + 1, edge_id)
	for z in range(lz, hz + 1):
		if get_edge_v(lx, z) == 0: set_edge_v(lx, z, edge_id)
		if get_edge_v(hx + 1, z) == 0: set_edge_v(hx + 1, z, edge_id)

## Flood-fill floors from (x, z): every cell reachable through same-floor cells
## without crossing a wall/door edge gets `id`. Returns the number of cells changed.
func flood_fill(x: int, z: int, id: int) -> int:
	if not in_bounds(x, z):
		return 0
	var from := get_floor(x, z)
	if from == id:
		return 0
	var changed := 0
	var stack: Array[Vector2i] = [Vector2i(x, z)]
	floors[_floor_idx(x, z)] = id
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		changed += 1
		for side in [Facing.NORTH, Facing.EAST, Facing.SOUTH, Facing.WEST]:
			if get_edge_on(c.x, c.y, side) != 0:
				continue
			var n := c + _side_step(side)
			if in_bounds(n.x, n.y) and floors[_floor_idx(n.x, n.y)] == from:
				floors[_floor_idx(n.x, n.y)] = id
				stack.append(n)
	return changed

## Wall off the level: every floor cell side that faces void (an empty cell or the
## grid boundary) and has no edge yet gets `edge_id`. Existing walls and doors are
## left alone. Returns the number of edges added.
func auto_wall(edge_id: int) -> int:
	var added := 0
	for z in height:
		for x in width:
			if floors[_floor_idx(x, z)] == 0:
				continue
			for side in [Facing.NORTH, Facing.EAST, Facing.SOUTH, Facing.WEST]:
				var n := Vector2i(x, z) + _side_step(side)
				if get_floor(n.x, n.y) == 0 and get_edge_on(x, z, side) == 0:
					set_edge_on(x, z, side, edge_id)
					added += 1
	return added

func _side_step(side: int) -> Vector2i:
	match side:
		Facing.NORTH: return Vector2i(0, -1)
		Facing.EAST:  return Vector2i(1, 0)
		Facing.SOUTH: return Vector2i(0, 1)
	return Vector2i(-1, 0)
#endregion


#region Sizing
## Allocate blank layers for the current width/height, discarding contents.
func _reset_arrays() -> void:
	floors = PackedInt32Array(); floors.resize(width * height)
	edges_v = PackedInt32Array(); edges_v.resize((width + 1) * height)
	edges_h = PackedInt32Array(); edges_h.resize(width * (height + 1))
	objects = {}
	floor_textures = {}
	ceilings = {}
	wear = {}
	# `links` is left alone: resize() calls this and must keep them. A link whose
	# end fell off the grid simply stops resolving (LevelPaintedLinks skips it).

## Resize the grid, preserving overlapping cells/edges/objects. Call this instead
## of assigning width/height directly.
func resize(new_w: int, new_h: int) -> void:
	new_w = maxi(1, new_w)
	new_h = maxi(1, new_h)
	if new_w == width and new_h == height and floors.size() == width * height:
		return
	var old_w := width
	var old_h := height
	var old_floors := floors
	var old_v := edges_v
	var old_h_arr := edges_h
	var old_objects := objects
	var old_floor_textures := floor_textures
	var old_ceilings := ceilings
	var old_wear := wear

	width = new_w
	height = new_h
	_reset_arrays()

	# Only copy if we actually had matching-sized old data (guards first init).
	if old_floors.size() == old_w * old_h:
		for z in mini(old_h, new_h):
			for x in mini(old_w, new_w):
				floors[_floor_idx(x, z)] = old_floors[z * old_w + x]
	if old_v.size() == (old_w + 1) * old_h:
		for z in mini(old_h, new_h):
			for x in mini(old_w + 1, new_w + 1):
				edges_v[_v_idx(x, z)] = old_v[z * (old_w + 1) + x]
	if old_h_arr.size() == old_w * (old_h + 1):
		for z in mini(old_h + 1, new_h + 1):
			for x in mini(old_w, new_w):
				edges_h[_h_idx(x, z)] = old_h_arr[z * old_w + x]
	for key in old_objects:
		if key.x < new_w and key.y < new_h:
			objects[key] = old_objects[key]
	for key in old_floor_textures:
		if key.x < new_w and key.y < new_h:
			floor_textures[key] = old_floor_textures[key]
	for key in old_ceilings:
		if key.x < new_w and key.y < new_h:
			ceilings[key] = old_ceilings[key]
	for key in old_wear:
		if key.x < new_w and key.y < new_h:
			wear[key] = old_wear[key]
#endregion
