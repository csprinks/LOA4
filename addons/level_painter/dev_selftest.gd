extends SceneTree

## Headless Phase-1 self test. Run with:
##   Godot.exe --headless --path <project> --script res://addons/level_painter/dev_selftest.gd
## Generates default_catalog.tres, builds a tiny map, saves a demo scene, and
## prints node counts. Scripts are load()ed by path so this works even if the
## global class cache is momentarily stale.

func _initialize() -> void:
	var DataS = load("res://addons/level_painter/grid_level_data.gd")
	var CatS  = load("res://addons/level_painter/tile_catalog.gd")
	var Build = load("res://addons/level_painter/grid_level_builder.gd")

	# 1) Generate + save the default catalog.
	var cat = CatS.default_catalog()
	var cat_path := "res://addons/level_painter/default_catalog.tres"
	var e := ResourceSaver.save(cat, cat_path)
	print("catalog save: ", error_string(e), "  tiles=", cat.tiles.size())

	# 2) Build a small painted map: a 5x4 room with a door on the south wall and
	#    a chest in a corner.
	var data = DataS.new()
	data.level_name = "SelfTest Room"
	data.resize(5, 4)
	for z in data.height:
		for x in data.width:
			data.set_floor(x, z, 1)                      # stone floor everywhere
	# Ring of walls around the room perimeter.
	for x in data.width:
		data.set_edge_on(x, 0, 0, 1)                     # NORTH border
		data.set_edge_on(x, data.height - 1, 2, 1)       # SOUTH border
	for z in data.height:
		data.set_edge_on(0, z, 3, 1)                     # WEST border
		data.set_edge_on(data.width - 1, z, 1, 1)        # EAST border
	data.set_edge_on(2, data.height - 1, 2, 2)           # a stone DOOR on south wall
	data.set_object(4, 0, &"chest", 2)                   # chest in NE corner, facing S
	data.spawn_cell = Vector2i(2, 1)

	# 3) Round-trip the data through a .tres to prove it serialises.
	var data_path := "res://addons/level_painter/selftest_level.tres"
	ResourceSaver.save(data, data_path)
	var reloaded = load(data_path)
	print("data round-trip: width=", reloaded.width, " floors=", reloaded.floors.size(),
		" edges_v=", reloaded.edges_v.size(), " edges_h=", reloaded.edges_h.size(),
		" objects=", reloaded.objects.size())

	# 4) Build the 3D subtree and count what came out.
	var root = Build.build(reloaded, cat)
	var floors_n = root.get_node("Floors").get_child_count()
	var walls_n = root.get_node("Walls").get_child_count()
	var objs_n = root.get_node("Objects").get_child_count()
	var spawn = root.get_node_or_null("PlayerSpawn")
	print("BUILD: floors=", floors_n, " walls/doors=", walls_n, " objects=", objs_n,
		" spawn=", ("yes @" + str(spawn.position) if spawn else "no"))

	# 5) Save the built subtree as a demo .tscn so it can be opened/run.
	var packed := PackedScene.new()
	# Re-own everything to root so the pack captures the whole tree.
	_reown(root, root)
	var pe := packed.pack(root)
	if pe == OK:
		ResourceSaver.save(packed, "res://addons/level_painter/selftest_built.tscn")
		print("packed demo scene saved OK")
	else:
		print("pack failed: ", error_string(pe))

	print("SELFTEST DONE")
	quit()

func _reown(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		# Do not descend into instanced scenes (they save as instances).
		if c.scene_file_path == "":
			_reown(c, owner)
