@tool
class_name LevelBuildPipeline
extends RefCounted

## Turns one painted floor into a playable level scene on disk. This is the whole
## "Build" step, shared by the editor dock and the in-game Level Editor so both
## produce identical levels:
##
##   1. connect stairs/doors to the floors they lead to   (LevelFloorLinks)
##   2. build the 3D nodes                                (GridLevelBuilder)
##   3. add lighting + the level bootstrap script, embed the paint data
##   4. carry over hand-made wiring from the previous build (LevelLinkKeeper)
##   5. wire the links painted on the Links layer          (LevelPaintedLinks)
##   6. pack and save the .tscn
##
## Works in the editor and at runtime (nothing here needs EditorInterface).

const PLAYER_LOADING := "res://Scenes/player_loading.gd"
const META_DATA := "_grid_level_data"   ## root meta carrying the paint data in a built scene


## Build `data` (a floor of `dungeon`) to `path`. Returns:
##   { "ok": bool, "error": String, "link_warnings": Array[String],
##     "carried": { "links", "dropped", "nodes" } }
static func build_floor(dungeon: DungeonData, data: GridLevelData, path: String, catalog: TileCatalog) -> Dictionary:
	var result := { "ok": false, "error": "", "link_warnings": [], "carried": {} }
	if data == null or catalog == null or path == "":
		result.error = "Nothing to build."
		return result

	data.built_path = path
	result.link_warnings = LevelFloorLinks.resolve_into(dungeon, data, path, catalog)

	var root: Node3D = GridLevelBuilder.build(data, catalog, null)

	# Make it playable/visible: lighting, environment, and the level bootstrap
	# script that spawns the player on standalone runs.
	_add_environment(root, data)
	if ResourceLoader.exists(PLAYER_LOADING):
		root.set_script(load(PLAYER_LOADING))
		var spawn := root.get_node_or_null("PlayerSpawn")
		if spawn:
			root.set("player_spawn", spawn)

	# Embed a deep copy of the paint data so the scene is self-describing / re-openable.
	root.set_meta(META_DATA, data.duplicate(true))

	# Rebuilding over an existing level: keep the links wired by hand in the previous
	# build, plus any nodes added under its root; then wire the painted links on top.
	result.carried = LevelLinkKeeper.carry_over(path, root)
	LevelPaintedLinks.apply(data, catalog, root)

	# Own the whole tree to root so pack() captures it (instanced props save as
	# instances; we don't descend into them).
	_reown(root, root)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()
	if pack_err != OK:
		result.error = "pack failed: " + error_string(pack_err)
		return result
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		result.error = "save failed: " + error_string(save_err)
		return result
	result.ok = true
	return result

## The GridLevelData embedded in a built level scene, or null.
static func embedded_data(path: String) -> GridLevelData:
	var scene = load(path)
	if not (scene is PackedScene):
		return null
	var inst: Node = scene.instantiate()
	var data: GridLevelData = null
	if inst.has_meta(META_DATA) and inst.get_meta(META_DATA) is GridLevelData:
		data = inst.get_meta(META_DATA)
	inst.free()
	return data

static func _add_environment(root: Node3D, data: GridLevelData) -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	light.shadow_enabled = true
	root.add_child(light)

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.6
	we.environment = env
	# A floor with a sky swaps the dark backdrop for it when the level loads.
	if LevelSky.is_enabled(data.sky):
		we.set_script(load("res://addons/level_painter/sky/level_sky_env.gd"))
		we.set("sky_settings", LevelSky.settings_for(data.sky))
	root.add_child(we)

static func _reown(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		if c.scene_file_path == "":
			_reown(c, owner)
