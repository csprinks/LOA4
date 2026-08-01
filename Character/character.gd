class_name Character
extends RefCounted

## A single playable hero: identity, the six stats, derived attributes (HP/AP/FP/
## armor), leveling, class choices, and equipped hand items. Serializes to/from a
## plain dict for the SaveSystem.
##
## Ported from LOA2, where this was split across a thin `Character` proxy and a
## `CharacterManager`. The proxy forwarded every call one-to-one with no
## polymorphism benefit, so the two were merged into this single class.

signal leveled_up(old_level, new_level, favor_gained)
signal xp_gained(amount)

# The six character stats, keyed by name -> Stat object. Order matters for the
# Character Creation screen and any stat UI.
const STAT_NAMES := ["Might", "Awareness", "Finesse", "Intellect", "Charm", "Fate"]

# Derived attributes
var hit_points: HitPoints
var action_points: ActionPoints
var fortune_points: FortunePoints
var armor: Armor
var level_system: LevelSystem

var character_name: String = "Unnamed Hero"
var portrait: String = "res://Portraits/Portrait_1.png"

# Equipped hand items, keyed by slot ("primary"/"secondary"). Each value is a
# dict produced by EquipmentSerializer.item_to_dict ({} means the slot is empty).
# The character card UI keeps this in sync with the on-screen weapon slots.
var equipment: Dictionary = {"primary": {}, "secondary": {}}

# Choices made on the Character Creation screen.
var primary_class: String = ""
var secondary_class: String = ""

var stats: Dictionary = {}

func _init() -> void:
	hit_points = HitPoints.new(100)
	action_points = ActionPoints.new(5)
	fortune_points = FortunePoints.new(1)
	armor = Armor.new(0)

	# Each stat is its own class so per-stat behaviour can be added later.
	stats = {
		"Might": Might.new(),
		"Awareness": Awareness.new(),
		"Finesse": Finesse.new(),
		"Intellect": Intellect.new(),
		"Charm": Charm.new(),
		"Fate": Fate.new(),
	}

	level_system = LevelSystem.new(1, 0, 25)
	level_system.level_up.connect(_on_level_up)
	level_system.xp_gained.connect(_on_xp_gained)

#region Identity
func get_name() -> String:
	return character_name
#endregion

#region Leveling
func reward_xp(amount: int) -> void:
	level_system.add_xp(amount)

func _on_level_up(old_level: int, new_level: int, favor_gained: int) -> void:
	leveled_up.emit(old_level, new_level, favor_gained)

func _on_xp_gained(amount: int) -> void:
	xp_gained.emit(amount)

func use_favor_points(cost: int) -> bool:
	return level_system.spend_favor_points(cost)
#endregion

#region Attributes
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

# Apply Character Creation allocations: {name: {base, deeds_spent, points_per_deed}}.
func apply_stat_data(stat_data: Dictionary) -> void:
	for stat_name in stats:
		if stat_data.has(stat_name):
			var d: Dictionary = stat_data[stat_name]
			stats[stat_name].configure(
				int(d.get("base", Stat.BASE_DEFAULT)),
				int(d.get("deeds_spent", 0)),
				int(d.get("points_per_deed", 1)))

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
			"current_xp": level_system.current_xp,
			"favor_points": level_system.favor_points
		},

		"equipment": equipment,

		"primary_class": primary_class,
		"secondary_class": secondary_class,
		"stats": _stats_to_dict()
	}

func to_json() -> String:
	return JSON.stringify(to_dict())

func from_dict(data: Dictionary) -> void:
	character_name = data.get("character_name", "Unnamed Hero")
	portrait = data.get("portrait", "res://Portraits/Portrait_1.png")

	if data.has("hit_points"):
		var hp_data = data["hit_points"]
		hit_points.set_max(hp_data.get("max", 100))
		hit_points.set_current(hp_data.get("current", 100))

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
		level_system.favor_points = level_data.get("favor_points", 0)

	# Equipped hand items. Normalise so both slot keys always exist.
	var equip_data = data.get("equipment", {})
	equipment = {
		"primary": equip_data.get("primary", {}) if typeof(equip_data) == TYPE_DICTIONARY else {},
		"secondary": equip_data.get("secondary", {}) if typeof(equip_data) == TYPE_DICTIONARY else {}
	}

	primary_class = data.get("primary_class", "")
	secondary_class = data.get("secondary_class", "")

	# Rebuild each stat from its saved {base, deeds_spent, points_per_deed}.
	var stats_data = data.get("stats", {})
	if typeof(stats_data) == TYPE_DICTIONARY:
		for stat_name in stats:
			var sd = stats_data.get(stat_name, null)
			if typeof(sd) == TYPE_DICTIONARY:
				stats[stat_name].from_dict(sd)

func from_json(json_string: String) -> void:
	var data = JSON.parse_string(json_string)
	if not data:
		push_error("Failed to parse character JSON")
		return
	from_dict(data)
#endregion
