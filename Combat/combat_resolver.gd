class_name CombatResolver
extends RefCounted

## Pure combat math: hit chance, damage, and crits. Stateless except for its RNG.
## Given attacker/defender Combatants it returns a plain result Dictionary the
## engine and UI can narrate. Every number comes from CombatConstants.

var rng: CombatRNG

func _init(combat_rng: CombatRNG = null) -> void:
	rng = combat_rng if combat_rng else CombatRNG.new()

# hit% = base + (accuracy - evasion) * per_point, clamped.
func hit_chance_percent(attacker: Combatant, defender: Combatant) -> int:
	var raw := CombatConstants.HIT_BASE_PERCENT \
		+ (attacker.accuracy - defender.evasion) * CombatConstants.HIT_PER_POINT
	return clampi(raw, CombatConstants.HIT_MIN_PERCENT, CombatConstants.HIT_MAX_PERCENT)

# crit% scales off the attacker's Fate.
func crit_chance_percent(attacker: Combatant) -> int:
	var raw := int(round(attacker.fate * CombatConstants.CRIT_PER_FATE))
	return clampi(raw, 0, CombatConstants.CRIT_MAX_PERCENT)

# Resolve one basic attack. Returns:
#   {
#     attacker, defender, hit_chance:int,
#     hit:bool, crit:bool, damage:int, defender_downed:bool
#   }
# Damage (on a hit) = weapon_roll + floor(Might * scale), doubled on a crit, then
# minus the defender's flat Armor (floored at MIN_DAMAGE). Defend and other status
# effects are applied inside Combatant.take_damage.
func resolve_attack(attacker: Combatant, defender: Combatant) -> Dictionary:
	var chance := hit_chance_percent(attacker, defender)
	var result := {
		"attacker": attacker,
		"defender": defender,
		"hit_chance": chance,
		"hit": false,
		"crit": false,
		"damage": 0,
		"defender_downed": false,
	}
	if not rng.chance_percent(chance):
		return result   # miss

	result["hit"] = true

	var profile := attacker.get_attack_profile()
	var base := rng.randi_range(int(profile["min"]), int(profile["max"]))
	var might_bonus := int(floor(attacker.might * CombatConstants.MIGHT_DAMAGE_SCALE))
	var raw := base + might_bonus

	if rng.chance_percent(crit_chance_percent(attacker)):
		result["crit"] = true
		raw = int(round(raw * CombatConstants.CRIT_MULTIPLIER))

	var after_armor: int = max(CombatConstants.MIN_DAMAGE, raw - defender.armor)
	var dealt := defender.take_damage(after_armor)  # status effects apply here
	result["damage"] = dealt
	result["defender_downed"] = defender.is_downed
	return result
