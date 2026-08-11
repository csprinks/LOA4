extends SceneTree

## Headless smoke test for the combat foundation. Run with:
##   godot --headless --path "E:/Godot Projects/loa-4" --script res://Combat/tests/combat_test.gd
##
## (If Godot can't resolve the new class_names, rebuild the class cache once first:
##   godot --headless --editor --quit --path "E:/Godot Projects/loa-4"
## then run the line above.)
##
## Uses a SEEDED CombatRNG so fights are deterministic. This is a fast, readable
## sanity check, not a formal test framework: each _test_* returns a failure count.

var _failures := 0

func _initialize() -> void:
	print("=== combat_test ===")
	_test_fight_terminates_and_rewards()
	_test_row_reach_and_promotion()
	_test_downed_and_revive()
	_test_defend_reduces_damage()
	_test_ap_banking()

	if _failures == 0:
		print("\n[combat_test] ALL CHECKS PASSED")
	else:
		printerr("\n[combat_test] %d CHECK(S) FAILED" % _failures)
	quit(_failures)

#region Helpers
func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)

func _make_hero(hero_name: String, might: int, finesse: int, awareness: int) -> Character:
	var c := Character.new()
	c.character_name = hero_name
	c.apply_stat_data({
		"Might": {"base": might, "deeds_spent": 0, "points_per_deed": 1},
		"Finesse": {"base": finesse, "deeds_spent": 0, "points_per_deed": 1},
		"Awareness": {"base": awareness, "deeds_spent": 0, "points_per_deed": 1},
	})
	return c

# Ally policy: attack the first reachable enemy if affordable, else pass.
func _ally_attacks_front(actor: Combatant, encounter: Encounter, controller) -> Dictionary:
	var atk := AttackAction.new()
	if actor.action_points < atk.ap_cost_for(actor):
		return {}
	var targets := encounter.reachable_enemies(actor)
	if targets.is_empty():
		return {}
	return {"action": atk, "target": targets[0]}
#endregion

func _test_fight_terminates_and_rewards() -> void:
	print("\n-- fight terminates + rewards --")
	var allies: Array = []
	for i in range(4):
		allies.append(Combatant.for_ally(_make_hero("Hero %d" % (i + 1), 16, 14, 12)))
	var enemies := [
		Combatant.for_enemy(MonsterLibrary.kobold(), 0),
		Combatant.for_enemy(MonsterLibrary.kobold(), 0),
	]
	var enc := Encounter.new(allies, enemies)
	var controller := CombatController.new(enc, CombatRNG.new(12345))
	controller.ally_action_provider = _ally_attacks_front

	var xp_before: int = allies[0].character.level_system.current_xp
	var status := controller.run_to_completion()

	_check(status != Encounter.Status.ONGOING, "fight reached a terminal status")
	_check(controller.round_number < 100, "fight ended before the round cap")
	if status == Encounter.Status.WIN:
		_check(enc.all_enemies_dead(), "WIN => all enemies dead")
		_check(allies[0].character.level_system.current_xp > xp_before,
			"WIN => surviving hero gained XP")
	print("  (result: status=%d, rounds=%d)" % [status, controller.round_number])

func _test_row_reach_and_promotion() -> void:
	print("\n-- row reach + front promotion --")
	var hero := Combatant.for_ally(_make_hero("Melee", 16, 14, 12))
	var front := Combatant.for_enemy(MonsterLibrary.kobold(), 0)
	var back := Combatant.for_enemy(MonsterLibrary.kobold_archer(), 1)
	var enc := Encounter.new([hero], [front, back])

	_check(enc.front_enemy_row() == 0, "front row is 0 while a front monster lives")
	var reachable := enc.reachable_enemies(hero)
	_check(reachable.has(front), "melee hero can reach the front-row monster")
	_check(not reachable.has(back), "melee hero cannot reach the back-row monster")

	# Wipe the front row; the back row should promote to reachable.
	front.take_damage(999)
	_check(front.is_downed, "front monster downed by lethal damage")
	_check(enc.front_enemy_row() == 1, "front row promotes to 1 after the front is cleared")
	_check(enc.reachable_enemies(hero).has(back),
		"melee hero can now reach the promoted back row")

func _test_downed_and_revive() -> void:
	print("\n-- downed + revive + LOSE --")
	var hero := Combatant.for_ally(_make_hero("Fragile", 10, 10, 10))
	var enc := Encounter.new([hero], [Combatant.for_enemy(MonsterLibrary.orc(), 0)])

	hero.take_damage(9999)
	_check(hero.is_downed, "hero is downed at 0 HP")
	_check(enc.living_allies().is_empty(), "downed hero is excluded from living allies")
	enc.refresh_status()
	_check(enc.status == Encounter.Status.LOSE, "all allies down => LOSE")

	hero.heal(25)
	_check(not hero.is_downed, "healing above 0 revives the downed hero")
	_check(hero.current_hp == 25, "revived hero has the healed HP")

func _test_defend_reduces_damage() -> void:
	print("\n-- defend mitigates damage --")
	var hero := Combatant.for_ally(_make_hero("Guard", 10, 10, 10))
	hero.add_status_effect(DefendEffect.new())
	var dealt := hero.take_damage(20)
	# DEFEND_DAMAGE_REDUCTION 0.5 => ceil(20 * 0.5) = 10.
	_check(dealt == 10, "Defend halves incoming damage (20 -> 10)")

func _test_ap_banking() -> void:
	print("\n-- AP banking --")
	var hero := Combatant.for_ally(_make_hero("Banker", 10, 10, 10))
	# Fresh combatant starts at max AP (5).
	_check(hero.action_points == 5, "starts at max AP (5)")
	hero.spend_ap(5)
	hero.refresh_ap_for_turn()
	_check(hero.action_points == 5, "spent-to-zero refreshes to max (5)")
	hero.refresh_ap_for_turn()  # unspent 5 + 5 = 10, cap = 2 * 5 = 10
	_check(hero.action_points == 10, "unspent AP banks up to the cap (10)")
	hero.refresh_ap_for_turn()  # 10 + 5 capped at 10
	_check(hero.action_points == 10, "banking never exceeds the cap")
