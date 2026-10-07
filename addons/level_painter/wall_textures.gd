@tool
class_name WallTextures
extends RefCounted

## The textures walls can be painted with: one folder each under DIR, holding
## Color / NormalGL / Roughness (and optionally Metalness, AmbientOcclusion,
## Displacement and Emission) maps plus a preview.
## A wall stores only the folder name (the Wall tile's "wall_texture" param);
## this turns the name into a shared material, a palette swatch, or a map colour.

const DIR := "res://Assets/Cloudforge/textures/"
const PARAM := "wall_texture"
## World units one repeat of a texture is WIDE. 2 = one repeat per cell, so a
## brick course reads at a sensible size on a 2 x 3 wall panel. Its height follows
## from the image's shape: several brick sets are 2:1 images, which cover 2 x 1
## units rather than being stretched over a square.
const TILE_SIZE := 2.0
## Trim (baseboards, cornices, beams) wears its wall's texture this much darker,
## so the course reads as separate stonework.
const TRIM_TINT := Color(0.62, 0.6, 0.58)
const SURFACE_SHADER := preload("res://addons/level_painter/blocks/dungeon_surface.gdshader")
## Map file name -> the shader parameter it feeds. AmbientOcclusion and
## Displacement are worth adding to a set: without them the shader guesses the
## crevices from the colour map and leaves the surface flat.
const OPTIONAL_MAPS := {
	"NormalGL": "normal_map",
	"Roughness": "roughness_map",
	"Metalness": "metalness_map",
	"AmbientOcclusion": "ao_map",
	"Displacement": "height_map",
	"Emission": "emission_map",
}

static var _names: PackedStringArray = []
static var _materials: Dictionary = {}
static var _colors: Dictionary = {}
static var _wear_map: ImageTexture
static var _wear_grid := Vector2.ONE

## Show the wear painted on `data` (the level now on screen): one texel per cell,
## read by every painted surface. Null, or a level with no wear painted, leaves
## everything at normal wear.
static func set_level_wear(data: GridLevelData) -> void:
	_wear_map = null
	if data != null and not data.wear.is_empty():
		var image := Image.create(data.width, data.height, false, Image.FORMAT_R8)
		image.fill(Color(0.5, 0.0, 0.0))
		for cell: Vector2i in data.wear:
			if data.in_bounds(cell.x, cell.y):
				image.set_pixel(cell.x, cell.y, Color(float(data.wear[cell]) * 0.5, 0.0, 0.0))
		_wear_map = ImageTexture.create_from_image(image)
		_wear_grid = Vector2(data.width, data.height)
	for m: ShaderMaterial in _materials.values():
		_apply_wear(m)

static func _apply_wear(m: ShaderMaterial) -> void:
	m.set_shader_parameter("has_wear_map", _wear_map != null)
	m.set_shader_parameter("wear_map", _wear_map)
	m.set_shader_parameter("wear_grid", _wear_grid)

## Every texture set available, sorted by name.
static func names() -> PackedStringArray:
	if _names.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			for sub in dir.get_directories():
				if _map(sub, "Color") != null:
					_names.append(sub)
			_names.sort()
	return _names

## "Bricks075A" -> "Bricks 075A".
static func label(name: String) -> String:
	var split := 0
	while split < name.length() and not name[split].is_valid_int():
		split += 1
	return name if split == 0 or split == name.length() else name.substr(0, split) + " " + name.substr(split)

## The material for a texture set (shared between everything using it), or null
## for "" / an unknown name. World-space triplanar (dungeon_surface.gdshader), so
## neighbouring panels and corner posts line up without any UV work. `flat` picks
## the variant for floors:
## a non-square image has to be laid along a different axis on a horizontal
## surface than on an upright one to keep its proportions. `trim` picks the
## darker variant.
static func material(name: String, flat: bool = false, trim: bool = false) -> ShaderMaterial:
	if name == "":
		return null
	var key := name + ("|flat" if flat else "") + ("|trim" if trim else "")
	if _materials.has(key):
		return _materials[key]
	var albedo := _map(name, "Color")
	if albedo == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo_map", albedo)
	# Maps a set doesn't have are left unset: the shader's defaults stand in for
	# them (flat normal, fully rough, non-metal).
	for map_name: String in OPTIONAL_MAPS:
		var map := _map(name, map_name)
		if map:
			m.set_shader_parameter(OPTIONAL_MAPS[map_name], map)
	m.set_shader_parameter("has_ao_map", _map(name, "AmbientOcclusion") != null)
	m.set_shader_parameter("has_height_map", _map(name, "Displacement") != null)
	m.set_shader_parameter("has_emission_map", _map(name, "Emission") != null)
	# Triplanar reads (x, y) / (z, y) on upright faces and (x, z) on level ones.
	# The image's V axis repeats `aspect` times as often as its U axis, so V is y
	# for walls and z for floors.
	var aspect := float(albedo.get_width()) / maxf(float(albedo.get_height()), 1.0)
	var u := 1.0 / TILE_SIZE
	m.set_shader_parameter("uv_scale", Vector3(u, u, u * aspect) if flat else Vector3(u, u * aspect, u))
	m.set_shader_parameter("wall_height", GridLevelBuilder.WALL_HEIGHT)
	m.set_shader_parameter("cell_size", GridLevelData.CELL)
	_apply_wear(m)
	if trim:
		m.set_shader_parameter("tint", TRIM_TINT)
	_materials[key] = m
	return m

static func preview(name: String) -> Texture2D:
	var tex := _map(name, "preview")
	return tex if tex else _map(name, "Color")

## A single colour standing for the texture, for drawing walls on the 2D map.
static func color(name: String) -> Color:
	if _colors.has(name):
		return _colors[name]
	var col := Color(0.6, 0.55, 0.45)
	var tex := preview(name)
	if tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			img.resize(1, 1, Image.INTERPOLATE_LANCZOS)
			col = img.get_pixel(0, 0)
			col.a = 1.0
	_colors[name] = col
	return col

static func _map(name: String, map_name: String) -> Texture2D:
	for ext: String in [".png", ".jpg"]:
		var path := DIR + name + "/" + map_name + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null
