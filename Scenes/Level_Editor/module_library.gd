class_name ModuleLibrary
extends RefCounted

## Where modules live and how they are saved, built and started.
##
## A MODULE is one adventure: a DungeonData (its floors, painted in the Level
## Editor) plus the level scenes built from it. Each module is a folder:
##
##   <root>/<module id>/module.tres            the editable source
##   <root>/<module id>/floors/floor_<uid>.tscn  one built, playable scene per floor
##
## <root> is res://Modules/ while developing (running from the Godot editor), so
## modules are part of the project and ship with the game. An exported game cannot
## write to res://, so there the editor saves to user://modules/ instead.
##
## One module can be marked as the CAMPAIGN: "New Game" starts on its first floor.

const DEV_ROOT := "res://Modules/"
const USER_ROOT := "user://modules/"
const CATALOG := "res://addons/level_painter/default_catalog.tres"
const MODULE_FILE := "module.tres"
const CAMPAIGN_FILE := "campaign.cfg"


static func root_dir() -> String:
	return DEV_ROOT if OS.has_feature("editor") else USER_ROOT

static func module_dir(id: String) -> String:
	return root_dir() + id + "/"

static func catalog() -> TileCatalog:
	return ResourceLoader.load(CATALOG) as TileCatalog


#region Listing / loading / saving
## Every module on disk, sorted by name:
## [{ id, name, description, floors: int, built: bool, campaign: bool }]
static func list_modules() -> Array:
	var out: Array = []
	var dir := DirAccess.open(root_dir())
	if dir == null:
		return out
	var campaign := get_campaign()
	for id in dir.get_directories():
		var dungeon := load_module(id)
		if dungeon == null:
			continue
		out.append({
			"id": id, "name": dungeon.dungeon_name, "description": dungeon.description,
			"floors": dungeon.floor_count(), "built": start_scene(dungeon) != "",
			"campaign": id == campaign,
		})
	out.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out

static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(module_dir(id) + MODULE_FILE)

## Read a module fresh from disk (never a cached copy), or null.
static func load_module(id: String) -> DungeonData:
	if not exists(id):
		return null
	var res = ResourceLoader.load(module_dir(id) + MODULE_FILE, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (res is DungeonData):
		return null
	(res as DungeonData).ensure_ids()
	return res

static func save_module(id: String, dungeon: DungeonData) -> Error:
	DirAccess.make_dir_recursive_absolute(module_dir(id))
	return ResourceSaver.save(dungeon, module_dir(id) + MODULE_FILE)

## Make a new one-floor module and return its id ("" if it could not be saved).
static func create_module(module_name: String) -> String:
	var clean := module_name.strip_edges()
	if clean == "":
		clean = "New Module"
	var base := LevelFloorLinks.sanitize_filename(clean)
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(module_dir(id)):
		id = "%s_%d" % [base, n]
		n += 1
	var dungeon := DungeonData.new()
	dungeon.dungeon_name = clean
	dungeon.add_floor("Floor 1", 16, 16)
	return id if save_module(id, dungeon) == OK else ""

## Delete a module's folder (source and built floors). Cannot be undone.
static func delete_module(id: String) -> void:
	if id == "" or id.contains("/") or id.contains("\\") or id.contains(".."):
		return
	_remove_dir(module_dir(id))
	if get_campaign() == id:
		set_campaign("")

static func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
#endregion


#region Building / starting
static func floor_scene_path(id: String, floor: GridLevelData) -> String:
	return module_dir(id) + "floors/floor_%s.tscn" % floor.uid

## Build every floor of a module into its floors/ folder. Returns:
##   { "ok": bool, "built": int, "errors": Array[String], "warnings": Array[String] }
static func build_module(id: String, dungeon: DungeonData) -> Dictionary:
	var report := { "ok": true, "built": 0, "errors": [], "warnings": [] }
	var cat := catalog()
	dungeon.ensure_ids()
	DirAccess.make_dir_recursive_absolute(module_dir(id) + "floors")
	# Give every floor its path first, so stairs on an early floor can already
	# point at a later one.
	var wanted := {}
	for floor in dungeon.floors:
		floor.built_path = floor_scene_path(id, floor)
		wanted[floor.built_path.get_file()] = true
	for floor in dungeon.floors:
		var result := LevelBuildPipeline.build_floor(dungeon, floor, floor.built_path, cat)
		report.warnings.append_array(result.link_warnings)
		if result.ok:
			report.built += 1
		else:
			report.ok = false
			report.errors.append("%s: %s" % [floor.level_name, result.error])
	# Scenes of floors that were removed from the module.
	var dir := DirAccess.open(module_dir(id) + "floors")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tscn") and not wanted.has(file):
				dir.remove(file)
	save_module(id, dungeon)   # remembers each floor's built_path
	return report

## The scene a module starts in (its first floor's built scene), or "" if it has
## not been built yet.
static func start_scene(dungeon: DungeonData) -> String:
	if dungeon == null or dungeon.floor_count() == 0:
		return ""
	var path := dungeon.get_floor(0).built_path
	return path if path != "" and ResourceLoader.exists(path) else ""
#endregion


#region Campaign (the module "New Game" starts in)
static func get_campaign() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(root_dir() + CAMPAIGN_FILE) != OK:
		return ""
	return String(cfg.get_value("campaign", "module", ""))

static func set_campaign(id: String) -> void:
	DirAccess.make_dir_recursive_absolute(root_dir())
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "module", id)
	cfg.save(root_dir() + CAMPAIGN_FILE)

## First level of the campaign module, or "" when none is set / built.
static func campaign_start_scene() -> String:
	return start_scene(load_module(get_campaign()))
#endregion
