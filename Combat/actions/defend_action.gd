class_name DefendAction
extends CombatAction

## Take a defensive stance: apply a DefendEffect that reduces incoming damage
## until the actor's next turn. Cheap in AP, so it also doubles as a way to bank
## AP for a bigger next turn.

func _init() -> void:
	display_name = "Defend"

func ap_cost_for(_actor: Combatant) -> int:
	return CombatConstants.AP_COST_DEFEND

func can_perform(actor: Combatant, _target: Combatant, _encounter: Encounter) -> bool:
	return actor.action_points >= ap_cost_for(actor)

func execute(actor: Combatant, _target: Combatant, _encounter: Encounter, _controller) -> Dictionary:
	actor.spend_ap(ap_cost_for(actor))
	actor.add_status_effect(DefendEffect.new())
	return {"action": "defend", "actor": actor}
