extends SceneTree

## Headless check of the skill tree rules. Run with:
##   godot --headless --path "E:/Godot Projects/loa-4" --script res://Character/tests/skill_tree_test.gd
## Exit code = number of failed checks (0 = all pass).

var _failures := 0

func _initialize() -> void:
	print("=== skill_tree_test ===")
	for attribute in Character.STAT_NAMES:
		_check(SkillTree.line(attribute).size() == SkillTree.LINE_LENGTH, "%s line is complete" % attribute)

	var might := SkillTree.line("Might")
	var fate := SkillTree.line("Fate")
	var c := Character.new()
	var book := c.skills.duplicate_book()
	var pool: int = c.available_attribute_points
	_check(pool == Character.STARTING_ATTRIBUTE_POINTS, "starting pool")

	_check(not book.advance(might[1], pool), "can't skip ahead in a line")
	_check(book.next_cost(might[0]) == 0 and book.advance(might[0], pool), "first free pick")
	_check(book.next_cost(might[1]) == 0 and book.advance(might[1], pool), "second free pick, same line")
	_check(book.free_picks_left == 0 and book.points_spent == 0, "free picks cost nothing")

	# 2 owned: position + 2 / 2.
	_check(book.next_cost(fate[0]) == 2 and book.next_cost(might[2]) == 4, "new-skill cost = position + owned / 2")
	_check(book.next_cost(might[0]) == 2, "rank 2 costs 2")
	_check(book.advance(might[0], pool) and book.next_cost(might[0]) == 3, "rank 3 costs 3")
	_check(book.advance(might[0], pool - book.points_spent), "upgrade to rank 3")
	_check(book.points_spent == 5 and book.next_cost(might[0]) == -1, "maxed skill has no next step")
	_check(not book.advance(fate[0], pool - book.points_spent), "overspend rejected")

	c.apply_skills(book)
	# Might I at rank 3 (+1 each) and Might II at rank 1 (+2).
	_check(c.get_stat("Might").total == 15 and c.get_stat("Fate").total == 10, "skills raise their line's stat")
	_check(c.available_attribute_points == 0, "pool spent")

	var hp_before: int = c.hit_points.max_value
	c.reward_xp(2200)   # level 1 -> 3
	_check(c.available_attribute_points == 2 * Character.ATTRIBUTE_POINTS_PER_LEVEL, "points granted per level gained")
	_check(c.hit_points.max_value == hp_before + 2 * Character.HP_PER_LEVEL, "HP from level only")

	# Raw attribute points: a flat 2 each, no skill needed.
	book = c.skills.duplicate_book()
	_check(book.buy_attribute("Fate", c.available_attribute_points)
		and book.buy_attribute("Fate", c.attribute_points_earned - book.points_spent), "raw attribute points bought")
	_check(not book.buy_attribute("Fate", 1) and not book.buy_attribute("Nope", 10), "bad raw buys rejected")
	c.apply_skills(book)
	_check(c.get_stat("Fate").total == 12 and c.available_attribute_points == 2 * Character.ATTRIBUTE_POINTS_PER_LEVEL - 4,
		"raw points raise the stat for 2 each")

	var copy := Character.new()
	copy.from_json(c.to_json())
	_check(copy.skills.equals(c.skills) and copy.get_stat("Might").total == 15 and copy.get_stat("Fate").total == 12
		and copy.available_attribute_points == c.available_attribute_points, "survives save/load")

	book = c.skills.duplicate_book()
	book.reset()
	c.apply_skills(book)
	_check(c.get_stat("Might").total == 10 and c.get_stat("Fate").total == 10 and c.skills.free_picks_left == SkillTree.FREE_PICKS
		and c.available_attribute_points == c.attribute_points_earned, "respec refunds everything")

	var old_save := Character.new()
	old_save.from_dict({"primary_class": "Knight", "level_system": {"current_level": 3},
		"stats": {"Might": {"base": 10, "points_spent": 2, "gain_per_point": 4}}})
	_check(old_save.get_stat("Might").total == 10 and old_save.skills.owned_count() == 0
		and old_save.available_attribute_points == 15, "pre-skill-tree save loads as a fresh build")

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
