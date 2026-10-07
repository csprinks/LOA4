extends SceneTree

## Headless check of the skill tree rules. Run with:
##   godot --headless --path "E:/Godot Projects/loa-4" --script res://Character/tests/skill_tree_test.gd
## Exit code = number of failed checks (0 = all pass).

var _failures := 0

func _initialize() -> void:
	print("=== skill_tree_test ===")
	for attribute in Character.STAT_NAMES:
		_check(SkillTree.line(attribute, 1).size() == SkillTree.LINE_LENGTH
			and SkillTree.line(attribute, 2).size() == SkillTree.LINE_LENGTH
			and SkillTree.skills_of(attribute).size() == 10, "%s has two full paths" % attribute)

	var might := SkillTree.line("Might", 1)
	var might_b := SkillTree.line("Might", 2)
	var fate := SkillTree.line("Fate", 1)
	var c := Character.new()
	var book := c.skills.duplicate_book()
	var sp: int = c.available_skill_points
	_check(sp == 5 and c.available_attribute_points == 5, "a new hero has 5 of each point")

	_check(not book.advance(might[1], sp) and not book.advance(might_b[1], sp), "can't start past a path's first skill")
	_check(book.next_cost(might[0]) == 0 and book.advance(might[0], sp), "first free pick")
	_check(book.next_cost(might_b[1]) == 0 and book.advance(might_b[1], sp), "second free pick crosses to the other path")
	_check(book.free_picks_left == 0 and book.skill_points_spent == 0, "free picks cost nothing")
	_check(book.is_reachable(might[2]) and book.is_reachable(might_b[2]) and not book.is_reachable(might[3]),
		"a skill opens both skills at the next position, and only those")

	# 2 owned: position + 2 / 2.
	_check(book.next_cost(fate[0]) == 2 and book.next_cost(might[2]) == 4 and book.next_cost(might_b[0]) == 2,
		"new-skill cost = position + owned / 2")
	_check(book.next_cost(might[0]) == 2, "rank 2 costs 2")
	_check(book.advance(might[0], sp) and book.next_cost(might[0]) == 3, "rank 3 costs 3")
	_check(book.advance(might[0], sp - book.skill_points_spent), "upgrade to rank 3")
	_check(book.skill_points_spent == 5 and book.next_cost(might[0]) == -1, "maxed skill has no next step")
	_check(not book.advance(fate[0], sp - book.skill_points_spent), "overspend rejected")

	# Attribute Points are their own pool: 1 each, untouched by skill spending.
	for i in 5:
		_check(book.buy_attribute("Fate", c.attribute_points_earned - book.attribute_points_spent), "raw Fate point %d" % (i + 1))
	_check(not book.buy_attribute("Fate", c.attribute_points_earned - book.attribute_points_spent)
		and not book.buy_attribute("Nope", 10), "bad raw buys rejected")

	c.apply_skills(book)
	# Might I at rank 3 (+1 each) and path-2 Might II at rank 1 (+2); five raw Fate.
	_check(c.get_stat("Might").total == 15 and c.get_stat("Fate").total == 15, "skills and raw points raise the stats")
	_check(c.available_skill_points == 0 and c.available_attribute_points == 0, "both pools spent")

	var hp_before: int = c.hit_points.max_value
	c.reward_xp(2200)   # level 1 -> 3
	_check(c.available_skill_points == 10 and c.available_attribute_points == 10, "5 of each point per level gained")
	_check(c.hit_points.max_value == hp_before + 2 * Character.HP_PER_LEVEL, "HP from level only")

	var copy := Character.new()
	copy.from_json(c.to_json())
	_check(copy.skills.equals(c.skills) and copy.get_stat("Might").total == 15 and copy.get_stat("Fate").total == 15
		and copy.available_skill_points == 10 and copy.available_attribute_points == 10, "survives save/load")

	book = c.skills.duplicate_book()
	book.reset()
	c.apply_skills(book)
	_check(c.get_stat("Might").total == 10 and c.get_stat("Fate").total == 10 and c.skills.free_picks_left == SkillTree.FREE_PICKS
		and c.available_skill_points == 15 and c.available_attribute_points == 15, "respec refunds everything")

	# A save from when one pool paid for both (raw points at 2 each).
	var shared := Character.new()
	shared.from_dict({"level_system": {"current_level": 3}, "attribute_points_earned": 15,
		"skills": {"ranks": {"might_1": 1}, "raw_points": {"Fate": 2}, "free_picks_left": 1, "points_spent": 6}})
	_check(shared.get_stat("Fate").total == 12 and shared.get_stat("Might").total == 11
		and shared.available_skill_points == 13 and shared.available_attribute_points == 13, "single-pool save is split")

	var old_save := Character.new()
	old_save.from_dict({"primary_class": "Knight", "level_system": {"current_level": 3},
		"stats": {"Might": {"base": 10, "points_spent": 2, "gain_per_point": 4}}})
	_check(old_save.get_stat("Might").total == 10 and old_save.skills.owned_count() == 0
		and old_save.available_skill_points == 15 and old_save.available_attribute_points == 15,
		"pre-skill-tree save loads as a fresh build")

	if _failures == 0:
		print("\n[skill_tree_test] ALL CHECKS PASSED")
	else:
		printerr("\n[skill_tree_test] %d CHECK(S) FAILED" % _failures)
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
