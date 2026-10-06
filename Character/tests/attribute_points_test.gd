extends SceneTree

## Headless check of the level-up Attribute Point loop. Run with:
##   godot --headless --path "E:/Godot Projects/loa-4" --script res://Character/tests/attribute_points_test.gd
## Exit code = number of failed checks (0 = all pass).

var _failures := 0

func _initialize() -> void:
	print("=== attribute_points_test ===")
	var c := Character.new()
	c.apply_stat_data({
		"Might": {"base": 10, "points_spent": 2, "gain_per_point": 4},
		"Fate": {"base": 10, "points_spent": 0, "gain_per_point": 1},
	})
	var hp_before: int = c.hit_points.max_value

	c.reward_xp(2200)   # level 1 -> 3
	_check(c.level_system.current_level == 3, "reached level 3")
	_check(c.available_attribute_points == 2 * Character.ATTRIBUTE_POINTS_PER_LEVEL, "points granted per level gained")

	var pool: int = c.available_attribute_points
	_check(not c.spend_attribute_points({"Might": pool + 1}), "overspend rejected")
	_check(not c.spend_attribute_points({"Might": -1}), "negative rejected")
	_check(not c.spend_attribute_points({"Nope": 1}), "unknown stat rejected")
	_check(c.available_attribute_points == pool and c.get_stat("Might").total == 18, "rejected spends change nothing")

	var hp_mid: int = c.hit_points.max_value
	c.take_damage(30)
	_check(c.spend_attribute_points({"Might": 1, "Fate": 1}), "valid spend accepted")
	_check(c.get_stat("Might").total == 22 and c.get_stat("Fate").total == 11, "stats rise by their Gain")
	_check(c.available_attribute_points == pool - 2, "pool reduced")
	_check(c.hit_points.max_value == hp_mid + Character.HP_PER_MIGHT_POINT, "Might point adds flat max HP")
	_check(c.hit_points.current == hp_mid - 30 + Character.HP_PER_MIGHT_POINT, "gained HP is granted, wounds kept")
	_check(hp_mid == hp_before + 2 * Character.HP_PER_LEVEL, "level-up HP unchanged")

	var copy := Character.new()
	copy.from_json(c.to_json())
	_check(copy.available_attribute_points == c.available_attribute_points
		and copy.get_stat("Might").total == 22, "survives save/load")

	if _failures == 0:
		print("\n[attribute_points_test] ALL CHECKS PASSED")
	else:
		printerr("\n[attribute_points_test] %d CHECK(S) FAILED" % _failures)
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
