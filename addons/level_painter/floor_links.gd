@tool
class_name LevelFloorLinks
extends RefCounted

## Connects floors of a dungeon to each other. A "connector" is any painted tile
## whose TileDef has a param of type "floor_link" (stairs, the stone door). You
## pick the floor it leads to in the dock; at build time resolve_into() works out
## the two things the runtime actually needs and writes them into the placement:
##
##   target_scene_path         the target floor's built scene
##   target_spawn_marker_name  where the party arrives on it
##
## Every connector also gets an arrival marker in the built level (see
## GridLevelBuilder._build_arrivals): "Arrive_<node name>", one step in front of
## the stairs / on the room side of the door, facing away from it. By default a
## connector arrives at its partner — the connector on the target floor that leads
## back here — so a staircase drops you at the foot of the matching staircase.
##
## A pit trap (TileDef.is_pit) is a one-way connector: nothing arrives at it, and by
## default it lands the party on the cell directly below it. Floors of a dungeon
## share one grid, so that needs no marker: the trap is given MARKER_BELOW and
## works the spot out from its own position.

const PARAM_FLOOR := "leads_to_floor"        ## uid of the floor this leads to ("" = set by hand)
const PARAM_ARRIVAL := "arrive_at"           ## ARRIVE_AUTO, ARRIVE_SPAWN, or a connector key
const PARAM_SCENE := "target_scene_path"
const PARAM_MARKER := "target_spawn_marker_name"

const ARRIVE_AUTO := ""
const ARRIVE_SPAWN := "spawn"
const SPAWN_MARKER := "PlayerSpawn"
const MARKER_BELOW := ""                     ## pit trap: land on the cell directly below


static func is_connector(def: TileDef) -> bool:
	if def == null:
		return false
	for p in def.params:
		if p.get("type", "") == "floor_link":
			return true
	return false

## Name of the arrival marker the builder makes for a connector node.
static func marker_name(node_name: String) -> String:
	return "Arrive_" + node_name

## Every connector painted on a floor. Each entry:
##   { key, kind ("object"|"edge"), pit, node_name, label, params, cell | axis+a+b }
## `key` identifies the connector on its floor ("obj:x,z", "V:x,z", "H:x,z").
static func connectors(data: GridLevelData, catalog: TileCatalog) -> Array:
	var out: Array = []
	if data == null or catalog == null:
		return out
	for cell in data.objects:
		var entry: Dictionary = data.objects[cell]
		var def := catalog.get_object(entry.get("id", &""))
		if not is_connector(def):
			continue
		out.append({
			"key": "obj:%d,%d" % [cell.x, cell.y], "kind": "object", "cell": cell, "pit": def.is_pit,
			"node_name": "%s_%d_%d" % [String(def.name_id), cell.x, cell.y],
			"label": "%s (%d, %d)" % [def.display_name, cell.x, cell.y],
			"params": entry.get("params", {}),
		})
	for z in data.height:
		for x in range(data.width + 1):
			_add_edge(out, data, catalog, "V", x, z, data.get_edge_v(x, z))
	for z in range(data.height + 1):
		for x in data.width:
			_add_edge(out, data, catalog, "H", x, z, data.get_edge_h(x, z))
	return out

static func _add_edge(out: Array, data: GridLevelData, catalog: TileCatalog,
		axis: String, a: int, b: int, id: int) -> void:
	if id == 0:
		return
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id)
	if not is_connector(def):
		return
	out.append({
		"key": data.edge_key(axis, a, b), "kind": "edge", "axis": axis, "a": a, "b": b, "pit": false,
		"node_name": "%s_%s_%d_%d" % [GridLevelBuilder._sanitize(def.display_name), axis, a, b],
		"label": "%s (%s %d, %d)" % [def.display_name, axis, a, b],
		"params": data.get_edge_params(axis, a, b),
	})

## The connectors a party can ARRIVE at: all of them but the pit traps.
static func arrival_points(data: GridLevelData, catalog: TileCatalog) -> Array:
	return connectors(data, catalog).filter(func(c): return not c.pit)

## The floor drawn as a blueprint under `floor` in the editors: the one its pit
## traps drop to, else the next floor in the dungeon's list. Null if there is none.
static func floor_below(dungeon: DungeonData, floor: GridLevelData, catalog: TileCatalog) -> GridLevelData:
	if dungeon == null or floor == null:
		return null
	for c in connectors(floor, catalog):
		if c.pit:
			var target := dungeon.floor_by_uid(c.params.get(PARAM_FLOOR, ""))
			if target != null and target != floor:
				return target
	var index := dungeon.floors.find(floor)
	return dungeon.get_floor(index + 1) if index >= 0 else null

## Does pit trap `c` land the party on the cell directly below it?
static func lands_below(c: Dictionary) -> bool:
	return c.pit and c.params.get(PARAM_ARRIVAL, ARRIVE_AUTO) == ARRIVE_AUTO

## Cells of `floor` that pit traps on the dungeon's other floors drop the party onto.
static func pit_landings(dungeon: DungeonData, floor: GridLevelData, catalog: TileCatalog) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if dungeon == null or floor == null:
		return out
	for other in dungeon.floors:
		if other == null or other == floor:
			continue
		for c in connectors(other, catalog):
			if lands_below(c) and c.params.get(PARAM_FLOOR, "") == floor.uid \
					and floor.get_floor(c.cell.x, c.cell.y) != 0:
				out.append(c.cell)
	return out

## Fill in target_scene_path / target_spawn_marker_name for every connector on
## `floor` that leads to another floor of `dungeon`. `floor_path` is where `floor`
## is being built. Connectors with no floor chosen keep their hand-set values.
## Returns human-readable warnings (empty when everything resolved cleanly).
static func resolve_into(dungeon: DungeonData, floor: GridLevelData, floor_path: String,
		catalog: TileCatalog) -> Array:
	var warnings: Array = []
	if dungeon == null or floor == null:
		return warnings
	for c in connectors(floor, catalog):
		var target_uid: String = c.params.get(PARAM_FLOOR, "")
		if target_uid == "":
			continue
		var target := dungeon.floor_by_uid(target_uid)
		if target == null:
			warnings.append("%s on '%s' leads to a floor that is not in this dungeon; its last target was kept."
				% [c.label, floor.level_name])
			continue
		if target.built_path == "":
			warnings.append("'%s' has not been built yet; %s on '%s' assumes %s."
				% [target.level_name, c.label, floor.level_name, path_for(target, floor_path)])
		var marker := _resolve_arrival(floor, target, c, catalog, warnings)
		_write(floor, c, PARAM_SCENE, path_for(target, floor_path))
		_write(floor, c, PARAM_MARKER, marker)
	return warnings

## Scene path a floor is (or will be) built to: its recorded build path, else a
## file named after it next to the floor that is linking to it.
static func path_for(target: GridLevelData, linking_floor_path: String) -> String:
	if target.built_path != "":
		return target.built_path
	return linking_floor_path.get_base_dir().path_join(sanitize_filename(target.level_name) + ".tscn")

static func _resolve_arrival(floor: GridLevelData, target: GridLevelData, c: Dictionary,
		catalog: TileCatalog, warnings: Array) -> String:
	var choice: String = c.params.get(PARAM_ARRIVAL, ARRIVE_AUTO)
	if choice == ARRIVE_SPAWN:
		return SPAWN_MARKER
	var there := arrival_points(target, catalog)
	if choice == ARRIVE_AUTO and c.pit:
		if target.get_floor(c.cell.x, c.cell.y) != 0:
			return MARKER_BELOW
		warnings.append("%s on '%s' has no floor below it on '%s'; using its spawn point."
			% [c.label, floor.level_name, target.level_name])
		return SPAWN_MARKER
	if choice != ARRIVE_AUTO:
		for t in there:
			if t.key == choice:
				return marker_name(t.node_name)
		warnings.append("%s on '%s' arrives at something that no longer exists on '%s'; using its spawn point."
			% [c.label, floor.level_name, target.level_name])
		return SPAWN_MARKER
	# Auto: the connector over there that leads back here. Stairs between floors
	# usually share a cell, so prefer the one at the same spot.
	var partner := {}
	for t in there:
		if t.params.get(PARAM_FLOOR, "") != floor.uid:
			continue
		if partner.is_empty() or t.key == c.key:
			partner = t
	return marker_name(partner.node_name) if not partner.is_empty() else SPAWN_MARKER

static func _write(floor: GridLevelData, c: Dictionary, pname: String, value) -> void:
	if c.kind == "object":
		floor.set_object_param(c.cell.x, c.cell.y, pname, value)
	else:
		floor.set_edge_param(c.axis, c.a, c.b, pname, value)

## Turn a floor name into a safe file basename.
static func sanitize_filename(s: String) -> String:
	var out := s.strip_edges()
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "."]:
		out = out.replace(bad, "_")
	return out if out != "" else "floor"
