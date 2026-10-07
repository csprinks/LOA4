@tool
class_name TileCatalog
extends Resource

## The palette: every tile you can paint. Data-driven so new floors/walls/props are
## added by editing the .tres (or default_catalog()) — no builder/dock code change.
##
## Look up by layer + id. FLOOR/EDGE use the integer `id`; OBJECT uses `name_id`.

@export var tiles: Array[TileDef] = []


func floor_tiles() -> Array[TileDef]:
	return _of_kind(TileDef.Kind.FLOOR)

func edge_tiles() -> Array[TileDef]:
	return _of_kind(TileDef.Kind.EDGE)

func object_tiles() -> Array[TileDef]:
	return _of_kind(TileDef.Kind.OBJECT)

func _of_kind(k: int) -> Array[TileDef]:
	var out: Array[TileDef] = []
	for t in tiles:
		if t != null and t.kind == k:
			out.append(t)
	return out

## Resolve a FLOOR or EDGE id within a layer. Returns null for 0 / unknown.
func get_by_id(kind: int, id: int) -> TileDef:
	if id == 0:
		return null
	for t in tiles:
		if t != null and t.kind == kind and t.id == id:
			return t
	return null

## Resolve an OBJECT tile by its StringName key.
func get_object(name_id: StringName) -> TileDef:
	for t in tiles:
		if t != null and t.kind == TileDef.Kind.OBJECT and t.name_id == name_id:
			return t
	return null


## A sensible starting palette pointing at existing game assets + the placeholder
## panel/floor scenes shipped with the addon. Used to seed default_catalog.tres.
static func default_catalog() -> TileCatalog:
	var base := "res://addons/level_painter/blocks/"
	var cat := TileCatalog.new()

	# --- Floors (int id) ---
	cat.tiles.append(_mk_floor(1, "Stone Floor", Color(0.62, 0.55, 0.42), base + "floor_tile.tscn"))
	# A pit is a floor sunk two units: it counts as floor (so Auto-Wall doesn't wall
	# it off from the room) but the party and push blocks drop into it.
	var pit := _mk_floor(2, "Pit", Color(0.16, 0.13, 0.20), base + "floor_tile.tscn")
	pit.y_offset = -2.0
	cat.tiles.append(pit)

	# --- Edges (int id): walls & doors ---
	var wall := _mk_edge(1, "Wall", Color(0.35, 0.30, 0.25), base + "wall_panel.tscn", 0.0, true)
	# Painted per wall on the Level Editor's Wall Textures layer ("" = plain).
	wall.params = [
		{ "name": WallTextures.PARAM, "label": "Texture", "type": "wall_texture", "default": "" },
	]
	cat.tiles.append(wall)
	var stone_door := _mk_edge(2, "Stone Door", Color(0.55, 0.75, 0.95),
		"res://Doors/Door_Stone/door_stone.tscn", 0.0, false)
	stone_door.wall_backed = true   # set into a solid wall (transition door)
	stone_door.params = [
		{ "name": "leads_to_floor", "label": "Leads to floor", "type": "floor_link", "default": "" },
		{ "name": "arrive_at", "label": "Arrive at", "type": "arrival", "default": "" },
		{ "name": "target_scene_path", "label": "Scene (if no floor chosen)", "type": "scene_path", "default": "" },
		{ "name": "target_spawn_marker_name", "label": "Marker (if no floor chosen)", "type": "string", "default": "PlayerSpawn" },
	]
	cat.tiles.append(stone_door)
	var grate := _mk_edge(3, "Grate Door", Color(0.45, 0.85, 0.95),
		"res://Doors/Door_Metal_Grate/Door_Grate.tscn", 1.0, false)
	grate.clear_height = 2.0   # the gate is 2 tall in a 3-tall wall
	cat.tiles.append(grate)

	# --- Objects (name_id) ---
	var chest := _mk_obj(&"chest", "Treasure Chest", Color(0.95, 0.80, 0.30),
		"res://Treasure_Chest/treasure_chest.tscn", 0.0)
	chest.facing_offset = 90   # chest model faces East by default; correct to painted facing
	chest.scale = 0.7          # the scene is ~1.5 long and waist high; a chest is knee high
	chest.params = [
		{ "name": "crowns_reward", "label": "Crowns", "type": "int", "default": 0 },
		{ "name": "contents", "label": "Items inside", "type": "resource_list", "default": [], "browse": "res://Inventory/Resources" },
	]
	cat.tiles.append(chest)
	var lever := _mk_obj(&"lever", "Lever", Color(0.80, 0.80, 0.85),
		"res://Lever/Lever.tscn", 1.0)
	lever.facing_offset = 180   # lever model faces the opposite of the painted facing
	lever.wall_mounted = true   # sits against the wall behind it, not at the cell centre
	# Links layer: what a lever can be dragged onto (edge 3 = Grate Door). Linking a
	# platform also switches it to "Lever toggle" so the lever actually drives it.
	# A lever linked to a Lever Puzzle joins its levers; the position it must be in
	# rides along (levers start Down, so "Up" means "this one has to be pulled").
	lever.params = [
		{ "name": "puzzle_required_state", "label": "In a puzzle, must be", "type": "enum", "default": 0,
			"options": ["Up (pulled)", "Down (left alone)"], "painter_only": true },
	]
	lever.link_rules = [
		{ "target": "edge:3", "property": "connected_doors", "many": true },
		{ "target": "obj:moving_platform", "property": "connected_platforms", "many": true,
			"target_set": { "activation_type": 1 } },
		{ "target": "obj:puzzle", "target_append": "levers",
			"target_append_value": { "property": "required_states", "param": "puzzle_required_state", "default": 0 } },
	]
	cat.tiles.append(lever)
	# Invisible in play: solves when every linked lever is in its required position,
	# then opens its doors / starts its platforms (once).
	var puzzle := _mk_obj(&"puzzle", "Lever Puzzle", Color(0.95, 0.55, 0.95),
		"res://Moving_Platform/puzzle_activator.tscn", 0.0)
	puzzle.params = [
		{ "name": "puzzle_id", "label": "Name", "type": "string", "default": "puzzle" },
		{ "name": "show_success_message", "label": "Announce when solved", "type": "bool", "default": true },
	]
	puzzle.link_rules = [
		{ "target": "edge:3", "property": "doors_to_open", "many": true },
		{ "target": "obj:moving_platform", "property": "platforms_to_activate", "many": true,
			"target_ref": "puzzle_activator", "target_set": { "activation_type": 2 } },
	]
	cat.tiles.append(puzzle)
	var stairs := _mk_obj(&"stairs", "Stairs", Color(0.70, 0.55, 0.90),
		"res://Stairs/level_stairs.tscn", 1.0)   # mesh centred on origin; lift base to floor
	stairs.arrival_local = Vector3(1, 0, 0)   # the flight climbs toward local -X; you arrive at its foot
	stairs.params = [
		{ "name": "leads_to_floor", "label": "Leads to floor", "type": "floor_link", "default": "" },
		{ "name": "arrive_at", "label": "Arrive at", "type": "arrival", "default": "" },
		{ "name": "prompt_text", "label": "Prompt text", "type": "string", "default": "" },
		{ "name": "target_scene_path", "label": "Scene (if no floor chosen)", "type": "scene_path", "default": "" },
		{ "name": "target_spawn_marker_name", "label": "Marker (if no floor chosen)", "type": "string", "default": "PlayerSpawn" },
	]
	cat.tiles.append(stairs)
	cat.tiles.append(_mk_obj(&"spike_trap", "Spike Trap", Color(0.90, 0.35, 0.35),
		"res://Spike_Trap/spike_trap.tscn", 0.0))
	cat.tiles.append(_mk_obj(&"fireball_trap", "Fireball Trap", Color(0.95, 0.55, 0.25),
		"res://Fireball_Trap/Fireball_Trap.tscn", 1.0))

	# A trap door that drops the party to another floor. It stands in for the cell's
	# floor tile and wears the floor texture around it.
	var pit_trap := _mk_obj(&"pit_trap", "Pit Trap", Color(0.50, 0.32, 0.20),
		"res://Pit_Trap/pit_trap.tscn", 0.0)
	pit_trap.is_pit = true
	pit_trap.params = [
		{ "name": "leads_to_floor", "label": "Drops to floor", "type": "floor_link", "default": "" },
		{ "name": "arrive_at", "label": "Land at", "type": "arrival", "default": "" },
		{ "name": "fall_damage_min", "label": "Fall damage, least (rolled per hero)", "type": "int", "default": 10 },
		{ "name": "fall_damage_max", "label": "Fall damage, most", "type": "int", "default": 30 },
		{ "name": "opened_by_blocks", "label": "A push block sets it off and falls through", "type": "bool", "default": true },
		{ "name": "message", "label": "Message when it opens", "type": "string", "default": "The floor gives way beneath you!" },
		{ "name": "target_scene_path", "label": "Scene (if no floor chosen)", "type": "scene_path", "default": "" },
		{ "name": "target_spawn_marker_name", "label": "Marker (if no floor chosen)", "type": "string", "default": "PlayerSpawn" },
	]
	cat.tiles.append(pit_trap)

	cat.tiles.append(_mk_obj(&"push_block", "Push Block", Color(0.60, 0.60, 0.55),
		"res://Push_Block/push_block.tscn", 1.0))
	# Plate -> door / platform links are painted on the Links layer (or wired by hand
	# in the built scene; both survive rebuilds).
	var plate := _mk_obj(&"pressure_plate", "Pressure Plate", Color(0.55, 0.85, 0.60),
		"res://Pressure Plate/pressure_plate.tscn", 0.0)
	plate.params = [
		{ "name": "doors_stay_open", "label": "Doors stay open once pressed", "type": "bool", "default": false },
	]
	# A linked platform needs to know its plate and be set to "Pressure plate".
	plate.link_rules = [
		{ "target": "edge:3", "property": "connected_doors", "many": true },
		{ "target": "obj:moving_platform", "property": "connected_platforms", "many": true,
			"target_ref": "pressure_plate", "target_set": { "activation_type": 3 } },
	]
	cat.tiles.append(plate)
	var platform := _mk_obj(&"moving_platform", "Moving Platform", Color(0.45, 0.60, 0.95),
		"res://Moving_Platform/moving_platform.tscn", 1.0)
	platform.params = [
		{ "name": "movement_sequence", "label": "Path (0 up, 1 down, 2 -X, 3 +X, 4 +Z, 5 -Z, 6 pause)",
			"type": "int_list", "default": [3, 6] },
		{ "name": "move_speed", "label": "Speed", "type": "float", "default": 2.0 },
		{ "name": "loop_movement", "label": "Loop", "type": "bool", "default": true },
		{ "name": "activation_type", "label": "Activated by", "type": "enum", "default": 0,
			"options": ["Always moving", "Lever toggle", "Lever puzzle", "Pressure plate"] },
	]
	cat.tiles.append(platform)
	# The lock's target door is a node reference: wire it in the built scene.
	var wall_lock := _mk_obj(&"wall_lock", "Wall Lock", Color(0.85, 0.70, 0.40),
		"res://Wall_Locks/wall_lock_basic.tscn", 1.2)
	wall_lock.facing_offset = 90   # model faces East (+X) by default
	wall_lock.wall_mounted = true
	wall_lock.link_rules = [
		{ "target": "edge:3", "property": "target_door", "many": false },
	]
	cat.tiles.append(wall_lock)
	# What a Wall Lock asks for: lies on the floor until the party picks it up.
	cat.tiles.append(_mk_obj(&"brass_key", "Brass Key", Color(0.90, 0.75, 0.30),
		"res://Keys/brass_key.tscn", 0.0))
	# A lit torch the party can lift out of its bracket and carry (see WallTorch).
	var wall_torch := _mk_obj(&"wall_torch", "Wall Torch", Color(1.0, 0.60, 0.25),
		"res://Wall_Torch/wall_torch.tscn", 1.5)
	wall_torch.wall_mounted = true
	wall_torch.facing_offset = 180   # the bracket's back is at z = 0 and it reaches toward +Z
	cat.tiles.append(wall_torch)
	var encounter := _mk_obj(&"encounter", "Monster Encounter", Color(0.85, 0.20, 0.25),
		"res://Combat/encounter_trigger.tscn", 1.0)
	encounter.params = [
		{ "name": "front_row", "label": "Front row monsters", "type": "resource_list", "default": [], "browse": "res://Combat/Monsters" },
		{ "name": "back_row", "label": "Back row monsters", "type": "resource_list", "default": [], "browse": "res://Combat/Monsters" },
		{ "name": "one_shot", "label": "Only once (gone after a win)", "type": "bool", "default": true },
	]
	cat.tiles.append(encounter)

	# Decorative props from Cloudforge, each a scene pre-fitted to this game's
	# scale (see Assets/Cloudforge/cloudforge_props.gd and build_props.gd).
	for prop in CloudforgeProps.PROPS:
		var decor := _mk_obj(StringName(prop["id"]), String(prop["label"]), Color(0.72, 0.62, 0.50),
			CloudforgeProps.scene_path(prop), float(prop.get("mount", 0.0)))
		if prop.get("wall", false):
			decor.wall_mounted = true
			decor.facing_offset = 180   # the model's back is at z = 0 and it reaches toward +Z
		cat.tiles.append(decor)
	return cat


static func _mk_floor(id: int, name: String, col: Color, scene: String) -> TileDef:
	var t := TileDef.new()
	t.kind = TileDef.Kind.FLOOR
	t.id = id; t.display_name = name; t.color = col; t.scene_path = scene
	return t

static func _mk_edge(id: int, name: String, col: Color, scene: String, y: float, blocks: bool) -> TileDef:
	var t := TileDef.new()
	t.kind = TileDef.Kind.EDGE
	t.id = id; t.display_name = name; t.color = col
	t.scene_path = scene; t.y_offset = y; t.blocks = blocks
	return t

static func _mk_obj(name_id: StringName, name: String, col: Color, scene: String, y: float) -> TileDef:
	var t := TileDef.new()
	t.kind = TileDef.Kind.OBJECT
	t.name_id = name_id; t.display_name = name; t.color = col
	t.scene_path = scene; t.y_offset = y
	return t
