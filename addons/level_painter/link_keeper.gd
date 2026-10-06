@tool
class_name LevelLinkKeeper
extends RefCounted

## Carries hand-made wiring from the previous build of a level into a fresh one, so
## "Build Level" no longer wipes it. Two things survive a rebuild:
##
##   1. Node links set in the Inspector on the built scene (lever -> doors/platforms,
##      pressure plate -> platforms, platform -> plate, wall lock -> door, ...). Any
##      property that holds a node reference is re-pointed at the same-named node in
##      the new build.
##   2. Nodes you added DIRECTLY UNDER THE LEVEL ROOT (e.g. a PuzzleActivator). They
##      are moved across whole, with their own settings and links.
##
## Nodes are matched by name, and painted nodes are named by tile + cell
## ("lever_3_2", "Grate_Door_H_4_1"). So a link is dropped when either end was
## erased or moved to another cell in the painter; everything else is kept.
##
## Reads the previous build from disk, so save the built scene after wiring it.

## Root children the painter generates itself; anything else under the root is yours.
const BUILDER_ROOT_NODES := ["Floors", "Walls", "Objects", "Arrivals", "PlayerSpawn", "Sun", "WorldEnvironment"]


## Copy links and extra root nodes from the scene at `old_path` (if there is one)
## onto `new_root`, a freshly built level that is not yet packed.
## Returns { "links": int, "dropped": int, "nodes": int }.
static func carry_over(old_path: String, new_root: Node) -> Dictionary:
	var report := { "links": 0, "dropped": 0, "nodes": 0 }
	if old_path == "" or not ResourceLoader.exists(old_path):
		return report
	var old_scene = ResourceLoader.load(old_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not (old_scene is PackedScene):
		return report

	var old_root: Node = old_scene.instantiate()
	if old_root == null:
		return report
	# Links the PAINTER made last time are not carried: the painter re-applies its
	# current set after us, so one deleted on the Links layer must not come back.
	var painted := {}
	for entry in old_root.get_meta(LevelPaintedLinks.META, []):
		if entry is Array and entry.size() == 3:
			painted["%s|%s|%s" % entry] = true

	report.nodes = _move_extra_nodes(old_root, new_root)
	old_root.free()
	_reapply_links(old_scene.get_state(), new_root, report, painted)
	return report


# Move every non-painter child of the old root into the new root.
static func _move_extra_nodes(old_root: Node, new_root: Node) -> int:
	var moved := 0
	for child in old_root.get_children():
		if BUILDER_ROOT_NODES.has(String(child.name)) or new_root.has_node(NodePath(child.name)):
			continue
		_clear_owner(child, old_root)
		old_root.remove_child(child)
		new_root.add_child(child)
		moved += 1
	return moved

static func _clear_owner(node: Node, old_owner: Node) -> void:
	if node.owner == old_owner:
		node.owner = null
	for c in node.get_children():
		_clear_owner(c, old_owner)


# Walk the old scene's saved properties; every node reference found is resolved
# against the NEW tree and set there. References whose source or target no longer
# exists are cleared (and counted as dropped) rather than left dangling.
static func _reapply_links(state: SceneState, new_root: Node, report: Dictionary, painted: Dictionary) -> void:
	for i in range(1, state.get_node_count()):   # 0 is the root (the dock wires that)
		var from := String(state.get_node_path(i)).trim_prefix("./")   # as LevelPaintedLinks records it
		var paths := {}   # property name -> NodePath, or Array of NodePath
		for p in state.get_node_property_count(i):
			var value = state.get_node_property_value(i, p)
			var prop := state.get_node_property_name(i, p)
			if value is NodePath and not (value as NodePath).is_empty():
				if not painted.has("%s|%s|%s" % [from, prop, _resolve(from, value)]):
					paths[prop] = value
			elif value is Array and not value.is_empty() and value.all(func(v): return v is NodePath):
				var hand_made: Array = value.filter(func(v):
					return not painted.has("%s|%s|%s" % [from, prop, _resolve(from, v)]))
				# Keep the property even when every entry was the painter's, so the
				# array is reset and the painter starts from a clean one.
				paths[prop] = hand_made
		if paths.is_empty():
			continue

		var node := new_root.get_node_or_null(state.get_node_path(i))
		if node == null:
			for prop in paths:
				report.dropped += (paths[prop].size() if paths[prop] is Array else 1)
			continue
		for prop in paths:
			_apply_link(node, prop, paths[prop], report)

static func _apply_link(node: Node, prop: StringName, value, report: Dictionary) -> void:
	var info := _property_info(node, prop)
	if info.is_empty():
		return
	if value is NodePath:
		if info.type == TYPE_NODE_PATH:
			return   # a plain path setting, not a node reference; the node keeps its own
		var target := node.get_node_or_null(value)
		node.set(prop, target)
		if target != null: report.links += 1
		else: report.dropped += 1
		return

	# Array of links.
	if info.type != TYPE_ARRAY or String(info.hint_string).begins_with(str(TYPE_NODE_PATH)):
		return
	var targets := []
	for path in value:
		var target := node.get_node_or_null(path)
		if target != null:
			targets.append(target)
			report.links += 1
		else:
			report.dropped += 1
	var current = node.get(prop)
	if current is Array:
		# Work on a COPY (which keeps the export's element type). In the editor the
		# value read back can be the scene's shared default array; filling that in
		# place makes the new value look unchanged, and it is then not saved.
		var typed: Array = current.duplicate()
		typed.assign(targets)
		node.set(prop, typed)
	else:
		node.set(prop, targets)

# Where a node-relative path ("../../Walls/Door") points, as a path from the root.
static func _resolve(from_node: String, relative: NodePath) -> String:
	var parts: Array = Array(from_node.split("/", false))
	if parts.size() > 0 and parts[0] == ".":
		parts.remove_at(0)
	for i in relative.get_name_count():
		var step := String(relative.get_name(i))
		if step == "..":
			if not parts.is_empty():
				parts.pop_back()
		elif step != ".":
			parts.append(step)
	return "/".join(parts)

static func _property_info(node: Node, prop: StringName) -> Dictionary:
	for info in node.get_property_list():
		if info.name == prop:
			return info
	return {}
