class_name Combatant
extends RefCounted

## The uniform fighter interface the turn engine drives. One Combatant wraps
## EITHER a hero Character (is_ally = true) OR a MonsterDefinition (an enemy).
## It holds the mutable per-battle state so a fight reads through one shape.
##
## HP policy: a hero's HP reads/writes straight through to its Character, so
## wounds taken in battle persist afterward (and the HUD reflects them). A
## monster's HP lives here and dies with the encounter.
##
## AP policy: AP is a per-battle resource tracked locally for BOTH kinds. It is
## intentionally NOT written through to Character.action_points, because banking
## (overflow above max) would be clamped by that class -- and out-of-battle AP is
## meaningless anyway. Max AP is still read from the source.

enum Kind { ALLY, ENEMY }

var kind: int = Kind.ENEMY
var is_ally: bool = false
var display_name: String = "Combatant"

# Enemy placement: which monster row (0 = front). Ignored for allies -- heroes
# have no rows.
var row: int = 0

# Active StatusEffect instances (Defend now; more later).
var status_effects: Array = []

# Downed = knocked out at 0 HP (revivable). Distinct from a future permanent
# "dead" state.
var is_downed: bool = false

# Exactly one source is set.
var character: Character = null           # when kind == ALLY
var monster: MonsterDefinition = null     # when kind == ENEMY

# Local mutable state.
var _monster_hp: int = 0                  # allies read HP through their Character
var _ap: int = 0                          # per-battle AP for both kinds

#region Construction
static func for_ally(c: Character) -> Combatant:
	var cb := Combatant.new()
	cb.kind = Kind.ALLY
	cb.is_ally = true
	cb.character = c
	cb.display_name = c.character_name
	cb.is_downed = c.hit_points.current <= 0
	cb._ap = c.action_points.max_value
	return cb

static func for_enemy(def: MonsterDefinition, enemy_row: int = -1) -> Combatant:
	var cb := Combatant.new()
	cb.kind = Kind.ENEMY
	cb.is_ally = false
	cb.monster = def
	cb.display_name = def.display_name
	cb.row = enemy_row if enemy_row >= 0 else def.default_row
	cb._monster_hp = def.max_hp
	cb._ap = def.max_action_points
	return cb
#endregion

#region Vitals
var current_hp: int:
	get: return character.hit_points.current if is_ally else _monster_hp

var max_hp: int:
	get: return character.hit_points.max_value if is_ally else monster.max_hp

var action_points: int:
	get: return _ap

var max_action_points: int:
	get: return character.action_points.max_value if is_ally else monster.max_action_points
#endregion

#region Stats & derived combat values
func _stat(stat_name: String) -> int:
	if is_ally:
		var s := character.get_stat(stat_name)
		return s.total if s else 0
	match stat_name:
		"Might": return monster.might
		"Finesse": return monster.finesse
		"Awareness": return monster.awareness
		"Fate": return monster.fate
	return 0

var might: int:
	get: return _stat("Might")
var finesse: int:
	get: return _stat("Finesse")
var awareness: int:
	get: return _stat("Awareness")
var fate: int:
	get: return _stat("Fate")

var armor: int:
	get: return character.armor.value if is_ally else monster.armor

# accuracy = Might + Finesse; evasion = Finesse + Awareness (design decision).
var accuracy: int:
	get: return might + finesse
var evasion: int:
	get: return finesse + awareness

# Initiative is rebuilt each round as initiative_base + a roll (engine adds roll).
var initiative_base: int:
	get: return finesse + awareness
#endregion

#region Attack profile
# Returns { min, max, is_ranged, ap_cost }. Enemies read their MonsterDefinition.
# Heroes read an equipped primary weapon if it exposes damage numbers, else fall
# back to unarmed defaults. The weapon-dict keys are best-effort until the full
# EquipmentSerializer weapon hookup is finalized (see TODO).
func get_attack_profile() -> Dictionary:
	if not is_ally:
		return {
			"min": monster.damage_min,
			"max": monster.damage_max,
			"is_ranged": monster.is_ranged,
			"ap_cost": monster.attack_ap_cost,
		}
	var weapon: Dictionary = character.get_equipment_slot("primary")
	# TODO: confirm EquipmentSerializer's serialized weapon keys and map cleanly.
	if weapon and weapon.has("minDamage") and weapon.has("maxDamage"):
		return {
			"min": int(weapon.get("minDamage", CombatConstants.UNARMED_MIN_DAMAGE)),
			"max": int(weapon.get("maxDamage", CombatConstants.UNARMED_MAX_DAMAGE)),
			"is_ranged": bool(weapon.get("isRanged", false)),
			"ap_cost": int(weapon.get("ActionPointCost", CombatConstants.AP_COST_ATTACK)),
		}
	return {
		"min": CombatConstants.UNARMED_MIN_DAMAGE,
		"max": CombatConstants.UNARMED_MAX_DAMAGE,
		"is_ranged": false,
		"ap_cost": CombatConstants.AP_COST_ATTACK,
	}
#endregion

#region Mutations
# Apply incoming damage after routing it through active status effects (Defend).
# Returns the actual amount dealt after mitigation.
func take_damage(amount: int) -> int:
	var final_amount := amount
	for effect in status_effects:
		final_amount = effect.modify_incoming_damage(final_amount)
	final_amount = max(0, final_amount)
	if is_ally:
		character.take_damage(final_amount)
	else:
		_monster_hp = max(0, _monster_hp - final_amount)
	if current_hp <= 0:
		is_downed = true
	return final_amount

# Heal HP. Healing a downed (KO'd) combatant above 0 revives it.
func heal(amount: int) -> void:
	if amount <= 0:
		return
	if is_ally:
		character.heal(amount)
	else:
		_monster_hp = min(max_hp, _monster_hp + amount)
	if current_hp > 0:
		is_downed = false

func spend_ap(amount: int) -> bool:
	if _ap < amount:
		return false
	_ap -= amount
	return true

# Restore AP (e.g. an Action Points potion), respecting the banking cap.
func restore_ap(amount: int) -> void:
	_ap = min(_ap_cap(), _ap + amount)

# Start-of-turn AP: refresh toward max, banking unspent AP up to the cap.
func refresh_ap_for_turn() -> void:
	_ap = min(_ap_cap(), _ap + max_action_points)

func _ap_cap() -> int:
	return int(round(max_action_points * CombatConstants.AP_BANK_CAP_MULT))

# Fortune Points are a hero-only spendable luck pool (rerolls). Enemies have none.
var fortune_points: int:
	get: return character.fortune_points.current if is_ally else 0

func spend_fortune(amount: int) -> void:
	if is_ally:
		character.fortune_points.reduce(amount)
#endregion

#region Status effects & turn lifecycle
func add_status_effect(effect: StatusEffect) -> void:
	status_effects.append(effect)
	effect.on_apply(self)

# Called by the engine at the start of this combatant's turn: bank/refresh AP,
# then tick down status effects (removing expired ones).
func begin_turn() -> void:
	refresh_ap_for_turn()
	_tick_status_effects()

func _tick_status_effects() -> void:
	var survivors: Array = []
	for effect in status_effects:
		if effect.on_turn_start(self):
			survivors.append(effect)
		else:
			effect.on_expire(self)
	status_effects = survivors
#endregion
