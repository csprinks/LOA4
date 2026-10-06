@tool
class_name DungeonData
extends Resource

## A whole multi-floor dungeon: an ordered list of GridLevelData floors, saved as a
## single .tres so you author every floor in one file. Each floor still builds to
## its OWN .tscn (floors are separate scenes at runtime). Stairs and doors connect
## floors by pointing at a floor's `uid` (see LevelFloorLinks); the scene path and
## arrival marker are filled in at build time.

@export var dungeon_name: String = "New Dungeon"
## Shown in the in-game Level Editor's module list.
@export_multiline var description: String = ""
@export var floors: Array[GridLevelData] = []


func floor_count() -> int:
	return floors.size()

func get_floor(i: int) -> GridLevelData:
	return floors[i] if i >= 0 and i < floors.size() else null

## Append a new blank floor and return it.
func add_floor(floor_name: String = "", w: int = 16, h: int = 16) -> GridLevelData:
	var f := GridLevelData.new()
	f.resize(w, h)
	f.level_name = floor_name if floor_name != "" else "Floor %d" % (floors.size() + 1)
	floors.append(f)
	ensure_ids()
	return f

## Remove floor i (never removes the last remaining floor).
func remove_floor(i: int) -> void:
	if i >= 0 and i < floors.size() and floors.size() > 1:
		floors.remove_at(i)

## Give every floor a uid that is unique within this dungeon (older files have
## none; a duplicated floor would share one). Call after loading or adding floors.
func ensure_ids() -> void:
	var seen := {}
	for f in floors:
		if f == null:
			continue
		while f.uid == "" or seen.has(f.uid):
			f.uid = "%08x%04x" % [randi(), seen.size()]
		seen[f.uid] = true

## The floor with this uid, or null.
func floor_by_uid(floor_uid: String) -> GridLevelData:
	if floor_uid == "":
		return null
	for f in floors:
		if f != null and f.uid == floor_uid:
			return f
	return null

## Wrap a single GridLevelData (e.g. a legacy .tres or one pulled from a built
## scene) into a one-floor dungeon.
static func from_single(floor: GridLevelData) -> DungeonData:
	var d := DungeonData.new()
	d.floors = [floor]
	d.dungeon_name = floor.level_name if floor.level_name != "" else "New Dungeon"
	d.ensure_ids()
	return d
