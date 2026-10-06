@tool
class_name LevelTileIcons
extends RefCounted

## Picture icons for the tiles in the palette: one PNG per tile under DIR, named
## after the tile (floor_<id>, edge_<id>, obj_<name_id>). They are thumbnails of
## the tiles' own 3D scenes, rendered by icons/build_icons.tscn - re-run that after
## adding a tile or changing a model:
##   Godot.exe --path <project> res://addons/level_painter/icons/build_icons.tscn
## A tile with no icon yet falls back to its colour swatch.

const DIR := "res://addons/level_painter/icons/"
const BADGE_COLOR := Color(0.47, 0.42, 0.35)

static var _cache: Dictionary = {}

static func key(def: TileDef) -> String:
	match def.kind:
		TileDef.Kind.FLOOR: return "floor_%d" % def.id
		TileDef.Kind.EDGE: return "edge_%d" % def.id
	return "obj_" + String(def.name_id)

static func path(def: TileDef) -> String:
	return DIR + key(def) + ".png"

## The tile's icon, or null if none has been built for it.
static func icon(def: TileDef) -> Texture2D:
	if def == null:
		return null
	var k := key(def)
	if not _cache.has(k):
		_cache[k] = load(path(def)) if ResourceLoader.exists(path(def)) else null
	return _cache[k]

## The icon on a mid-tone tile, for lists with a dark background (several models
## - the lever, the grate - are near black). Null if the tile has no icon.
static func badge(def: TileDef) -> Texture2D:
	var plain := icon(def)
	if plain == null:
		return null
	var k := "badge:" + key(def)
	if not _cache.has(k):
		var picture := plain.get_image()
		if picture.is_compressed():
			picture.decompress()
		picture.convert(Image.FORMAT_RGBA8)
		var tile := Image.create(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
		tile.fill(BADGE_COLOR)
		tile.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
		_cache[k] = ImageTexture.create_from_image(tile)
	return _cache[k]
