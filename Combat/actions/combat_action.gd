class_name CombatAction
extends RefCounted

## Base class for a command a combatant can take on its turn. Subclasses set an
## AP cost, declare valid targets, and implement execute(). This is the seam
## through which spells/abilities join later: an AbilityAction will extend this
## with its own AP (or other resource) cost and effect, and the engine -- which
## only ever talks to CombatAction -- won't change.

var display_name: String = "Action"

# AP this action costs `actor`. Some actions compute it dynamically (Attack uses
# the weapon/monster attack cost), so it takes the actor.
func ap_cost_for(_actor: Combatant) -> int:
	return 0

# Is this action legal for `actor` against `target` in `encounter` right now?
# `target` may be null for self / no-target actions. The base check is just AP;
# subclasses add target and reach rules.
func can_perform(actor: Combatant, _target: Combatant, _encounter: Encounter) -> bool:
	return actor.action_points >= ap_cost_for(actor)

# Perform the action. Implementations MUST spend AP via actor.spend_ap(). Returns
# a result Dictionary describing what happened, for the combat log / UI. The
# `controller` gives access to the resolver, RNG, and integration seams.
func execute(_actor: Combatant, _target: Combatant, _encounter: Encounter, _controller) -> Dictionary:
	return {}
