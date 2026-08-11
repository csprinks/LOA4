class_name StatusEffect
extends RefCounted

## Base class for a temporary condition on a combatant. Defend is the only one in
## v1, but poison, stun, haste, shields, etc. all subclass this. An effect carries
## a remaining duration in TURNS (a combatant acts once per round) and exposes
## hooks the engine calls at defined moments; subclasses override only what they
## need.

signal expired(effect)

var display_name: String = "Effect"
var turns_remaining: int = 1

func _init(name: String = "Effect", duration_turns: int = 1) -> void:
	display_name = name
	turns_remaining = duration_turns

# Called once when the effect is first attached to a combatant.
func on_apply(_combatant) -> void:
	pass

# Called at the start of the owning combatant's turn. Return false to signal the
# effect has expired and should be removed. Default: count down the duration.
func on_turn_start(_combatant) -> bool:
	turns_remaining -= 1
	return turns_remaining > 0

# Hook to alter incoming damage before it is applied. Return the modified amount.
# Called by Combatant.take_damage for every active effect, in order.
func modify_incoming_damage(amount: int) -> int:
	return amount

# Called just before the effect is removed from the combatant.
func on_expire(_combatant) -> void:
	expired.emit(self)
