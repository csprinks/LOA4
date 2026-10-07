class_name SkillLattice
extends Control

## One attribute's skills on the character sheet: its two paths as two rows of
## SkillNodes, and the lines between them -- straight along a path and diagonal
## where the paths cross, since a skill opens both skills at the next position.
## A line lights up in the attribute's colour once the skills at both its ends
## are owned, running from the earlier skill to the later one.

const LINK_TIME := 0.22    # how long a line takes to light up
const LINK_DIM := Color(0.49, 0.36, 0.15, 0.55)

var nodes: Dictionary = {}          # skill id -> SkillNode

var _attribute: String
var _links: Array = []              # [from SkillDefinition, to SkillDefinition]
var _fill: Dictionary = {}          # link index -> 0..1 of it lit


func _init(attribute: String) -> void:
	_attribute = attribute
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SkillNode.NODE_SIZE.x * SkillTree.LINE_LENGTH,
		SkillNode.NODE_SIZE.y * SkillTree.PATHS)
	for skill in SkillTree.skills_of(attribute):
		var node := SkillNode.new(skill)
		node.position = Vector2((skill.position - 1) * SkillNode.NODE_SIZE.x,
			(skill.path - 1) * SkillNode.NODE_SIZE.y)
		node.size = SkillNode.NODE_SIZE
		nodes[skill.id] = node
		add_child(node)
		for required in SkillTree.prerequisites(skill):
			_links.append([required, skill])


# `owned`: skill id -> true for every owned skill. `animate` runs the light along
# lines that have just completed; false snaps them.
func show_links(owned: Dictionary, animate: bool) -> void:
	for i in _links.size():
		var lit: bool = owned.has(_links[i][0].id) and owned.has(_links[i][1].id)
		var was_lit: bool = _fill.get(i, 0.0) > 0.0
		if not lit:
			_fill[i] = 0.0
		elif not was_lit:
			if animate:
				_fill[i] = 0.001
				create_tween().tween_method(_set_fill.bind(i), 0.0, 1.0, LINK_TIME)
			else:
				_fill[i] = 1.0
		elif not animate:
			_fill[i] = 1.0
	queue_redraw()


func _set_fill(value: float, index: int) -> void:
	if _fill.get(index, 0.0) > 0.0:   # not unlit again since the tween began
		_fill[index] = maxf(value, 0.001)
		queue_redraw()


func _draw() -> void:
	var color := SkillTree.color_of(_attribute)
	for i in _links.size():
		draw_line(_center(_links[i][0]), _center(_links[i][1]), LINK_DIM, 3.0, true)
	# Lit lines go on top of every dim one.
	for i in _links.size():
		var lit: float = _fill.get(i, 0.0)
		if lit <= 0.0:
			continue
		var from := _center(_links[i][0])
		var tip := from.lerp(_center(_links[i][1]), lit)
		draw_line(from, tip, color, 4.0, true)
		if lit < 1.0:
			draw_circle(tip, 5.0, color.lightened(0.5))


func _center(skill: SkillDefinition) -> Vector2:
	return Vector2((skill.position - 0.5) * SkillNode.NODE_SIZE.x,
		(skill.path - 1) * SkillNode.NODE_SIZE.y + SkillNode.CENTER_Y)
