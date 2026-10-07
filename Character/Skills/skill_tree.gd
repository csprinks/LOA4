class_name SkillTree
extends RefCounted

## The shared skill tree: one line of LINE_LENGTH skills per attribute, loaded
## from the SkillDefinition resources in DEFINITION_DIR. Static and read-only --
## what a hero actually owns lives in their SkillBook. Tunables for the whole
## system live here.

const DEFINITION_DIR := "res://Character/Skills/Definitions/"
const LINE_LENGTH := 5
# Buying a skill is rank 1; it can then be upgraded up to MAX_RANK.
const MAX_RANK := 3
# Skills a new hero picks for free at creation.
const FREE_PICKS := 2
# New-skill cost = position + (skills already owned / OWNED_PER_SURCHARGE).
const OWNED_PER_SURCHARGE := 2
# Attribute Points one raw +1 to an attribute costs (no skill involved).
const ATTRIBUTE_POINT_COST := 2

const COLORS := {
	"Might": Color(0.82, 0.27, 0.2),
	"Awareness": Color(0.36, 0.7, 0.33),
	"Finesse": Color(0.9, 0.72, 0.24),
	"Intellect": Color(0.3, 0.55, 0.9),
	"Charm": Color(0.88, 0.42, 0.66),
	"Fate": Color(0.62, 0.42, 0.88),
}

static var _lines: Dictionary = {}   # attribute -> Array of SkillDefinition, by position
static var _by_id: Dictionary = {}   # id -> SkillDefinition


# The skills of one attribute's line, in purchase order.
static func line(attribute: String) -> Array:
	_ensure_loaded()
	return _lines.get(attribute, [])


static func get_skill(id: String) -> SkillDefinition:
	_ensure_loaded()
	return _by_id.get(id, null)


# The skill that must be owned before `skill` can be bought (null for the first).
static func prerequisite(skill: SkillDefinition) -> SkillDefinition:
	if skill.position <= 1:
		return null
	return line(skill.attribute)[skill.position - 2]


static func color_of(attribute: String) -> Color:
	return COLORS.get(attribute, UIStyle.GOLD)


static func _ensure_loaded() -> void:
	if not _lines.is_empty():
		return
	for attribute in Character.STAT_NAMES:
		var skills := []
		for pos in range(1, LINE_LENGTH + 1):
			var path := "%s%s_%d.tres" % [DEFINITION_DIR, attribute.to_lower(), pos]
			var skill := load(path) as SkillDefinition
			if skill == null:
				push_error("SkillTree: missing skill definition %s" % path)
				continue
			skills.append(skill)
			_by_id[skill.id] = skill
		_lines[attribute] = skills
