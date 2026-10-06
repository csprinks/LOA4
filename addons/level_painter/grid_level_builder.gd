@tool
class_name GridLevelBuilder
extends RefCounted

## Turns a GridLevelData (+ TileCatalog) into a 3D Node3D subtree: floor tiles,
## ceiling slabs, per-edge wall/door panels, props, and a PlayerSpawn marker. Pure construction —
## no editor/runtime state — so both the dock ("Build Level") and a runtime loader
## can call build() and get the same result.
##
## World mapping (matches the game's 2-unit grid):
##   cell (x, z) center      -> (x*CELL, 0, z*CELL)
##   vertical edge ex        -> world X (ex - 0.5)*CELL  (runs along Z, yaw 90°)
##   horizontal edge ez      -> world Z (ez - 0.5)*CELL  (runs along X, yaw 0°)

const CELL := GridLevelData.CELL


## Build the whole level under a fresh Node3D and return it. `owner_for_editor`,
## if given, is set as the owner of every created node so they get saved into a
## packed scene (needed when building to a .tscn from the editor).
static func build(data: GridLevelData, catalog: TileCatalog, owner_for_editor: Node = null) -> Node3D:
	var root := Node3D.new()
	root.name = _sanitize(data.level_name) if data.level_name != "" else "GridLevel"

	var floors_parent := _child(root, "Floors", owner_for_editor)
	var walls_parent := _child(root, "Walls", owner_for_editor)
	var objects_parent := _child(root, "Objects", owner_for_editor)

	_build_floors(data, catalog, floors_parent, owner_for_editor)
	if not data.ceilings.is_empty():
		_build_ceilings(data, _child(root, "Ceilings", owner_for_editor), owner_for_editor)
	_build_edges(data, catalog, walls_parent, owner_for_editor)
	_build_corner_posts(data, catalog, walls_parent, owner_for_editor)
	_build_objects(data, catalog, objects_parent, owner_for_editor)
	_build_spawn(data, root, owner_for_editor)
	_build_arrivals(data, catalog, _child(root, "Arrivals", owner_for_editor), owner_for_editor)

	return root


#region Floors
static func _build_floors(data: GridLevelData, catalog: TileCatalog, parent: Node, own: Node) -> void:
	var n := 0
	for z in data.height:
		for x in data.width:
			var id := data.get_floor(x, z)
			if id == 0 or _is_pit_cell(data, catalog, x, z):
				continue   # a pit trap is its own floor
			var def := catalog.get_by_id(TileDef.Kind.FLOOR, id)
			var node := _instance_or_slab(def, Vector3(CELL, 0.4, CELL), Color(0.6, 0.55, 0.42))
			node.name = "Floor_%d_%d" % [x, z]
			var texture := data.get_floor_texture(x, z)
			if texture != "":
				if node.get_script() == null:   # a bare slab, not the floor tile scene
					node.set_script(TEXTURED_WALL)
				node.set(WallTextures.PARAM, texture)
			parent.add_child(node)
			node.position = Vector3(x * CELL, (def.y_offset if def else 0.0), z * CELL)
			_own(node, own)
			n += 1

static func _is_pit_cell(data: GridLevelData, catalog: TileCatalog, x: int, z: int) -> bool:
	var entry := data.get_object(x, z)
	if entry.is_empty():
		return false
	var def := catalog.get_object(entry.get("id", &""))
	return def != null and def.is_pit

## The floor texture a pit trap at `cell` takes on to blend in: the commonest one
## among the floor cells beside it ("" = plain floor), the earliest on a tie. Falls
## back to the cells diagonal to it, then to what is painted on its own cell.
static func surrounding_floor_texture(data: GridLevelData, cell: Vector2i) -> String:
	for ring in [[Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)],
			[Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]]:
		var counts := {}   # insertion-ordered, so a tie goes to the first seen
		for step: Vector2i in ring:
			var n := cell + step
			if data.get_floor(n.x, n.y) != 0:
				var texture := data.get_floor_texture(n.x, n.y)
				counts[texture] = int(counts.get(texture, 0)) + 1
		var best := ""
		var best_count := 0
		for texture in counts:
			if counts[texture] > best_count:
				best = texture
				best_count = counts[texture]
		if best_count > 0:
			return best
	return data.get_floor_texture(cell.x, cell.y)
#endregion


#region Ceilings
const WALL_HEIGHT := 3.0
const CEILING_THICKNESS := 0.2
const CEILING_COLOR := Color(0.30, 0.26, 0.22)

## One slab per roofed cell, resting on top of the walls. It casts shadow, so a
## roofed room is dark under a sky; nothing walks up there, so it has no collider.
static func _build_ceilings(data: GridLevelData, parent: Node, own: Node) -> void:
	var plain := StandardMaterial3D.new()
	plain.albedo_color = CEILING_COLOR
	plain.roughness = 0.95
	for cell in data.ceilings:
		if data.get_floor(cell.x, cell.y) == 0:
			continue
		var slab := CSGBox3D.new()
		slab.name = "Ceiling_%d_%d" % [cell.x, cell.y]
		slab.size = Vector3(CELL, CEILING_THICKNESS, CELL)
		slab.material = plain
		var texture := String(data.ceilings[cell])
		if texture != "":
			slab.set_script(TEXTURED_WALL)
			slab.set(WallTextures.PARAM, texture)
		parent.add_child(slab)
		slab.position = Vector3(cell.x * CELL, WALL_HEIGHT + CEILING_THICKNESS * 0.5, cell.y * CELL)
		_own(slab, own)
#endregion


#region Edges (walls / doors)
static func _build_edges(data: GridLevelData, catalog: TileCatalog, parent: Node, own: Node) -> void:
	# Vertical edges: run along Z, yaw 90°, at world X (ex - 0.5)*CELL.
	for z in data.height:
		for ex in range(data.width + 1):
			var id := data.get_edge_v(ex, z)
			if id != 0:
				_place_edge(data, catalog, parent, own, id,
					Vector3((ex - 0.5) * CELL, 0.0, z * CELL), PI * 0.5, "V", ex, z)
	# Horizontal edges: run along X, yaw 0°, at world Z (ez - 0.5)*CELL.
	for ez in range(data.height + 1):
		for x in data.width:
			var id := data.get_edge_h(x, ez)
			if id != 0:
				_place_edge(data, catalog, parent, own, id,
					Vector3(x * CELL, 0.0, (ez - 0.5) * CELL), 0.0, "H", x, ez)

static func _place_edge(data: GridLevelData, catalog: TileCatalog, parent: Node, own: Node,
		id: int, pos: Vector3, yaw: float, tag: String, a: int, b: int) -> void:
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id)
	var node := _instance_or_slab(def, Vector3(CELL, 3.0, 0.2), Color(0.35, 0.30, 0.25))
	# Name by the tile (Wall_…, Stone_Door_…) so doors are findable in the node list,
	# not lost among generic Edge_ entries. Keep the H/V + coords suffix as an anchor.
	var prefix := _sanitize(def.display_name) if def else "Edge"
	node.name = "%s_%s_%d_%d" % [prefix, tag, a, b]
	parent.add_child(node)
	node.position = pos + Vector3.UP * (def.y_offset if def else 0.0)
	node.rotation.y = yaw
	if def:
		_apply_params(node, def, data.get_edge_params(tag, a, b))
	# Transition doors sit in a solid wall: build a backing panel on the same edge
	# and nudge the door toward the room so it stays visible in front of it.
	if def and def.wall_backed:
		var wall_def := catalog.get_by_id(TileDef.Kind.EDGE, 1)
		var wall := _instance_or_slab(wall_def, Vector3(CELL, 3.0, 0.2), Color(0.35, 0.30, 0.25))
		wall.name = "WallBack_%s_%d_%d" % [tag, a, b]
		parent.add_child(wall)
		wall.position = pos
		wall.rotation.y = yaw
		# The wall a door is set in wears whatever texture was painted on that edge.
		wall.set(WallTextures.PARAM, data.get_edge_params(tag, a, b).get(WallTextures.PARAM, ""))
		_own(wall, own)
		node.position += _inside_dir(data, tag, a, b) * 0.3   # clear of the wall face
	_own(node, own)

## Unit direction from an edge toward the adjacent cell that has a floor (the room
## side), or ZERO if both/neither do. Used to nudge a wall-backed door into view.
static func _inside_dir(data: GridLevelData, tag: String, a: int, b: int) -> Vector3:
	if tag == "V":   # edge a is west of cell a; neighbours are (a-1, b) and (a, b)
		var west := data.get_floor(a - 1, b) != 0
		var east := data.get_floor(a, b) != 0
		if east and not west: return Vector3(1, 0, 0)
		if west and not east: return Vector3(-1, 0, 0)
	else:            # edge b is north of cell b; neighbours are (a, b-1) and (a, b)
		var north := data.get_floor(a, b - 1) != 0
		var south := data.get_floor(a, b) != 0
		if south and not north: return Vector3(0, 0, 1)
		if north and not south: return Vector3(0, 0, -1)
	return Vector3.ZERO
#endregion


#region Corner posts
## Fill the seam where a vertical and a horizontal wall meet. A thin panel only
## covers its own edge line, so at an L/T/X junction the two panels leave a small
## notch at the corner. We drop a short pillar on any grid vertex that has walls in
## BOTH axes — corners and junctions get a clean post, straight runs get nothing.
const POST_SIZE := 0.26   # a touch wider than the 0.2 panel thickness
const TEXTURED_WALL := preload("res://addons/level_painter/blocks/textured_wall.gd")

static func _build_corner_posts(data: GridLevelData, catalog: TileCatalog, parent: Node, own: Node) -> void:
	var col := Color(0.34, 0.29, 0.24)
	var wall_def := catalog.get_by_id(TileDef.Kind.EDGE, 1) if catalog else null
	if wall_def:
		col = wall_def.color
	for vz in range(data.height + 1):
		for vx in range(data.width + 1):
			var has_h := data.get_edge_h(vx - 1, vz) != 0 or data.get_edge_h(vx, vz) != 0
			var has_v := data.get_edge_v(vx, vz - 1) != 0 or data.get_edge_v(vx, vz) != 0
			if not (has_h and has_v):
				continue
			var post := CSGBox3D.new()
			post.name = "Post_%d_%d" % [vx, vz]
			post.size = Vector3(POST_SIZE, 3.0, POST_SIZE)
			post.use_collision = true
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			post.material = mat
			# Match the walls meeting here, if any of them has a painted texture.
			var texture := _post_texture(data, vx, vz)
			if texture != "":
				post.set_script(TEXTURED_WALL)
				post.set(WallTextures.PARAM, texture)
			parent.add_child(post)
			post.position = Vector3((vx - 0.5) * CELL, 1.5, (vz - 0.5) * CELL)
			_own(post, own)
#endregion


## The painted texture of the first textured wall touching grid vertex (vx, vz).
static func _post_texture(data: GridLevelData, vx: int, vz: int) -> String:
	for edge in [["H", vx - 1, vz], ["H", vx, vz], ["V", vx, vz - 1], ["V", vx, vz]]:
		var id := data.get_edge_h(edge[1], edge[2]) if edge[0] == "H" else data.get_edge_v(edge[1], edge[2])
		if id == 0:
			continue
		var texture := String(data.get_edge_params(edge[0], edge[1], edge[2]).get(WallTextures.PARAM, ""))
		if texture != "":
			return texture
	return ""


#region Objects
static func _build_objects(data: GridLevelData, catalog: TileCatalog, parent: Node, own: Node) -> void:
	for key in data.objects:
		var entry: Dictionary = data.objects[key]
		var def := catalog.get_object(entry.get("id", &""))
		if def == null or def.scene_path == "":
			continue
		var scene := load(def.scene_path)
		if scene == null:
			push_warning("GridLevelBuilder: object scene missing: " + def.scene_path)
			continue
		var node: Node3D = scene.instantiate()
		node.name = "%s_%d_%d" % [String(def.name_id), key.x, key.y]
		parent.add_child(node)
		node.position = Vector3(key.x * CELL, def.y_offset, key.y * CELL)
		var facing := int(entry.get("facing", 0))
		# Wall-mounted props (levers) slide back to the wall behind them — opposite
		# the way they face — instead of floating at the cell centre.
		if def.wall_mounted:
			node.position -= _facing_world(facing) * (CELL * 0.5 - 0.1)
		node.rotation.y = _facing_to_yaw(facing) + deg_to_rad(def.facing_offset)
		_apply_params(node, def, entry.get("params", {}))
		if def.is_pit:
			node.set(WallTextures.PARAM, surrounding_floor_texture(data, key))
		_own(node, own)  # instance root only; Godot saves the subtree as an instance

## Push a placement's per-parameter values onto the instanced node via set(). The
## schema lives on the TileDef; the values (or the schema default) come from the
## placement. resource_list loads each path and assigns into the node's typed array.
static func _apply_params(node: Node, def: TileDef, params: Dictionary) -> void:
	for p in def.params:
		var pname: String = p.get("name", "")
		if pname == "":
			continue
		var val = params.get(pname, p.get("default", null))
		if val == null or p.get("painter_only", false):
			continue   # painter_only: read by the painter itself (e.g. link rules), not a node property
		match p.get("type", "string"):
			"floor_link", "arrival":
				pass   # painter-only; LevelFloorLinks turns these into the scene + marker params
			"resource_list":
				var loaded := []
				for path in val:
					if typeof(path) == TYPE_STRING and path != "":
						var r = load(path)
						if r != null:
							loaded.append(r)
				var existing = node.get(pname)
				if existing is Array:
					# Fill a copy, never the array read back: in the editor that can be
					# the scene's shared default, and an in-place edit would not be saved.
					var typed_list: Array = existing.duplicate()
					typed_list.assign(loaded)   # preserves the export's element type
					node.set(pname, typed_list)
				else:
					node.set(pname, loaded)
			"int_list":
				var ints := []
				for v in val:
					ints.append(int(v))
				var current = node.get(pname)
				if current is Array:
					var typed_ints: Array = current.duplicate()
					typed_ints.assign(ints)   # preserves a typed (e.g. enum) array
					node.set(pname, typed_ints)
				else:
					node.set(pname, ints)
			"enum", "int":
				node.set(pname, int(val))
			"float":
				node.set(pname, float(val))
			_:
				node.set(pname, val)
#endregion



#region Spawn
static func _build_spawn(data: GridLevelData, root: Node, own: Node) -> void:
	var cell := data.spawn_cell
	if cell.x < 0:
		cell = _first_floor_cell(data)
	if cell.x < 0:
		return
	var marker := Marker3D.new()
	marker.name = "PlayerSpawn"
	root.add_child(marker)
	marker.position = Vector3(cell.x * CELL, 0.5, cell.y * CELL)
	marker.rotation.y = _facing_to_yaw(data.spawn_facing)
	_own(marker, own)

static func _first_floor_cell(data: GridLevelData) -> Vector2i:
	for z in data.height:
		for x in data.width:
			if data.get_floor(x, z) != 0:
				return Vector2i(x, z)
	return Vector2i(-1, -1)
#endregion


#region Arrival markers (where the party lands when coming from another floor)
## One Marker3D per connector (stairs, transition door), named
## LevelFloorLinks.marker_name(<node name>). Stairs: one cell out from the foot of
## the flight. Doors: the cell on the room side. Both face away from the connector.
## Pit traps get none: nothing arrives at a hole in the floor.
static func _build_arrivals(data: GridLevelData, catalog: TileCatalog, parent: Node, own: Node) -> void:
	for c in LevelFloorLinks.arrival_points(data, catalog):
		var pose := arrival_pose(data, catalog, c)
		var away: Vector3 = pose.away
		var marker := Marker3D.new()
		marker.name = LevelFloorLinks.marker_name(c.node_name)
		parent.add_child(marker)
		marker.position = Vector3(pose.cell.x * CELL, 0.5, pose.cell.y * CELL)   # standing height
		marker.rotation.y = atan2(-away.x, -away.z)   # forward (-Z) points away
		_own(marker, own)

## Where the party lands when arriving at connector `c` (an entry from
## LevelFloorLinks.connectors): { "cell": Vector2i, "away": Vector3 unit facing }.
static func arrival_pose(data: GridLevelData, catalog: TileCatalog, c: Dictionary) -> Dictionary:
	var pos: Vector3
	var away: Vector3
	if c.kind == "object":
		var entry: Dictionary = data.objects[c.cell]
		var def := catalog.get_object(entry.get("id", &""))
		var yaw := _facing_to_yaw(int(entry.get("facing", 0))) + deg_to_rad(def.facing_offset)
		var step := def.arrival_local.rotated(Vector3.UP, yaw)
		away = step.normalized() if step.length() > 0.01 else _facing_world(int(entry.get("facing", 0)))
		pos = Vector3(c.cell.x * CELL, 0.0, c.cell.y * CELL) + step * CELL
	else:
		away = _inside_dir(data, c.axis, c.a, c.b)
		if away == Vector3.ZERO:   # floor on both sides (or neither): pick a floored one
			if c.axis == "V":
				away = Vector3(1, 0, 0) if data.get_floor(c.a, c.b) != 0 else Vector3(-1, 0, 0)
			else:
				away = Vector3(0, 0, 1) if data.get_floor(c.a, c.b) != 0 else Vector3(0, 0, -1)
		var edge_pos := Vector3((c.a - 0.5) * CELL, 0.0, c.b * CELL) if c.axis == "V" \
			else Vector3(c.a * CELL, 0.0, (c.b - 0.5) * CELL)
		pos = edge_pos + away * CELL * 0.5
	# Round onto the grid (the rotations above leave float dust).
	return { "cell": Vector2i(roundi(pos.x / CELL), roundi(pos.z / CELL)), "away": away }
#endregion


#region Helpers
## Rotate a node so its default forward (-Z) points along the given cardinal.
## forward(yaw) = (-sin yaw, 0, -cos yaw); yaw = -facing * 90° gives N,E,S,W.
static func _facing_to_yaw(facing: int) -> float:
	return -float(facing) * PI * 0.5

## World-space unit vector for a facing cardinal (North = -Z, matching the game).
static func _facing_world(facing: int) -> Vector3:
	match facing:
		GridLevelData.Facing.NORTH: return Vector3(0, 0, -1)
		GridLevelData.Facing.EAST:  return Vector3(1, 0, 0)
		GridLevelData.Facing.SOUTH: return Vector3(0, 0, 1)
		GridLevelData.Facing.WEST:  return Vector3(-1, 0, 0)
	return Vector3(0, 0, -1)

## Instance the tile's scene, or fall back to a plain CSG box of `size`/`col`
## when the tile has no scene (used for floors painted as bare slabs).
static func _instance_or_slab(def: TileDef, size: Vector3, col: Color) -> Node3D:
	if def != null and def.scene_path != "":
		var scene := load(def.scene_path)
		if scene != null:
			return scene.instantiate()
		push_warning("GridLevelBuilder: scene missing, using slab: " + def.scene_path)
	var box := CSGBox3D.new()
	box.size = size
	box.use_collision = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	box.material = mat
	return box

static func _child(parent: Node, name: String, own: Node) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	_own(n, own)
	return n

static func _own(node: Node, own: Node) -> void:
	if own != null:
		node.owner = own

## Replace characters Godot disallows in node names (it would sanitize anyway,
## but doing it here keeps names predictable).
static func _sanitize(s: String) -> String:
	var out := s
	for bad in [".", ":", "@", "/", "%", " "]:
		out = out.replace(bad, "_")
	return out if out != "" else "GridLevel"
#endregion
