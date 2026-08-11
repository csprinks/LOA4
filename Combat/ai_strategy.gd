class_name AIStrategy
extends RefCounted

## Decides an enemy's action on its turn. The engine calls choose_action(); the
## base does nothing (passes). Concrete strategies subclass this, so smarter or
## per-monster behavior drops in without touching the turn engine.

# Return { action: CombatAction, target: Combatant } to act, or {} to pass.
func choose_action(_actor: Combatant, _encounter: Encounter, _controller) -> Dictionary:
	return {}
