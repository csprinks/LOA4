extends Node3D

## A wall, floor or ceiling piece that can wear a painted texture. `wall_texture` is the
## name of a WallTextures set ("" = the piece's own plain material); the Level
## Painter sets it per wall / floor cell, and it is applied when the level loads.
## Works on a CSG shape directly (corner posts, ceiling slabs, trim) or on a root
## with a CSG child (the wall panel and floor tile scenes).

@export var wall_texture: String = ""
## Trim (baseboard, cornice, beam): wears the darker variant of the texture, laid
## upright whatever the piece's shape.
@export var trim: bool = false

func _ready() -> void:
	apply_wall_texture()

func apply_wall_texture() -> void:
	if wall_texture == "":
		return
	var target: Node = self
	if not (target is CSGPrimitive3D):
		target = null
		for child in get_children():
			if child is CSGPrimitive3D:
				target = child
				break
	if target == null:
		return
	# A slab wider than it is tall is floor or ceiling, and takes the level-facing material.
	var flat: bool = not trim and target is CSGBox3D and target.size.y < minf(target.size.x, target.size.z)
	var mat := WallTextures.material(wall_texture, flat, trim)
	if mat:
		target.material = mat
