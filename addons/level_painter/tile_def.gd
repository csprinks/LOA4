@tool
class_name TileDef
extends Resource

## One paintable tile in the palette. The catalog (TileCatalog) holds a list of
## these; GridLevelData stores only integer/StringName ids, and the builder + dock
## resolve them back to a TileDef to know what to draw and what to spawn.
##
## Scenes are referenced by PATH (not an embedded PackedScene) and load()ed at
## build time, so swapping the art asset is a one-line path change and the .tres
## stays free of uid churn.

## Which layer this tile paints into.
enum Kind {
	FLOOR,   ## fills a cell (index id in GridLevelData.floors)
	EDGE,    ## sits on a cell edge: walls, doors (id in edges_v / edges_h)
	OBJECT,  ## a prop placed at a cell center (id in GridLevelData.objects)
}

## Integer id used for FLOOR / EDGE layers (must be unique & non-zero within its
## layer; 0 is reserved for "empty"). OBJECT tiles are keyed by `name_id` instead.
@export var id: int = 0

## StringName key used for OBJECT tiles (stable across reordering, unlike int id).
@export var name_id: StringName = &""

@export var kind: Kind = Kind.FLOOR
@export var display_name: String = "Tile"

## Colour used to draw this tile on the 2D painting canvas.
@export var color: Color = Color.WHITE

## Scene instanced in 3D for EDGE / OBJECT tiles (and FLOOR if you want tile art).
## Leave empty for a FLOOR that the builder should render as a plain CSG slab.
@export_file("*.tscn") var scene_path: String = ""

## Vertical offset applied to the spawned instance (floor props ~0, wall-height ~1).
@export var y_offset: float = 0.0

## OBJECT only: extra yaw (degrees) added when spawning, to correct a prop whose
## model does NOT default to facing North (-Z). E.g. the chest model faces East by
## default, so it needs +90 to make the painted facing match what's rendered.
@export var facing_offset: int = 0

## OBJECT only: uniform scale applied when spawning, for a prop whose scene is
## built at a different size than it should stand in a level.
@export var scale: float = 1.0

## EDGE only: does this edge block movement / line of sight? Walls do; an open
## doorway visual might not. (Doors handle their own blocking at runtime.)
@export var blocks: bool = true

## Per-placement parameter schema. Each entry is a Dictionary describing a property
## the builder should push onto the spawned node, and the dock should expose an
## editor for. Keys:
##   name    : exact @export property name on the target scene's root
##   label   : human label shown in the dock
##   type    : "string" | "int" | "float" | "bool" | "scene_path" | "resource_list"
##             | "enum" (int index; needs `options`) | "int_list" (comma-separated)
##   default : value used when the placement doesn't override it
##             | "floor_link" (which floor of the dungeon this leads to)
##             | "arrival" (where on that floor the party arrives)
##   options : "enum" only — the choice labels, in enum order
##   browse  : "resource_list" only — folder the in-game Level Editor lists files from
##   painter_only : true if the value is NOT a property of the node (it is read by
##             the painter, e.g. by a link rule's target_append_value)
## "floor_link" / "arrival" are painter-only: they are resolved into the node's
## target scene + spawn marker at build time (see LevelFloorLinks), not set as-is.
## Example (stairs): { "name": "target_scene_path", "label": "Target scene",
##                     "type": "scene_path", "default": "" }
@export var params: Array[Dictionary] = []

## EDGE door only: also build a solid wall panel on this edge (behind the door) so
## the door reads as set into a wall and blocks movement — for transition doors
## like the stone door. The door is nudged toward the room so it stays visible.
@export var wall_backed: bool = false

## EDGE door only: how tall the doorway is, when shorter than the wall. The
## builder fills the gap above it with a piece of wall that wears the texture of
## the walls beside it. 0 = the door fills the wall's full height.
@export var clear_height: float = 0.0

## OBJECT only: what this tile can be LINKED to on the painter's Links layer, and
## what a link sets on the built nodes. One Dictionary per kind of target:
##   target     : "obj:<name_id>" or "edge:<id>" — the tile it may be linked to
##   property   : property on THIS node that receives the target node
##   many       : true if `property` is an array (several targets), false for one
##   target_ref : optional — property on the TARGET that points back at this node
##   target_set : optional — { property: value } also set on the target
##   target_append : optional — ARRAY property on the target that collects this node
##             (`property` may then be omitted: a lever just joins a puzzle's levers)
##   target_append_value : optional, with target_append — { property, param, default }:
##             also append this placement's painted `param` value to the target's
##             `property`, keeping the two arrays in step
## Example (pressure plate -> moving platform):
##   { "target": "obj:moving_platform", "property": "connected_platforms", "many": true,
##     "target_ref": "pressure_plate", "target_set": { "activation_type": 3 } }
@export var link_rules: Array[Dictionary] = []

## OBJECT connector (stairs) only: where the party stands when ARRIVING at this prop
## from another floor, in cells, in the prop's own space (it turns with the prop).
## Stairs use (1, 0, 0): one cell out from the foot of the flight. The arrival
## marker faces along this direction, i.e. away from the prop.
@export var arrival_local: Vector3 = Vector3.ZERO

## OBJECT only: this prop is a hole in the floor (the pit trap). The builder leaves
## the cell's floor tile out and hands the prop the floor texture around it (as
## `wall_texture`). As a connector it is one-way: nothing arrives at it, and by
## default it lands the party on the cell directly below on the floor it leads to.
@export var is_pit: bool = false

## OBJECT only: slide the prop back against the wall behind it (opposite its facing)
## instead of standing at the cell centre — for wall-mounted props like levers.
@export var wall_mounted: bool = false
