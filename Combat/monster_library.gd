class_name MonsterLibrary
extends RefCounted

## Code-built sample MonsterDefinitions so the combat core can run and be tested
## before any .tres monster resources are authored. Real content should live in
## .tres files under Combat/Monsters/; these are placeholders for bootstrapping.

static func kobold() -> MonsterDefinition:
	var m := MonsterDefinition.new()
	m.display_name = "Kobold"
	m.max_hp = 220
	m.max_action_points = 4
	m.might = 8
	m.finesse = 12
	m.awareness = 10
	m.fate = 6
	m.armor = 1
	m.damage_min = 7
	m.damage_max = 12
	m.attack_ap_cost = 3
	m.default_row = 0
	m.xp_reward = 20
	m.crowns_reward = 3
	return m

static func orc() -> MonsterDefinition:
	var m := MonsterDefinition.new()
	m.display_name = "Orc"
	m.max_hp = 340
	m.max_action_points = 5
	m.might = 15
	m.finesse = 9
	m.awareness = 8
	m.fate = 5
	m.armor = 3
	m.damage_min = 14
	m.damage_max = 22
	m.attack_ap_cost = 3
	m.default_row = 0
	m.xp_reward = 40
	m.crowns_reward = 8
	# Sample loot: an Orc drops a healing potion into the shared backpack on death.
	m.loot.append(preload("res://Inventory/Resources/Potions/healing.tres"))
	return m

# A ranged monster: placed in the back row, still able to hit any hero.
static func kobold_archer() -> MonsterDefinition:
	var m := MonsterDefinition.new()
	m.display_name = "Kobold Archer"
	m.max_hp = 180
	m.max_action_points = 4
	m.might = 7
	m.finesse = 14
	m.awareness = 12
	m.fate = 7
	m.armor = 0
	m.damage_min = 8
	m.damage_max = 13
	m.is_ranged = true
	m.attack_ap_cost = 3
	m.default_row = 1
	m.xp_reward = 25
	m.crowns_reward = 4
	# Sample loot: the archer drops an Action Points potion.
	m.loot.append(preload("res://Inventory/Resources/Potions/action_points.tres"))
	return m
