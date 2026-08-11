class_name FleeAction
extends CombatAction

## Attempt to flee the encounter. On success by an ally, the whole encounter ends
## as FLED (no rewards). Enemies don't flee in v1, but the action is symmetric so
## an AI could later use it to remove a single monster.

func _init() -> void:
	display_name = "Flee"

func ap_cost_for(_actor: Combatant) -> int:
	return CombatConstants.AP_COST_FLEE

func can_perform(actor: Combatant, _target: Combatant, _encounter: Encounter) -> bool:
	return actor.action_points >= ap_cost_for(actor)

func execute(actor: Combatant, _target: Combatant, encounter: Encounter, controller) -> Dictionary:
	actor.spend_ap(ap_cost_for(actor))
	var success: bool = controller.rng.chance_percent(CombatConstants.FLEE_BASE_PERCENT)
	if success and actor.is_ally:
		encounter.status = Encounter.Status.FLED
	return {"action": "flee", "actor": actor, "success": success}
