@tool
class_name LevelValidator
extends RefCounted

## Checks a painted floor for the mistakes that otherwise only show up in play:
## no way in, stairs and doors that lead nowhere, props floating over void, rooms
## nobody can reach. Pure data in, list of problems out — the dock shows the list
## and jumps to the cell when you click one.
##
## Each problem: { "severity": ERROR | WARNING, "text": String, "cell": Vector2i }
## (`cell` is (-1, -1) when the problem isn't tied to one spot.) Errors are things
## that will be broken in the built level; warnings are things that are probably
## not what you meant. Neither stops a build.

const ERROR := "error"
const WARNING := "warning"
const NO_CELL := Vector2i(-1, -1)

const _SIDES := [GridLevelData.Facing.NORTH, GridLevelData.Facing.EAST,
	GridLevelData.Facing.SOUTH, GridLevelData.Facing.WEST]


static func validate(dungeon: DungeonData, floor: GridLevelData, catalog: TileCatalog) -> Array:
	var out: Array = []
	if floor == null or catalog == null:
		return out
	if _floor_count(floor) == 0:
		_add(out, ERROR, "Nothing is painted on this floor.", NO_CELL)
		return out
	_check_spawn(floor, catalog, out)
	_check_objects(floor, catalog, out)
	_check_edges(floor, catalog, out)
	_check_connectors(dungeon, floor, catalog, out)
	_check_open_sides(floor, out)
	_check_reachability(dungeon, floor, catalog, out)
	# Errors first, then warnings; stable within each.
	var errors := out.filter(func(p): return p.severity == ERROR)
	var warnings := out.filter(func(p): return p.severity == WARNING)
	return errors + warnings

## "2 errors, 1 warning" (or "" when the list is empty).
static func summary(problems: Array) -> String:
	if problems.is_empty():
		return ""
	var errors := problems.filter(func(p): return p.severity == ERROR).size()
	var warnings := problems.size() - errors
	var parts: Array = []
	if errors > 0:
		parts.append("%d error%s" % [errors, "" if errors == 1 else "s"])
	if warnings > 0:
		parts.append("%d warning%s" % [warnings, "" if warnings == 1 else "s"])
	return ", ".join(parts)


#region Checks
static func _check_spawn(floor: GridLevelData, catalog: TileCatalog, out: Array) -> void:
	var cell := floor.spawn_cell
	if cell.x < 0:
		var first := GridLevelBuilder._first_floor_cell(floor)
		_add(out, WARNING, "No spawn point set; the party will start at the first floor cell (%d, %d)."
			% [first.x, first.y], first)
		return
	if floor.get_floor(cell.x, cell.y) == 0:
		_add(out, ERROR, "The spawn point (%d, %d) is not on a floor." % [cell.x, cell.y], cell)
	var entry := floor.get_object(cell.x, cell.y)
	if not entry.is_empty():
		var def := catalog.get_object(entry.get("id", &""))
		_add(out, WARNING, "The spawn point shares its cell with %s." % (def.display_name if def else "an object"), cell)

static func _check_objects(floor: GridLevelData, catalog: TileCatalog, out: Array) -> void:
	for cell in floor.objects:
		var entry: Dictionary = floor.objects[cell]
		var def := catalog.get_object(entry.get("id", &""))
		var where := "(%d, %d)" % [cell.x, cell.y]
		if def == null:
			_add(out, ERROR, "Unknown object '%s' at %s; it will not be built." % [entry.get("id", &""), where], cell)
			continue
		var label := "%s %s" % [def.display_name, where]
		if floor.get_floor(cell.x, cell.y) == 0:
			_add(out, ERROR, "%s is not on a floor." % label, cell)
		if def.wall_mounted:
			var behind: int = (int(entry.get("facing", 0)) + 2) % 4
			if floor.get_edge_on(cell.x, cell.y, behind) == 0:
				_add(out, WARNING, "%s has no wall behind it to hang on." % label, cell)
		var params: Dictionary = entry.get("params", {})
		_check_params(def, params, label, cell, out)
		if def.name_id == &"puzzle":
			var key := floor.object_key(cell.x, cell.y)
			var links := LevelPaintedLinks.valid_links(floor, catalog)
			if not links.any(func(l): return l.to == key):
				_add(out, WARNING, "%s has no levers linked to it, so it can never be solved." % label, cell)
			if not links.any(func(l): return l.from == key):
				_add(out, WARNING, "%s is not linked to any door or platform, so solving it does nothing." % label, cell)
			if String(params.get("puzzle_id", "puzzle")).strip_edges() == "":
				_add(out, ERROR, "%s needs a name, or it can never be solved." % label, cell)
		if def.name_id == &"encounter" and (params.get("front_row", []) as Array).is_empty() \
				and (params.get("back_row", []) as Array).is_empty():
			_add(out, WARNING, "%s has no monsters, so it will never start a fight." % label, cell)

static func _check_edges(floor: GridLevelData, catalog: TileCatalog, out: Array) -> void:
	for key in floor.edge_params:
		var parts := String(key).split(":")
		var coords := parts[1].split(",") if parts.size() == 2 else PackedStringArray()
		if coords.size() != 2:
			continue
		var a := int(coords[0])
		var b := int(coords[1])
		var id := floor.get_edge_v(a, b) if parts[0] == "V" else floor.get_edge_h(a, b)
		var def := catalog.get_by_id(TileDef.Kind.EDGE, id)
		if def != null:
			_check_params(def, floor.edge_params[key], "%s (%s %d, %d)" % [def.display_name, parts[0], a, b],
				_edge_cell(floor, parts[0], a, b), out)

# Problems any tile's parameters can have: files that are not there.
static func _check_params(def: TileDef, params: Dictionary, label: String, cell: Vector2i, out: Array) -> void:
	for p in def.params:
		var pname: String = p.get("name", "")
		var value = params.get(pname, p.get("default", null))
		match p.get("type", "string"):
			"scene_path":
				# A connector's scene is rewritten at build time when a floor is chosen.
				if params.get(LevelFloorLinks.PARAM_FLOOR, "") != "" and pname == LevelFloorLinks.PARAM_SCENE:
					continue
				if value is String and value != "" and not ResourceLoader.exists(value):
					_add(out, ERROR, "%s: scene not found: %s" % [label, value], cell)
			"resource_list":
				if value is Array:
					for path in value:
						if not (path is String) or not ResourceLoader.exists(path):
							_add(out, ERROR, "%s: file not found: %s" % [label, path], cell)
			"int_list":
				if pname == "movement_sequence" and value is Array:
					if value.is_empty():
						_add(out, WARNING, "%s has an empty path, so it will not move." % label, cell)
					for step in value:
						if int(step) < 0 or int(step) > 6:
							_add(out, ERROR, "%s: %d is not a path code (use 0 to 6)." % [label, int(step)], cell)

static func _check_connectors(dungeon: DungeonData, floor: GridLevelData, catalog: TileCatalog, out: Array) -> void:
	for c in LevelFloorLinks.connectors(floor, catalog):
		var cell: Vector2i = c.cell if c.kind == "object" else _edge_cell(floor, c.axis, c.a, c.b)
		var target_uid: String = c.params.get(LevelFloorLinks.PARAM_FLOOR, "")
		if target_uid == "":
			if String(c.params.get(LevelFloorLinks.PARAM_SCENE, "")) == "":
				_add(out, WARNING, "%s does not lead anywhere yet (choose a floor or a scene)." % c.label, cell)
		else:
			var target := dungeon.floor_by_uid(target_uid) if dungeon else null
			if target == null:
				_add(out, ERROR, "%s leads to a floor that is no longer in this dungeon." % c.label, cell)
			elif LevelFloorLinks.lands_below(c):
				if target.get_floor(cell.x, cell.y) == 0:
					_add(out, WARNING, "%s has no floor below it on '%s'; the party will land at that floor's spawn point."
						% [c.label, target.level_name], cell)
				else:
					var under := catalog.get_object(target.get_object(cell.x, cell.y).get("id", &""))
					if under != null:
						_add(out, WARNING, "%s drops the party onto %s on '%s'." % [c.label, under.display_name, target.level_name], cell)
			else:
				var arrive: String = c.params.get(LevelFloorLinks.PARAM_ARRIVAL, LevelFloorLinks.ARRIVE_AUTO)
				if arrive != LevelFloorLinks.ARRIVE_AUTO and arrive != LevelFloorLinks.ARRIVE_SPAWN:
					var keys := LevelFloorLinks.arrival_points(target, catalog).map(func(t): return t.key)
					if not keys.has(arrive):
						_add(out, WARNING, "%s arrives at stairs or a door that no longer exists on '%s'; it will use that floor's spawn point."
							% [c.label, target.level_name], cell)
		if c.pit:
			continue   # one-way: nothing arrives at a pit trap
		# Where a party coming FROM the other side lands on this floor.
		var landing: Vector2i = GridLevelBuilder.arrival_pose(floor, catalog, c).cell
		if floor.get_floor(landing.x, landing.y) == 0:
			_add(out, WARNING, "%s: the cell in front of it (%d, %d) has no floor, so it cannot be walked into or arrived at."
				% [c.label, landing.x, landing.y], cell)

static func _check_open_sides(floor: GridLevelData, out: Array) -> void:
	var open := 0
	var sample := NO_CELL
	for z in floor.height:
		for x in floor.width:
			if floor.get_floor(x, z) == 0:
				continue
			for side in _SIDES:
				var n: Vector2i = Vector2i(x, z) + floor._side_step(side)
				if floor.get_floor(n.x, n.y) == 0 and floor.get_edge_on(x, z, side) == 0:
					open += 1
					if sample == NO_CELL:
						sample = Vector2i(x, z)
	if open > 0:
		_add(out, WARNING, "%d floor side%s open onto empty space, e.g. at (%d, %d). Auto-Wall closes them."
			% [open, " is" if open == 1 else "s are", sample.x, sample.y], sample)

# Flood from every way INTO the floor (the spawn, wherever stairs/doors drop the
# party, and under other floors' pit traps) through anything walkable; floor that
# is never reached is cut off.
static func _check_reachability(dungeon: DungeonData, floor: GridLevelData, catalog: TileCatalog, out: Array) -> void:
	var seeds: Array[Vector2i] = []
	var spawn := floor.spawn_cell if floor.spawn_cell.x >= 0 else GridLevelBuilder._first_floor_cell(floor)
	seeds.append(spawn)
	for c in LevelFloorLinks.arrival_points(floor, catalog):
		seeds.append(GridLevelBuilder.arrival_pose(floor, catalog, c).cell)
	seeds.append_array(LevelFloorLinks.pit_landings(dungeon, floor, catalog))

	var reached := {}
	var stack: Array[Vector2i] = []
	for s in seeds:
		if floor.get_floor(s.x, s.y) != 0 and not reached.has(s):
			reached[s] = true
			stack.append(s)
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for side in _SIDES:
			if _edge_blocks(catalog, floor.get_edge_on(cell.x, cell.y, side)):
				continue
			var n: Vector2i = cell + floor._side_step(side)
			if floor.get_floor(n.x, n.y) != 0 and not reached.has(n):
				reached[n] = true
				stack.append(n)

	var cut_off := 0
	var sample := NO_CELL
	for z in floor.height:
		for x in floor.width:
			if floor.get_floor(x, z) != 0 and not reached.has(Vector2i(x, z)):
				cut_off += 1
				if sample == NO_CELL:
					sample = Vector2i(x, z)
	if cut_off > 0:
		_add(out, WARNING, "%d floor cell%s cannot be reached from the spawn point or any stairs/door/pit, e.g. (%d, %d)."
			% [cut_off, "" if cut_off == 1 else "s", sample.x, sample.y], sample)
#endregion


#region Helpers
static func _add(out: Array, severity: String, text: String, cell: Vector2i) -> void:
	out.append({ "severity": severity, "text": text, "cell": cell })

static func _floor_count(floor: GridLevelData) -> int:
	var n := 0
	for id in floor.floors:
		if id != 0:
			n += 1
	return n

# Walls block; so does a transition door (it is set into a solid wall and takes
# you to another level rather than through). Grates and open doorways do not.
static func _edge_blocks(catalog: TileCatalog, id: int) -> bool:
	if id == 0:
		return false
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id)
	return def == null or def.blocks or def.wall_backed

# A cell next to an edge, for "jump to" (the floored side when there is one).
static func _edge_cell(floor: GridLevelData, axis: String, a: int, b: int) -> Vector2i:
	var first := Vector2i(a, b)
	var second := Vector2i(a - 1, b) if axis == "V" else Vector2i(a, b - 1)
	if floor.get_floor(first.x, first.y) == 0 and floor.get_floor(second.x, second.y) != 0:
		return second
	return first
#endregion
