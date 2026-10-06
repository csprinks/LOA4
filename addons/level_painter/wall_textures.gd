@tool
class_name WallTextures
extends RefCounted

## The textures walls can be painted with: one folder each under DIR, holding
## Color / NormalGL / Roughness (and optionally Metalness) maps plus a preview.
## A wall stores only the folder name (the Wall tile's "wall_texture" param);
## this turns the name into a shared material, a palette swatch, or a map colour.

const DIR := "res://Assets/Cloudforge/textures/"
const PARAM := "wall_texture"
## World units one repeat of a texture is WIDE. 2 = one repeat per cell, so a
## brick course reads at a sensible size on a 2 x 3 wall panel. Its height follows
## from the image's shape: several brick sets are 2:1 images, which cover 2 x 1
## units rather than being stretched over a square.
const TILE_SIZE := 2.0

static var _names: PackedStringArray = []
static var _materials: Dictionary = {}
static var _colors: Dictionary = {}

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
## for "" / an unknown name. World-space triplanar, so neighbouring panels and
## corner posts line up without any UV work. `flat` picks the variant for floors:
## a non-square image has to be laid along a different axis on a horizontal
## surface than on an upright one to keep its proportions.
static func material(name: String, flat: bool = false) -> StandardMaterial3D:
	if name == "":
		return null
	var key := name + ("|flat" if flat else "")
	if _materials.has(key):
		return _materials[key]
	var albedo := _map(name, "Color")
	if albedo == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	var normal := _map(name, "NormalGL")
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	var roughness := _map(name, "Roughness")
	if roughness:
		m.roughness_texture = roughness
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var metalness := _map(name, "Metalness")
	if metalness:
		m.metallic = 1.0
		m.metallic_texture = metalness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	# Triplanar reads (x, y) / (z, y) on upright faces and (x, z) on level ones.
	# The image's V axis repeats `aspect` times as often as its U axis, so V is y
	# for walls and z for floors.
	var aspect := float(albedo.get_width()) / maxf(float(albedo.get_height()), 1.0)
	var u := 1.0 / TILE_SIZE
	m.uv1_scale = Vector3(u, u, u * aspect) if flat else Vector3(u, u * aspect, u)
	# Floors are seen at a grazing angle; without this they smear into the distance.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
