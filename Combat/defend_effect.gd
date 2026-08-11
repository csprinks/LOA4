class_name DefendEffect
extends StatusEffect

## The buff applied by the Defend action: reduces incoming damage by
## CombatConstants.DEFEND_DAMAGE_REDUCTION until the start of the defender's next
## turn (duration 1 turn -> ticks down when they next act).

var reduction: float = CombatConstants.DEFEND_DAMAGE_REDUCTION

func _init() -> void:
	super("Defending", CombatConstants.DEFEND_DURATION_TURNS)

func modify_incoming_damage(amount: int) -> int:
	return int(ceil(amount * (1.0 - reduction)))
