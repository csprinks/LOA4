class_name SkillTree
extends RefCounted

## The shared skill tree: for each attribute, PATHS paths of LINE_LENGTH skills,
## loaded from the SkillDefinition resources in DEFINITION_DIR. The paths cross:
## a skill needs ANY skill of its attribute one position earlier, on either path,
## so a build can hop between them. Static and read-only -- what a hero actually
## owns lives in their SkillBook. Tunables for the whole system live here.

const DEFINITION_DIR := "res://Character/Skills/Definitions/"
const PATHS := 2
const LINE_LENGTH := 5
# Buying a skill is rank 1; it can then be upgraded up to MAX_RANK.
const MAX_RANK := 3
# Free steps a new hero gets at creation: each buys a skill or a rank of one.
const FREE_PICKS := 2
# New-skill cost in Skill Points = position + (skills already owned / OWNED_PER_SURCHARGE).
const OWNED_PER_SURCHARGE := 2
# Attribute Points one raw +1 to an attribute costs.
const ATTRIBUTE_POINT_COST := 1

const COLORS := {
	"Might": Color(0.82, 0.27, 0.2),
	"Awareness": Color(0.36, 0.7, 0.33),
	"Finesse": Color(0.9, 0.72, 0.24),
	"Intellect": Color(0.3, 0.55, 0.9),
	"Charm": Color(0.88, 0.42, 0.66),
	"Fate": Color(0.62, 0.42, 0.88),
}

static var _lines: Dictionary = {}   # "attribute|path" -> Array of SkillDefinition, by position
static var _all: Dictionary = {}     # attribute -> Array of every SkillDefinition in it
static var _by_id: Dictionary = {}   # id -> SkillDefinition


# The skills of one path of an attribute, by position.
static func line(attribute: String, path: int = 1) -> Array:
	_ensure_loaded()
	return _lines.get("%s|%d" % [attribute, path], [])


# Every skill of an attribute, both paths.
static func skills_of(attribute: String) -> Array:
	_ensure_loaded()
	return _all.get(attribute, [])


static func get_skill(id: String) -> SkillDefinition:
	_ensure_loaded()
	return _by_id.get(id, null)


# The skills that unlock `skill`: owning any ONE of them is enough. Empty for a
# path's first skill, which is always open.
static func prerequisites(skill: SkillDefinition) -> Array:
	var out := []
	if skill.position <= 1:
		return out
	for path in range(1, PATHS + 1):
		var skills := line(skill.attribute, path)
		if skills.size() >= skill.position - 1:
			out.append(skills[skill.position - 2])
	return out


static func color_of(attribute: String) -> Color:
	return COLORS.get(attribute, UIStyle.GOLD)


static func _ensure_loaded() -> void:
	if not _lines.is_empty():
		return
	for attribute in Character.STAT_NAMES:
		_all[attribute] = []
		for path in range(1, PATHS + 1):
			var skills := []
			for pos in range(1, LINE_LENGTH + 1):
				var file := "%s_%s%d.tres" % [attribute.to_lower(), "" if path == 1 else "b", pos]
				var skill := load(DEFINITION_DIR + file) as SkillDefinition
				if skill == null:
					push_error("SkillTree: missing skill definition %s" % file)
					continue
				skills.append(skill)
				_all[attribute].append(skill)
				_by_id[skill.id] = skill
			_lines["%s|%d" % [attribute, path]] = skills
