extends Node

# Global character utility functions.

static func create_default_character(char_name: String, portrait: String) -> Character:
	var character = Character.new()
	character.character_name = char_name
	character.portrait = portrait
	return character

static func copy_character_data(source: Character, target: Character) -> void:
	target.from_dict(source.to_dict())

static func create_character_from_data(data: Dictionary) -> Character:
	var character = Character.new()
	character.from_dict(data)
	return character

static func get_character_stats_summary(character: Character) -> Dictionary:
	if not character:
		return {}

	return {
		"name": character.character_name,
		"level": character.level_system.current_level,
		"hp": "%d/%d" % [character.hit_points.current, character.hit_points.max_value],
		"ap": "%d/%d" % [character.action_points.current, character.action_points.max_value],
		"fp": character.fortune_points.current,
		"favor": character.level_system.favor_points
	}

# Validation functions
static func is_character_valid(character: Character) -> bool:
	return character != null

static func heal_party(party: Array[Character]) -> void:
	for character in party:
		if is_character_valid(character):
			character.hit_points.reset()
			character.action_points.reset()

static func apply_party_damage(party: Array[Character], damage: int) -> void:
	for character in party:
		if is_character_valid(character):
			character.take_damage(damage)
