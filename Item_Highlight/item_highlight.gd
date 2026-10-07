class_name ItemHighlight

## The glint that sweeps across things the party can take. It is laid over each
## mesh as an overlay, so the meshes' own materials are left alone.

const MATERIAL: ShaderMaterial = preload("res://Item_Highlight/item_highlight.tres")

## Puts the glint on every mesh at or under root.
static func apply(root: Node) -> void:
	if root is MeshInstance3D:
		root.material_overlay = MATERIAL
	for child in root.get_children():
		apply(child)
