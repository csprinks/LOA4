extends SceneTree

## Headless test of the paint canvas logic + the playable build path (things a
## headless run CAN exercise; the editor-only dock UI is validated by the editor
## loading the plugin without errors).

var _fail := 0

func _initialize() -> void:
	var CanvasS = load("res://addons/level_painter/dock/level_paint_canvas.gd")
	var DataS = load("res://addons/level_painter/grid_level_data.gd")
	var Build = load("res://addons/level_painter/grid_level_builder.gd")
	var CatS = load("res://addons/level_painter/tile_catalog.gd")

	# Regenerate the default catalog so the saved .tres carries the new param schemas.
	var cat = CatS.default_catalog()
	ResourceSaver.save(cat, "res://addons/level_painter/default_catalog.tres")

	var data = DataS.new()
	data.resize(6, 6)

	var canvas = CanvasS.new()
	get_root().add_child(canvas)
	canvas.setup(data, cat)
	canvas.zoom = 30.0
	canvas.pan = Vector2.ZERO

	# --- Edge hit-testing: vertical edge at grid x=3 within cell z=1 ---
	canvas.active_layer = canvas.LAYER_EDGE
	canvas.active_edge_id = 1
	canvas._apply_at(Vector2(90, 45), false)          # grid (3.0, 1.5)
	_check("vertical edge painted", data.get_edge_v(3, 1) == 1)

	# --- Edge hit-testing: horizontal edge at grid z=4 within cell x=2 ---
	canvas._apply_at(Vector2(75, 120), false)         # grid (2.5, 4.0)
	_check("horizontal edge painted", data.get_edge_h(2, 4) == 1)

	# --- Clicking a cell CENTRE on the edge layer paints nothing (must be on a line) ---
	canvas._apply_at(Vector2(15, 15), false)          # grid (0.5, 0.5) - dead centre
	_check("edge: centre click is a no-op",
		data.get_edge_v(0, 0) == 0 and data.get_edge_v(1, 0) == 0 \
		and data.get_edge_h(0, 0) == 0 and data.get_edge_h(0, 1) == 0)

	# --- Floor layer ---
	canvas.active_layer = canvas.LAYER_FLOOR
	canvas.active_floor_id = 1
	canvas._apply_at(Vector2(42, 78), false)          # grid (1.4, 2.6) -> cell (1,2)
	_check("floor painted", data.get_floor(1, 2) == 1)
	canvas._apply_at(Vector2(42, 78), true)           # erase
	_check("floor erased", data.get_floor(1, 2) == 0)

	# --- Object layer ---
	canvas.active_layer = canvas.LAYER_OBJECT
	canvas.active_object_id = &"chest"
	canvas.active_facing = 2
	canvas._apply_at(Vector2(75, 75), false)          # grid (2.5,2.5) -> cell (2,2)
	var obj = data.get_object(2, 2)
	_check("object placed", obj.get("id", &"") == &"chest" and obj.get("facing", -1) == 2)

	# --- Undo / redo (whole stroke) ---
	var before = canvas._snapshot()
	canvas._apply_at(Vector2(150, 150), false)        # cell (5,5) chest
	var after = canvas._snapshot()
	canvas._push_undo(before, after)
	_check("stroke recorded object", data.get_object(5, 5).get("id", &"") == &"chest")
	canvas.undo()
	_check("undo removed object", data.get_object(5, 5).is_empty())
	canvas.redo()
	_check("redo restored object", data.get_object(5, 5).get("id", &"") == &"chest")

	# --- Full playable build path (mirrors the dock's _on_build_selected) ---
	for z in 6:
		for x in 6:
			data.set_floor(x, z, 1)
	data.spawn_cell = Vector2i(1, 1)
	var root = Build.build(data, cat, null)
	_add_environment(root)
	root.set_script(load("res://Scenes/player_loading.gd"))
	var spawn = root.get_node_or_null("PlayerSpawn")
	if spawn:
		root.set("player_spawn", spawn)
	_reown(root, root)
	var packed = PackedScene.new()
	var pe = packed.pack(root)
	_check("playable pack OK", pe == OK)
	_check("root has player_loading script", root.get_script() != null)
	_check("root has Sun light", root.get_node_or_null("Sun") != null)
	var se = ResourceSaver.save(packed, "res://addons/level_painter/dev_built_playable.tscn")
	_check("playable scene saved", se == OK)

	# --- Corner posts: a plain rectangular room has posts only at its 4 corners ---
	var room = DataS.new()
	room.resize(5, 4)
	for x in room.width:
		room.set_edge_on(x, 0, GridLevelData.Facing.NORTH, 1)
		room.set_edge_on(x, room.height - 1, GridLevelData.Facing.SOUTH, 1)
	for z in room.height:
		room.set_edge_on(0, z, GridLevelData.Facing.WEST, 1)
		room.set_edge_on(room.width - 1, z, GridLevelData.Facing.EAST, 1)
	var rroot = Build.build(room, cat, null)
	var posts := 0
	for c in rroot.get_node("Walls").get_children():
		if String(c.name).begins_with("Post_"):
			posts += 1
	_check("rectangular room has exactly 4 corner posts", posts == 4)

	# --- Per-object parameters land on the built nodes ---
	var pdata = DataS.new()
	pdata.resize(4, 4)
	for z in 4:
		for x in 4:
			pdata.set_floor(x, z, 1)
	pdata.set_object(0, 0, &"stairs", 0)
	pdata.set_object_param(0, 0, "target_scene_path", "res://Modules/Showcase/floors/floor_cellar.tscn")
	pdata.set_object_param(0, 0, "prompt_text", "You descend...")
	pdata.set_object(3, 3, &"chest", 1)   # facing East
	pdata.set_object_param(3, 3, "crowns_reward", 250)
	pdata.set_object_param(3, 3, "contents",
		["res://Inventory/Resources/Weapons/sword_1h.tres", "res://Inventory/Resources/Potions/healing.tres"])
	var proot = Build.build(pdata, cat, null)
	var stairs_node = proot.get_node("Objects/stairs_0_0")
	var chest_node = proot.get_node("Objects/chest_3_3")
	_check("stairs target_scene_path applied",
		stairs_node.get("target_scene_path") == "res://Modules/Showcase/floors/floor_cellar.tscn")
	_check("stairs prompt_text applied", stairs_node.get("prompt_text") == "You descend...")
	_check("stairs y_offset lifts base to floor", absf(stairs_node.position.y - 1.0) < 0.001)
	_check("chest crowns_reward applied", chest_node.get("crowns_reward") == 250)
	var contents = chest_node.get("contents")
	_check("chest contents loaded (2 resources)", contents is Array and contents.size() == 2)

	# Chest facing East should render facing East: yaw = _facing_to_yaw(EAST) + 90° = 0.
	_check("chest facing offset corrects orientation (East -> yaw 0)",
		absf(chest_node.rotation.y) < 0.001)

	# --- Params survive a .tres round-trip ---
	ResourceSaver.save(pdata, "res://addons/level_painter/dev_params.tres")
	var reloaded = load("res://addons/level_painter/dev_params.tres")
	var re = reloaded.get_object(3, 3)
	_check("params round-trip via .tres", re.get("params", {}).get("crowns_reward", 0) == 250)

	# --- Built .tscn embeds paint data and can be re-opened (the save/load fix) ---
	var eroot = Build.build(pdata, cat, null)
	eroot.set_meta("_grid_level_data", pdata.duplicate(true))
	_reown(eroot, eroot)
	var epacked = PackedScene.new()
	epacked.pack(eroot)
	ResourceSaver.save(epacked, "res://addons/level_painter/dev_embed.tscn")
	var eps = load("res://addons/level_painter/dev_embed.tscn")
	var einst = eps.instantiate()
	var embedded = einst.get_meta("_grid_level_data") if einst.has_meta("_grid_level_data") else null
	_check("built .tscn embeds paint data", embedded != null and embedded is GridLevelData)
	if embedded:
		_check("embedded data has floors", embedded.get_floor(1, 1) == 1)
		_check("embedded data has chest object", embedded.get_object(3, 3).get("id", &"") == &"chest")
		_check("embedded chest param survived", embedded.get_object(3, 3).get("params", {}).get("crowns_reward", 0) == 250)
	einst.free()

	# --- Edge params: a Stone Door gets its target_scene_path (level transition) ---
	var ddata = DataS.new()
	ddata.resize(4, 4)
	for z in 4:
		for x in 4:
			ddata.set_floor(x, z, 1)
	ddata.set_edge_h(1, 2, 2)   # Stone Door (edge id 2) on horizontal edge (1, 2)
	ddata.set_edge_param("H", 1, 2, "target_scene_path", "res://Modules/Showcase/floors/floor_upper.tscn")
	var droot = Build.build(ddata, cat, null)
	var door_node = droot.get_node_or_null("Walls/Stone_Door_H_1_2")
	_check("stone door edge instanced", door_node != null)
	if door_node:
		_check("stone door target_scene_path applied",
			door_node.get("target_scene_path") == "res://Modules/Showcase/floors/floor_upper.tscn")
	_check("stone door gets a backing wall",
		droot.get_node_or_null("Walls/WallBack_H_1_2") != null)

	# --- Erasing an edge clears its params ---
	ddata.set_edge_h(1, 2, 0)
	_check("erasing edge clears its params", ddata.get_edge_params("H", 1, 2).is_empty())

	# --- Edge params round-trip via .tres ---
	ddata.set_edge_h(0, 0, 2)
	ddata.set_edge_param("H", 0, 0, "target_scene_path", "res://foo.tscn")
	ResourceSaver.save(ddata, "res://addons/level_painter/dev_edge.tres")
	var dreload = load("res://addons/level_painter/dev_edge.tres")
	_check("edge params round-trip via .tres",
		dreload.get_edge_params("H", 0, 0).get("target_scene_path", "") == "res://foo.tscn")

	# --- Lever placement: facing_offset (180) + wall_mounted offset ---
	var ldata = DataS.new()
	ldata.resize(4, 4)
	for z in 4:
		for x in 4:
			ldata.set_floor(x, z, 1)
	ldata.set_object(1, 1, &"lever", 0)   # facing North
	var lroot = Build.build(ldata, cat, null)
	var lever_node = lroot.get_node_or_null("Objects/lever_1_1")
	_check("lever built", lever_node != null)
	if lever_node:
		_check("lever facing_offset applied (180)",
			absf(absf(lever_node.rotation.y) - PI) < 0.01)
		# Lever facing North (0) mounts against the wall behind it (+Z) at cell (1,1):
		# base z=2, plus (CELL/2 - 0.1)=0.9 -> 2.9.
		_check("lever wall-mounted offset (against wall behind)",
			absf(lever_node.position.z - 2.9) < 0.001)

	# --- Edge painting axis-lock: a stroke locked to H won't paint a V edge, even
	#     at a spot where the vertical line is the nearest. ---
	var axdata = DataS.new()
	axdata.resize(6, 6)
	canvas.setup(axdata, cat)
	canvas.zoom = 30.0
	canvas.pan = Vector2.ZERO
	canvas.active_layer = canvas.LAYER_EDGE
	canvas.active_edge_id = 1
	canvas._painting = true
	canvas._stroke_axis = ""
	canvas._apply_at(Vector2(75, 90), false)     # grid (2.5, 3.0): paints hedge(2,3), locks H
	_check("axis-lock: first edge paints + locks H",
		axdata.get_edge_h(2, 3) == 1 and canvas._stroke_axis == "H")
	canvas._apply_at(Vector2(90, 91.5), false)   # grid (3.0, 3.05): V is nearest, but locked to H
	_check("axis-lock: locked stroke ignores the perpendicular V edge", axdata.get_edge_v(3, 3) == 0)
	_check("axis-lock: locked stroke paints the H edge instead", axdata.get_edge_h(3, 3) == 1)
	canvas._painting = false
	canvas._stroke_axis = ""

	# --- Multi-floor dungeon: build a DungeonData, round-trip it, build each floor ---
	var DungeonS = load("res://addons/level_painter/dungeon_data.gd")
	var dungeon = DungeonS.new()
	var f1 = dungeon.add_floor("Ground Floor", 5, 5)
	f1.set_floor(0, 0, 1)
	f1.set_object(1, 1, &"stairs", 0)
	var f2 = dungeon.add_floor("Basement", 8, 6)
	f2.set_floor(2, 2, 1)
	_check("dungeon has two floors", dungeon.floor_count() == 2)
	_check("floors keep their own size", f1.width == 5 and f2.width == 8)

	ResourceSaver.save(dungeon, "res://addons/level_painter/dev_dungeon.tres")
	var dre = load("res://addons/level_painter/dev_dungeon.tres")
	_check("dungeon round-trips via .tres",
		dre.floor_count() == 2 and dre.get_floor(0).level_name == "Ground Floor"
		and dre.get_floor(1).width == 8)

	# Build each floor to its own scene (mirrors Build All Floors).
	var built_ok := true
	for i in dre.floor_count():
		var froot = Build.build(dre.get_floor(i), cat, null)
		if froot.get_node_or_null("Floors") == null:
			built_ok = false
	_check("each floor builds to its own scene tree", built_ok)

	# Removing a floor never drops the last one.
	dre.remove_floor(0)
	_check("remove_floor works", dre.floor_count() == 1)
	dre.remove_floor(0)
	_check("remove_floor keeps at least one floor", dre.floor_count() == 1)

	# A legacy single GridLevelData wraps into a one-floor dungeon.
	var wrapped = DungeonS.from_single(f2)
	_check("from_single wraps a lone floor", wrapped.floor_count() == 1 and wrapped.get_floor(0) == f2)

	print("DOCK TEST: ", ("ALL PASS" if _fail == 0 else str(_fail) + " FAILED"))
	quit()

func _check(name: String, ok: bool) -> void:
	print(("  ok  " if ok else "  FAIL") + " | " + name)
	if not ok:
		_fail += 1

func _add_environment(root: Node3D) -> void:
	var light := DirectionalLight3D.new(); light.name = "Sun"
	root.add_child(light)
	var we := WorldEnvironment.new(); we.name = "WorldEnvironment"
	we.environment = Environment.new()
	root.add_child(we)

func _reown(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		if c.scene_file_path == "":
			_reown(c, owner)
