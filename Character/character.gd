class_name Character
extends RefCounted

## A single playable hero: identity, the six stats, derived attributes (HP/AP/FP/
## armor), leveling, owned skills, and equipped items. There are no fixed classes:
## the skills a hero takes (SkillBook) raise the stats and define the build.
## Serializes to/from a plain dict for the SaveSystem.

signal leveled_up(old_level, new_level)
signal xp_gained(amount)

# The six character stats, keyed by name -> Stat object. Order matters for the
# Character Creation screen and any stat UI.
const STAT_NAMES := ["Might", "Awareness", "Finesse", "Intellect", "Charm", "Fate"]

# --- Derived max HP ---------------------------------------------------------
# max_hp = HP_BASE + HP_PER_LEVEL * (level - 1). Level only for now; individual
# Might skills can add HP once real skills exist. "Gritty" tuning: a level-1 hero
# has 110 HP and ~452 by level 20. Recomputed on level-up and on loading a save.
const HP_BASE := 110
const HP_PER_LEVEL := 18

# Derived attributes
var hit_points: HitPoints
var action_points: ActionPoints
var fortune_points: FortunePoints
var armor: Armor
var level_system: LevelSystem

var character_name: String = "Unnamed Hero"
var portrait: String = "res://Portraits/Portrait_1.png"

# Equipped items, keyed by slot. Each value is a dict produced by
# EquipmentSerializer.item_to_dict ({} means the slot is empty). The character
# card UI keeps this in sync with the on-screen equip slots (hands, the two
# consumable quick slots, and armor).
const EQUIPMENT_SLOTS := ["primary", "secondary", "consumable1", "consumable2", "head", "chest", "hands", "feet", "neck", "ring"]
var equipment: Dictionary = {}

# Free-text title the player writes on the character sheet ("Paladin", "Hedge
# Witch", ...). Purely cosmetic -- the skills are the real class.
var title: String = ""

# Owned skills. Bought and upgraded on the character sheet (UI/character_sheet.gd)
# with Attribute Points; each rank raises the stat of the skill's line.
var skills: SkillBook

# Attribute Points buy skills, skill ranks and raw attribute points: a hero
# starts with a few and earns more every level. Only the lifetime total is stored; what is left to spend is
# that minus whatever the SkillBook has sunk, so a respec refunds everything.
const STARTING_ATTRIBUTE_POINTS := 5
const ATTRIBUTE_POINTS_PER_LEVEL := 5
var attribute_points_earned: int = STARTING_ATTRIBUTE_POINTS
var available_attribute_points: int:
	get: return attribute_points_earned - skills.points_spent

var stats: Dictionary = {}

func _init() -> void:
	action_points = ActionPoints.new(5)
	fortune_points = FortunePoints.new(1)
	armor = Armor.new(0)
	skills = SkillBook.new()

	# Each stat is its own class so per-stat behaviour can be added later.
	stats = {
		"Might": Might.new(),
		"Awareness": Awareness.new(),
		"Finesse": Finesse.new(),
		"Intellect": Intellect.new(),
		"Charm": Charm.new(),
		"Fate": Fate.new(),
	}

	level_system = LevelSystem.new(1, 0)
	level_system.level_up.connect(_on_level_up)
	level_system.xp_gained.connect(_on_xp_gained)

	# HP is derived from level, so build it after the level system exists and
	# start the hero at full health.
	hit_points = HitPoints.new(compute_max_hp())

	for slot in EQUIPMENT_SLOTS:
		equipment[slot] = {}

#region Identity
func get_name() -> String:
	return character_name
#endregion

#region Leveling
func reward_xp(amount: int) -> void:
	level_system.add_xp(amount)

func _on_level_up(old_level: int, new_level: int) -> void:
	attribute_points_earned += (new_level - old_level) * ATTRIBUTE_POINTS_PER_LEVEL
	# Higher level => higher max HP; grant the gained HP so leveling heals.
	refresh_max_hp("delta")
	leveled_up.emit(old_level, new_level)

func _on_xp_gained(amount: int) -> void:
	xp_gained.emit(amount)
#endregion

#region Attributes
# Max HP derived from the current level (see the HP_* constants).
func compute_max_hp() -> int:
	var lvl: int = level_system.current_level if level_system else 1
	return HP_BASE + HP_PER_LEVEL * (lvl - 1)

# Recompute max HP and reconcile current HP. `fill` decides what happens to the
# current value:
#   "full"  -> jump current up to the new max (fresh hero / character creation)
#   "delta" -> add only the gained amount to current (level-up)
#   "keep"  -> leave current as-is, only clamped down to the new max (load)
func refresh_max_hp(fill: String = "delta") -> void:
	var old_max := hit_points.max_value
	var new_max := compute_max_hp()
	hit_points.set_max(new_max)
	match fill:
		"full":
			hit_points.reset()
		"delta":
			if new_max > old_max:
				hit_points.increase(new_max - old_max)
		"keep":
			pass

func add_fortune_points(amount: int) -> void:
	fortune_points.increase(amount)

func take_damage(amount: int) -> void:
	hit_points.reduce(amount)

func heal(amount: int) -> void:
	hit_points.increase(amount)

func use_action_points(amount: int) -> bool:
	if action_points.has_points(amount):
		action_points.reduce(amount)
		return true
	return false

func restore_action_points(amount: int) -> void:
	action_points.increase(amount)

func reset_action_points() -> void:
	action_points.reset()
#endregion

#region Stats
func get_stat(stat_name: String) -> Stat:
	return stats.get(stat_name, null)

# Replace this hero's skills with `book` (the character sheet's confirmed draft)
# and re-derive the stats from them.
func apply_skills(book: SkillBook) -> void:
	skills.copy_from(book)
	refresh_stat_bonuses()

# Re-derive every stat's bonus from the owned skills.
func refresh_stat_bonuses() -> void:
	for stat_name in stats:
		stats[stat_name].set_bonus(skills.stat_bonus(stat_name))

func _stats_to_dict() -> Dictionary:
	var out := {}
	for stat_name in stats:
		out[stat_name] = stats[stat_name].to_dict()
	return out
#endregion

#region Equipment
# Slot keys are "primary" / "secondary"; item_dict is an EquipmentSerializer dict
# ({} means the slot is empty).
func get_equipment_slot(slot_key: String) -> Dictionary:
	return equipment.get(slot_key, {})

func set_equipment_slot(slot_key: String, item_dict: Dictionary) -> void:
	equipment[slot_key] = item_dict
#endregion

#region Serialization
func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"portrait": portrait,

		"hit_points": {
			"current": hit_points.current,
			"max": hit_points.max_value
		},
		"action_points": {
			"current": action_points.current,
			"max": action_points.max_value
		},
		"fortune_points": fortune_points.current,
		"armor": armor.value,

		"level_system": {
			"current_level": level_system.current_level,
			"current_xp": level_system.current_xp
		},

		"equipment": equipment,

		"title": title,
		"attribute_points_earned": attribute_points_earned,
		"skills": skills.to_dict(),
		"stats": _stats_to_dict()
	}

func to_json() -> String:
	return JSON.stringify(to_dict())

func from_dict(data: Dictionary) -> void:
	character_name = data.get("character_name", "Unnamed Hero")
	portrait = data.get("portrait", "res://Portraits/Portrait_1.png")

	# Max HP is derived from level, recomputed after it loads below, so
	# the stored max is ignored -- only the saved current (wound state) is kept.
	# -1 means "no saved value"; the hero is then filled to the recomputed max.
	var saved_hp_current := -1
	if data.has("hit_points"):
		saved_hp_current = int(data["hit_points"].get("current", -1))

	if data.has("action_points"):
		var ap_data = data["action_points"]
		action_points.set_max(ap_data.get("max", 5))
		action_points.set_current(ap_data.get("current", 5))

	fortune_points.set_current(data.get("fortune_points", 1))
	armor.set_value(data.get("armor", 0))

	if data.has("level_system"):
		var level_data = data["level_system"]
		level_system.current_level = level_data.get("current_level", 1)
		level_system.current_xp = level_data.get("current_xp", 0)

	# Equipped items. Normalise so every slot key always exists.
	var equip_data = data.get("equipment", {})
	equipment = {}
	for slot in EQUIPMENT_SLOTS:
		equipment[slot] = equip_data.get(slot, {}) if typeof(equip_data) == TYPE_DICTIONARY else {}

	title = data.get("title", "")
	# A save from before the skill tree has neither key: the hero then loads with
	# no skills and the full pool their level has earned.
	attribute_points_earned = int(data.get("attribute_points_earned",
		STARTING_ATTRIBUTE_POINTS + ATTRIBUTE_POINTS_PER_LEVEL * (level_system.current_level - 1)))
	var skill_data = data.get("skills", {})
	skills.from_dict(skill_data if typeof(skill_data) == TYPE_DICTIONARY else {})

	# Rebuild each stat's base, then its bonus from the skills just loaded.
	var stats_data = data.get("stats", {})
	if typeof(stats_data) == TYPE_DICTIONARY:
		for stat_name in stats:
			var sd = stats_data.get(stat_name, null)
			if typeof(sd) == TYPE_DICTIONARY:
				stats[stat_name].from_dict(sd)

	refresh_stat_bonuses()

	# Level is loaded now: derive max HP and restore the saved current (migrates
	# older saves whose stored max predates this formula).
	refresh_max_hp("keep")
	if saved_hp_current >= 0:
		hit_points.set_current(saved_hp_current)

func from_json(json_string: String) -> void:
	var data = JSON.parse_string(json_string)
	if not data:
		push_error("Failed to parse character JSON")
		return
	from_dict(data)
#endregion
