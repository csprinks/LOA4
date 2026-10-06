@tool
class_name LevelPaintedLinks
extends RefCounted

## Trigger links painted on the Links layer ("this lever works that door"). The
## floor stores only { from, to } keys (GridLevelData.links); this class knows
## what a pair MEANS — by looking up the source tile's TileDef.link_rules — and
## wires the built nodes accordingly at build time.
##
## Painted links and hand-made wiring coexist: apply() records what it set in the
## level root's META, and LevelLinkKeeper leaves those entries alone on the next
## rebuild, so a link you delete in the painter really goes away while anything
## you wired by hand in the Inspector is still carried over.

const META := "_painted_links"   ## root meta: Array of [node path, property, target path]


## { kind: "object", cell } or { kind: "edge", axis, a, b }; {} if not a key.
static func parse_key(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	var coords := parts[1].split(",")
	if coords.size() != 2 or not coords[0].is_valid_int() or not coords[1].is_valid_int():
		return {}
	var a := int(coords[0])
	var b := int(coords[1])
	match parts[0]:
		"obj": return { "kind": "object", "cell": Vector2i(a, b) }
		"V", "H": return { "kind": "edge", "axis": parts[0], "a": a, "b": b }
	return {}

## The tile placed at `key` on this floor, or null.
static func tile_at(data: GridLevelData, catalog: TileCatalog, key: String) -> TileDef:
	var k := parse_key(key)
	if k.is_empty() or data == null or catalog == null:
		return null
	if k.kind == "object":
		var entry := data.get_object(k.cell.x, k.cell.y)
		return catalog.get_object(entry.get("id", &"")) if not entry.is_empty() else null
	var id := data.get_edge_v(k.a, k.b) if k.axis == "V" else data.get_edge_h(k.a, k.b)
	return catalog.get_by_id(TileDef.Kind.EDGE, id)

## "Lever (1, 1)" / "Grate Door (H 2, 0)".
static func label_for(data: GridLevelData, catalog: TileCatalog, key: String) -> String:
	var def := tile_at(data, catalog, key)
	var k := parse_key(key)
	if def == null or k.is_empty():
		return key
	if k.kind == "object":
		return "%s (%d, %d)" % [def.display_name, k.cell.x, k.cell.y]
	return "%s (%s %d, %d)" % [def.display_name, k.axis, k.a, k.b]

## Can a link be dragged FROM the thing at `key`?
static func can_start(data: GridLevelData, catalog: TileCatalog, key: String) -> bool:
	var def := tile_at(data, catalog, key)
	return def != null and not def.link_rules.is_empty()

## The source tile's rule that allows linking from -> to, or {} if they can't be.
static func rule_for(data: GridLevelData, catalog: TileCatalog, from: String, to: String) -> Dictionary:
	var src := tile_at(data, catalog, from)
	var dst := tile_at(data, catalog, to)
	if src == null or dst == null or from == to:
		return {}
	var wanted := ("edge:%d" % dst.id) if dst.kind == TileDef.Kind.EDGE else ("obj:%s" % dst.name_id)
	for rule in src.link_rules:
		if rule.get("target", "") == wanted:
			return rule
	return {}

## Every stored link that still makes sense: [{ from, to, rule }]. Links whose end
## was erased, moved off the grid, or replaced by something unlinkable are skipped.
static func valid_links(data: GridLevelData, catalog: TileCatalog) -> Array:
	var out: Array = []
	if data == null:
		return out
	for l in data.links:
		var rule := rule_for(data, catalog, l.get("from", ""), l.get("to", ""))
		if not rule.is_empty():
			out.append({ "from": l.from, "to": l.to, "rule": rule })
	return out

## Path (from the level root) of the node the builder makes for `key`.
static func node_path(data: GridLevelData, catalog: TileCatalog, key: String) -> NodePath:
	var def := tile_at(data, catalog, key)
	var k := parse_key(key)
	if def == null:
		return NodePath()
	if k.kind == "object":
		return NodePath("Objects/%s_%d_%d" % [String(def.name_id), k.cell.x, k.cell.y])
	return NodePath("Walls/%s_%s_%d_%d" % [GridLevelBuilder._sanitize(def.display_name), k.axis, k.a, k.b])

## Wire every painted link onto a freshly built level (after LevelLinkKeeper has
## carried over the hand-made ones) and record them in the root's META.
## Returns how many links were applied.
static func apply(data: GridLevelData, catalog: TileCatalog, root: Node) -> int:
	var record: Array = []
	var applied := 0
	for link in valid_links(data, catalog):
		var src_path := node_path(data, catalog, link.from)
		var dst_path := node_path(data, catalog, link.to)
		var src := root.get_node_or_null(src_path)
		var dst := root.get_node_or_null(dst_path)
		if src == null or dst == null:
			continue
		var rule: Dictionary = link.rule
		# Source-side: this node points at the target.
		var prop: String = rule.get("property", "")
		if prop != "":
			if rule.get("many", false):
				_append(src, prop, dst)
			else:
				src.set(prop, dst)
			record.append([String(src_path), prop, String(dst_path)])

		# Target-side: the target points back at this node...
		var back: String = rule.get("target_ref", "")
		if back != "":
			dst.set(back, src)
			record.append([String(dst_path), back, String(src_path)])
		# ...or collects it in a list, optionally with a matching value alongside
		# (a puzzle's levers + the position each one must be in).
		var collect: String = rule.get("target_append", "")
		if collect != "" and _append(dst, collect, src):
			record.append([String(dst_path), collect, String(src_path)])
			var paired: Dictionary = rule.get("target_append_value", {})
			if not paired.is_empty():
				var params := _params_at(data, link.from)
				_append(dst, paired.get("property", ""), params.get(paired.get("param", ""), paired.get("default", 0)), true)
		var extra: Dictionary = rule.get("target_set", {})
		for key in extra:
			dst.set(key, extra[key])
		applied += 1
	root.set_meta(META, record)
	return applied

# Append to an array property (a copy is written back: in the editor the array
# read from a node can be the scene's shared default, and editing that in place
# is not saved). Returns false if `value` was already in it and repeats are off.
static func _append(node: Node, prop: String, value, allow_repeat := false) -> bool:
	if prop == "":
		return false
	var current = node.get(prop)
	var list: Array = current.duplicate() if current is Array else []
	if not allow_repeat and list.has(value):
		return false
	list.append(value)
	node.set(prop, list)
	return true

# The painted parameters of the placement at `key`.
static func _params_at(data: GridLevelData, key: String) -> Dictionary:
	var k := parse_key(key)
	if k.is_empty():
		return {}
	if k.kind == "object":
		return data.get_object(k.cell.x, k.cell.y).get("params", {})
	return data.get_edge_params(k.axis, k.a, k.b)
